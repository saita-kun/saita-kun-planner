#!/usr/bin/env python3
"""Regressions for specs without bundled subsidy assumptions."""
import copy
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/lib'))
import build_submission
import check_spec


class GeneralSubsidies(unittest.TestCase):
    def test_optional_industry(self):
        schema = json.loads((ROOT / 'schemas/company-profile.schema.json').read_text())
        self.assertNotIn('industry_class', schema['required'])
        self.assertIn('industry_class', schema['properties'])

    def test_extension_info(self):
        spec = json.loads((ROOT / 'specs/jizokuka-20/jizokuka-20.json').read_text())
        keys = ['extension_{:02d}'.format(i) for i in range(12)]
        for i, rule in enumerate(spec['eligibility']['rules'][:2]):
            rule['predicate'] = {'all': [
                {'scope': 'profile', 'key': key, 'op': 'eq', 'value': True}
                for key in keys]}
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / 'spec.json'
            path.write_text(json.dumps(spec))
            errors, warnings, lines = check_spec.check_spec(path)
            info = [line for line in lines if line.startswith('INFO: この spec')]
            self.assertEqual(len(info), 1)
            self.assertIn('12 件', info[0])
            self.assertIn('/intake', info[0])
            self.assertEqual(info[0].split(': ')[-1].split(', '), keys)
            self.assertFalse(any('predicate references undeclared profile key' in w for w in warnings))

    def test_funding_and_cli(self):
        funding = {
            'base_award': {'name': '基本', 'max_amount': 120, 'subsidy_rate': 0.5,
                           'source_clauses': ['base-source']},
            'add_ons': [
                {'addon_id': 'selected', 'max_amount_delta': 20, 'rate_override': 0.75,
                 'source_clauses': ['addon-source']},
                {'addon_id': 'other', 'max_amount_delta': 999}],
            'eligible_expenses': [],
        }
        spec = {'subsidy_id': 'example', 'funding': funding}
        chosen = {'base': True, 'addon_ids': ['selected']}
        document = build_submission.render(spec, {}, 'hash', [], chosen)
        self.assertIn('全体の上限額: 120 万円 / 補助率: 0.5（根拠: base-source）', document)
        self.assertIn('上乗せ額: 20 万円 / 補助率の置き換え: 0.75（根拠: addon-source）', document)
        self.assertNotIn('999', document)
        empty = build_submission.render({'funding': {}}, {}, 'hash', [], chosen)
        self.assertIn('全体の上限額: 読み取ったデータにありません / 補助率: 読み取ったデータにありません', empty)
        self.assertIn('上乗せ額: 読み取ったデータにありません', empty)
        self.assertIn('枠選択が未確認', build_submission.render(spec, {}, 'hash', []))
        combined = copy.deepcopy(funding)
        combined['combinations'] = [{'addon_ids': ['selected', 'other'],
                                     'max_amount_total': 200, 'source_clauses': ['combo-source']}]
        lines = build_submission.funding_lines(combined, {'base': True, 'addon_ids': ['other', 'selected']})
        self.assertIn('併用時の上限総額: 200 万円（根拠: combo-source）', '\n'.join(lines))
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / 'drafts').mkdir()
            (root / 'spec.json').write_text(json.dumps(spec))
            app = root / 'application.json'
            app.write_text(json.dumps({'subsidy_id': 'example', 'chosen_funding': chosen}))
            command = [sys.executable, str(ROOT / 'tools/lib/build_submission.py'),
                       str(root / 'spec.json'), str(root / 'drafts'),
                       '--current-application', str(app), '--output', '-']
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('全体の上限額: 120 万円', result.stdout)
            app.write_text(json.dumps({'subsidy_id': 'different', 'chosen_funding': chosen}))
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('does not match spec', result.stdout)

    def test_submission_wording(self):
        checklist = (ROOT / '.claude/commands/finalize.md').read_text()
        document = build_submission.render({}, {}, 'hash', [])
        fixture = json.loads((ROOT / 'specs/jizokuka-20/jizokuka-20.json').read_text())
        spec = {
            'funding': fixture['funding'],
            'deliverables': [{
                'deliverable_id': 'plan',
                'name': '事業計画',
                'phase': 'application',
                'sections': fixture['deliverables'][0]['sections'],
            }],
        }
        chosen = {'base': True, 'addon_ids': [fixture['funding']['add_ons'][0]['addon_id']]}
        populated = build_submission.render(spec, {}, 'hash', [], chosen)
        for text in (checklist, document, populated):
            self.assertNotIn('貼り付け', text)
            self.assertNotIn('必要アカウント', text)
            self.assertNotIn('申請システム', text)
        for text in (document, populated):
            self.assertNotIn('電子申請', text)
        for line in checklist.splitlines():
            if '電子申請' in line:
                self.assertIn('郵送', line)
        self.assertIn('様式・申請画面に書き写す本文', document)
        self.assertIn('電子申請・郵送・持参・メール', checklist)
        self.assertIn('アカウント・押印・部数', checklist)


if __name__ == '__main__':
    unittest.main()
