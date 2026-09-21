#!/bin/bash
# Exercise the promotion code extracted from the shipped command.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 -u -B - "$ROOT" <<'PY'
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
command = (root / ".claude/commands/build-pack.md").read_text(encoding="utf-8")
blocks = re.findall(
    r"^python3 - '<subsidy_id>' '<source_spec_path>' <<'PY'\n(.*?)^PY$",
    command, re.MULTILINE | re.DOTALL,
)
if len(blocks) != 1:
    raise SystemExit("FAIL: expected exactly one embedded pack promotion block")
promotion = blocks[0]
sid = "pack-fixture"
flat = pathlib.Path(f"input/spec/{sid}.json")
packed = pathlib.Path(f"input/spec/{sid}/{sid}.json")
passed = failed = 0


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def make_case(label, source=None, state="drafting", subsidy_id=sid):
    if source is None:
        source = pathlib.Path(f"input/spec/{subsidy_id}.json")
    packed = pathlib.Path(f"input/spec/{subsidy_id}/{subsidy_id}.json")
    work = temporary / label
    (work / "tools/lib").mkdir(parents=True)
    (work / "schemas").mkdir()
    for name in ("check_pack", "check_spec", "spec_resolver"):
        shutil.copyfile(root / f"tools/lib/{name}.py", work / f"tools/lib/{name}.py")
    shutil.copyfile(root / "schemas/taxonomy-v1.json", work / "schemas/taxonomy-v1.json")
    for name in ("check-pack", "check-spec"):
        script = (root / f"tools/{name}.sh").read_text(encoding="utf-8")
        observer = '''
if [ "$1" = "--resolve-application" ] || [ "PHASE" = "check-pack" ]; then
  python3 - <<'OBSERVE'
import json
import pathlib
app = json.loads(pathlib.Path("input/current-application.json").read_text())
with pathlib.Path("events.jsonl").open("a") as stream:
    stream.write(json.dumps({"phase": "PHASE", "app": app,
        "sources": [pathlib.Path("input/spec/" + app["subsidy_id"] + suffix).exists()
                    for suffix in (".json", ".confirmation.json")]}) + "\\n")
OBSERVE
fi
'''.replace("PHASE", name)
        (work / f"tools/{name}.sh").write_text("#!/bin/bash\n" + observer + script, encoding="utf-8")
    pack_dir = (work / packed).parent
    fixture = root / "tools/fixtures/packs/green"
    for path in fixture.rglob("*"):
        if path.is_file():
            target = pack_dir / path.relative_to(fixture).as_posix().replace(sid, subsidy_id)
            target.parent.mkdir(parents=True, exist_ok=True)
            data = path.read_bytes().replace(sid.encode(), subsidy_id.encode())
            if path.suffix == ".md" and subsidy_id.startswith("-"):
                # The limited frontmatter parser requires quoted leading hyphens.
                data = data.replace(f"subsidy_id: {subsidy_id}\n".encode(),
                                    f'subsidy_id: "{subsidy_id}"\n'.encode())
            target.write_bytes(data)
    spec_bytes = (work / packed).read_bytes().replace(b"\n", b"\r\n")
    (work / packed).write_bytes(spec_bytes)
    digest = hashlib.sha256(spec_bytes).hexdigest()
    confirmation_path = (work / packed).with_suffix(".confirmation.json")
    confirmation = json.loads(confirmation_path.read_text(encoding="utf-8"))
    confirmation.update(spec_path=source.as_posix(), spec_sha256=digest)
    original = [spec_bytes, (json.dumps(confirmation, ensure_ascii=False, indent=4) + "\n\n").encode()]
    sources = [work / source, (work / source).with_suffix(".confirmation.json")]
    for path, data in zip(sources, original):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    confirmation["spec_path"] = packed.as_posix()
    write_json(confirmation_path, confirmation)
    manifest_path = pack_dir / "pack.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["spec"]["sha256"] = digest
    manifest["confirmation"]["sha256"] = hashlib.sha256(confirmation_path.read_bytes()).hexdigest()
    for note in manifest["notes"]:
        note["sha256"] = hashlib.sha256((pack_dir / note["path"]).read_bytes()).hexdigest()
        note["derived_from_spec_sha256"] = digest
    write_json(manifest_path, manifest)
    if source.parts[0] == "specs" and len(source.parts) == 3:
        shutil.copytree(pack_dir / "notes", sources[0].parent / "notes")
        manifest["confirmation"]["sha256"] = hashlib.sha256(original[1]).hexdigest()
        write_json(sources[0].parent / "pack.json", manifest)
    app = {"subsidy_id": subsidy_id, "spec_path": source.as_posix(), "spec_version": 1,
           "state": state, "chosen_funding": {"base_award": "fake", "add_ons": ["selected"]},
           "updated_at": "2026-01-01T00:00:00+09:00", "custom": {"keep": True}}
    write_json(work / "input/current-application.json", app)
    archive = work / f"input/.archive/spec/{subsidy_id}/{digest}"
    return work, sources, original, archive, app


