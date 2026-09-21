#!/usr/bin/env python3
import argparse
import errno
import hashlib
import json
import os
import pathlib
import stat
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
    upstream_bytes: bytes
    upstream_stat: os.stat_result
    upstream_xattrs: typing.Dict[str, bytes]


def read_xattrs(fd: int) -> typing.Dict[str, bytes]:
    attributes: typing.Dict[str, bytes] = {}
    if sys.platform != "linux" or not hasattr(os, "listxattr"):
        return attributes
    try:
        names = os.listxattr(fd)
    except OSError as exc:
        if exc.errno not in (errno.ENOTSUP, errno.ENODATA, errno.EINVAL):
            raise
        return attributes
    for name in names:
        try:
            attributes[name] = os.getxattr(fd, name)
        except OSError as exc:
            # Match copystat's handling of unavailable or restricted attributes.
            if exc.errno not in (errno.EPERM, errno.ENOTSUP, errno.ENODATA,
                                 errno.EINVAL, errno.EACCES):
                raise
    return attributes


def write_xattrs(path: pathlib.Path, attributes: typing.Dict[str, bytes]) -> None:
    for name, value in attributes.items():
        try:
            os.setxattr(path, name, value)
        except OSError as exc:
            if exc.errno not in (errno.EPERM, errno.ENOTSUP, errno.ENODATA,
                                 errno.EINVAL, errno.EACCES):
                raise


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
    relpath = normalize_manifest_path(relpath)
    root_resolved = root.resolve()
    candidate = root.joinpath(*pathlib.PurePosixPath(relpath).parts)
    resolved = candidate.resolve(strict=False)
    try:
        resolved_relative = resolved.relative_to(root_resolved)
    except ValueError as exc:
        raise UpdateCoreError(f"path escapes repository root: {relpath}") from exc
    check_protected_update_path(resolved_relative.as_posix())
    return candidate


def check_protected_update_path(value: str) -> None:
    if value == STATE_FILE:
        raise UpdateCoreError(f"protected update path: {STATE_FILE} must not be part of core_paths")
    if any(value == prefix[:-1] or value.startswith(prefix) for prefix in DISALLOWED_PREFIXES):
        raise UpdateCoreError(f"protected update path: user data path must not be part of core_paths: {value}")
    if value.startswith(".claude/commands/my-") or "/my-" in value:
        raise UpdateCoreError(f"protected update path: user command path must not be part of core_paths: {value}")


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
    if value != pure.as_posix() or not pure.parts or ".." in pure.parts:
        raise UpdateCoreError(f"manifest path must be normalized: {value}")
    check_protected_update_path(value)
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
    with tmp_path.open("w", encoding="utf-8") as fh:
        fh.write("{\n")
        fh.write('  "state_version": 1,\n')
        sorted_keys = sorted(files)
        if sorted_keys:
            fh.write('  "files": {\n')
            for index, key in enumerate(sorted_keys):
                comma = "," if index < len(sorted_keys) - 1 else ""
                # Keep path keywords and sha256 values on separate lines for raw-text scanners.
                encoded_key = json.dumps(key, ensure_ascii=False)
                encoded_hash = json.dumps(files[key], ensure_ascii=False)
                fh.write(f"    {encoded_key}:\n")
                fh.write(f"      {encoded_hash}{comma}\n")
            fh.write("  }\n")
        else:
            fh.write('  "files": {}\n')
        fh.write("}\n")
    tmp_path.replace(state_path)


def build_state_files(repo_root: pathlib.Path, core_paths: typing.List[str]) -> typing.Dict[str, str]:
    files: typing.Dict[str, str] = {}
    for relpath in core_paths:
        path = safe_join(repo_root, relpath)
        file_hash = sha256_file(path)
        if file_hash is None:
            raise UpdateCoreError(f"manifest path is missing: {relpath}")
        files[relpath] = file_hash
    return files


