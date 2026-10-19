#!/usr/bin/env python3
"""Reject prohibited customer-facing claims in the public export surface.

The Japanese phrase set is derived from
saita-kun-web docs/policies/lp-forbidden-phrases.txt
(fixed subset, 2026-07-17). This checker is intentionally maintained as an
independent fixed version and does not synchronize with that repository.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Iterable


EXPORT_EXCLUDED_PATHS = pathlib.PurePosixPath(
    "tools/lib/export-excluded-paths.txt"
)
DEFAULT_ALLOWLIST = pathlib.PurePosixPath(
    "tools/forbidden-phrase-allowlist.json"
)

# Keep this as the single negation-term constant used by the checker and tests.
NEGATION_TERMS = (
    "ません",
    "しません",
    "いたしません",
    "行いません",
    "ではありません",
    "ではない",
    "ではなく",
    "しない",
    "行わない",
    "できません",
    "できない",
    "禁止",
    "不可",
)

JAPANESE_FORBIDDEN_PATTERNS = (
    ("adoption-result", re.compile(r"採択され(?:ます|る)")),
    ("adoption-causative", re.compile(r"採択させます")),
    (
        "certain-adoption",
        re.compile(r"(?:必ず|絶対に?|確実に)(?:採択|通り|受かり)"),
    ),
    ("will-pass", re.compile(r"(?:通り|受かり)ます")),
    ("guarantee", re.compile(r"保証(?:します|いたします)")),
    ("guarantee-adoption", re.compile(r"採択を保証")),
    ("fully-automatic", re.compile(r"(?:全|完全)自動")),
    ("automatic-action", re.compile(r"自動で(?:作成|完成|申請|提出)")),
    ("drafting-agency", re.compile(r"作成代行")),
    ("proxy-action", re.compile(r"代理(?:提出|申請)")),
    ("ghostwriting", re.compile(r"代筆")),
    ("success-fee", re.compile(r"成功報酬")),
)

ENGLISH_FORBIDDEN_PATTERNS = (
    ("guaranteed-approval", re.compile(r"guaranteed\s+approval", re.I)),
    ("guarantee-of-adoption", re.compile(r"guarantee\s+of\s+adoption", re.I)),
    (
        "file-on-behalf",
        re.compile(r"\bwe\s+(?:file|submit)\s+on\s+your\s+behalf\b", re.I),
    ),
    ("on-behalf", re.compile(r"\bon\s+your\s+behalf\b", re.I)),
    (
        "fully-automated-filing",
        re.compile(r"fully\s+automated\s+(?:filing|submission)", re.I),
    ),
    (
        "automatic-filing",
        re.compile(r"automatically\s+(?:files|submits)", re.I),
    ),
    ("certain-success", re.compile(r"100%\s+(?:success|approval)", re.I)),
)

CUSTOMER_TEXT_SUFFIXES = frozenset({".md", ".markdown", ".yml", ".yaml"})
CUSTOMER_TEXT_TREES = frozenset({"templates", "examples"})


@dataclass(frozen=True)
class Hit:
    path: str
    line: int
    language: str
    pattern: str
    phrase: str
    sentence: str


@dataclass(frozen=True)
class AllowlistEntry:
    path: str
    sentence: str
    reason: str


def _normalized_relative_path(value: str, *, source: str) -> str:
    candidate = value.strip().rstrip("/")
    pure = pathlib.PurePosixPath(candidate)
    if (
        not candidate
        or candidate.startswith("/")
        or "\\" in candidate
        or any(part in {"", ".", ".."} for part in pure.parts)
    ):
        raise ValueError(f"invalid relative path in {source}: {value!r}")
    return pure.as_posix()


def parse_export_excluded_paths(text: str, *, source: str) -> tuple[str, ...]:
    """Parse the shared list without silently changing path entries."""
    entries: list[str] = []
    seen: set[str] = set()
    for line_number, raw_line in enumerate(text.split("\n"), start=1):
        line_source = f"{source}:{line_number}"
        if "\r" in raw_line:
            raise ValueError(
                f"export exclusion line contains CR in {line_source}: {raw_line!r}"
            )
        if raw_line == "":
            continue
        if raw_line.startswith("#"):
            continue
        if any(character.isspace() for character in raw_line):
            raise ValueError(
                "export exclusion path contains whitespace in "
                f"{line_source}: {raw_line!r}"
            )

        candidate = raw_line[:-1] if raw_line.endswith("/") else raw_line
        entry = _normalized_relative_path(candidate, source=line_source)
        if candidate != entry:
            raise ValueError(
                f"export exclusion path is not normalized in {line_source}: "
                f"{raw_line!r}"
            )
        if entry in seen:
            raise ValueError(f"duplicate export exclusion path in {line_source}: {entry}")
        entries.append(entry)
        seen.add(entry)
    if not entries:
        raise ValueError(f"export exclusion path list is empty: {source}")
    return tuple(entries)


def load_export_excluded_paths(root: pathlib.Path) -> tuple[str, ...]:
    path = root / EXPORT_EXCLUDED_PATHS
    return parse_export_excluded_paths(
        path.read_text(encoding="utf-8"), source=path.as_posix()
    )


def is_export_excluded(path: str, excluded_paths: Iterable[str]) -> bool:
    return any(path == entry or path.startswith(f"{entry}/") for entry in excluded_paths)


def is_customer_owned_path(path: str) -> bool:
    pure = pathlib.PurePosixPath(path)
    if not pure.parts:
        return False
    if pure.parts[0] == "input":
        return True
    return bool(
        len(pure.parts) >= 2
        and pure.parts[0] == "knowledge"
        and pure.parts[1] in {"records", "lessons"}
    )


def is_customer_text_path(path: str) -> bool:
    pure = pathlib.PurePosixPath(path)
    return (
        pure.suffix.lower() in CUSTOMER_TEXT_SUFFIXES
        or (pure.parts and pure.parts[0] in CUSTOMER_TEXT_TREES)
    )


def repository_text_paths(root: pathlib.Path) -> tuple[str, ...]:
    excluded_paths = load_export_excluded_paths(root)
    result = subprocess.run(
        [
            "git",
            "-C",
            str(root),
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ValueError(f"cannot list repository files: {detail}")
    repository_paths = result.stdout.decode("utf-8").split("\0")
    candidates = tuple(
        sorted(
            path
            for path in repository_paths
            if path
            if not is_customer_owned_path(path)
            and not is_export_excluded(path, excluded_paths)
            and is_customer_text_path(path)
        )
    )
    missing = [path for path in candidates if not (root / path).is_file()]
    if missing:
        raise ValueError(f"public core customer-text file is missing: {missing}")
    return candidates


def iter_sentences(text: str) -> Iterable[tuple[int, str]]:
    """Yield non-empty sentences split at Japanese stops and newlines."""
    for line_number, line in enumerate(text.splitlines(), start=1):
        for sentence in line.split("。"):
            normalized = sentence.strip()
            if normalized:
                yield line_number, normalized


def load_allowlist(path: pathlib.Path) -> tuple[AllowlistEntry, ...]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("allowlist_version") != 1:
        raise ValueError(f"unsupported allowlist_version in {path}")
    raw_entries = document.get("entries")
    if not isinstance(raw_entries, list):
        raise ValueError(f"allowlist entries must be an array: {path}")
    entries: list[AllowlistEntry] = []
    seen: set[tuple[str, str]] = set()
    for index, raw in enumerate(raw_entries):
        if not isinstance(raw, dict):
            raise ValueError(f"allowlist entry {index} must be an object")
        raw_path = raw.get("path")
        raw_sentence = raw.get("sentence")
        raw_reason = raw.get("reason")
        if not all(
            isinstance(value, str) and bool(value.strip())
            for value in (raw_path, raw_sentence, raw_reason)
        ):
            raise ValueError(
                f"allowlist entry {index} requires non-empty string values for "
                "path, sentence, and reason"
            )
        entry_path = _normalized_relative_path(
            raw_path, source=f"{path}:entries[{index}].path"
        )
        sentence = raw_sentence.strip()
        reason = raw_reason.strip()
        key = (entry_path, sentence)
        if key in seen:
            raise ValueError(f"duplicate allowlist entry: {entry_path}: {sentence}")
        entries.append(AllowlistEntry(entry_path, sentence, reason))
        seen.add(key)
    return tuple(entries)


def find_forbidden(
    text: str,
    source_path: str,
    allowed_sentences: Iterable[tuple[str, str]] = (),
) -> tuple[list[Hit], set[tuple[str, str]]]:
    allowed = set(allowed_sentences)
    hits: list[Hit] = []
    used_allowlist: set[tuple[str, str]] = set()
    for line, sentence in iter_sentences(text):
        candidates: list[Hit] = []
        if not any(term in sentence for term in NEGATION_TERMS):
            for name, pattern in JAPANESE_FORBIDDEN_PATTERNS:
                for match in pattern.finditer(sentence):
                    candidates.append(
                        Hit(source_path, line, "ja", name, match.group(0), sentence)
                    )
        for name, pattern in ENGLISH_FORBIDDEN_PATTERNS:
            for match in pattern.finditer(sentence):
                candidates.append(
                    Hit(source_path, line, "en", name, match.group(0), sentence)
                )
        key = (source_path, sentence)
        if candidates and key in allowed:
            used_allowlist.add(key)
        else:
            hits.extend(candidates)
    return hits, used_allowlist


def scan_repository(
    root: pathlib.Path,
    allowlist: tuple[AllowlistEntry, ...],
) -> tuple[list[Hit], set[tuple[str, str]]]:
    allowed_keys = {(entry.path, entry.sentence) for entry in allowlist}
    hits: list[Hit] = []
    used: set[tuple[str, str]] = set()
    for relative_path in repository_text_paths(root):
        text = (root / relative_path).read_text(encoding="utf-8")
        file_hits, file_used = find_forbidden(text, relative_path, allowed_keys)
        hits.extend(file_hits)
        used.update(file_used)
    return hits, used


def _print_hit(hit: Hit) -> None:
    print(
        f"FORBIDDEN: {hit.path}:{hit.line}: {hit.language}/{hit.pattern}: "
        f"{hit.phrase!r} in {hit.sentence!r}"
    )


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check public customer-facing text for prohibited claims."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Explicit UTF-8 files to scan; repository mode is used when omitted.",
    )
    parser.add_argument(
        "--repo-root",
        type=pathlib.Path,
        help="Repository root; defaults to the root containing this helper.",
    )
    parser.add_argument(
        "--allowlist",
        type=pathlib.Path,
        help="Use an explicit reviewed sentence allowlist.",
    )
    parser.add_argument(
        "--no-allowlist",
        action="store_true",
        help="Disable the default allowlist.",
    )
    parser.add_argument(
        "--list-files",
        action="store_true",
        help="List repository files in the public customer-text scan surface.",
    )
    parser.add_argument(
        "--normalize-export-exclusions",
        type=pathlib.Path,
        metavar="PATH",
        help="Validate an exclusion list and print one normalized path per line.",
    )
    args = parser.parse_args(argv)
    if args.allowlist and args.no_allowlist:
        parser.error("--allowlist and --no-allowlist are mutually exclusive")
    if args.list_files and args.paths:
        parser.error("--list-files does not accept explicit paths")
    if args.normalize_export_exclusions and (
        args.paths
        or args.list_files
        or args.allowlist
        or args.no_allowlist
        or args.repo_root
    ):
        parser.error(
            "--normalize-export-exclusions does not accept other modes or options"
        )
    return args


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.normalize_export_exclusions:
            exclusion_path = args.normalize_export_exclusions
            for entry in parse_export_excluded_paths(
                exclusion_path.read_text(encoding="utf-8"),
                source=exclusion_path.as_posix(),
            ):
                print(entry)
            return 0
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"ERROR: forbidden phrase checker: {exc}", file=sys.stderr)
        return 2

    root = (
        args.repo_root.resolve()
        if args.repo_root
        else pathlib.Path(__file__).resolve().parents[2]
    )
    try:
        if args.list_files:
            for relative_path in repository_text_paths(root):
                print(relative_path)
            return 0

        if args.paths:
            allowlist_path = args.allowlist
            allowlist = load_allowlist(allowlist_path) if allowlist_path else ()
            allowed_keys = {(entry.path, entry.sentence) for entry in allowlist}
            hits: list[Hit] = []
            for raw_path in args.paths:
                path = pathlib.Path(raw_path)
                source_path = path.as_posix()
                file_hits, _ = find_forbidden(
                    path.read_text(encoding="utf-8"), source_path, allowed_keys
                )
                hits.extend(file_hits)
            for hit in hits:
                _print_hit(hit)
            return 1 if hits else 0

        if args.no_allowlist:
            allowlist = ()
        else:
            allowlist_path = args.allowlist or root / DEFAULT_ALLOWLIST
            allowlist = load_allowlist(allowlist_path)
        hits, used = scan_repository(root, allowlist)
        for hit in hits:
            _print_hit(hit)
        stale = {
            (entry.path, entry.sentence)
            for entry in allowlist
            if (entry.path, entry.sentence) not in used
        }
        for path, sentence in sorted(stale):
            print(f"STALE_ALLOWLIST: {path}: {sentence!r}")
        return 1 if hits or stale else 0
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"ERROR: forbidden phrase checker: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
