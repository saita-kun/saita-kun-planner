#!/usr/bin/env python3
"""Read-only application progress for applicants (Python 3.7+)."""
import argparse
import datetime
import json
import pathlib
import re
import sys
import tempfile
import os

sys.dont_write_bytecode = True
import check_setup
import predicate
from check_drafts import build_section_index, check_review_record, draft_bodies_sha256, parse_frontmatter
from check_spec import (JST, check_confirmation_sha, is_provider_confirmed, evaluate_application_deadlines,
                        parse_now, deadline_remaining_days, select_application_deadline,
                        evaluate_schedule_deadlines)
from spec_resolver import ResolverError, resolve_application_spec, resolve_bundled_specs
from check_pack import check_pack

ROOT = pathlib.Path(__file__).resolve().parents[2]
STATES = ['spec_draft', 'spec_confirmed', 'intake_done', 'fit_done',
          'planned', 'drafting', 'verified', 'finalized']


def read_object(path, fenced=False):
    text = path.read_text(encoding='utf-8')
    if fenced:
        match = re.match(r'\A```json\n(.*?)\n```(?:\n|$)', text, re.S)
        if match is None:
            raise ValueError('先頭の JSON 記録がありません')
        text = match.group(1)
    data = json.loads(text)
    if not isinstance(data, dict):
        raise ValueError('JSON object が必要です')
    return data