def build_available_state_files(
    repo_root: pathlib.Path,
    core_paths: typing.List[str],
) -> typing.Dict[str, str]:
    files: typing.Dict[str, str] = {}
    for relpath in core_paths:
        path = safe_join(repo_root, relpath)
        file_hash = sha256_file(path)
        if file_hash is not None:
            files[relpath] = file_hash
    return files


def classify_status(
    local_hash: typing.Optional[str],
    upstream_hash: str,
    previous_hash: typing.Optional[str],
) -> str:
    if local_hash is None:
        return "new"
    if local_hash == upstream_hash:
        return "unchanged"
    if previous_hash is None:
        return "unknown-ancestor"
    if local_hash != previous_hash:
        return "user-modified"
    return "changed"


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

        # Capture content and metadata from the same open file for later apply.
        with upstream_path.open("rb") as fh:
            upstream_bytes = fh.read()
            upstream_stat = os.fstat(fh.fileno())
            upstream_xattrs = read_xattrs(fh.fileno())
        upstream_hash = hashlib.sha256(upstream_bytes).hexdigest()
        local_hash = sha256_file(local_path)
        previous_hash = state_files.get(relpath)
        status = classify_status(local_hash, upstream_hash, previous_hash)

        statuses.append(
            FileStatus(
                relpath=relpath,
                status=status,
                local_path=local_path,
                upstream_path=upstream_path,
                local_hash=local_hash,
                upstream_hash=upstream_hash,
                previous_hash=previous_hash,
                upstream_bytes=upstream_bytes,
                upstream_stat=upstream_stat,
                upstream_xattrs=upstream_xattrs,
            )
        )
    return statuses


def apply_updates(
    repo_root: pathlib.Path,
    upstream_root: pathlib.Path,
    statuses: typing.List[FileStatus],
    state_files: typing.Dict[str, str],
    force_files: typing.Set[str],
) -> typing.Dict[str, str]:
    next_state = dict(state_files)
    manifest_paths = {item.relpath for item in statuses}
    unknown_forces = sorted(force_files - manifest_paths)
    if unknown_forces:
        raise UpdateCoreError("--force-file path is not in upstream core_paths: " + ", ".join(unknown_forces))

    # Recheck every path before any writes, including paths skipped without force.
    for item in statuses:
        safe_join(upstream_root, item.relpath)
        safe_join(repo_root, item.relpath)

    for item in statuses:
        safe_join(upstream_root, item.relpath)
        local_path = safe_join(repo_root, item.relpath)
        # Use the latest local content for both reporting and the write decision.
        local_hash = sha256_file(local_path)
        status = classify_status(local_hash, item.upstream_hash, item.previous_hash)
        # Preserve intervening changes, including a restored ancestor or removal.
        if local_hash != item.local_hash:
            status = "user-modified"
        print(f"{status}\t{item.relpath}")
        if status == "unknown-ancestor" and item.relpath not in force_files:
            print(
                f"WARN: skipped unknown-ancestor {item.relpath} "
                "(no recorded ancestor; run --adopt-ancestor <installed-version-dir>, "
                f"or override with --force-file {item.relpath})"
            )
            continue
        if status == "user-modified" and item.relpath not in force_files:
            print(f"WARN: skipped user-modified {item.relpath} (use --force-file {item.relpath} to override)")
            continue
        if status in {"new", "changed", "unknown-ancestor", "user-modified"}:
            local_path.parent.mkdir(parents=True, exist_ok=True)
            local_path.write_bytes(item.upstream_bytes)
            # Restore captured xattrs before permissions, without reopening upstream.
            write_xattrs(local_path, item.upstream_xattrs)
            local_path.chmod(stat.S_IMODE(item.upstream_stat.st_mode))
            os.utime(local_path, ns=(item.upstream_stat.st_atime_ns, item.upstream_stat.st_mtime_ns))
            # Match copystat flags handling using only the captured metadata.
            if hasattr(item.upstream_stat, "st_flags") and hasattr(os, "chflags"):
                try:
                    os.chflags(local_path, item.upstream_stat.st_flags)
                except OSError as exc:
                    if exc.errno not in (errno.EOPNOTSUPP, errno.ENOTSUP):
                        raise
        next_state[item.relpath] = item.upstream_hash
    return next_state


