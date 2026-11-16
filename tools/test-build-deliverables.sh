#!/bin/bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${PLANNER_PYTHON:-python3}" -B - "$ROOT" <<'PY'
import copy
import datetime
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(source / 'tools/lib'))
import build_deliverables as build
from schedule import relative_deadline_text

spec_path = source / 'specs/jizokuka-20/jizokuka-20.json'
spec = json.loads(spec_path.read_text())
now = datetime.datetime(2026, 11, 14, tzinfo=build.check_spec.JST)
app = dict(subsidy_id=spec['subsidy_id'], spec_version=spec['spec_version'],
           spec_path=str(spec_path), chosen_funding=None, state='fit_done')
expr = dict(scope='profile', key='flag', op='eq', value=True)
item = copy.deepcopy(spec['deliverables'][0])
for required in (True, False):
    item.update(required=required, required_if=expr)
    for flag, result in [(True, 'true'), (False, 'false'), (None, 'unknown')]:
        assert build.classification(item, build.predicate.build_contexts({'flag': flag}, app))[0] == result
    item['required_if'] = None
    assert build.classification(item, build.predicate.build_contexts({}, app))[0] == ('required' if required else 'natural')
item['required_if'] = dict(scope='application', key='chosen_funding.base', op='eq', value='base')
fixture = copy.deepcopy(spec)
fixture['deliverables'] = [item]
body = build.render(fixture, app, {}, 'fixture.json', 'digest', now)
assert '判定 UNKNOWN' in body and '特例を使う場合に必要になるもの' in body
assert all(s['section_id'] in body for s in item['sections'])
item['required_if'] = expr
for flag, label in [(True, '必須・条件付き（判定 TRUE）'), (False, '該当なし（判定 FALSE）'), (None, '判定 UNKNOWN')]:
    assert label in build.render(fixture, app, {'flag': flag}, 'fixture.json', 'digest', now)
item.update(required=False, required_if=None)
assert '自然文のみ・機械評価なし' in build.render(fixture, app, {}, 'fixture.json', 'digest', now)
item['due_event_id'] = None
assert '期限未設定 [要確認]: 公式の公募要領で確認' in build.render(fixture, app, {}, 'fixture.json', 'digest', now)
assert '残り1日' in build.deadline(dict(date='2026-11-15', time='17:00', hard=True), now)
assert '期限切れ' in build.deadline(dict(date='2026-11-13'), now)
assert build.cell('a|b\nc') == 'a&#124;b c'
assert build.cell('  日本語  \n  の条件\n\nです。 ') == '日本語の条件です。'
assert build.cell(' 条件  A\n B\t\tC\n 日本語\n 2 ') == '条件 A B C 日本語 2'
assert build.cell('条件（\n 原文） & <x>') == '条件（原文） &amp; &lt;x&gt;'
assert build.CHECK == '未記載 [要確認]'
assert '「未記載 [要確認]」は、公募要領から読み取れなかった項目です。' in body
assert build.deadline(dict(name='後日発表', timezone='Asia/Tokyo'), now) == '日付は未定（後日発表）[要確認]'
assert 'Asia/Tokyo' in build.deadline(dict(date='2026-11-15', timezone='Asia/Tokyo'), now)

# Summaries reuse deadline evaluation, include unknown conditions, and omit false ones.
summary_spec = copy.deepcopy(fixture)
summary_spec['schedule'] = [dict(event_id=k, date=date, time=time) for k, date, time in
                            [('late', '2026-11-15', '17:00'), ('early', '2026-11-13', None)]]
summary_spec['schedule'] += [dict(event_id='unknown', name='後日発表', timezone='Asia/Tokyo'),
                            dict(event_id='relative', relative=dict(anchor='通知日', offset=None, direction=None))]
summary_spec['deliverables'] = [dict(item, name=name, due_event_id=event, required_if=condition)
                               for name, event, condition in [('後の期限', 'late', None),
                               ('前の期限', 'early', expr), ('日付不明', 'unknown', None),
                               ('期限未設定', None, None), ('相対期限', 'relative', None),
                               ('除外する期限', 'late', dict(expr, value=False)),
                               ('除外する未設定', None, dict(expr, value=False))]]