def inspect(root, steps, now, notices):
    from check_drafts import coverage_inputs_sha256

    by_id = {s['step_id']: s for s in steps}

    def set_status(key, status, reason='', detail=None):
        by_id[key].update(status=status, reason=reason, detail=detail)

    def unknown(start, reason):
        for step in steps[start:]:
            set_status(step['step_id'], 'unknown', reason)
        return None

    setup_status, setup_errors = check_setup.inspect_setup(root)
    if setup_status == 'invalid':
        return unknown(0, '／'.join(setup_errors))
    set_status('setup', 'done' if setup_status == 'done' else 'todo', '／'.join(setup_errors))
    if setup_status != 'done':
        return None
    app_path = root / 'input/current-application.json'
    if not app_path.exists():
        return None
    try:
        app = read_object(app_path)
        state = app.get('state')
        sid = app.get('subsidy_id')
        if state not in STATES or not isinstance(sid, str) or not re.fullmatch('[a-z0-9-]+', sid):
            raise ValueError('状態または補助金 ID が不正です')
    except (OSError, ValueError, UnicodeError) as exc:
        return unknown(1, '申請の状態記録を読み取れません: ' + str(exc))
    rank = STATES.index(state)
    set_status('spec-entry', 'done')
    try:
        resolved = resolve_application_spec(root, sid)
        spec = read_object(resolved.spec_path)
    except (ResolverError, OSError, ValueError, UnicodeError):
        return unknown(2, '補助金のデータを解決・読み取りできません')
    confirmed = rank >= 1 and spec.get('status') == 'confirmed'
    set_status('confirm-spec', 'done' if confirmed else 'todo')
    if confirmed and is_provider_confirmed(spec, resolved.spec_path):
        by_id['confirm-spec']['detail'] = {'confirmed_by': 'provider'}
    try:
        bundled = next((s for s in resolve_bundled_specs(root / 'specs', root)
                        if s.subsidy_id == sid), None)
        if bundled and bundled.pack_path and not check_pack(bundled.pack_path)[0]:
            by_id['build-pack']['detail'] = {'bundled_pack': True}
    except (ResolverError, OSError, ValueError, UnicodeError):
        pass
    if (root / 'input/spec' / sid / 'pack.json').is_file():
        set_status('build-pack', 'done')
    for key, minimum in [('intake', 2), ('subsidy-fit', 3), ('plan-deliverables', 4)]:
        if rank >= minimum and (key != 'plan-deliverables' or (root / 'input/deliverables.md').is_file()):
            set_status(key, 'done')
    try:
        profile_path = root / 'input/company-profile.json'
        profile = read_object(profile_path) if profile_path.exists() else {}
        contexts = predicate.build_contexts(profile, app)
        section_errors = []
        coverage_inputs = {}
        _, required_sections = build_section_index(spec, section_errors, contexts, coverage_inputs)
        if section_errors:
            return unknown(7, '／'.join(section_errors))
        targets = {key for key, value in required_sections.items() if value == predicate.TRUE}
        unknown_count = sum(value == predicate.UNKNOWN for value in required_sections.values())
    except (OSError, ValueError, UnicodeError, predicate.PredicateInputError):
        return unknown(7, '対象セクションを読み取れません')
    drafts_dir = root / 'input/drafts' / sid
    produced, draft_errors = {}, []
    paths = sorted(drafts_dir.glob('*.md'))
    for path in paths:
        try:
            fm, _, errors = parse_frontmatter(path, path.read_text(encoding='utf-8'))
            draft_errors.extend(errors)
            if not errors:
                produced[(fm['deliverable_id'], fm['section_id'])] = path
        except (OSError, UnicodeError):
            draft_errors.append('叩き台を読み取れません')
    count = len(targets.intersection(produced))
    reviews = sorted((root / 'input/reviews').glob('*.md'))
    if reviews:
        valid = bool(paths) and not draft_errors and any(
            not check_review_record(p, drafts_dir, produced) for p in reviews)
        set_status('review', 'done' if valid else 'stale',
                   '' if valid else '本文の変更、未点検のセクション、または記録の不備があります')
    report_path = root / 'input/checks/verify-report.md'
    if report_path.exists():
        coverage_stale = False
        try:
            report = read_object(report_path, fenced=True)
            digest, errors = draft_bodies_sha256(drafts_dir)
            check_confirmation_sha(resolved.spec_path, report_path, report, errors)
            coverage_stale = report.get('coverage_inputs_sha256') != coverage_inputs_sha256(coverage_inputs)
            valid = (not errors and not draft_errors and not coverage_stale and
                     report.get('draft_bodies_sha256') == digest and
                     report.get('spec_check') == report.get('draft_check') == 'green')
        except (OSError, ValueError, UnicodeError):
            valid = False
        set_status('verify', 'done' if valid else 'stale',
                   '検査の後に、必須かどうかの判定に使う会社情報・申請情報が変わっています' if coverage_stale else
                   '' if valid else '検査記録が現在の本文・補助金データと一致しないか、検査が未完了です')
    if state == 'finalized':
        if by_id['verify']['status'] == 'stale':
            set_status('finalize', 'stale', '機械検査をやり直して最終確認を更新してください')
        elif by_id['verify']['status'] == 'done' and (root / 'input/final-checklist.md').is_file():
            set_status('finalize', 'done')
    drafts_done = (count == len(targets) and not draft_errors or
                   bool(paths) and by_id['review']['status'] == by_id['verify']['status'] == 'done' or
                   by_id['finalize']['status'] == 'done')
    set_status('draft-section', 'done' if drafts_done else 'todo',
               '不足のセクションは、最終確認（/finalize）でご自身で別に作るかを確かめます'
               if drafts_done and count < len(targets) else '',
               detail={'count': count, 'total': len(targets), 'draft_count': len(paths), 'unknown': unknown_count})
    for path in sorted((root / 'knowledge/records').glob('*.json')):
        try:
            record = read_object(path)
            if (record.get('subsidy_id') == sid and
                    isinstance(record.get('record_id'), str) and
                    re.fullmatch('[a-z0-9-]+', record['record_id']) and
                    type(record.get('spec_version')) is int and
                    record.get('result') in ('adopted', 'rejected', 'not_submitted', 'pending')):
                set_status('retrospect', 'done')
                set_status('submit', 'done')
        except (OSError, ValueError, UnicodeError):
            notices['warnings'].append('注意: 振り返りの記録を読み取れません（{}）'.format(path.name))
    if by_id['submit']['status'] != 'done':
        set_status('submit', 'todo', '記録なし')
    deadlines = evaluate_application_deadlines(spec, now) if confirmed else []
    if not deadlines:
        return None
    event = select_application_deadline(deadlines)
    cutoff = (datetime.date.fromisoformat(event.raw_date),
              datetime.time.fromisoformat(event.raw_time) if event.raw_time else datetime.time.max)
    for date, time, item, evaluation in evaluate_schedule_deadlines(spec, now):
        if not evaluation.expired and (date, time) < cutoff:
            issuer = next((d.get('issuer') for d in spec.get('deliverables', [])
                           if d.get('due_event_id') == evaluation.event_id and d.get('issuer')), None)
            notices['nearest_deadline'] = dict(date=evaluation.raw_date,
                name=item.get('name', evaluation.event_id), issuer=issuer,
                remaining_days=deadline_remaining_days(evaluation.raw_date, now))
            break
    return {'date': event.raw_date, 'time': event.raw_time, 'expired': event.expired,
            'remaining_days': deadline_remaining_days(event.raw_date, now)}


