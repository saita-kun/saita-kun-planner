#!/bin/bash
set -u

# The good fixture intentionally includes a draft whose frontmatter and preamble
# exceed the section's max_chars=30 limit. Its counted body is short enough, and
# a follow-up "## " section after the draft body must not be counted. The good
# spec also has an optional section with no draft; that must not emit a WARN.
# The partial fixture proves required ai_draftable coverage gaps remain WARNs.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
SPEC="tools/fixtures/spec/good-spec.json"

pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

assert_check_drafts_passes() {
  local dir="$1"
  local output
  if output=$(bash tools/check-drafts.sh "$SPEC" "$dir" 2>&1); then
    if printf '%s\n' "$output" | grep -q '^FAIL:'; then
      fail "check-drafts emitted FAIL while passing: $dir :: $output"
    elif printf '%s\n' "$output" | grep -q '^WARN:'; then
      fail "check-drafts emitted unexpected WARN while passing: $dir :: $output"
    elif ! printf '%s\n' "$output" | grep -q '^OK:'; then
      fail "check-drafts passing output should include OK: $dir :: $output"
    else
      pass
    fi
  else
    fail "check-drafts should pass: $dir :: $output"
  fi
}

assert_check_drafts_fails() {
  local dir="$1"
  local output status
  output=$(bash tools/check-drafts.sh "$SPEC" "$dir" 2>&1)
  status=$?
  if [ "$status" -eq 0 ]; then
    fail "check-drafts should fail: $dir :: $output"
    return
  fi
  if printf '%s\n' "$output" | grep -q '^FAIL:'; then
    pass
  else
    fail "check-drafts failure should include a FAIL line: $dir :: $output"
  fi
}

assert_check_drafts_warns_without_failing() {
  local dir="$1"
  local output status
  output=$(bash tools/check-drafts.sh "$SPEC" "$dir" 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    fail "check-drafts should not fail on coverage WARN: $dir :: $output"
    return
  fi
  if printf '%s\n' "$output" | grep -q '^WARN:'; then
    pass
  else
    fail "check-drafts should emit WARN for partial coverage: $dir :: $output"
  fi
}

assert_duplicate_drafts_fail_with_both_paths() {
  local dir="tools/fixtures/drafts/drafts-duplicate"
  local first_path="$dir/section-1-duplicate.md"
  local second_path="$dir/section-1.md"
  local expected="duplicate draft for deliverable-1/section-1"
  local output status
  output=$(bash tools/check-drafts.sh "$SPEC" "$dir" 2>&1)
  status=$?
  if [ "$status" -eq 0 ]; then
    fail "duplicate drafts should fail: $dir :: $output"
    return
  fi
  if printf '%s\n' "$output" | grep -qF -- "FAIL: $expected" &&
     printf '%s\n' "$output" | grep -qF -- "$first_path" &&
     printf '%s\n' "$output" | grep -qF -- "$second_path"; then
    pass
  else
    fail "duplicate drafts failure should include both paths: $dir :: $output"
  fi
}

assert_check_drafts_passes "tools/fixtures/drafts/drafts-good"

for broken_dir in \
  tools/fixtures/drafts/drafts-overflow \
  tools/fixtures/drafts/drafts-no-frontmatter \
  tools/fixtures/drafts/drafts-unknown-ids \
  tools/fixtures/drafts/drafts-no-heading; do
  assert_check_drafts_fails "$broken_dir"
done

assert_check_drafts_warns_without_failing "tools/fixtures/drafts/drafts-partial"
assert_duplicate_drafts_fail_with_both_paths

test_tane01_draft_pack_roots() {
  local case_dir root_value output status
  case_dir=$(mktemp -d "${TMPDIR:-/tmp}/check-drafts-tane01.XXXXXX") || exit 1
  for root_value in 'null' '[]' 'true' '"text"'; do
    printf '%s\n' "$root_value" > "$case_dir/spec.json"
    output=$(bash tools/check-drafts.sh "$case_dir/spec.json" tools/fixtures/drafts/drafts-good 2>&1)
    status=$?
    if [ "$status" -eq 1 ] &&
       printf '%s\n' "$output" | grep -qF 'FAIL: spec root must be an object'; then
      pass
    else
      fail "tane01 draft spec root $root_value must exit 1 with root diagnostic :: $output"
    fi
  done
  rm -rf -- "$case_dir"
}

test_tane01_draft_pack_roots
if python3 - <<'PY'
import copy
import hashlib
import shlex
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path("tools/lib").resolve()))
from check_drafts import build_section_index, draft_bodies_sha256


