#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import shutil
import sys
import typing


STATE_FILE = ".update-core-state.json"
MANIFEST_FILE = "core-manifest.json"
DISALLOWED_PREFIXES = ("input/", "knowledge/")


class UpdateCoreError(Exception):
    pass


class FileStatus(typing.NamedTuple):
    relpath: str
    status: str
    local_path: pathlib.Path
    upstream_path: pathlib.Path
    local_hash: typing.Optional[str]
    upstream_hash: str
    previous_hash: typing.Optional[str]


def sha256_file(path: pathlib.Path) -> typing.Optional[str]:
    if not path.exists():
        return None
    if not path.is_file():
        raise UpdateCoreError(f"not a regular file: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_join(root: pathlib.Path, relpath: str) -> pathlib.Path:
    root_resolved = root.resolve()
    candidate = root.joinpath(*pathlib.PurePosixPath(relpath).parts)
    resolved = candidate.resolve(strict=False)
    try:
        resolved.relative_to(root_resolved)
    except ValueError as exc:
        raise UpdateCoreError(f"path escapes repository root: {relpath}") from exc
    return candidate


def normalize_manifest_path(value: typing.Any) -> str:
    if not isinstance(value, str):
        raise UpdateCoreError(f"manifest path must be a string: {value!r}")
    if not value or value.strip() != value:
        raise UpdateCoreError(f"manifest path has invalid whitespace: {value!r}")
    if "\\" in value:
        raise UpdateCoreError(f"manifest path must use forward slashes: {value}")
    if any(ch in value for ch in "*?[]"):
        raise UpdateCoreError(f"manifest path must not contain glob syntax: {value}")

    pure = pathlib.PurePosixPath(value)
    if pure.is_absolute():
        raise UpdateCoreError(f"manifest path must be relative: {value}")
    if any(part in ("", ".", "..") for part in pure.parts):
        raise UpdateCoreError(f"manifest path must be normalized: {value}")
    if value == STATE_FILE:
        raise UpdateCoreError(f"{STATE_FILE} must not be part of core_paths")
    if any(value == prefix[:-1] or value.startswith(prefix) for prefix in DISALLOWED_PREFIXES):
        raise UpdateCoreError(f"user data path must not be part of core_paths: {value}")
    if value.startswith(".claude/commands/my-") or "/my-" in value:
        raise UpdateCoreError(f"user command path must not be part of core_paths: {value}")
    return value


def load_manifest(upstream_root: pathlib.Path) -> typing.List[str]:
    manifest_path = upstream_root / MANIFEST_FILE
    try:
        with manifest_path.open(encoding="utf-8") as fh:
            manifest = json.load(fh)
    except FileNotFoundError as exc:
        raise UpdateCoreError(f"missing upstream {MANIFEST_FILE}: {manifest_path}") from exc
    except json.JSONDecodeError as exc:
        raise UpdateCoreError(f"invalid upstream {MANIFEST_FILE}: line {exc.lineno} column {exc.colno}") from exc

    if not isinstance(manifest, dict):
        raise UpdateCoreError(f"{MANIFEST_FILE} must be a JSON object")
    if "manifest_version" not in manifest:
        raise UpdateCoreError(f"{MANIFEST_FILE} missing manifest_version")
    core_paths = manifest.get("core_paths")
    if not isinstance(core_paths, list) or not core_paths:
        raise UpdateCoreError(f"{MANIFEST_FILE}.core_paths must be a non-empty array")

    normalized: typing.List[str] = []
    seen: typing.Set[str] = set()
    for raw_path in core_paths:
        relpath = normalize_manifest_path(raw_path)
        if relpath in seen:
            raise UpdateCoreError(f"duplicate core_paths entry: {relpath}")
        seen.add(relpath)
        normalized.append(relpath)
    if MANIFEST_FILE not in seen:
        raise UpdateCoreError(f"{MANIFEST_FILE} must list itself in core_paths")
    return normalized


def load_state(repo_root: pathlib.Path) -> typing.Dict[str, str]:
    state_path = repo_root / STATE_FILE
    if not state_path.exists():
        return {}
    try:
        with state_path.open(encoding="utf-8") as fh:
            state = json.load(fh)
    except json.JSONDecodeError as exc:
        raise UpdateCoreError(f"invalid {STATE_FILE}: line {exc.lineno} column {exc.colno}") from exc

    if not isinstance(state, dict):
        raise UpdateCoreError(f"{STATE_FILE} must be a JSON object")
    files = state.get("files")
    if not isinstance(files, dict):
        raise UpdateCoreError(f"{STATE_FILE}.files must be an object")

    normalized: typing.Dict[str, str] = {}
    for raw_path, raw_hash in files.items():
        relpath = normalize_manifest_path(raw_path)
        if not isinstance(raw_hash, str) or len(raw_hash) != 64:
            raise UpdateCoreError(f"invalid sha256 in {STATE_FILE}: {relpath}")
        normalized[relpath] = raw_hash
    return normalized


def write_state(repo_root: pathlib.Path, files: typing.Dict[str, str]) -> None:
    state_path = repo_root / STATE_FILE
    tmp_path = repo_root / f"{STATE_FILE}.tmp"
    payload = {
        "state_version": 1,
        "files": {key: files[key] for key in sorted(files)},
    }
    with tmp_path.open("w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    tmp_path.replace(state_path)


def classify_files(
    repo_root: pathlib.Path,
    upstream_root: pathlib.Path,
    core_paths: typing.List[str],
    state_files: typing.Dict[str, str],
) -> typing.List[FileStatus]:
    statuses: typing.List[FileStatus] = []
    for relpath in core_paths:
        upstream_path = safe_join(upstream_root, relpath)
        local_path = safe_join(repo_root, relpath)

        if not upstream_path.is_file():
            raise UpdateCoreError(f"upstream manifest path is not a regular file: {relpath}")
        if local_path.exists() and not local_path.is_file():
            raise UpdateCoreError(f"local manifest path is not a regular file: {relpath}")

        upstream_hash = sha256_file(upstream_path)
        if upstream_hash is None:
            raise UpdateCoreError(f"upstream manifest path is missing: {relpath}")
        local_hash = sha256_file(local_path)
        previous_hash = state_files.get(relpath)

        if local_hash is None:
            status = "new"
        elif local_hash == upstream_hash:
            status = "unchanged"
        elif previous_hash is None:
            status = "user-modified"
        elif local_hash != previous_hash:
            status = "user-modified"
        else:
            status = "changed"

        statuses.append(
            FileStatus(
                relpath=relpath,
                status=status,
                local_path=local_path,
                upstream_path=upstream_path,
                local_hash=local_hash,
                upstream_hash=upstream_hash,
                previous_hash=previous_hash,
            )
        )
    return statuses


def apply_updates(
    statuses: typing.List[FileStatus],
    state_files: typing.Dict[str, str],
    force_files: typing.Set[str],
) -> typing.Dict[str, str]:
    next_state = dict(state_files)
    manifest_paths = {item.relpath for item in statuses}
    unknown_forces = sorted(force_files - manifest_paths)
    if unknown_forces:
        raise UpdateCoreError("--force-file path is not in upstream core_paths: " + ", ".join(unknown_forces))

    for item in statuses:
        print(f"{item.status}\t{item.relpath}")
        if item.status == "user-modified" and item.relpath not in force_files:
            print(f"WARN: skipped user-modified {item.relpath} (use --force-file {item.relpath} to override)")
            continue
        if item.status in {"new", "changed", "user-modified"}:
            item.local_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item.upstream_path, item.local_path)
        next_state[item.relpath] = item.upstream_hash
    return next_state


def parse_args(argv: typing.List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Update saita-kun-planner core files from an upstream checkout."
    )
    parser.add_argument("upstream_checkout", help="Path to the upstream checkout to copy core files from.")
    parser.add_argument("--repo-root", required=True, help=argparse.SUPPRESS)
    parser.add_argument("--dry-run", action="store_true", help="Print per-file status without changing files.")
    parser.add_argument("--apply", action="store_true", help="Copy changed manifest files that are not user-modified.")
    parser.add_argument(
        "--force-file",
        action="append",
        default=[],
        help="With --apply, overwrite one user-modified manifest path.",
    )
    args = parser.parse_args(argv)
    if args.dry_run and args.apply:
        parser.error("--dry-run and --apply are mutually exclusive")
    if args.force_file and not args.apply:
        parser.error("--force-file requires --apply")
    return args


def main(argv: typing.List[str]) -> int:
    args = parse_args(argv)
    repo_root = pathlib.Path(args.repo_root).resolve()
    upstream_root = pathlib.Path(args.upstream_checkout).resolve()
    if not upstream_root.is_dir():
        print(f"FAIL: upstream checkout is not a directory: {upstream_root}", file=sys.stderr)
        return 1

    try:
        core_paths = load_manifest(upstream_root)
        state_files = load_state(repo_root)
        force_files = {normalize_manifest_path(path) for path in args.force_file}
        statuses = classify_files(repo_root, upstream_root, core_paths, state_files)
        if args.apply:
            next_state = apply_updates(statuses, state_files, force_files)
            write_state(repo_root, next_state)
        else:
            for item in statuses:
                print(f"{item.status}\t{item.relpath}")
        return 0
    except UpdateCoreError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
