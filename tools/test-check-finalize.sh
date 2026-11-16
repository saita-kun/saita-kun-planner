#!/bin/bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source tools/lib/python-resolver.sh
planner_resolve_python "$ROOT/input/.planner-python"
"${PLANNER_PY[@]}" - <<'PY'
import hashlib, json, os, pathlib, shutil, subprocess, sys, tempfile, unittest
import contextlib, io
from unittest.mock import patch
sys.path.insert(0, str(pathlib.Path('tools/lib').resolve()))
from check_drafts import check_drafts, draft_bodies_sha256
import check_finalize
ROOT = pathlib.Path.cwd()

class FinalizeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        self.input = self.root / 'input'
        self.drafts = self.input / 'drafts/fixture-good'
        shutil.copytree(ROOT / 'tools/fixtures/drafts/drafts-good', self.drafts)
        (self.input / 'checks').mkdir()
        (self.input / 'reviews').mkdir()
        self.spec = str(ROOT / 'tools/fixtures/spec/good-spec.json')
        self.app = self.input / 'current-application.json'
        self.app.write_text(json.dumps(dict(subsidy_id='fixture-good', spec_path=self.spec, spec_version=1, state='verified')))
        (self.input / 'company-profile.json').write_text('{}')
        self.saved = dict(spec_check='green', draft_check='green', spec_path=self.spec, spec_version=1,
                          spec_sha256=hashlib.sha256(pathlib.Path(self.spec).read_bytes()).hexdigest(),
                          draft_hash_algorithm='fixture', generated_at='2026-11-14T00:00:00+09:00')
        self.refresh()

    def refresh(self):
        self.saved['draft_bodies_sha256'] = draft_bodies_sha256(self.drafts)[0]
        self.saved['coverage_inputs_sha256'] = check_drafts(pathlib.Path(self.spec), self.drafts,
            self.input / 'company-profile.json', self.app)[2]['coverage_inputs_sha256']
        self.save()
        self.review('all', ['section-1', 'section-2'])

    def save(self):
        (self.input / 'checks/verify-report.md').write_text('```json\n'+json.dumps(self.saved)+'\n```\n', encoding='utf-8')

    def review(self, name, sections, quote='Fixture clause text.'):
        record = dict(reviewed_draft_bodies_sha256=self.saved['draft_bodies_sha256'],
                      reviewed_sections=['deliverable-1/'+s for s in sections], reviewed_at='2026-11-14T00:00:00+09:00')
        (self.input / ('reviews/'+name+'.md')).write_text('```json\n'+json.dumps(record)+
            '\n```\n| clause_id | quoted_text |\n| --- | --- |\n| clause-1 | '+quote+' |\n', encoding='utf-8')

    def run_cli(self, expected=0, *args):
        before = self.app.read_bytes() if self.app.exists() else None
        result = subprocess.run(['bash', str(ROOT / 'tools/check-finalize.sh'), '--root', str(self.root), *args],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
        self.assertEqual(result.returncode, expected, result.stdout)
        if expected:
            self.assertNotIn(": :", result.stdout)
        if '--record-finalized' not in args or expected:
            self.assertEqual(self.app.read_bytes() if self.app.exists() else None, before)
        return result.stdout

    def test_pass_and_checklist(self):
        output = self.run_cli()
        self.assertIn("checklist: spec_check=green\n", output)
        keys = 'verify_report_path spec_check draft_check spec_path spec_version spec_sha256 actual_spec_sha256 spec_recheck_exit_code review_path reviewed_draft_bodies_sha256 review_record_exit_code review_quotes_exit_code draft_bodies_sha256 actual_draft_bodies_sha256 coverage_inputs_sha256 actual_coverage_inputs_sha256 coverage_recheck_exit_code spec_hash_match draft_hash_match coverage_hash_match generated_at state_before waived_sections'.split()
        for key in keys:
            self.assertIn('checklist: '+key+'=', output)
        data = json.loads(self.run_cli(0, '--format', 'json'))
        self.assertEqual([g['status'] for g in data['gates']], ['PASS']*5)
        self.assertIn('[要確認]', output)
        info = [line for line in output.splitlines() if line.startswith('INFO:')]
        self.assertTrue(info)
        self.assertEqual(len(info), len(set(info)))

    def test_only_identical_info_is_suppressed(self):
        evidence = ['INFO: repeated', 'INFO: different', 'FAIL: repeated', 'WARN: repeated', 'ERROR: repeated']
        report = dict(gates=[dict(id='fixture', status='PASS', reason='', evidence=evidence)] * 2,
                      checklist_values={'fixture': True})
        for mode in ('text', 'json'):
            output = io.StringIO()
            with patch.object(check_finalize, 'run', return_value=(1, report)), \
                    patch.object(sys, 'argv', ['check-finalize', '--root', str(ROOT), '--format', mode]), \
                    contextlib.redirect_stdout(output):
                self.assertEqual(check_finalize.main(), 1)
            if mode == 'json':
                self.assertEqual(json.loads(output.getvalue()), report)
            else:
                lines = output.getvalue().splitlines()
                for line in evidence:
                    self.assertEqual(lines.count(line), 1 if line.startswith('INFO:') else 2)
                self.assertEqual(lines.count('PASS: fixture'), 2)
                self.assertEqual(lines.count('checklist: fixture=true'), 1)

    def test_report_and_spec_failures(self):
        original = dict(self.saved)
        for key, value, gate in [('draft_check','fail',0), ('spec_check','fail',0), ('spec_sha256','0'*64,1),
                                 ('spec_version',2,1), ('spec_path','missing',1), ('coverage_inputs_sha256',None,3)]:
            self.saved = dict(original, **{key:value}); self.save()
            data = json.loads(self.run_cli(1, '--format', 'json'))
            self.assertEqual(data['gates'][gate]['status'], 'FAIL')
            self.assertTrue(data['gates'][gate]['reason'].endswith(': /verify を再実行してください'))
            self.assertTrue(all(g['status']=='BLOCKED' for g in data['gates'][gate+1:]))
        self.saved = dict(original); self.saved.pop('coverage_inputs_sha256'); self.save()
        self.run_cli(1)
        (self.input / 'checks/verify-report.md').unlink()
        self.run_cli(1)
        self.app.unlink()
        output = self.run_cli(2)
        self.assertIn('FAIL: verify_report: 状態ファイル（input/current-application.json）がありません: /select-subsidy または /ingest-guidelines\n', output)
        self.assertNotIn('/verify を再実行', output)
        self.assertNotIn('[Errno', output)

    def test_unverified_state(self):
        app = json.loads(self.app.read_text()); app['state'] = 'planned'
        self.app.write_text(json.dumps(app))
        output = self.run_cli(1)
        self.assertIn('FAIL: verify_report: 先に /review と /verify を済ませてください（現在の状態: planned）\n', output)
        self.assertNotIn('/verify を再実行', output)
        self.assertNotIn('/confirm-spec', output)

    def test_draft_and_coverage(self):
        path = self.drafts / 'section-1.md'
        path.write_text(path.read_text(encoding='utf-8').replace('## 叩き台', '## 叩き台\n字'), encoding='utf-8')
        output = self.run_cli(1)
        self.assertIn('BLOCKED: coverage', output)
        self.assertIn(': /verify を再実行してください\n', output)
        path.unlink(); self.refresh()
        output = self.run_cli(1)
        self.assertIn('FAIL: coverage: 必須 draft の欠落は /draft-section', output)
        self.assertNotIn('/verify を再実行', output)
        self.run_cli(0, '--waive', 'deliverable-1/section-1')
        self.run_cli(1, '--waive', 'deliverable-1/section-2')
        (self.drafts / 'section-2.md').unlink(); self.refresh()
        output = self.run_cli(1, '--waive', 'deliverable-1/section-1', '--waive', 'deliverable-1/section-2')
        self.assertIn('draft 0 件なら /plan-deliverables を使ってください\n', output)
        self.assertNotIn('/verify を再実行', output)

    def test_reviews(self):
        (self.input / 'reviews/all.md').unlink(); self.run_cli(1)
        self.review('a', ['section-1']); self.run_cli(1)
        self.review('b', ['section-2']); self.run_cli(1)
        self.review('a', ['section-1','section-2'], 'fabricated'); self.run_cli(1)
        self.review('z', ['section-1','section-2'])
        self.assertIn('input/reviews/z.md', self.run_cli())

    def test_spec_recheck_and_custom_inputs(self):
        custom_app = self.input / 'custom-application.json'
        custom_profile = self.input / 'custom-profile.json'
        shutil.copyfile(self.app, custom_app)
        custom_profile.write_text('{}')
        options = ('--current-application', str(custom_app), '--profile', str(custom_profile))
        self.run_cli(0, *options)
        custom_profile.write_text('{')
        self.assertIn('FAIL: coverage', self.run_cli(1, *options))
        custom_profile.write_text('{}')
        broken_spec = self.root / 'broken-spec.json'
        broken_spec.write_text('{}')
        app = json.loads(custom_app.read_text()); app['spec_path'] = str(broken_spec)
        custom_app.write_text(json.dumps(app))
        self.saved.update(spec_path=str(broken_spec), spec_sha256=hashlib.sha256(broken_spec.read_bytes()).hexdigest())
        self.save()
        data = json.loads(self.run_cli(1, *options, '--format', 'json'))
        self.assertEqual(data['checklist_values']['spec_recheck_exit_code'], 1)
        self.assertEqual(data['gates'][2]['status'], 'BLOCKED')

    def test_execution_errors(self):
        self.run_cli(2, '--format', 'invalid')
        self.app.write_text('{')
        self.assertIn('状態ファイル（input/current-application.json）を JSON として読めません: /select-subsidy または /ingest-guidelines\n', self.run_cli(2))
        result = subprocess.run(['bash', str(ROOT / 'tools/check-finalize.sh')],
            env=dict(os.environ, PLANNER_PYTHON=str(self.root / 'missing-python')),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 2)

    def test_record(self):
        self.run_cli(1, '--record-finalized')
        for name, other in [('final-checklist.md','submission-summary.md'), ('submission-summary.md','final-checklist.md')]:
            (self.input / name).write_text('fixture')
            self.run_cli(1, '--record-finalized')
            (self.input / name).unlink()
        for name in ('final-checklist.md','submission-summary.md'):
            (self.input / name).write_text('fixture')
        self.run_cli(0, '--record-finalized')
        app = json.loads(self.app.read_text())
        self.assertEqual(app['state'], 'finalized')
        self.assertEqual(app['finalized_at'], app['updated_at'])
        self.saved['draft_check']='fail'; self.save(); self.run_cli(1, '--record-finalized')

unittest.main(verbosity=2)
PY
