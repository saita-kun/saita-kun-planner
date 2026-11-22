"""Page-aware verbatim CLI regressions using temporary fixture specs."""
import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class SpecPagesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = pathlib.Path(self.temp.name)
        self.path = self.directory / "spec.json"
        self.extract = self.directory / "extract.md"
        self.spec = json.loads((ROOT / "tools/fixtures/spec/verbatim-match.json").read_text())
        self.spec["source_documents"][0]["extract_path"] = str(self.extract)
        self.clause = self.spec["clauses"][0]
        self.clause.update(page=9, raw_text="対象となる経費")
        self.extract.write_text("## p.9\n別の説明\n## p.10\n対象となる経費\n", encoding="utf-8")
        confirmation = json.loads((ROOT / "tools/fixtures/spec/verbatim-match.confirmation.json").read_text())
        confirmation["spec_path"] = str(self.path)
        self.path.with_suffix(".confirmation.json").write_text(json.dumps(confirmation))

    def cli(self, expected=0, gate=False, path=None):
        self.path.write_text(json.dumps(self.spec), encoding="utf-8")
        command = ["bash", "tools/check-spec.sh", str(path or self.path)]
        if gate:
            command += ["--gate", "confirm"]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, expected, output)
        return output

    def test_wrong_page_warns_and_confirm_fails(self):
        for gate, code, prefix in [(False, 0, "WARN:"), (True, 1, "FAIL:")]:
            output = self.cli(code, gate)
            self.assertIn(prefix + " clause page mismatch", output)
            self.assertIn("clause-1; declared page 9; found pages 10", output)
            self.assertIn("1 page mismatched", output)
        self.clause["page"] = 10
        self.assertIn("0 page mismatched", self.cli(gate=True))

    def test_cross_page_clause(self):
        self.extract.write_text("## p.9\n対象となる\n## p.10\n経費\n", encoding="utf-8")
        self.assertIn("1/1 matched", self.cli(gate=True))
        self.assertIn("0 page mismatched", self.cli(gate=True))
        self.clause["page"] = 10
        self.assertIn("declared page 10; found pages 9", self.cli(1, True))

    def test_nonconsecutive_pages_do_not_join(self):
        self.extract.write_text("## p.9\n対象となる\n## p.11\n経費\n", encoding="utf-8")
        self.clause["raw_text"] += "のみ"
        self.assertIn("clause verbatim mismatch", self.cli(1, True))

    def test_three_page_clause_matches_start_page(self):
        self.extract.write_text("## p.9\n対象と\n## p.10\nなる\n## p.11\n経費\n", encoding="utf-8")
        output = self.cli(gate=True)
        self.assertIn("1/1 matched", output)
        self.assertIn("0 page mismatched", output)
        self.assertNotIn("clause verbatim mismatch", output)

    def test_three_page_clause_rejects_middle_page(self):
        self.extract.write_text("## p.9\n対象と\n## p.10\nなる\n## p.11\n経費\n", encoding="utf-8")
        self.clause["page"] = 10
        output = self.cli(1, True)
        self.assertIn("clause page mismatch (ページ不一致)", output)
        self.assertIn("declared page 10; found pages 9", output)
        self.assertIn("1/1 matched", output)
        self.assertIn("1 page mismatched", output)

    def test_nonconsecutive_pages_keep_whole_text_matching(self):
        self.extract.write_text("## p.9\n対象となる\n## p.11\n経費\n", encoding="utf-8")
        for page in (9, 11):
            for gate in (False, True):
                with self.subTest(page=page, gate=gate):
                    self.clause["page"] = page
                    output = self.cli(gate=gate)
                    self.assertIn("1/1 matched", output)
                    self.assertIn("0 page mismatched", output)
                    self.assertNotIn("clause page mismatch", output)
                    self.assertNotIn("clause verbatim mismatch", output)

    def test_null_page_and_unanchored_extract_keep_whole_text_matching(self):
        self.clause["page"] = None
        self.assertIn("0 page mismatched", self.cli(gate=True))
        self.clause["page"] = 9
        self.extract.write_text("対象となる経費", encoding="utf-8")
        self.assertIn("1/1 matched", self.cli(gate=True))

    def test_missing_declared_anchor(self):
        self.clause["page"] = 99
        self.assertIn("declared page 99; found pages 10", self.cli(1, True))

    def test_repeated_text_on_declared_page(self):
        self.extract.write_text("## p.9\n対象となる経費\n## p.10\n対象となる経費\n", encoding="utf-8")
        self.clause["page"] = 10
        self.assertIn("0 page mismatched", self.cli(gate=True))

    def test_bundled_and_example_specs(self):
        paths = [ROOT / "specs/jizokuka-20/jizokuka-20.json"]
        for path in (ROOT / "examples").rglob("*.json"):
            data = json.loads(path.read_text())
            if "clauses" in data and "source_documents" in data:
                paths.append(path)
        self.assertGreater(len(paths), 1)
        for path in paths:
            with self.subTest(path=path):
                output = self.cli(path=path)
                self.assertIn("0 page mismatched", output)
                self.assertNotIn("clause page mismatch", output)


if __name__ == "__main__":
    unittest.main()