def command_label(step):
    return ' または '.join('/' + c for c in step['commands'])


def show(args):
    flow = read_object(ROOT / 'templates/progress/command-flow.json')
    steps = [dict(s, status='optional' if s['optional'] else 'todo', reason='', detail=None)
             for s in flow['steps']]
    notices = dict(nearest_deadline=None, warnings=[])
    deadline = inspect(args.root, steps, args.now, notices)
    nearest = notices['nearest_deadline']
    required = [s for s in steps if not s['optional']]
    current = next((s for s in required if s['status'] != 'done'), None)
    if current and current['status'] == 'todo':
        current['status'] = 'current'
    unknown = next((s for s in steps if s['status'] == 'unknown'), None)
    numbers = {s['step_id']: i for i, s in enumerate(required, 1)}
    index = numbers[current['step_id']] if current else len(required)
    commands = current['commands'] if current else []
    if unknown:
        line = '現在地: 確認できません（{}）。/start で状態を確認してください'.format(unknown['reason'])
        commands = ['start']
    elif current:
        label = command_label(current) or '提出はご自身で行います'
        line = '現在地: {}/{} {}（{}）'.format(index, len(required), current['label'], label)
        if current['step_id'] == 'draft-section' and current['detail']:
            detail = current['detail']
            line += '・必須セクション {count}/{total} 作成済み'.format(**detail)
            if detail['unknown']:
                line += '・判定できないセクション {}'.format(detail['unknown'])
        if nearest:
            line += '｜直近の期限 {date}・残り {remaining_days} 日'.format(**nearest)
        if deadline:
            if deadline['expired']:
                line += '｜申請締切 {} を過ぎています'.format(deadline['date'])
            else:
                line += '｜申請締切 {}{}・残り {} 日'.format(
                    deadline['date'], ' ' + deadline['time'] if deadline['time'] else '',
                    deadline['remaining_days'])
        if args.phase == 'begin' and args.command and args.command not in commands:
            line += '｜実行中: /' + args.command
    else:
        line = '現在地: すべての工程が済んでいます'
    lines = []
    if commands:
        lines.append('次のコマンド: ' + ' または '.join('/' + c for c in commands))
    elif current and current['step_id'] == 'submit':
        lines.append('次にすること: input/final-checklist.md に残っている確認をご自身で済ませたうえで、ご自身で提出します（最終確認の記録は、提出してよいという意味ではありません）。結果が出たら /retrospect')
    if nearest:
        name = nearest['name'] + ('（窓口: {}）'.format(nearest['issuer']) if nearest['issuer'] else '')
        lines.append('直近の期限: {} {}・残り {} 日'.format(nearest['date'], name, nearest['remaining_days']))
    if current and current['step_id'] == 'spec-entry' and args.command != 'start':
        lines.append(current['guidance'])
    for step in steps:
        if step['status'] == 'stale':
            lines.append('やり直しが必要: {}（{}）'.format(command_label(step), step['reason']))
    statuses = {s['step_id']: s['status'] for s in steps}
    if statuses['confirm-spec'] == 'done' and statuses['build-pack'] == 'optional':
        pack = next(s for s in steps if s['step_id'] == 'build-pack')
        label = ('同梱の書き方メモがあります。不足を補いたい場合だけ実行します'
                 if (pack['detail'] or {}).get('bundled_pack') else '書き方メモ')
        lines.append('任意: /build-pack（{}）'.format(label))
    lines.extend(notices['warnings'])
    result = dict(version=1, phase=args.phase, command=args.command,
                  current_step=current['step_id'] if current else None,
                  position=dict(index=index, total=len(required)), deadline=deadline,
                  steps=steps, next_commands=commands, line=line,
                  display_lines=lines, **notices)
    if args.format == 'json':
        print(json.dumps(result, ensure_ascii=False))
        return
    print(line)
    if args.phase != 'begin':
        for value in lines:
            print(value)
        if not args.no_html:
            write_diagram(args, result, flow, numbers)


