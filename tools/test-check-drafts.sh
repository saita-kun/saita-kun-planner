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
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path("tools/lib").resolve()))
from check_drafts import build_section_index


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
            "sections": [{"section_id": "body"}, {"section_id": "extra", "optional": True}],
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
            ["INFO: [要確認] total: 0"], result.stdout,
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


unittest.main(verbosity=2)
PY
then
  pass
else
  fail "section definition checks must pass"
fi

echo "=== test-check-drafts: $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