def run_promotion(work, source=flat, failure=None, subsidy_id=sid):
    runner = [sys.executable, "-B", "-"]
    if failure:
        runner = [sys.executable, "-B", "-c", '''
import os
import sys
from unittest import mock
operation = "replace" if sys.argv.pop(1) == "application" else "link"
original = getattr(os, operation)
calls = 0
def fail_operation(*args, **kwargs):
    global calls
    calls += 1
    if operation == "replace" or calls == 2:
        raise OSError("fake write failure")
    return original(*args, **kwargs)
with mock.patch("os." + operation, side_effect=fail_operation):
    exec(compile(sys.stdin.read(), "build-pack.md", "exec"))
''', failure]
    result = subprocess.run(
        runner + [subsidy_id, source.as_posix()], input=promotion,
        cwd=work, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        env=dict(os.environ, PLANNER_PYTHON=sys.executable, PYTHONDONTWRITEBYTECODE="1"),
    )
    return result


def preserved_fields(app):
    return {key: value for key, value in app.items() if key not in ("spec_path", "updated_at")}


def archive_after_verified_pack():
    work, sources, original, archive, app = make_case("verified")
    result = run_promotion(work)
    assert result.returncode == 0, result.stdout + result.stderr
    assert not any(path.exists() for path in sources)
    assert {path.name for path in archive.iterdir()} == {path.name for path in sources}
    assert [(archive / path.name).read_bytes() for path in sources] == original
    updated = json.loads((work / "input/current-application.json").read_text())
    assert updated["spec_path"] == packed.as_posix()
    assert updated["updated_at"] != app["updated_at"]
    assert preserved_fields(updated) == preserved_fields(app)
    events = [json.loads(line) for line in (work / "events.jsonl").read_text().splitlines()]
    assert [event["phase"] for event in events] == ["check-pack", "check-spec"]
    assert events[0]["app"] == app
    assert events[1]["app"] == updated
    assert all(event["sources"] == [True, True] for event in events)
    resolved = subprocess.run(["bash", "tools/check-spec.sh", "--resolve-application"],
                              cwd=work, stdout=subprocess.PIPE, universal_newlines=True)
    assert resolved.returncode == 0 and resolved.stdout.strip() == packed.as_posix()
    # Restoring exclusive copies recovers the exact original bytes.
    for source, data in zip(sources, original):
        with source.open("xb") as stream:
            stream.write((archive / source.name).read_bytes())
        assert source.read_bytes() == data


def archive_leading_hyphen_id():
    subsidy_id = "-p73"
    work, sources, original, archive, app = make_case("leading-hyphen", subsidy_id=subsidy_id)
    result = run_promotion(work, sources[0].relative_to(work), subsidy_id=subsidy_id)
    assert result.returncode == 0, result.stdout + result.stderr
    assert not any(path.exists() for path in sources)
    assert {path.name for path in archive.iterdir()} == {path.name for path in sources}
    assert [(archive / path.name).read_bytes() for path in sources] == original
    updated = json.loads((work / "input/current-application.json").read_text())
    assert updated["spec_path"] == f"input/spec/{subsidy_id}/{subsidy_id}.json"
    assert preserved_fields(updated) == preserved_fields(app)
    events = [json.loads(line) for line in (work / "events.jsonl").read_text().splitlines()]
    assert [event["phase"] for event in events] == ["check-pack", "check-spec"]
    assert events[0]["app"] == app
    assert events[1]["app"] == updated
    assert all(event["sources"] == [True, True] for event in events)


