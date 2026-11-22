#!/bin/bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/lib/python-resolver.sh" || exit 1
planner_resolve_python "$ROOT/input/.planner-python" || exit 1
"${PLANNER_PY[@]}" -B - "$ROOT" <<'PY'
import contextlib
import io
from unittest.mock import patch
import hashlib
import json
import pathlib
import os
import re
import html
import shutil
import subprocess
import sys
import tempfile

repo = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(repo / 'tools/lib'))
import progress
from check_drafts import build_section_index, coverage_inputs_sha256, draft_bodies_sha256
PASS = FAIL = 0


def check(label, value):
    global PASS, FAIL
    if value:
        PASS += 1
    else:
        FAIL += 1
        print('FAIL: ' + label)


with tempfile.TemporaryDirectory(prefix='planner-progress-') as tmp:
    root = pathlib.Path(tmp)
    def write(path, value):
        p = root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(value) if isinstance(value, dict) else value, encoding='utf-8')
        return p

    def run(*args):
        result = subprocess.run(['bash', str(repo / 'tools/progress.sh'), 'show', '--root',
                                 str(root), '--now', '2026-11-13'] + list(args),
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8')
        if result.returncode:
            raise AssertionError(result.stderr)
        return result.stdout

    def data():
        return json.loads(run('--format', 'json'))

    def current(expected):
        check('current ' + expected, data()['current_step'] == expected)

    def status(key):
        return next(s['status'] for s in data()['steps'] if s['step_id'] == key)

    output = root / 'input/progress.html'
    check('missing input graceful', '図: 書き出せませんでした' in run('--phase', 'end'))
    check('missing input not created', not (root / 'input').exists())
    current('setup')
    check('empty setup exact', run('--command', 'setup') ==
          '現在地: 1/12 作業環境を整えて約束ごとを確認する（/setup）\n')
    check('no early optional', '任意:' not in run('--phase', 'resume'))
    for name in ['TERMS.md', 'docs/data-policy.md']:
        write(name, (repo / name).read_text(encoding='utf-8'))
    write('input/setup-state.json', dict(setup_state_version=1,
          setup_completed_at='2026-11-13T12:00:00+09:00', result_report_choice='保留',
          terms_sha256=hashlib.sha256((root / 'TERMS.md').read_bytes()).hexdigest(),
          data_policy_sha256=hashlib.sha256((root / 'docs/data-policy.md').read_bytes()).hexdigest()))
    for options in [('--phase', 'begin'), ('--phase', 'end', '--format', 'json'),
                    ('--phase', 'resume', '--no-html')]:
        run(*options)
        check('no html ' + str(options), not output.exists())
    for phase in ('end', 'resume'):
        run('--phase', phase)
        check('html ' + phase, output.is_file())
        output.unlink()
    current('spec-entry')
    entry = '現在地: 2/12 補助金のデータを用意する（/ingest-guidelines または /select-subsidy）'
    guidance = '案内: 初めての場合や、どちらを選ぶか迷う場合は /start（全体の流れと選び方の案内）'
    for phase in ('end', 'resume'):
        lines = run('--phase', phase, '--command', 'setup').splitlines()
        check('completed command exact ' + phase, lines[0] == entry)
        check('entry guidance exact ' + phase, lines[1:3] ==
              ['次のコマンド: /ingest-guidelines または /select-subsidy', guidance])
        document = output.read_text(encoding='utf-8')
        check('entry html exact ' + phase, '<p>' + '<br>'.join(lines[1:3]) + '<br>' in document)
        check('start no guidance ' + phase, guidance not in run('--phase', phase, '--command', 'start'))
    check('running mismatch exact', run('--command', 'setup') == entry + '｜実行中: /setup\n')
    check('running current exact', run('--command', 'select-subsidy') == entry + '\n')
    check('guidance json', guidance in json.loads(run('--phase', 'end', '--format', 'json'))['display_lines'])
    sid = 'jizokuka-20'
    shutil.copytree(str(repo / 'specs' / sid), str(root / 'specs' / sid))
    copied_confirmation = root / 'specs' / sid / (sid + '.confirmation.json')
    confirmation_data = json.loads(copied_confirmation.read_text())
    confirmation_data['spec_path'] = str(root / 'specs' / sid / (sid + '.json'))
    write(copied_confirmation, confirmation_data)
    copied_pack = root / 'specs' / sid / 'pack.json'
    pack_data = json.loads(copied_pack.read_text())
    pack_data['confirmation']['sha256'] = hashlib.sha256(copied_confirmation.read_bytes()).hexdigest()
    write(copied_pack, pack_data)
    app = dict(subsidy_id=sid, state='spec_draft')
    def state(value):
        app['state'] = value
        write('input/current-application.json', app)
    state('spec_draft')
    current('confirm-spec')
    check('no unconfirmed optional', '任意:' not in run('--phase', 'end'))
    visible = ''.join(re.findall(r'<text[^>]*>(.*?)</text>', output.read_text(encoding='utf-8')))
    check('unconfirmed external guidance',
          '補助金のデータが確定すると、外部の窓口の手続きと期限がここに出ます。' in visible)
    check('unconfirmed deadline hidden', '申請締切' not in run() and '直近の期限' not in run())
    state('spec_confirmed')
    current('intake')
    nearest_line = '直近の期限: 2026-12-04 事業支援計画書（様式4）発行の受付締切（窓口: 商工会・商工会議所）・残り 20 日'
    for phase in ('begin', 'end', 'resume'):
        lines = run('--phase', phase, '--now', '2026-11-14').splitlines()
        check('nearest header exact ' + phase, lines[0] ==
              '現在地: 4/12 会社と事業の情報を整理する（/intake）｜直近の期限 2026-12-04・残り 20 日｜申請締切 2026-12-15 17:00・残り 31 日')
        check('nearest phase lines ' + phase, len(lines) == 1 if phase == 'begin' else lines[2] == nearest_line)
    gate = subprocess.run(['bash', str(repo / 'tools/check-spec.sh'),
                           str(root / 'specs' / sid / (sid + '.json')), '--gate', 'select', '--now', '2026-11-14'],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8')
    check('nearest gate exact', gate.returncode == 0 and
          'INFO: 残り 20 日: 事業支援計画書（様式4）発行の受付締切（2026-12-04）' in gate.stdout.splitlines())
    nearest = json.loads(run('--format', 'json', '--now', '2026-11-14'))
    check('nearest json', nearest['nearest_deadline']['remaining_days'] == 20 and nearest_line in nearest['display_lines'])
    check('deadline days', '残り 32 日' in run())
    spec_path = root / 'specs' / sid / (sid + '.json')
    confirmation_path = spec_path.with_suffix('.confirmation.json')
    saved_spec, saved_confirmation = spec_path.read_bytes(), confirmation_path.read_bytes()
    spec = json.loads(saved_spec)
    confirmation = json.loads(saved_confirmation)
    confirmation['spec_path'] = str(spec_path.resolve())
    extra = next(e for e in spec['schedule'] if e['event_id'] == 'yoshiki4-deadline')
    extra.update(event_kind='application_deadline', date='2026-11-01')
    for label, date, now, expected, code in [
        ('mixed deadlines', '2026-11-01', '2026-11-13', '2026-12-15 17:00・残り 32 日', 0),
        ('all expired', '2026-11-01', '2026-12-16', '2026-12-15 を過ぎています', 1),
        ('two active', '2026-12-01', '2026-11-13', '2026-12-01 17:00・残り 18 日', 0),
    ]:
        extra.update(date=date, time='17:00')
        write(spec_path, spec)
        confirmation['spec_sha256'] = hashlib.sha256(spec_path.read_bytes()).hexdigest()
        write(confirmation_path, confirmation)
        line = run('--now', now).splitlines()[0]
        gate = subprocess.run(['bash', str(repo / 'tools/check-spec.sh'), str(spec_path),
                               '--gate', 'select', '--now', now],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8')
        check(label, expected in line and gate.returncode == code)
        if code == 0:
            check(label + ' gate days', 'INFO: ' + expected.split('・')[1] in gate.stdout)
        else:
            check(label + ' first warning', 'application deadline 2026-12-15 has passed' in gate.stdout)
    spec_path.write_bytes(saved_spec)
    confirmation_path.write_bytes(saved_confirmation)
    for date, expected in [('2026-12-15', None), ('2026-12-16', None), ('2026-11-14', 0)]:
        altered = json.loads(saved_spec)
        event = next(e for e in altered['schedule'] if e['event_id'] == 'yoshiki4-deadline')
        event.update(date=date, time='17:00')
        write(spec_path, altered)
        result = json.loads(run('--format', 'json', '--now', '2026-11-14T17:00:00+09:00'))
        check('nearest boundary ' + date, result['nearest_deadline'] is None if expected is None
              else result['nearest_deadline']['remaining_days'] == expected)
    spec_path.write_bytes(saved_spec)
    check('past nearest hidden', '直近の期限' not in run('--now', '2026-12-05'))
    check('expired', 'を過ぎています' in run('--now', '2026-12-16'))
    check('command mismatch', '実行中: /review' in run('--command', 'review'))
    check('begin one line', len(run().splitlines()) == 1)
    check('resume optional', '任意: /build-pack（同梱の書き方メモがあります。不足を補いたい場合だけ実行します）' in run('--phase', 'resume').splitlines())
    local_flat = write('input/spec/' + sid + '.json', json.loads(saved_spec))
    bundled_dir = root / 'specs' / sid
    bundled_dir.rename(root / 'saved-pack')
    check('absent pack fallback exact', '任意: /build-pack（書き方メモ）' in run('--phase', 'end').splitlines())
    (root / 'saved-pack').rename(bundled_dir)
    local_flat.unlink()
    state('intake_done')
    current('subsidy-fit')
    run('--phase', 'end')
    document = output.read_text(encoding='utf-8')
    check('text unchanged except diagram line', run('--phase', 'end') ==
          run('--phase', 'end', '--no-html') + '図: input/progress.html（ブラウザで開くと全工程が見られます）\n')
    check('offline html', not re.search(r'https?://|<script|<link|@import|url\(',
          document.replace('http://www.w3.org/2000/svg', '')))
    for label in ['経営者（あなた）', 'Claude Code との作業', '外部の窓口']:
        check('lane ' + label, label in document)
    check('current marker', 'data-step-id="subsidy-fit" data-status="current"' in document)
    check('done marker', 'data-step-id="intake" data-status="done"' in document)
    check('human gate', 'あなたの確認が必要' in document)
    check('creation date', '作成日: 2026-11-13' in document)
    def card(document, step_id):
        return re.search(r'<g data-step-id="' + step_id + r'".*?</g>', document, re.S)[0]
    current_card = card(document, 'subsidy-fit')
    number = re.search(r'現在地: (\d+)/', run())[1]
    check('current number matches text', '>' + number + '. ' in current_card
          and int(number) == data()['position']['index'])
    optional_card = card(document, 'build-pack')
    check('optional unnumbered dashed', '>任意 書き方メモを作る<' in optional_card
          and 'stroke-dasharray' in optional_card and not re.search(r'>\d+\. ', optional_card))
    check('done gate wording', '同梱データ（提供元が確認済み）' in card(document, 'confirm-spec')
          and 'あなたの確認が必要' not in card(document, 'confirm-spec'))
    check('provider json', next(s['detail'] for s in data()['steps'] if s['step_id'] == 'confirm-spec')
          == {'confirmed_by': 'provider'})
    promoted = root / 'input/spec' / sid
    shutil.copytree(str(root / 'specs' / sid), str(promoted))
    promoted_spec = promoted / (sid + '.json')
    promoted_report = promoted / (sid + '.confirmation.json')
    original_bytes = promoted_spec.read_bytes()
    report = json.loads(promoted_report.read_text(encoding='utf-8'))
    report['spec_path'] = str(promoted_spec)
    for case in ('provider', 'applicant', 'changed', 'broken', 'missing'):
        promoted_spec.write_bytes(original_bytes + (b'\n' if case == 'changed' else b''))
        report['confirmed_by'] = 'applicant' if case == 'applicant' else 'provider'
        write(promoted_report, '{' if case == 'broken' else report)
        if case == 'missing':
            promoted_report.unlink()
        result = data()
        detail = next(s['detail'] for s in result['steps'] if s['step_id'] == 'confirm-spec')
        check('promoted provider json ' + case,
              (detail == {'confirmed_by': 'provider'}) == (case == 'provider'))
        run('--phase', 'end')
        check('promoted provider wording ' + case,
              ('同梱データ（提供元が確認済み）' in
               card(output.read_text(encoding='utf-8'), 'confirm-spec')) == (case == 'provider'))
    shutil.rmtree(str(promoted))
    check('diagram lines exact', all(html.escape(line) + '<br>' in document
          for line in run('--phase', 'end', '--no-html').splitlines()[1:3]))
    check('pending gate wording', 'あなたの確認が必要' in current_card)
    visible = ''.join(re.findall(r'<text[^>]*>(.*?)</text>', document))
    check('sentence punctuation', '期限はご自身で確かめてください。' in visible
          and '公式の公募要領です。</p>' in document and '最新になります。</p>' in document
          and '。 ' not in document)

    source_path = root / 'specs' / sid / (sid + '.json')
    source = json.loads(source_path.read_text(encoding='utf-8'))
    from check_spec import evaluate_event_deadline, deadline_remaining_days, parse_now
    for item in source['deliverables']:
        if item.get('produced_by') == 'external':
            check('external name', html.escape(item['name']) in document)
            event = next(e for e in source['schedule'] if e['event_id'] == item['due_event_id'])
            evaluation = evaluate_event_deadline(event, parse_now('2026-11-13'))
            if evaluation:
                check('external days', '残り {} 日'.format(deadline_remaining_days(
                    evaluation.raw_date, parse_now('2026-11-13'))) in document)
    check('application days', '残り 32 日' in document)
    if os.environ.get('PROGRESS_SAMPLE_PATH'):
        sample_path = pathlib.Path(os.environ['PROGRESS_SAMPLE_PATH'])
        sample_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(str(output), str(sample_path))
    original_source = source_path.read_bytes()
    source['name'] = '<制度&名称>'
    write(source_path, source)
    check('invalid pack fallback exact', '任意: /build-pack（書き方メモ）' in run('--phase', 'end').splitlines())
    check('escape spec name', '&lt;制度&amp;名称&gt;' in output.read_text(encoding='utf-8')
          and '<制度&名称>' not in output.read_text(encoding='utf-8'))
    from progress_render import external_cards
    relative_spec = dict(deliverables=[dict(name='外部手続き', produced_by='external',
                         issuer='窓口', due_event_id='relative-test')],
                         schedule=[dict(event_id='relative-test', relative=dict(
                             anchor='交付決定', offset={'value': 30, 'unit': 'day'}, direction='within_after'))])
    check('relative deadline preserved', external_cards(relative_spec, parse_now('2026-11-13'))
          == [['外部手続き', '窓口: 窓口', '交付決定から30日以内']])
    existing = (output.stat().st_mtime_ns, output.read_bytes())
    for options in [('--phase', 'begin'), ('--phase', 'end', '--format', 'json'),
                    ('--phase', 'end', '--no-html'), ('--phase', 'resume', '--no-html')]:
        run(*options)
        check('preserve html ' + str(options), existing == (output.stat().st_mtime_ns, output.read_bytes()))
    source_path.write_bytes(original_source)
    run('--phase', 'end', '--now', '2026-12-16')
    check('expired external', '期限を過ぎています' in output.read_text(encoding='utf-8'))
    with patch('tempfile.NamedTemporaryFile', side_effect=PermissionError('denied')):
        out = io.StringIO()
        with patch.object(sys, 'argv', ['progress', 'show', '--root', str(root), '--phase', 'end']), contextlib.redirect_stdout(out):
            code = progress.main()
        check('unwritable graceful', code == 0 and '現在地:' in out.getvalue()
              and '図: 書き出せませんでした' in out.getvalue())
    state('fit_done')
    current('plan-deliverables')
    state('planned')
    current('plan-deliverables')
    write('input/deliverables.md', '提出物')
    current('draft-section')
    spec_path = root / 'specs' / sid / (sid + '.json')
    spec = json.loads(spec_path.read_text(encoding='utf-8'))
    targets = [(d['deliverable_id'], s['section_id']) for d in spec['deliverables']
               if d.get('produced_by') == 'ai_draftable' for s in d.get('sections', [])
               if not s.get('optional', False)]
    sample = (repo / 'tools/fixtures/drafts/drafts-good/section-1.md').read_text(encoding='utf-8')
    body = sample[sample.index('## 叩き台'):]
    def draft(i, key):
        return write('input/drafts/{}/{}.md'.format(sid, i),
                     '---\ndeliverable_id: {}\nsection_id: {}\n---\n{}'.format(*key, body))
    first = draft(0, targets[0])
    state('drafting')
    current('draft-section')
    detail = next(s['detail'] for s in data()['steps'] if s['step_id'] == 'draft-section')
    draft_line = '現在地: 7/12 計画書の叩き台を作る（/draft-section）・必須セクション 1/7 作成済み'
    suffix = '｜直近の期限 2026-12-04・残り 21 日｜申請締切 2026-12-15 17:00・残り 32 日'
    check('draft header exact', run().splitlines()[0] == draft_line + suffix)
    run('--phase', 'end')
    check('draft diagram count', '>1/7 セクション<' in card(output.read_text(), 'draft-section'))
    check('partial counts', detail['count'] == 1 and detail['total'] == len(targets))
    for i, key in enumerate(targets[1:], 1):
        draft(i, key)
    current('review')
    original_spec = spec_path.read_text(encoding='utf-8')
    spec['deliverables'].append(dict(deliverable_id='conditional', produced_by='ai_draftable',
        required_if=dict(scope='profile', key='extra', op='eq', value=True),
        sections=[dict(section_id='extra')]))
    write(spec_path, spec)
    detail = next(s['detail'] for s in data()['steps'] if s['step_id'] == 'draft-section')
    check('missing profile unknown', detail['unknown'] == 1 and detail['total'] == len(targets))
    saved_first = first.read_text()
    first.unlink()
    expected_unknown = draft_line.replace('1/7', '6/7') + '・判定できないセクション 1' + suffix
    check('unknown count header exact', run().splitlines()[0] == expected_unknown)
    check('unknown count json line', data()['line'] == expected_unknown)
    first.write_text(saved_first)
    write('input/company-profile.json', dict(extra=False))
    check('false condition complete', status('draft-section') == 'done')
    write('input/company-profile.json', dict(extra=True))
    check('true condition incomplete', status('draft-section') == 'current')
    spec['deliverables'][-1]['required_if'] = dict(scope='application', key='extra', op='eq', value=False)
    app['extra'] = True
    state('drafting')
    write(spec_path, spec)
    check('application false condition complete', status('draft-section') == 'done')
    spec_path.write_text(original_spec, encoding='utf-8')
    digest, errors = draft_bodies_sha256(first.parent)
    check('fixture body extraction', not errors)
    def fenced(path, value):
        return write(path, '```json\n' + json.dumps(value) + '\n```\n')
    review = dict(reviewed_at='2026-11-13T12:00:00+09:00',
                  reviewed_draft_bodies_sha256=digest, reviewed_sections=['/'.join(k) for k in targets])
    fenced('input/reviews/all.md', dict(review, reviewed_sections=[]))
    check('partial review stale', status('review') == 'stale')
    fenced('input/reviews/all.md', review)
    current('verify')
    def coverage_hash():
        inputs = {}
        build_section_index(json.loads(spec_path.read_text()), [],
                            progress.predicate.build_contexts(
                                json.loads((root / 'input/company-profile.json').read_text()), app), inputs)
        return coverage_inputs_sha256(inputs)
    report = dict(coverage_inputs_sha256=coverage_hash(), spec_check='green', draft_check='green', draft_bodies_sha256=digest,
                  spec_sha256=hashlib.sha256(spec_path.read_bytes()).hexdigest())
    fenced('input/checks/verify-report.md', report)
    state('verified')
    current('finalize')
    fenced('input/checks/verify-report.md', {k: v for k, v in report.items() if k != 'coverage_inputs_sha256'})
    check('legacy report stale', status('verify') == 'stale')
    for scope, key, before, after in [('profile', 'extra', True, False),
                                       ('application', 'chosen_funding', 'general', 'special')]:
        spec['deliverables'][-1]['required_if'] = dict(scope=scope, key=key, op='eq', value=before)
        write(spec_path, spec)
        app[key] = before
        state('verified')
        write('input/company-profile.json', dict(extra=True))
        fresh = dict(report, coverage_inputs_sha256=coverage_hash(),
                     spec_sha256=hashlib.sha256(spec_path.read_bytes()).hexdigest())
        fenced('input/checks/verify-report.md', fresh)
        check(scope + ' fresh verify', status('verify') == 'done')
        if scope == 'profile':
            write('input/company-profile.json', dict(extra=after))
        else:
            app[key] = after
            state('verified')
        check(scope + ' changed verify stale', status('verify') == 'stale')
        check(scope + ' stale instructions', 'やり直しが必要: /verify' in run('--phase', 'end'))
        check(scope + ' stale reason', next(s['reason'] for s in data()['steps'] if s['step_id'] == 'verify')
              == '検査の後に、必須かどうかの判定に使う会社情報・申請情報が変わっています')
    spec_path.write_text(original_spec, encoding='utf-8')
    fenced('input/checks/verify-report.md', report)
    spec_bytes = spec_path.read_bytes()
    spec_path.write_bytes(spec_bytes + b'\n')
    check('changed spec stale', status('verify') == 'stale')
    spec_path.write_bytes(spec_bytes)
    write('input/checks/verify-report.md', 'broken')
    check('broken report stale', status('verify') == 'stale')
    fenced('input/checks/verify-report.md', report)
    structured = json.loads(run('--phase', 'end', '--command', 'review', '--format', 'json'))
    check('json contract', structured['version'] == 1 and structured['phase'] == 'end'
          and structured['command'] == 'review' and structured['position'] == dict(index=10, total=12)
          and structured['next_commands'] == ['finalize'] and structured['line'].startswith('現在地: ')
          and structured['deadline']['remaining_days'] == 32)
    original = first.read_text(encoding='utf-8')
    first.write_text(original.replace('## 叩き台', '## 叩き台\n変更'), encoding='utf-8')
    check('changed verify stale', status('verify') == 'stale')
    check('stale instructions', 'やり直しが必要: /verify' in run('--phase', 'end'))
    check('stale marker', 'data-step-id="verify" data-status="stale"' in output.read_text(encoding='utf-8'))
    state('finalized')
    check('finalize stale', status('finalize') == 'stale')
    first.write_text(original, encoding='utf-8')
    write('input/final-checklist.md', '本人の確認')
    current('submit')
    first.unlink()
    waived_digest, _ = draft_bodies_sha256(first.parent)
    fenced('input/checks/verify-report.md', dict(report, draft_bodies_sha256=waived_digest))
    fenced('input/reviews/all.md', dict(review, reviewed_draft_bodies_sha256=waived_digest,
                                       reviewed_sections=['/'.join(k) for k in targets[1:]]))
    state('verified')
    current('finalize')
    partial = data()
    step = next(s for s in partial['steps'] if s['step_id'] == 'draft-section')
    check('partial next finalize', partial['next_commands'] == ['finalize'])
    check('partial draft done with reason', step['status'] == 'done' and step['reason'] ==
          '不足のセクションは、最終確認（/finalize）でご自身で別に作るかを確かめます')
    check('partial counts retained', step['detail']['count'] == len(targets) - 1
          and step['detail']['total'] == len(targets))
    review_path = root / 'input/reviews/all.md'
    saved_review = review_path.read_text()
    review_path.unlink()
    current('draft-section')
    review_path.write_text(saved_review)
    state('finalized')
    current('submit')
    check('waived draft done', status('draft-section') == 'done')
    submission = '次にすること: input/final-checklist.md に残っている確認をご自身で済ませたうえで、ご自身で提出します（最終確認の記録は、提出してよいという意味ではありません）。結果が出たら /retrospect'
    check('submission instructions', submission in run('--phase', 'end').splitlines())
    check('submission diagram exact', '<p>' + submission + '<br>' in output.read_text())
    check('submission json', submission in data()['display_lines'])
    broken = write('knowledge/records/z-broken.json', '{broken')
    warning = '注意: 振り返りの記録を読み取れません（z-broken.json）'
    for phase in ('end', 'resume'):
        check('unreadable record exact ' + phase, warning in run('--phase', phase).splitlines())
        check('unreadable record keeps progress ' + phase, data()['current_step'] == 'submit')
    check('unreadable record begin', len(run().splitlines()) == 1)
    check('unreadable record json', data()['warnings'] == [warning])
    write('knowledge/records/result.json', dict(record_id='result', subsidy_id=sid,
                                               spec_version=1, result='pending'))
    check('all complete', data()['current_step'] is None and 'すべての工程が済んでいます' in run())
    check('unreadable after valid record', warning in run('--phase', 'end').splitlines())
    broken.unlink()
    def snapshot():
        return {str(p.relative_to(root)): (p.stat().st_mtime_ns, p.read_bytes())
                for p in root.rglob('*') if p.is_file() and p != output}
    before = snapshot()
    run('--phase', 'end')
    run('--phase', 'resume')
    data()
    check('read only contents paths mtimes', before == snapshot())
    shutil.copytree(str(root / 'specs' / sid), str(root / 'input/spec' / sid))
    run('--phase', 'end')
    local_card = card(output.read_text(), 'confirm-spec')
    check('local confirmation exact', '>あなたが確認する工程<' in local_card
          and next(s['detail'] for s in data()['steps'] if s['step_id'] == 'confirm-spec') is None)
    check('local pack done', status('build-pack') == 'done')
    run('--phase', 'end')
    optional_card = card(output.read_text(encoding='utf-8'), 'build-pack')
    check('optional done unnumbered', '>任意 書き方メモを作る<' in optional_card and '✓ 済み' in optional_card
          and 'stroke-dasharray' not in optional_card and not re.search(r'>\d+\. ', optional_card))
    check('built pack no optional', '任意:' not in run('--phase', 'resume'))
    flow = json.loads((repo / 'templates/progress/command-flow.json').read_text(encoding='utf-8'))
    check('flow contract', flow['version'] == 1 and len(flow['steps']) == 13
          and [lane['lane_id'] for lane in flow['lanes']] == ['owner', 'claude', 'external']
          and [s['step_id'] for s in flow['steps'] if s['human_gate']]
          == ['setup', 'confirm-spec', 'subsidy-fit', 'finalize', 'submit'])
    check('guide commands accepted', all('実行中' in run('--command', c) or 'すべて' in run('--command', c)
                                         for c in flow['guide_commands']))
    setup_path = root / 'input/setup-state.json'
    setup_text = setup_path.read_text(encoding='utf-8')
    setup = json.loads(setup_text)
    setup['terms_sha256'] = '0' * 64
    write(setup_path, setup)
    current('setup')
    check('renewal reason', bool(data()['steps'][0]['reason']))
    for invalid in ('{broken', '[]', '{}'):
        write(setup_path, invalid)
        check('invalid setup', '確認できません' in run())
    setup_path.write_text(setup_text, encoding='utf-8')
    write('input/current-application.json', '{broken')
    check('broken state', '確認できません' in run())
    check('unknown downstream', all(s['status'] == 'unknown' for s in data()['steps'][1:]))
    state('unrecognized')
    check('unknown state', '確認できません' in run())
    write('input/setup-state.json', {})
    check('invalid setup unknown', status('setup') == 'unknown' and '確認できません' in run())
    bad = subprocess.run(['bash', str(repo / 'tools/progress.sh'), 'show', '--phase', 'bad'],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    check('argument error', bad.returncode == 2)
    for target in ('show', 'read_object'):
        for fmt in ('text', 'json'):
            out, err = io.StringIO(), io.StringIO()
            with patch.object(progress, target, side_effect=RuntimeError('broken\ndetail')), \
                 patch.object(sys, 'argv', ['progress', 'show', '--format', fmt]), \
                 contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = progress.main()
            line = json.loads(out.getvalue())['line'] if fmt == 'json' else out.getvalue().strip()
            check('internal error ' + target + fmt, code == 0 and '道具の内部エラー: RuntimeError' in line
                  and len(err.getvalue().splitlines()) == 1 and 'Traceback' not in err.getvalue())
print('=== test-progress: {} pass / {} fail ==='.format(PASS, FAIL))
sys.exit(1 if FAIL else 0)
PY
