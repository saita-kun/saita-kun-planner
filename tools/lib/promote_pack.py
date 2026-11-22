#!/usr/bin/env python3
"""Select a verified pack and archive its original flat files."""
import contextlib
import datetime
import hashlib
import io
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

import check_pack
import check_spec


def require(condition, message):
    if not condition:
        raise SystemExit("FAIL: " + message)


def plain_path(path):
    require(not any(p.is_symlink() for p in (path, *path.parents)),
            f"symbolic link is not supported: {path}")
    return path


def write_application(path, data):
    descriptor, name = tempfile.mkstemp(prefix=".build-pack-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
        os.replace(name, path)
    finally:
        if pathlib.Path(name).exists():
            pathlib.Path(name).unlink()


def copy_exclusive(path, data):
    stream = path.open("xb")
    try:
        with stream:
            stream.write(data)
    except OSError:
        path.unlink()
        raise


def promote(subsidy_id, source_text):
    require(re.fullmatch(r"[a-z0-9-]+", subsidy_id), "invalid subsidy_id")
    source = pathlib.Path(source_text)
    flat = pathlib.Path(f"input/spec/{subsidy_id}.json")
    pack_dir = pathlib.Path(f"input/spec/{subsidy_id}")
    spec_path = plain_path(pack_dir / f"{subsidy_id}.json")
    require(source.parts and not source.is_absolute() and ".." not in source.parts
            and source.as_posix() == source_text
            and (source in (flat, spec_path) or source.parts[0] == "specs"),
            "use the original repo-relative source_spec_path")
    app_path = plain_path(pathlib.Path("input/current-application.json"))
    before = app_path.read_bytes()
    app = json.loads(before)
    require(isinstance(app, dict) and app.get("subsidy_id") == subsidy_id
            and isinstance(app.get("spec_path"), str) and app["spec_path"]
            and app.get("state") in ("spec_confirmed", "intake_done", "fit_done",
                                     "planned", "drafting", "verified", "finalized"),
            "current application must identify a confirmed spec")
    status = check_pack.main(["check-pack", str(pack_dir)])
    if status:
        raise subprocess.CalledProcessError(status, ["bash", "tools/check-pack.sh", str(pack_dir)])
    manifest = json.loads((pack_dir / "pack.json").read_text(encoding="utf-8"))
    require(manifest["spec"]["path"] == spec_path.name
            and manifest["confirmation"]["path"] == f"{subsidy_id}.confirmation.json",
            "pack must list the promoted spec and confirmation paths")
    spec_bytes = spec_path.read_bytes()
    digest = hashlib.sha256(spec_bytes).hexdigest()
    archive = pathlib.Path(f"input/.archive/spec/{subsidy_id}/{digest}")
    records = []
    if source == flat:
        plain_path(archive)
        # Validate both files before changing references or creating archive entries.
        for old in (flat, flat.with_suffix(".confirmation.json")):
            plain_path(old)
            saved = plain_path(archive / old.name)
            require(old.is_file() or saved.is_file(), f"missing source and archive: {old}")
            data = old.read_bytes() if old.exists() else saved.read_bytes()
            if saved.exists():
                require(saved.read_bytes() == data, f"archive conflict: {saved}")
            records.append((old, saved, data))
        require(records[0][2] == spec_bytes, "original spec differs from verified pack")
        confirmation = json.loads(records[1][2])
        confirmation["spec_path"] = spec_path.as_posix()
        require(confirmation == json.loads(spec_path.with_suffix(".confirmation.json").read_bytes()),
                "original confirmation differs from verified pack")

    if app["spec_path"] != spec_path.as_posix():
        app["spec_path"] = spec_path.as_posix()
        app["updated_at"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
        write_application(app_path, (json.dumps(app, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    try:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = check_spec.resolve_application_cli(pathlib.Path.cwd(), subsidy_id, None, False)
        require(status == 0 and output.getvalue().strip() == spec_path.as_posix(),
                "promoted spec could not be resolved; application restored")
    except (SystemExit, OSError, ValueError, KeyError, TypeError):
        write_application(app_path, before)
        raise

    if records:
        archive.mkdir(parents=True, exist_ok=True)
        # Exclusive copies preserve bytes without requiring hardlink support.
        for old, saved, data in records:
            if not saved.exists():
                copy_exclusive(saved, data)
            require(saved.read_bytes() == data, f"archive bytes differ: {saved}")
        for old, saved, data in records:
            if old.exists():
                require(old.read_bytes() == saved.read_bytes() == data, f"source bytes changed: {old}")
                old.unlink()
        print(f"OK: original files archived in {archive}")
    print(f"OK: verified pack selected: {spec_path}")


def main(argv):
    args = argv[1:]
    require(len(args) in (2, 4),
            "usage: bash tools/promote-pack.sh <subsidy_id> <source_spec_path> [--root <dir>]")
    if len(args) == 4:
        require(args[2] == "--root", "expected --root <dir>")
    previous = pathlib.Path.cwd()
    try:
        if len(args) == 4:
            os.chdir(args[3])
        promote(args[0], args[1])
    finally:
        os.chdir(previous)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as exc:
        raise SystemExit(f"FAIL: pack promotion stopped: {exc}")