def archive_failure_preserves_sources():
    for mode in ("pack", "resolve-failure", "resolve-mismatch", "conflict-spec",
                 "conflict-confirmation", "missing-confirmation", "changed-spec",
                 "changed-confirmation", "archive-symlink", "draft-state", "application"):
        work, sources, original, archive, _ = make_case(mode)
        if mode == "pack":
            (work / packed).parent.joinpath("pack.json").write_text("{}")
        elif mode.startswith("resolve-"):
            wrapper = work / "tools/check-spec.sh"
            fake = "exit 7" if mode == "resolve-failure" else "echo specs/other.json; exit 0"
            wrapper.write_text('#!/bin/bash\nif [ "$1" = "--resolve-application" ]; then\n'
                               + fake + "\nfi\n" + wrapper.read_text())
        elif mode.startswith("conflict-"):
            archive.mkdir(parents=True)
            index = 0 if mode == "conflict-spec" else 1
            (archive / sources[index].name).write_bytes(b"existing archive bytes")
        elif mode == "missing-confirmation":
            sources[1].unlink()
        elif mode.startswith("changed-"):
            index = 0 if mode == "changed-spec" else 1
            value = json.loads(sources[index].read_bytes())
            value["name" if index == 0 else "confirmed_at"] = "different value"
            write_json(sources[index], value)
        elif mode == "archive-symlink":
            (work / "archive-target").mkdir()
            (work / "input/.archive").symlink_to(work / "archive-target", target_is_directory=True)
        elif mode == "draft-state":
            app_path = work / "input/current-application.json"
            app = json.loads(app_path.read_text())
            app["state"] = "spec_draft"
            write_json(app_path, app)
        before = {path: path.read_bytes() for path in (work / "input").rglob("*") if path.is_file()}
        result = run_promotion(work, failure=mode if mode == "application" else None)
        assert result.returncode != 0, mode
        after = {path: path.read_bytes() for path in (work / "input").rglob("*") if path.is_file()}
        assert before == after, mode
        if mode == "archive-symlink":
            assert not list((work / "archive-target").glob("**/*"))


def archive_retry_is_idempotent():
    work, sources, original, archive, _ = make_case("archive-write-failure")
    result = run_promotion(work, failure="archive")
    assert result.returncode != 0 and "fake write failure" in result.stderr
    assert [path.read_bytes() for path in sources] == original
    assert (archive / sources[0].name).read_bytes() == original[0]
    result = run_promotion(work)
    assert result.returncode == 0, result.stdout + result.stderr
    assert not any(path.exists() for path in sources)
    assert [(archive / path.name).read_bytes() for path in sources] == original
    for moved in ((), (0,), (1,), (0, 1)):
        work, sources, original, archive, _ = make_case("retry-" + str(moved))
        archive.mkdir(parents=True)
        for index, source in enumerate(sources):
            (archive / source.name).write_bytes(original[index])
            if index in moved:
                source.unlink()
        result = run_promotion(work)
        assert result.returncode == 0, result.stdout + result.stderr
        assert not any(path.exists() for path in sources)
        assert [(archive / path.name).read_bytes() for path in sources] == original
        before = {path: path.read_bytes() for path in (work / "input").rglob("*") if path.is_file()}
        result = run_promotion(work)
        assert result.returncode == 0, result.stdout + result.stderr
        assert before == {path: path.read_bytes() for path in (work / "input").rglob("*") if path.is_file()}


def bundled_source_untouched():
    for state in ("spec_confirmed", "intake_done", "fit_done", "planned", "drafting", "verified", "finalized"):
        for source in (pathlib.Path(f"specs/{sid}.json"), pathlib.Path(f"specs/{sid}/{sid}.json")):
            work, sources, original, _, app = make_case(state + "-" + str(len(source.parts)), source, state)
            # Local flat files must remain untouched when the copy source is bundled.
            for target, data in zip((work / flat, (work / flat).with_suffix(".confirmation.json")), original):
                target.write_bytes(data)
            bundled_before = {path: path.read_bytes() for path in (work / "specs").rglob("*") if path.is_file()}
            result = run_promotion(work, source)
            assert result.returncode == 0, result.stdout + result.stderr
            assert [path.read_bytes() for path in sources] == original
            assert bundled_before == {path: path.read_bytes() for path in (work / "specs").rglob("*") if path.is_file()}
            assert [(work / flat).read_bytes(), (work / flat).with_suffix(".confirmation.json").read_bytes()] == original
            assert not (work / "input/.archive").exists()
            updated = json.loads((work / "input/current-application.json").read_text())
            assert updated["spec_path"] == packed.as_posix()
            assert preserved_fields(updated) == preserved_fields(app)


with tempfile.TemporaryDirectory(prefix="planner pack archive ") as directory:
    temporary = pathlib.Path(directory)
    for test in (archive_after_verified_pack, archive_leading_hyphen_id, archive_failure_preserves_sources,
                 archive_retry_is_idempotent, bundled_source_untouched):
        try:
            test()
            passed += 1
            print(f"PASS: {test.__name__}")
        except Exception as exc:
            failed += 1
            print(f"FAIL: {test.__name__}: {exc}")

print(f"=== test-build-pack-archive: {passed} pass / {failed} fail ===")
sys.exit(1 if failed else 0)
PY