summary = build.render(summary_spec, app, {'flag': True}, 'fixture.json', 'digest', now)
summary = summary.split('## 先に確かめること\n')[1].split('## AIと作る成果物')[0]
assert summary.index('- 2026-11-13 ／ 期限切れ ／ 前の期限') < summary.index('- 2026-11-15 17:00 ／ 残り 1 日 ／ 後の期限')
assert '- 日付不明\n' in summary and '- 期限未設定\n' in summary
assert '相対期限' not in summary and '除外する' not in summary
summary_spec['deliverables'] = []
empty = build.render(summary_spec, app, {}, 'fixture.json', 'digest', now)
assert '### 日付の決まっている期限\n\n該当なし' in empty
assert '### 期限がまだ分からないもの\n\n該当なし' in empty
assert build.cell(['a|b', 'c']) == 'a&#124;b、c'
assert build.cell([]) == 'なし'
assert build.cell({'base': 'a', 'addon_ids': ['b', 'c']}) == '（addon_ids：b、c、base：a）'
assert build.cell({'all': [expr]}) == '（all：（key：flag、op：eq、scope：profile、value：true））'
assert build.cell(None) == build.CHECK
assert build.cell(True) == 'true'
assert '{"' not in body

with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    (root / 'input').mkdir()
    current = root / 'input/current-application.json'
    profile = root / 'input/company-profile.json'
    notes = root / 'input/deliverables-notes.md'
    output = root / 'input/deliverables.md'
    current.write_text(json.dumps(app), encoding='utf-8')
    profile.write_text('{}', encoding='utf-8')
    notes.write_text('Applicant notes\n', encoding='utf-8')
    def snapshot():
        return {str(p): (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mtime_ns) for p in root.rglob('*') if p.is_file() and p != output}
    def run(*extra):
        return subprocess.run(['bash', str(source / 'tools/build-deliverables.sh'), '--root', str(root), '--now', '2026-11-14'] + list(extra), stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding='utf-8')
    before = snapshot()
    result = run()
    assert result.returncode == 0, result.stderr
    assert result.stdout == 'OK: deliverables written: input/deliverables.md\n'
    body = output.read_text(encoding='utf-8')
    for d in spec['deliverables']:
        assert d['deliverable_id'] in body
        event = next((e for e in spec['schedule'] if e['event_id'] == d.get('due_event_id')), None)
        assert build.cell(build.deadline(event, now)) in body
    assert '{"' not in body
    calendar = body.split('## 締切カレンダー\n', 1)[1].split('\n## ', 1)[0]
    for event in spec['schedule']:
        row = next(line for line in calendar.splitlines() if line.startswith('| ' + event['event_id'] + ' |'))
        relative_cell = row.split(' | ')[7]
        assert relative_cell == build.cell(relative_deadline_text(event))
        assert event['event_id'] in body
        if event.get('relative'):
            assert '{' not in row and '}' not in row
            assert relative_deadline_text(event) in relative_cell
            assert relative_deadline_text(event) in body
            assert "（基準になる日が決まった後に、公式の案内で日付を確認 [要確認]）" in body
            assert "anchor" not in build.deadline(event, now)
    assert hashlib.sha256(spec_path.read_bytes()).hexdigest() in body
    assert run().returncode == 0 and output.read_text(encoding='utf-8') == body
    assert run('--output', '-').stdout == body
    assert snapshot() == before
    assert run('--output', 'input/deliverables-notes.md').returncode == 2
    assert run('--now', 'invalid').returncode == 2
    assert run('--output', 'input/company-profile.json').returncode == 2
    assert run('--profile', 'missing.json').returncode == 2
    app['spec_version'] += 1
    current.write_text(json.dumps(app), encoding='utf-8')
    assert run().returncode == 2
    app['spec_version'] -= 1
    altered = root / 'fixture.json'
    app['spec_path'] = str(altered)
    current.write_text(json.dumps(app), encoding='utf-8')
    for status, broken, expected in [('draft', False, 1), ('confirmed', True, 2), ('confirmed', False, 1)]:
        changed = copy.deepcopy(spec)
        changed['status'] = status
        if broken:
            changed['deliverables'][0]['due_event_id'] = 'missing-event'
        altered.write_text(json.dumps(changed), encoding='utf-8')
        assert run().returncode == expected
        assert output.read_text(encoding='utf-8') == body
    assert notes.read_text(encoding='utf-8') == 'Applicant notes\n'
print('PASS: deliverables classification, deadlines, CLI failures, deterministic output and write isolation')
PY