def parse_args(argv: typing.List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Update saita-kun-planner core files from an upstream checkout."
    )
    parser.add_argument("upstream_checkout", nargs="?", help="Path to the upstream checkout to copy core files from.")
    parser.add_argument("--repo-root", required=True, help=argparse.SUPPRESS)
    parser.add_argument("--dry-run", action="store_true", help="Print per-file status without changing files.")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Copy changed manifest files not classified as user-modified or unknown-ancestor.",
    )
    parser.add_argument(
        "--generate-state",
        action="store_true",
        help=(
            f"Write {STATE_FILE} for the current repo-root from its own manifest. "
            "Use only in a repo whose core files have not been modified; modified content "
            "would become the ancestor and could be silently overwritten by a later --apply."
        ),
    )
    parser.add_argument(
        "--adopt-ancestor",
        metavar="DIR",
        help=(
            "Record ancestors from a checkout of the version this repo was created from "
            "(writes state only; never overwrites core files)."
        ),
    )
    parser.add_argument(
        "--force-file",
        action="append",
        default=[],
        help="With --apply, overwrite one user-modified or unknown-ancestor manifest path.",
    )
    args = parser.parse_args(argv)
    if args.dry_run and args.apply:
        parser.error("--dry-run and --apply are mutually exclusive")
    if args.adopt_ancestor is not None:
        if args.upstream_checkout:
            parser.error("--adopt-ancestor does not take upstream_checkout")
        if args.generate_state or args.dry_run or args.apply or args.force_file:
            parser.error("--adopt-ancestor cannot be combined with other modes or --force-file")
    else:
        if args.force_file and not args.apply:
            parser.error("--force-file requires --apply")
        if args.generate_state:
            if args.upstream_checkout:
                parser.error("--generate-state does not take upstream_checkout")
            if args.dry_run or args.apply or args.force_file:
                parser.error("--generate-state cannot be combined with update options")
        elif not args.upstream_checkout:
            parser.error("upstream_checkout is required unless --generate-state or --adopt-ancestor is used")
    return args


def main(argv: typing.List[str]) -> int:
    args = parse_args(argv)
    repo_root = pathlib.Path(args.repo_root).resolve()

    try:
        if args.generate_state:
            core_paths = load_manifest(repo_root)
            write_state(repo_root, build_state_files(repo_root, core_paths))
            return 0

        if args.adopt_ancestor is not None:
            ancestor_root = pathlib.Path(args.adopt_ancestor).resolve()
            if not ancestor_root.is_dir():
                raise UpdateCoreError(f"ancestor checkout is not a directory: {ancestor_root}")
            if ancestor_root == repo_root:
                raise UpdateCoreError(
                    "--adopt-ancestor directory resolves to --repo-root; "
                    "use --generate-state for an unmodified repo"
                )
            core_paths = load_manifest(ancestor_root)
            adopted_files = build_available_state_files(ancestor_root, core_paths)
            next_state = dict(load_state(repo_root))
            next_state.update(adopted_files)
            write_state(repo_root, next_state)
            print(f"adopted ancestor from {ancestor_root}: {len(adopted_files)} paths")
            return 0

        upstream_root = pathlib.Path(args.upstream_checkout).resolve()
        if not upstream_root.is_dir():
            print(f"FAIL: upstream checkout is not a directory: {upstream_root}", file=sys.stderr)
            return 1

        core_paths = load_manifest(upstream_root)
        state_files = load_state(repo_root)
        force_files = {normalize_manifest_path(path) for path in args.force_file}
        statuses = classify_files(repo_root, upstream_root, core_paths, state_files)
        if args.apply:
            next_state = apply_updates(repo_root, upstream_root, statuses, state_files, force_files)
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
