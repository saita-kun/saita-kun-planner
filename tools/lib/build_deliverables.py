#!/usr/bin/env python3
"""Generate a replaceable planning view; never modify applicant notes."""
import argparse
import datetime
import hashlib
import os
import pathlib
import re
import sys
import tempfile

sys.dont_write_bytecode = True
import check_spec
import predicate
from schedule import relative_deadline_text
from spec_resolver import ResolverError, repo_relative_path, resolve_application_spec

CHECK = '未記載 [要確認]'


def display_value(value):
    if isinstance(value, list):
        return "、".join(display_value(v) for v in value) or "なし"
    if isinstance(value, dict):
        return "（" + "、".join(k + "：" + display_value(v) for k, v in sorted(value.items())) + "）"
    if value is None:
        return CHECK
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def cell(value):
    value = display_value(value)
    lines = [re.sub(r'[ \t]{2,}', ' ', line.strip()) for line in value.splitlines()]
    joined = ''
    for line in filter(None, lines):
        separator = '' if not joined or (ord(joined[-1]) > 127 and ord(line[0]) > 127) else ' '
        joined += separator + line
    return joined.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('|', '&#124;')


def table(headers, rows):
    return ['| ' + ' | '.join(map(cell, headers)) + ' |',
            '| ' + ' | '.join(['---'] * len(headers)) + ' |'] + [
                '| ' + ' | '.join(map(cell, row)) + ' |' for row in rows] + ['']


def remaining_label(event, evaluation, now, spacing=""):
    # The schema has no start kind; identify soft opening milestones by name.
    opening = (event.get('hard') is False and event.get('event_kind') == 'other'
               and '開始' in event.get('name', '')
               and not any(word in event.get('name', '') for word in ('締切', '期限', '終了')))
    if opening:
        return '受付開始済み' if evaluation.expired else '受付開始まで{0}{1}{0}日'.format(
            spacing, check_spec.deadline_remaining_days(evaluation.raw_date, now))
    return '期限切れ' if evaluation.expired else '残り{0}{1}{0}日'.format(
        spacing, check_spec.deadline_remaining_days(evaluation.raw_date, now))


def deadline(event, now):
    if event is None:
        return '期限未設定 [要確認]: 公式の公募要領で確認'
    label = relative_deadline_text(event)
    if label:
        label += '（基準になる日が決まった後に、公式の案内で日付を確認 [要確認]）'
    elif any(event.get(k) for k in ('date', 'starts_at', 'ends_at', 'time')):
        label = ' '.join(str(event[k]) for k in ('date', 'starts_at', 'ends_at', 'time', 'timezone') if event.get(k))
    else:
        label = '日付は未定（{}）[要確認]'.format(event.get('name') or '名称未記載')
    evaluation = check_spec.evaluate_event_deadline(event, now)
    if evaluation:
        label += ' / ' + remaining_label(event, evaluation, now)
    if event.get('hard'):
        label += ' / 【hard=true: 失権・提出不可につながる可能性がある硬い期限】'
    return label


def classification(item, contexts):
    expr = item.get('required_if')
    if expr is None:
        return ('required', '必須') if item['required'] else ('natural', '条件付き（自然文のみ・機械評価なし）[要確認]')
    result = predicate.eval_predicate(expr, contexts)
    return result, {'true': '必須・条件付き（判定 TRUE）', 'false': '該当なし（判定 FALSE）',
                    'unknown': '条件付き（判定 UNKNOWN）[要確認]'}[result]