def write_diagram(args, result, flow, numbers):
    temporary = None
    try:
        from progress_render import render_html
        spec = None
        try:
            app = read_object(args.root / 'input/current-application.json')
            resolved = resolve_application_spec(args.root, app['subsidy_id'])
            spec = read_object(resolved.spec_path)
        except (ResolverError, OSError, ValueError, UnicodeError, KeyError):
            pass
        confirmed = any(s['step_id'] == 'confirm-spec' and s['status'] == 'done'
                        for s in result['steps'])
        document = render_html(result, flow, args.now, numbers, spec, confirmed)
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8',
                                         dir=str(args.root / 'input'),
                                         prefix='.progress-', suffix='.tmp', delete=False) as stream:
            temporary = pathlib.Path(stream.name)
            stream.write(document)
        os.replace(str(temporary), str(args.root / 'input/progress.html'))
        print('図: input/progress.html（ブラウザで開くと全工程が見られます）')
    except Exception as exc:
        print('図: 書き出せませんでした（{}）'.format(' '.join(str(exc).splitlines())))
    finally:
        if temporary is not None:
            try:
                temporary.unlink()
            except OSError:
                pass


def main():
    parser = argparse.ArgumentParser(description='申請作業の現在地を読み取り専用で表示します')
    parser.add_argument('action', choices=['show'])
    parser.add_argument('--phase', choices=['begin', 'end', 'resume'], default='begin')
    flow_error, commands = None, None
    try:
        flow = read_object(ROOT / 'templates/progress/command-flow.json')
        commands = sorted(set(flow['guide_commands'] + [c for s in flow['steps'] for c in s['commands']]))
    except Exception as exc:
        flow_error = exc
    parser.add_argument('--command', choices=commands)
    parser.add_argument('--format', choices=['text', 'json'], default='text')
    parser.add_argument('--no-html', action='store_true', help='HTML 図を書き出さない')
    parser.add_argument('--now', type=parse_now, default=datetime.datetime.now(JST))
    parser.add_argument('--root', type=pathlib.Path, default=ROOT)
    args = parser.parse_args()
    try:
        if flow_error:
            raise flow_error
        show(args)
    except Exception as exc:
        line = '現在地: 確認できません（道具の内部エラー: {}）。/start で状態を確認してください'.format(type(exc).__name__)
        print(json.dumps({'line': line}, ensure_ascii=False) if args.format == 'json' else line)
        print('道具の内部エラー: {}: {}'.format(type(exc).__name__, ' '.join(str(exc).splitlines())), file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