class DraftInfoTests(unittest.TestCase):
    def test_bare_need_check_locations(self):
        import shutil
        with tempfile.TemporaryDirectory() as temporary:
            drafts = pathlib.Path(temporary) / 'drafts'
            shutil.copytree('tools/fixtures/drafts/drafts-good', drafts)
            path = sorted(drafts.glob('*.md'))[0]
            original = path.read_text()
            number = len(original.splitlines()) + 1
            path.write_text(original.rstrip('\n') + '\n要確認と要確認 [要確認]\n')
            result = subprocess.run(['bash', 'tools/check-drafts.sh',
                'tools/fixtures/spec/good-spec.json', str(drafts)],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn('INFO: bare 要確認 total: 2', result.stdout)
            self.assertIn(f'INFO: bare 要確認: {path}:{number}', result.stdout)

    def test_body_counts_and_chars_match_submission(self):
        from build_submission import collect_drafts, render
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            spec = {"deliverables": [{"deliverable_id": "plan", "produced_by": "ai_draftable",
                    "required": True, "sections": [{"section_id": "clean", "max_chars": 3},
                    {"section_id": "marked", "max_chars": 100}]}]}
            spec_path = root / "spec.json"
            spec_path.write_text(json.dumps(spec), encoding="utf-8")
            for section, body in [("clean", " ＡＢ\n C "), ("marked", "[要確認]案[要確認]")]:
                (root / (section + ".md")).write_text(
                    "---\ndeliverable_id: plan\nsection_id: " + section + "\n---\n"
                    "未確認事項: `[要確認]` を参照\n## 叩き台\n" + body +
                    "\n## `[要確認]` リスト\n", encoding="utf-8")
            result = subprocess.run(["bash", "tools/check-drafts.sh", str(spec_path), str(root)],
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            self.assertEqual(result.returncode, 0, result.stdout)
            for line in ["[要確認] total: 6", "[要確認] in draft bodies: 2",
                         "[要確認] in draft body: plan/clean 0",
                         "[要確認] in draft body: plan/marked 2",
                         "chars: plan/clean 3/3", "chars: plan/marked 11/100"]:
                self.assertIn("INFO: " + line, result.stdout.splitlines())
            errors = []
            drafts = collect_drafts(root, errors)
            self.assertEqual(errors, [])
            self.assertEqual([drafts[("plan", key)].need_check_count for key in ("clean", "marked")], [0, 2])
            rendered = render(spec, drafts, draft_bodies_sha256(root)[0], [])
            self.assertEqual(rendered.count("[要確認] が 2 か所残っています。"), 1)
            self.assertNotIn("[要確認] が 0 か所", rendered)

    def test_info_additions_preserve_exit_codes_and_hashes(self):
        from check_drafts import check_drafts
        # Snapshots taken before the INFO additions, including FAIL and WARN cases.
        snapshots = [
            ("drafts-good", 0, "b923d20c76a169db3de2385ee16c0cc00a0bcdb2542a1cf0fdcc581cfccc38ec"),
            ("drafts-overflow", 1, "13a0b73b35d2993442e6f8683b9c08509ac5af37e9692c7ec3f7227dc4ee9bce"),
            ("drafts-partial", 0, "02382ca2d1e895a18d02728900f3a364d8e2eaa8eeaec53a557a480341cb13d3"),
        ]
        spec = pathlib.Path("tools/fixtures/spec/good-spec.json")
        for name, status, digest in snapshots:
            with self.subTest(fixture=name):
                drafts = pathlib.Path("tools/fixtures/drafts") / name
                result = subprocess.run(["bash", "tools/check-drafts.sh", str(spec), str(drafts)],
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                self.assertEqual(result.returncode, status, result.stdout)
                self.assertEqual(draft_bodies_sha256(drafts), (digest, []))
                self.assertEqual(check_drafts(spec, drafts)[2]["coverage_inputs_sha256"],
                                 "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945")


class SectionDefinitionTests(unittest.TestCase):
    def setUp(self):
        self.spec = json.loads(pathlib.Path("tools/fixtures/spec/good-spec.json").read_text(encoding="utf-8"))
        self.spec["status"] = "draft"
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)

    def run_check(self, drafts_dir):
        path = self.root / "spec.json"
        path.write_text(json.dumps(self.spec), encoding="utf-8")
        return subprocess.run(
            ["bash", "tools/check-drafts.sh", str(path), str(drafts_dir)],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )

    def test_tane04_duplicate_section_definition(self):
        sections = self.spec["deliverables"][0]["sections"]
        sections.append(dict(sections[1], max_chars=10000))
        result = self.run_check("tools/fixtures/drafts/drafts-good")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("FAIL: duplicate section_id: deliverable-1/section-2", result.stdout)

    def test_tane04_preserve_first_definition(self):
        sections = self.spec["deliverables"][0]["sections"]
        sections.append(dict(sections[1], max_chars=10000))
        errors = []
        index, _ = build_section_index(self.spec, errors)
        self.assertEqual(index[("deliverable-1", "section-2")]["max_chars"], 30)
        self.assertIs(index[("deliverable-1", "section-2")], sections[1])
        result = self.run_check("tools/fixtures/drafts/drafts-overflow")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("exceeds max_chars 30 for deliverable-1/section-2", result.stdout)

    def test_tane04_section_scope(self):
        second = copy.deepcopy(self.spec["deliverables"][0])
        second["deliverable_id"] = "deliverable-2"
        self.spec["deliverables"].append(second)
        drafts_dir = self.root / "drafts"
        drafts_dir.mkdir()
        for source in pathlib.Path("tools/fixtures/drafts/drafts-good").glob("*.md"):
            text = source.read_text(encoding="utf-8")
            (drafts_dir / source.name).write_text(text, encoding="utf-8")
            (drafts_dir / f"deliverable-2-{source.name}").write_text(
                text.replace("deliverable_id: deliverable-1", "deliverable_id: deliverable-2"),
                encoding="utf-8",
            )
        result = self.run_check(drafts_dir)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("WARN:", result.stdout)


class RequiredCoverageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        self.drafts = self.root / "drafts"
        self.drafts.mkdir()
        self.checker = pathlib.Path("tools/check-drafts.sh").resolve()
        self.deliverable = {
            "deliverable_id": "plan", "produced_by": "ai_draftable", "required": True,
            "sections": [{"section_id": "body", "max_chars": 100},
                         {"section_id": "extra", "max_chars": 100, "optional": True}],
        }
        self.spec = {"subsidy_id": "fixture-tane09", "spec_version": 1,
                     "deliverables": [self.deliverable]}
        self.application = {"subsidy_id": "fixture-tane09", "spec_version": 1, "enabled": True}
        self.leaf = {"scope": "profile", "key": "enabled", "op": "eq", "value": True}

    def context_args(self, option, document):
        path = self.root / (option.lstrip("-") + ".json")
        path.write_text(json.dumps(document), encoding="utf-8")
        return [option, str(path)]

    def run_check(self, *args):
        path = self.root / "spec.json"
        path.write_text(json.dumps(self.spec), encoding="utf-8")
        return subprocess.run(
            ["bash", str(self.checker), str(path), str(self.drafts), *args], cwd=self.root,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )

    def assert_coverage(self, args, expected, unknown=()):
        result = self.run_check(*args)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("OK: draft checks passed", result.stdout)
        self.assertNotIn("FAIL:", result.stdout)
        self.assertEqual(
            [line for line in result.stdout.splitlines() if line.startswith("INFO:")],
            ["INFO: [要確認] total: 0", "INFO: [要確認] in draft bodies: 0",
             *(["INFO: [要確認] in draft body: plan/body 0", "INFO: chars: plan/body 5/100"]
               if (self.drafts / "body.md").exists() else []),
             "INFO: coverage_inputs_sha256: " +
             re.search(r"^INFO: coverage_inputs_sha256: ([0-9a-f]{64})$", result.stdout, re.M).group(1)], result.stdout,
        )
        warnings = [line for line in result.stdout.splitlines() if line.startswith("WARN:")]
        actual, marked = set(), set()
        for line in warnings:
            match = re.search(r"missing draft for ([^:\s]+)", line)
            self.assertIsNotNone(match, line)
            actual.add(match[1])
            if "[要確認]" in line:
                marked.add(match[1])
        self.assertEqual(actual, set(expected), result.stdout)
        self.assertEqual(len(warnings), len(expected), result.stdout)
        self.assertEqual(marked, set(unknown), result.stdout)

    def assert_context_failure(self, args, diagnostic):
        result = self.run_check(*args)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("FAIL: " + diagnostic, result.stdout)
        self.assertNotIn("Traceback", result.stdout)

    def test_tane09_required_matrix(self):
        # Columns follow the planning table: absent, null, true, false, unknown.
        matrix = {True: (True, True, True, False, True),
                  False: (False, False, True, False, True)}
        for scope in ("profile", "application"):
            with self.subTest(scope=scope):
                self.spec["deliverables"] = []
                expected, unknown = set(), set()
                for required, row in matrix.items():
                    for condition, included in zip(("absent", "null", "true", "false", "unknown"), row):
                        item = copy.deepcopy(self.deliverable)
                        item.update(deliverable_id=f"{required}-{condition}", required=required)
                        if condition == "null":
                            item["required_if"] = None
                        elif condition != "absent":
                            item["required_if"] = dict(self.leaf, scope=scope,
                                key="missing" if condition == "unknown" else "enabled",
                                value=condition != "false")
                        self.spec["deliverables"].append(item)
                        key = item["deliverable_id"] + "/body"
                        if included:
                            expected.add(key)
                        if condition == "unknown":
                            unknown.add(key)
                args = self.context_args("--profile", {"enabled": True})
                args += self.context_args("--current-application", self.application)
                self.assert_coverage(args, expected, unknown)
                self.assert_coverage(args[:2] if scope == "profile" else args[2:], expected, unknown)

    def test_tane09_context_validation(self):
        # Explicit context files are validated even without conditional coverage.
        for option, label in (("--profile", "profile"), ("--current-application", "current application")):
            for document in (None, [], True, 1, "text"):
                with self.subTest(option=option, document=document):
                    self.assert_context_failure(self.context_args(option, document), label + " root must be an object")
            for data in (b"{", b"\xff"):
                path = self.root / "invalid.json"
                path.write_bytes(data)
                self.assert_context_failure([option, str(path)], label + " invalid JSON")
            self.assert_context_failure([option, str(self.root / "missing.json")], label + " not found")
            self.assert_context_failure([option, str(self.root)], label + " cannot be read" if option == "--profile"
                                        else label + " could not be read")
        for key, bad_values, type_name in (("subsidy_id", (None, 1, True, []), "a string"),
                                           ("spec_version", (None, True, "1", 1.0), "an integer")):
            application = dict(self.application)
            del application[key]
            self.assert_context_failure(self.context_args("--current-application", application),
                                        "current application missing " + key)
            for value in bad_values:
                application[key] = value
                self.assert_context_failure(self.context_args("--current-application", application),
                                            f"current application {key} must be {type_name}")
            application[key] = "different" if key == "subsidy_id" else 2
            self.assert_context_failure(self.context_args("--current-application", application),
                                        f"current application {key} mismatch")
        for extra_args in ([], self.context_args("--current-application", self.application)):
            self.assert_context_failure(self.context_args("--profile", {"application": {}}) + extra_args,
                                        "profile must not contain top-level application")
        application_leaf = dict(self.leaf, scope="application")
        for predicate in (application_leaf, {"not": application_leaf},
                          {"any": [self.leaf, {"all": [application_leaf]}]}):
            self.deliverable["required_if"] = predicate
            self.assert_context_failure(self.context_args("--profile", {"enabled": True}),
                                        "application scope requires --current-application")

    def test_tane09_coverage_contract(self):
        self.assert_coverage([], {"plan/body"})
        for args in (("--profile",), ("--current-application",), ("extra",)):
            result = self.run_check(*args)
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("usage:", result.stdout)
        self.deliverable["required_if"] = self.leaf
        # Missing, null, and differently typed values remain unknown.
        for args in ([], self.context_args("--profile", {})):
            self.assert_coverage(args, {"plan/body"}, {"plan/body"})
        for value in (None, 1, "true"):
            self.assert_coverage(self.context_args("--profile", {"enabled": value}),
                                 {"plan/body"}, {"plan/body"})
        self.assert_coverage(self.context_args("--profile", {"profile": {"enabled": False}}), set())
        (self.drafts / "body.md").write_text(
            "---\ndeliverable_id: plan\nsection_id: body\n---\n## 叩き台\nDraft\n", encoding="utf-8")
        self.assert_coverage([], set())
        self.assert_coverage(self.context_args("--profile", {"enabled": False}), set())
        for produced_by, sections in (("external", []), ("external", [{"section_id": "body"}]),
                                      ("ai_draftable", []),
                                      ("ai_draftable", [{"section_id": "body", "optional": True}])):
            with self.subTest(produced_by=produced_by, sections=sections):
                self.spec["deliverables"] = [dict(self.deliverable, deliverable_id="excluded",
                    produced_by=produced_by, sections=sections,
                    required_if=dict(self.leaf, scope="application"))]
                # Use an empty directory so coverage exclusions are observable.
                self.drafts = self.root / "empty"
                self.drafts.mkdir(exist_ok=True)
                self.assert_coverage([], set())


class CoverageGateTests(unittest.TestCase):
    setUp = RequiredCoverageTests.setUp
    run_check = RequiredCoverageTests.run_check
    context_args = RequiredCoverageTests.context_args

    def add_draft(self, section="extra"):
        (self.drafts / (section + ".md")).write_text(
            "---\ndeliverable_id: plan\nsection_id: " + section +
            "\n---\n## 叩き台\nDraft\n", encoding="utf-8")

    def test_small_wording_id_hints(self):
        second = copy.deepcopy(self.deliverable)
        second["deliverable_id"] = "another"
        manual = dict(second, deliverable_id="manual", produced_by="applicant")
        self.spec["deliverables"].extend([manual, second])
        for deliverable, section, hint in (
            ("missing", "body", "有効な deliverable_id: plan, another"),
            ("plan", "missing", "plan の有効な section_id: body, extra"),
        ):
            with self.subTest(deliverable=deliverable, section=section):
                for name in ("one", "two"):
                    (self.drafts / (name + ".md")).write_text(
                        f"---\ndeliverable_id: {deliverable}\nsection_id: {section}\n---\n## 叩き台\n本文\n",
                        encoding="utf-8")
                result = self.run_check()
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertEqual(result.stdout.count("INFO: " + hint + "\n"), 1)
                for name in ("one", "two"):
                    failure = (f"FAIL: {self.drafts / (name + '.md')}: "
                               f"unknown deliverable_id/section_id: {deliverable}/{section}")
                    self.assertIn(failure, result.stdout)
                    if name == "one":
                        self.assertIn(failure + "\nINFO: " + hint, result.stdout)

    def test_small_wording_valid_ids(self):
        self.add_draft("body")
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("有効な", result.stdout)
        self.assertNotIn("max_chars not set", result.stdout)

    def test_small_wording_waive_hints(self):
        self.add_draft("body")
        result = self.run_check("--require-coverage", "--waive", "missing/body",
                                "--waive", "plan/missing")
        self.assertEqual(result.returncode, 1, result.stdout)
        hint = "INFO: 有効な <deliverable_id>/<section_id>: plan/body, plan/extra"
        self.assertEqual(result.stdout.count(hint), 1)
        self.assertIn("FAIL: unknown section for --waive: missing/body\n" + hint, result.stdout)
        self.assertIn("FAIL: unknown section for --waive: plan/missing", result.stdout)

    def test_small_wording_null_limits(self):
        for section in ("body", "extra"):
            self.add_draft(section)
        before = self.run_check()
        for section, pages in zip(self.deliverable["sections"], (None, 1)):
            section.update(max_chars=None, max_pages=pages)
        after = self.run_check()
        self.assertEqual(before.returncode, 0, before.stdout)
        self.assertEqual(after.returncode, 0, after.stdout)
        added = [line for line in after.stdout.splitlines()
                 if line.startswith("INFO: max_chars not set in spec:")]
        self.assertEqual(added, [
            "INFO: max_chars not set in spec: plan/body (5 chars)",
            "INFO: max_chars not set in spec: plan/extra (5 chars)",
        ])
        expected = before.stdout.replace("INFO: chars: plan/body 5/100", added[0])
        expected = expected.replace("INFO: chars: plan/extra 5/100", added[1])
        self.assertEqual(after.stdout, expected)

    def assert_result(self, args, status, message):
        result = self.run_check(*args)
        self.assertEqual(result.returncode, status, result.stdout)
        self.assertIn(message, result.stdout)
        return result.stdout

    def test_b2_required_missing_and_legacy(self):
        self.add_draft()
        self.assert_result([], 0, "WARN: missing draft for plan/body")
        self.assert_result(["--require-coverage"], 1, "FAIL: missing required draft for plan/body")
        self.assert_result(["--require-coverage", "--waive", "plan/body"], 0,
                           "INFO: waived by applicant: plan/body")

    def test_b2_partial_and_multiple_waivers(self):
        self.add_draft()
        self.deliverable["sections"].append({"section_id": "other"})
        args = ["--require-coverage", "--waive", "plan/body"]
        output = self.assert_result(args, 1, "FAIL: missing required draft for plan/other")
        self.assertNotIn("FAIL: missing required draft for plan/body", output)
        output = self.assert_result(args + ["--waive", "plan/other"], 0,
                                    "INFO: waived by applicant: plan/other")
        self.assertIn("INFO: waived by applicant: plan/body", output)

    def test_b2_invalid_waivers(self):
        self.add_draft()
        for value, message in [
            ("plan/unknown", "unknown section for --waive"),
            ("unknown/body", "unknown section for --waive"),
            ("body", "invalid format for --waive"),
            ("plan/body/extra", "invalid format for --waive"),
            ("/body", "invalid format for --waive"),
            ("plan/", "invalid format for --waive"),
            ("plan/extra", "draft exists for --waive"),
        ]:
            with self.subTest(value=value):
                self.assert_result(["--require-coverage", "--waive", value], 1, "FAIL: " + message)
        self.assert_result(["--waive", "plan/body"], 1, "FAIL: --waive requires --require-coverage")

    def test_b2_unknown_stays_warning(self):
        self.add_draft()
        self.deliverable["required_if"] = self.leaf
        for args in (["--require-coverage"], ["--require-coverage", "--waive", "plan/body"]):
            output = self.assert_result(args, 0, "WARN: [要確認] missing draft for plan/body")
            self.assertNotIn("FAIL:", output)

    def test_b2_empty_drafts(self):
        for args in (["--require-coverage"],
                     ["--require-coverage", "--waive", "plan/body", "--waive", "plan/extra"]):
            self.assert_result(args, 1, "FAIL: no drafts:")
        self.assert_result([], 0, "WARN: missing draft for plan/body")

    def test_b2_hash_independent_of_flags(self):
        self.add_draft()
        self.deliverable["required_if"] = self.leaf
        for context in ([], self.context_args("--profile", {"enabled": False})):
            hashes = []
            for flags in ([], ["--require-coverage"],
                          ["--require-coverage", "--waive", "plan/body"]):
                output = self.assert_result(context + flags, 0, "INFO: coverage_inputs_sha256:")
                hashes.append(re.search(r"coverage_inputs_sha256: ([0-9a-f]{64})", output).group(1))
            self.assertEqual(len(set(hashes)), 1)
        context = self.context_args("--profile", {"enabled": True})
        legacy = self.assert_result(context, 0, "WARN: missing draft")
        waived = self.assert_result(context + ["--require-coverage", "--waive", "plan/body"], 0,
                                    "INFO: waived by applicant:")
        pattern = r"coverage_inputs_sha256: ([0-9a-f]{64})"
        self.assertEqual(re.search(pattern, legacy).group(1), re.search(pattern, waived).group(1))


class ReviewRecordTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        self.drafts = self.root / "drafts"
        self.drafts.mkdir()
        self.spec = self.root / "spec.json"
        self.spec.write_text(json.dumps({"deliverables": [
            {"deliverable_id": "plan", "produced_by": "ai_draftable", "required": True,
             "sections": [{"section_id": "one"}, {"section_id": "two"}]}
        ]}), encoding="utf-8")
        for section in ("one", "two"):
            (self.drafts / (section + ".md")).write_text(
                "---\ndeliverable_id: plan\nsection_id: " + section + "\n---\n## 叩き台\nBody\n", encoding="utf-8")
        self.path = self.root / "review.md"
        self.record = {"reviewed_draft_bodies_sha256": draft_bodies_sha256(self.drafts)[0],
                       "reviewed_sections": ["plan/one", "plan/two"],
                       "reviewed_at": "2026-11-13T12:00:00Z"}

    def run_record(self, record=None, raw=None, enabled=True):
        self.path.write_text(raw if raw is not None else "```json\n" + json.dumps(
            self.record if record is None else record) + "\n```\n", encoding="utf-8")
        return subprocess.run(["bash", "tools/check-drafts.sh", str(self.spec), str(self.drafts)] +
                              (["--review-record", str(self.path)] if enabled else []),
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    def test_b3_valid_extra_and_coverage_hash(self):
        legacy = self.run_record(enabled=False)
        result = self.run_record()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("INFO: review record ok:", result.stdout)
        self.assertIn("(2 sections)", result.stdout)
        pattern = r"^INFO: coverage_inputs_sha256: (.+)$"
        self.assertEqual(re.findall(pattern, legacy.stdout, re.M), re.findall(pattern, result.stdout, re.M))
        self.assertEqual(len(re.findall(pattern, result.stdout, re.M)), 1)
        self.record["reviewed_sections"].append("extra/absent")
        self.assertEqual(self.run_record().returncode, 0)

    def test_b3_stale_and_mutated_body(self):
        record = dict(self.record, reviewed_draft_bodies_sha256="0" * 64)
        result = self.run_record(record)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL: review record hash mismatch:", result.stdout)
        self.assertEqual(self.run_record().returncode, 0)
        path = self.drafts / "one.md"
        path.write_text(path.read_text(encoding="utf-8").replace("Body", "BodX"), encoding="utf-8")
        result = self.run_record()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL: review record hash mismatch:", result.stdout)

    def test_b3_missing_section(self):
        self.record["reviewed_sections"] = ["plan/one"]
        result = self.run_record()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL: review record missing sections:", result.stdout)
        self.assertIn("plan/two", result.stdout)

    def test_b3_unreadable(self):
        for raw in ("# review\n", "\n```json\n{}\n```", "```json\n{broken}\n```", "```json\n[]\n```"):
            with self.subTest(raw=raw):
                result = self.run_record(raw=raw)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("FAIL: review record unreadable:", result.stdout)
        records = []
        for key in self.record:
            record = dict(self.record)
            del record[key]
            records.append(record)
        for key, value in (("reviewed_sections", "plan/one"), ("reviewed_sections", [42]),
                           ("reviewed_draft_bodies_sha256", "z" * 64),
                           ("reviewed_draft_bodies_sha256", "a" * 63),
                           ("reviewed_at", 42), ("reviewed_at", "2026-99-13T12:00:00")):
            records.append(dict(self.record, **{key: value}))
        for record in records:
            with self.subTest(record=record):
                result = self.run_record(record)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("FAIL: review record unreadable:", result.stdout)


class CoverageFreshnessTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        (self.root / "tools").symlink_to(pathlib.Path("tools").resolve(), target_is_directory=True)
        self.input = self.root / "input"
        self.drafts = self.input / "drafts/fixture-p95"
        self.drafts.mkdir(parents=True)
        (self.input / "checks").mkdir()
        self.spec = {
            "subsidy_id": "fixture-p95", "spec_version": 1, "status": "confirmed",
            "clauses": [{"clause_id": "c1", "text": "Fixture clause"}],
            "deliverables": [
                {"deliverable_id": "plan", "produced_by": "ai_draftable", "required": True,
                 "required_if": {"scope": "profile", "key": "employees", "op": "gte", "value": 20},
                 "sections": [{"section_id": "body"}]},
                {"deliverable_id": "ready", "produced_by": "ai_draftable", "required": True,
                 "sections": [{"section_id": "body"}]},
            ],
        }
        self.write_json("spec.json", self.spec)
        self.profile = {"employees": 10, "company_name": "Fixture"}
        self.write_json("company-profile.json", self.profile)
        self.application = {"subsidy_id": "fixture-p95", "spec_version": 1,
                            "spec_path": "input/spec.json", "state": "drafting",
                            "chosen_funding": {"enabled": False}}
        self.write_json("current-application.json", self.application)
        (self.drafts / "ready.md").write_text(
            "---\ndeliverable_id: ready\nsection_id: body\n---\n## 叩き台\nDraft\n", encoding="utf-8")
        self.verify_doc = pathlib.Path(".claude/commands/verify.md").read_text(encoding="utf-8")
        # These coverage unit fixtures isolate spec validation; the integration suite uses real specs.
        self.finalize_blocks = ["""
import argparse, pathlib, sys
sys.path.insert(0, str(pathlib.Path('tools/lib').resolve()))
import check_finalize
check_finalize.check_spec.main = lambda argv: 0
WAIVED = []
args = argparse.Namespace(current_application='input/current-application.json',
    profile='input/company-profile.json', waive=WAIVED, record_finalized=False)
code, report = check_finalize.run(args)
print(report)
sys.exit(1 if code else 0)
"""]
        self.finalize_update = self.finalize_blocks[0].replace('record_finalized=False', 'record_finalized=True')

    def write_json(self, name, data):
        (self.input / name).write_text(json.dumps(data), encoding="utf-8")

    def run_checker(self):
        command = re.search(r"^bash tools/check-drafts\.sh .+$", self.verify_doc, re.M).group(0)
        command = command.replace("<spec>", "input/spec.json").replace("<subsidy_id>", "fixture-p95")
        return subprocess.run(shlex.split(command), cwd=self.root,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    def digest(self, result):
        self.assertEqual(result.returncode, 0, result.stdout)
        matches = re.findall(r"^INFO: coverage_inputs_sha256: ([0-9a-f]{64})$", result.stdout, re.M)
        self.assertEqual(len(matches), 1, result.stdout)
        return matches[0]

    def save_verification(self):
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stdout)
        body_hash, errors = draft_bodies_sha256(self.drafts)
        self.assertEqual(errors, [])
        report = {
            "spec_check": "green", "draft_check": "green", "spec_path": "input/spec.json",
            "spec_version": 1, "spec_sha256": hashlib.sha256((self.input / "spec.json").read_bytes()).hexdigest(),
            "draft_bodies_sha256": body_hash, "draft_hash_algorithm": "fixture", "generated_at": "fixture",
        }
        match = re.search(r"^INFO: coverage_inputs_sha256: ([0-9a-f]{64})$", result.stdout, re.M)
        if match:
            report["coverage_inputs_sha256"] = match.group(1)
        self.write_report(report, result.stdout)
        self.application.update(state="verified", verified_at="fixture", updated_at="fixture",
                                verify_report_path="input/checks/verify-report.md", draft_bodies_sha256=body_hash)
        self.write_json("current-application.json", self.application)
        reviews = self.input / "reviews"
        reviews.mkdir(exist_ok=True)
        (reviews / "all.md").write_text("```json\n" + json.dumps({
            "reviewed_draft_bodies_sha256": body_hash,
            "reviewed_sections": ["ready/body"],
            "reviewed_at": "2026-11-13T12:00:00+09:00",
        }) + "\n```\n\n| clause_id | quoted_text |\n| --- | --- |\n| c1 | Fixture clause |\n", encoding="utf-8")
        return report

    def write_report(self, report, output=""):
        coverage = "\n".join(line for line in output.splitlines() if line.startswith("WARN:")) or "なし"
        (self.input / "checks/verify-report.md").write_text(
            "```json\n" + json.dumps(report) + "\n```\n\n## coverage gaps\n" + coverage + "\n", encoding="utf-8")

    def finalize_gate(self):
        for code in self.finalize_blocks:
            result = subprocess.run([sys.executable, "-c", code], cwd=self.root,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            if result.returncode:
                return result
        return result

    def finalize_application(self):
        result = self.finalize_gate()
        self.assertEqual(result.returncode, 0, result.stdout)
        (self.input / "final-checklist.md").write_text("Fixture checklist\n", encoding="utf-8")
        (self.input / "submission-summary.md").write_text("Fixture summary\n", encoding="utf-8")
        self.finalize_update = self.finalize_blocks[0].replace("record_finalized=False", "record_finalized=True")
        result = subprocess.run([sys.executable, "-c", self.finalize_update], cwd=self.root,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.application = json.loads((self.input / "current-application.json").read_text(encoding="utf-8"))
        self.assertEqual(self.application["state"], "finalized")

    def assert_finalized_recovery(self, report):
        application_path = self.input / "current-application.json"
        before = json.loads(application_path.read_text(encoding="utf-8"))
        self.assertEqual(before["state"], "finalized")
        report_bytes = (self.input / "checks/verify-report.md").read_bytes()
        checklist_bytes = (self.input / "final-checklist.md").read_bytes()
        self.assertEqual(report["spec_sha256"], hashlib.sha256((self.input / "spec.json").read_bytes()).hexdigest())
        self.assertEqual(report["draft_bodies_sha256"], draft_bodies_sha256(self.drafts)[0])
        result = self.finalize_gate()
        self.assertEqual(result.returncode, 1, result.stdout)
        recovered = json.loads(application_path.read_text(encoding="utf-8"))
        self.assertEqual(recovered["state"], "finalized", "failed freshness gate must preserve state")
        self.assertEqual(recovered, before)
        self.assertEqual((self.input / "checks/verify-report.md").read_bytes(), report_bytes)
        self.assertEqual((self.input / "final-checklist.md").read_bytes(), checklist_bytes)
        # Repeating the gate preserves state and keeps the stale report invalid.
        self.assertEqual(self.finalize_gate().returncode, 1)
        self.assertEqual(json.loads(application_path.read_text(encoding="utf-8")), recovered)
        prerequisite = re.search(r"^2\..+`state` が (.+?)であること。", self.verify_doc, re.M).group(1)
        self.assertIn(recovered["state"], re.findall(r"`([^`]+)`", prerequisite))
        self.application = recovered
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stdout)
        update_code = re.search(
            r"python3 - <<'PY'\n(.*?)\nPY",
            self.verify_doc.split("## `current-application.json` の更新")[1], re.S).group(1)
        update_code = update_code.replace("ここに report と同じ 64 桁 hex を入れる",
                                          report["draft_bodies_sha256"])
        result = subprocess.run([sys.executable, "-c", update_code], cwd=self.root,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.application = json.loads(application_path.read_text(encoding="utf-8"))
        self.assertEqual(self.application["state"], "verified")
        self.assertEqual((self.input / "final-checklist.md").read_bytes(), checklist_bytes)
        refreshed = self.save_verification()
        self.assertEqual(refreshed["coverage_inputs_sha256"], self.digest(self.run_checker()))
        self.assertEqual(refreshed["spec_sha256"], report["spec_sha256"])
        self.assertEqual(refreshed["draft_bodies_sha256"], report["draft_bodies_sha256"])
        self.finalize_application()

    def test_b3_finalize_review_selection(self):
        self.save_verification()
        review = self.input / "reviews/all.md"
        valid = review.read_text(encoding="utf-8")
        app_before = (self.input / "current-application.json").read_bytes()
        review.unlink()
        result = self.finalize_gate()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("review record absent", result.stdout)
        review.write_text(valid + "\n| clause_id | quoted_text |\n| --- | --- |\n| c1 | fabricated |\n", encoding="utf-8")
        result = self.finalize_gate()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("review quote check failed", result.stdout)
        (review.parent / "z-valid.md").write_text(valid, encoding="utf-8")
        result = self.finalize_gate()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("adopted review record: input/reviews/z-valid.md", result.stdout)
        self.assertEqual((self.input / "current-application.json").read_bytes(), app_before)
        self.assertFalse((self.input / "final-checklist.md").exists())

    def test_b2_finalize_blocks_missing_without_mutation(self):
        self.profile["employees"] = 25
        self.write_json("company-profile.json", self.profile)
        self.application["state"] = "verified"
        self.write_json("current-application.json", self.application)
        self.save_verification()
        paths = [self.input / name for name in
                 ("current-application.json", "checks/verify-report.md")]
        before = [path.read_bytes() for path in paths]
        result = self.finalize_gate()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("FAIL: missing required draft for plan/body", result.stdout)
        self.assertEqual([path.read_bytes() for path in paths], before)
        self.assertFalse((self.input / "final-checklist.md").exists())
        self.finalize_blocks = [code.replace("WAIVED = []", 'WAIVED = ["plan/body"]')
                                for code in self.finalize_blocks]
        self.finalize_application()

    def test_p95_finalized_legacy_report_can_reverify(self):
        report = self.save_verification()
        self.finalize_application()
        report.pop("coverage_inputs_sha256")
        self.write_report(report)
        self.assert_finalized_recovery(report)

    def test_p95_finalized_profile_change_can_reverify(self):
        report = self.save_verification()
        self.finalize_application()
        # Applicant explicitly chooses to prepare plan/body separately in this scenario.
        self.finalize_blocks = [code.replace("WAIVED = []", 'WAIVED = ["plan/body"]')
                                for code in self.finalize_blocks]
        self.profile["employees"] = 25
        self.write_json("company-profile.json", self.profile)
        self.assert_finalized_recovery(report)
        self.assertIn("WARN: missing draft for plan/body",
                      (self.input / "checks/verify-report.md").read_text(encoding="utf-8"))

    def test_p95_finalized_application_change_can_reverify(self):
        self.spec["deliverables"][0]["required_if"] = {
            "scope": "application", "key": "chosen_funding.enabled", "op": "eq", "value": True}
        self.write_json("spec.json", self.spec)
        report = self.save_verification()
        self.finalize_application()
        # Applicant explicitly chooses to prepare plan/body separately in this scenario.
        self.finalize_blocks = [code.replace("WAIVED = []", 'WAIVED = ["plan/body"]')
                                for code in self.finalize_blocks]
        self.application["chosen_funding"]["enabled"] = True
        self.write_json("current-application.json", self.application)
        self.assert_finalized_recovery(report)
        self.assertIn("WARN: missing draft for plan/body",
                      (self.input / "checks/verify-report.md").read_text(encoding="utf-8"))

    def test_p95_current_finalized_report_preserves_state(self):
        self.save_verification()
        self.finalize_application()
        paths = [self.input / name for name in
                 ("current-application.json", "checks/verify-report.md", "final-checklist.md")]
        before = [path.read_bytes() for path in paths]
        result = self.finalize_gate()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual([path.read_bytes() for path in paths], before)

    def test_p95_profile_change_invalidates_saved_coverage(self):
        report = self.save_verification()
        self.assertEqual(self.finalize_gate().returncode, 0)
        self.assertIn("## coverage gaps\nなし", (self.input / "checks/verify-report.md").read_text(encoding="utf-8"))
        # Applicant explicitly chooses to prepare plan/body separately in this scenario.
        self.finalize_blocks = [code.replace("WAIVED = []", 'WAIVED = ["plan/body"]')
                                for code in self.finalize_blocks]
        self.profile["employees"] = 25
        self.write_json("company-profile.json", self.profile)
        self.assertEqual(report["spec_sha256"], hashlib.sha256((self.input / "spec.json").read_bytes()).hexdigest())
        self.assertEqual(report["draft_bodies_sha256"], draft_bodies_sha256(self.drafts)[0])
        self.assertIn("WARN: missing draft for plan/body", self.run_checker().stdout)
        result = self.finalize_gate()
        self.assertEqual(result.returncode, 1, "finalize accepted stale coverage after employees 10 -> 25")
        self.assertIn("coverage_inputs_sha256 mismatch", result.stdout)
        self.save_verification()
        self.assertEqual(self.finalize_gate().returncode, 0)

    def test_p95_verify_records_coverage_inputs(self):
        digest = self.digest(self.run_checker())
        sample = json.loads(re.search(r"```json\n(.*?)\n```", self.verify_doc, re.S).group(1))
        self.assertIn("coverage_inputs_sha256", sample)
        self.assertEqual(self.save_verification()["coverage_inputs_sha256"], digest)
        self.assertEqual(self.digest(self.run_checker()), digest)
        self.profile["company_name"] = "Updated fixture"
        self.write_json("company-profile.json", self.profile)
        self.assertEqual(self.digest(self.run_checker()), digest)
        self.assertEqual(self.finalize_gate().returncode, 0)

    def test_p95_legacy_or_invalid_coverage_hash_is_rejected(self):
        report = self.save_verification()
        for value in (None, "", "invalid", "0" * 64):
            with self.subTest(value=value):
                report["coverage_inputs_sha256"] = value
                self.write_report(report)
                self.assertEqual(self.finalize_gate().returncode, 1)
        report.pop("coverage_inputs_sha256")
        self.write_report(report)
        self.assertEqual(self.finalize_gate().returncode, 1)

    def test_p95_nested_inputs_and_unknown_changes(self):
        self.spec["deliverables"][0]["required_if"] = {"all": [
            {"scope": "profile", "key": "staff.employees", "op": "gte", "value": 20},
            {"not": {"any": [{"scope": "application", "key": "chosen_funding.enabled",
                              "op": "eq", "value": True}]}}]}
        self.write_json("spec.json", self.spec)
        self.write_json("company-profile.json", {"profile": {"staff": {"employees": 10}}})
        original = self.digest(self.run_checker())
        self.save_verification()
        # Applicant explicitly chooses to prepare plan/body separately in this scenario.
        self.finalize_blocks = [code.replace("WAIVED = []", 'WAIVED = ["plan/body"]')
                                for code in self.finalize_blocks]
        self.application["chosen_funding"]["enabled"] = True
        self.write_json("current-application.json", self.application)
        self.assertNotEqual(self.digest(self.run_checker()), original)
        self.assertEqual(self.finalize_gate().returncode, 1)
        self.application["chosen_funding"]["enabled"] = False
        self.write_json("current-application.json", self.application)
        for staff in ({"employees": 25}, {}, {"employees": None}, {"employees": "25"}):
            with self.subTest(staff=staff):
                self.write_json("company-profile.json", {"profile": {"staff": staff}})
                self.assertNotEqual(self.digest(self.run_checker()), original)
                self.assertEqual(self.finalize_gate().returncode, 1)

    def test_p95_invalid_context_cannot_reuse_report(self):
        self.save_verification()
        for name in ("company-profile.json", "current-application.json"):
            path = self.input / name
            original = path.read_bytes()
            for content in (b"{", b"[]", b"\xff", None):
                with self.subTest(name=name, content=content):
                    if content is None:
                        path.unlink()
                    else:
                        path.write_bytes(content)
                    self.assertEqual(self.finalize_gate().returncode, 1)
                    self.assertNotIn("coverage_inputs_sha256:", self.run_checker().stdout)
            path.write_bytes(original)


unittest.main(verbosity=2)
PY
then
  pass
else
  fail "section definition checks must pass"
fi

echo "=== test-check-drafts: $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