def render(spec, app, profile, path, digest, now):
    contexts = predicate.build_contexts(profile, app)
    events = {e['event_id']: e for e in spec['schedule']}
    clauses = {c['clause_id']: c for c in spec['clauses']}
    out = ['# 成果物マニフェスト', '', 'この一覧は道具が spec から生成したものです。書き足しは `input/deliverables-notes.md` に書いてください（この一覧は再生成で上書きされます）', '',
           '「未記載 [要確認]」は、公募要領から読み取れなかった項目です。公式の公募要領・様式・申請システムで確かめてください。', '',
           '## 作成メモ', '', '- auto-generated / 再生成可能なビュー', '- 生成日時: ' + now.isoformat(), '- spec: ' + path,
           '- version: ' + str(spec['spec_version']), '- sha256: ' + digest,
           '- 作成者は顧客本人です。AI は補助・整理のみで、申請代行・代理提出は行いません。',
           '- 最終確認・手動の消し込みは /finalize の提出前チェックリストで行います。', '', '## 対象申請', '']
    out += table(['項目', '内容'], [(k, app.get(k)) for k in ('subsidy_id', 'spec_version', 'chosen_funding')] + [('spec_path', path), ('state_before', app.get('state'))])
    records = []
    fields = 'deliverable_id name type phase produced_by issuer format upload_target due_event_id depends_on evidence_needed source_clauses'.split()
    sections = 'section_id name kind max_chars max_pages guidance review_criteria source_clauses'.split()
    for item in spec['deliverables']:
        result, label = classification(item, contexts)
        condition = item.get('condition') or ' / '.join([item['name']] + [clauses[c].get('raw_text') or clauses[c]['text'] for c in item['source_clauses']])
        values = [item.get(k) if k != 'issuer' else item.get(k) or '顧客本人が準備' for k in fields]
        values += [deadline(events.get(item.get('due_event_id')), now), events.get(item.get('due_event_id'), {}).get('hard'), label, condition, item.get('required_if'), '[要確認]' if result == 'natural' else label]
        records.append((item, result, values))
    dated, unknown, conditional = [], [], []
    for item, result, _ in records:
        if result == 'false':
            continue
        event = events.get(item.get('due_event_id'))
        if result == 'natural':
            conditional.append([item['name'], deadline(event, now), item.get('condition') or '該当するかを本人が確認 [要確認]'])
            continue
        evaluation = check_spec.evaluate_event_deadline(event, now) if event else None
        if evaluation:
            date_time = evaluation.raw_date + (' ' + evaluation.raw_time if evaluation.raw_time else '')
            remaining = remaining_label(event, evaluation, now, spacing=' ')
            dated.append((evaluation.raw_date, evaluation.raw_time or '23:59:59',
                          '- {} ／ {} ／ {}'.format(date_time, remaining, cell(item['name']))))
        elif event is None or not any(event.get(k) for k in ('date', 'starts_at', 'ends_at', 'relative')):
            unknown.append('- ' + cell(item['name']))
    out += ['## 先に確かめること', '', '### 日付の決まっている期限', '']
    out += [row for _, _, row in sorted(dated)] or ['該当なし']
    out += ['', '### 期限がまだ分からないもの', ''] + (unknown or ['該当なし']) + ['']
    out += ['### 条件に当てはまる場合だけ必要なもの（該当するかを本人が確認）', '']
    out += table(['成果物名', '期限', '条件'], conditional) if conditional else ['該当なし', '']
    groups = [
        ('AIと作る成果物', lambda d, r: d['produced_by'] == 'ai_draftable'),
        ('人がやることリスト', lambda d, r: d['type'] == 'procedure' or d['produced_by'] in ('human_only', 'external')),
        ('添付チェックリスト', lambda d, r: d['type'] == 'attachment'),
        ('締切カレンダー', None),
        ('required_if が [要確認] の項目', lambda d, r: r == 'unknown'),
        ('条件付き（該当する場合のみ提出）', lambda d, r: r == 'natural'),
        ('対象外候補（該当なしの候補）', lambda d, r: r == 'false')]
    for title, select in groups:
        out += ['## ' + title, '']
        if title.startswith('条件付き'):
            out += ['該当有無は顧客本人が判断し、/finalize の提出前チェックリストで1件ずつ確認してください。', '']
        for phase in sorted({d.get('phase', 'application') for d in (spec['schedule'] if select is None else spec['deliverables'])}, key=lambda p: (p != 'application', p)):
            out += ['### ' + ('申請フェーズ' if phase == 'application' else '採択後') + ' (' + phase + ')', '']
            if select is None:
                keys = 'event_id name event_kind phase date starts_at ends_at relative time timezone hard source_clauses'.split()
                ordered = sorted(spec['schedule'], key=lambda e: (e.get('date') or e.get('starts_at') or e.get('ends_at') or '9999', e['event_id']))
                out += table(keys + ['期限'], [[relative_deadline_text(e) if k == "relative" and e.get(k) is not None else e.get(k) for k in keys] + [deadline(e, now)] for e in ordered if e.get('phase', 'application') == phase])
                continue
            chosen = [(d, r, v) for d, r, v in records if select(d, r) and d.get('phase', 'application') == phase]
            for d, r, values in chosen:
                out += ['#### 成果物: ' + cell(d['name']), '']
                if r == 'unknown' and app.get('chosen_funding') is None and predicate.predicate_uses_application_scope(d.get('required_if')):
                    out += ['特例を使う場合に必要になるもの `[要確認]`。required_if が [要確認] の項目を参照。特例を決めたら `/subsidy-fit` → `/plan-deliverables` をやり直してください。', '']
                headers = fields + ['期限', 'hard', 'required_if 評価', '条件（原文のまま）', 'required_if', '該当']
                if title == 'AIと作る成果物':
                    out += table(['項目', '内容'], zip(headers, values))
                else:
                    headers = [({'人がやることリスト': '作業名', '添付チェックリスト': '添付名'}.get(title, '成果物名') if k == 'name' else k) for k in headers]
                    out += table(headers, [values])
                if d.get('sections'):
                    out += ['##### sections', ''] + table(sections, [[s.get(k) for k in sections] for s in d['sections']])
            if not chosen:
                out += ['該当なし', '']
    return '\n'.join(out + ['## 次に実行するコマンド', '', '`/draft-section`', ''])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[2])
    parser.add_argument('--current-application', default='input/current-application.json')
    parser.add_argument('--profile', default='input/company-profile.json')
    parser.add_argument('--output', default='input/deliverables.md')
    parser.add_argument('--now', type=datetime.date.fromisoformat)
    args = parser.parse_args()
    try:
        root = args.root.resolve()
        app = predicate.load_current_application(root / args.current_application)
        if not all(app.get(k) is not None for k in ('spec_path', 'subsidy_id', 'spec_version')):
            raise ValueError('current application requires spec_path, subsidy_id and spec_version')
        resolved = resolve_application_spec(root, app['subsidy_id'], pathlib.Path(app['spec_path']))
        path = resolved.spec_path
        spec = predicate.load_json(path)
        predicate.validate_application_binding(spec, app)
        events = {e['event_id'] for e in spec['schedule']}
        if any(d.get('due_event_id') is not None and d['due_event_id'] not in events for d in spec['deliverables']):
            raise ValueError('due_event_id references missing schedule event')
        now = datetime.datetime.combine(args.now, datetime.time(), tzinfo=check_spec.JST) if args.now else datetime.datetime.now(check_spec.JST)
        if spec.get('status') != 'confirmed':
            print('FAIL: spec must be confirmed', file=sys.stderr)
            return 1
        errors, warnings, _ = check_spec.check_spec(path, now=now)
        if errors:
            print('FAIL: ' + '\n'.join(errors), file=sys.stderr)
            return 1
        profile = predicate.load_json(root / args.profile)
        if not isinstance(profile, dict):
            raise ValueError('profile must be an object')
        body = render(spec, app, profile, repo_relative_path(path, root), hashlib.sha256(path.read_bytes()).hexdigest(), now)
        if args.output == '-':
            print(body, end='')
        else:
            output = root / args.output
            protected = {path.resolve(), (root / args.current_application).resolve(), (root / args.profile).resolve(), (root / 'input/deliverables-notes.md').resolve()}
            if output.resolve() in protected:
                raise ValueError('output must not overwrite source inputs or applicant notes')
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', newline='\n', dir=str(output.parent), delete=False) as stream:
                    temporary = stream.name
                    stream.write(body)
                os.replace(temporary, str(output))
                print('OK: deliverables written: ' + pathlib.Path(os.path.relpath(str(output), str(root))).as_posix())
            finally:
                if temporary and os.path.exists(temporary):
                    os.unlink(temporary)
        return 0
    except (OSError, ValueError, KeyError, TypeError, ResolverError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
