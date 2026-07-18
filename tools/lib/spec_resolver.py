#!/usr/bin/env python3
"""Resolve canonical bundled subsidy specs with pack precedence."""

from __future__ import annotations

import dataclasses
import json
import pathlib
import typing


Json = typing.Any


class ResolverError(Exception):
    """Raised when bundled specs cannot be resolved without ambiguity."""

    def __init__(self, messages: typing.Iterable[str]) -> None:
        self.messages = tuple(messages)
        super().__init__("; ".join(self.messages))


@dataclasses.dataclass(frozen=True)
class BundledSpec:
    subsidy_id: str
    spec_path: pathlib.Path
    source_kind: str
    pack_path: typing.Optional[pathlib.Path] = None


def repo_relative_path(path: pathlib.Path, repo_root: pathlib.Path) -> str:
    """Return a stable POSIX path, relative to the repository when possible."""

    try:
        return path.resolve().relative_to(repo_root.resolve()).as_posix()
    except (OSError, ValueError):
        return path.as_posix()


def _load_object(path: pathlib.Path, label: str, errors: typing.List[str]) -> typing.Optional[typing.Dict[str, Json]]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        errors.append(f"{label} not found: {path.as_posix()}")
        return None
    except json.JSONDecodeError as exc:
        errors.append(
            f"{label} invalid JSON: {path.as_posix()}: "
            f"line {exc.lineno} column {exc.colno}"
        )
        return None
    except OSError as exc:
        errors.append(f"{label} cannot be read: {path.as_posix()}: {exc}")
        return None
    if not isinstance(value, dict):
        errors.append(f"{label} root must be an object: {path.as_posix()}")
        return None
    return value


def _pack_spec_path(
    pack_path: pathlib.Path,
    pack: typing.Dict[str, Json],
    errors: typing.List[str],
) -> typing.Optional[pathlib.Path]:
    spec_entry = pack.get("spec")
    raw_path = spec_entry.get("path") if isinstance(spec_entry, dict) else None
    if not isinstance(raw_path, str) or not raw_path:
        errors.append(f"pack.spec.path must be a non-empty string: {pack_path.as_posix()}")
        return None

    pure_path = pathlib.PurePosixPath(raw_path)
    if (
        pure_path.is_absolute()
        or "\\" in raw_path
        or pure_path.as_posix() != raw_path
        or any(part in {"", ".", ".."} for part in pure_path.parts)
    ):
        errors.append(f"pack.spec.path must be a normalized relative path: {pack_path.as_posix()}")
        return None

    candidate = pack_path.parent.joinpath(*pure_path.parts)
    try:
        candidate.resolve().relative_to(pack_path.parent.resolve())
    except (OSError, ValueError):
        errors.append(f"pack.spec.path escapes its pack directory: {pack_path.as_posix()}")
        return None
    if not candidate.is_file():
        errors.append(
            f"pack spec file not found: {pack_path.as_posix()} -> {candidate.as_posix()}"
        )
        return None
    return candidate


def _duplicate_messages(
    grouped: typing.Dict[str, typing.List[BundledSpec]],
    source_kind: str,
    repo_root: pathlib.Path,
) -> typing.List[str]:
    messages: typing.List[str] = []
    for subsidy_id, candidates in sorted(grouped.items()):
        if len(candidates) < 2:
            continue
        paths = ", ".join(
            sorted(repo_relative_path(candidate.spec_path, repo_root) for candidate in candidates)
        )
        messages.append(
            f"duplicate bundled subsidy_id in {source_kind} specs: {subsidy_id}: {paths}"
        )
    return messages


def resolve_bundled_specs(
    bundled_root: pathlib.Path,
    repo_root: pathlib.Path,
) -> typing.List[BundledSpec]:
    """Resolve one canonical spec per subsidy_id.

    Canonical packs (``<root>/<pack>/pack.json``) take precedence over residual
    flat specs (``<root>/<id>.json``). Duplicate IDs within either source kind
    are rejected instead of being selected by filesystem iteration order.
    """

    errors: typing.List[str] = []
    if not bundled_root.is_dir():
        raise ResolverError([f"bundled specs directory not found: {bundled_root.as_posix()}"])

    packs_by_id: typing.Dict[str, typing.List[BundledSpec]] = {}
    for pack_path in sorted(bundled_root.glob("*/pack.json"), key=lambda path: path.as_posix()):
        pack = _load_object(pack_path, "pack", errors)
        if pack is None:
            continue
        subsidy_id = pack.get("subsidy_id")
        if not isinstance(subsidy_id, str) or not subsidy_id:
            errors.append(f"pack.subsidy_id must be a non-empty string: {pack_path.as_posix()}")
            continue
        spec_path = _pack_spec_path(pack_path, pack, errors)
        if spec_path is None:
            continue
        spec = _load_object(spec_path, "pack spec", errors)
        if spec is None:
            continue
        if spec.get("subsidy_id") != subsidy_id:
            errors.append(
                f"pack subsidy_id mismatch: {pack_path.as_posix()} declares {subsidy_id!r}, "
                f"spec declares {spec.get('subsidy_id')!r}"
            )
            continue
        packs_by_id.setdefault(subsidy_id, []).append(
            BundledSpec(subsidy_id, spec_path, "pack", pack_path)
        )

    flats_by_id: typing.Dict[str, typing.List[BundledSpec]] = {}
    for spec_path in sorted(bundled_root.glob("*.json"), key=lambda path: path.as_posix()):
        if spec_path.name == "pack.json" or spec_path.name.endswith(".confirmation.json"):
            continue
        spec = _load_object(spec_path, "flat spec", errors)
        if spec is None:
            continue
        subsidy_id = spec.get("subsidy_id")
        if subsidy_id is None:
            continue
        if not isinstance(subsidy_id, str) or not subsidy_id:
            errors.append(
                f"flat spec subsidy_id must be a non-empty string: {spec_path.as_posix()}"
            )
            continue
        flats_by_id.setdefault(subsidy_id, []).append(
            BundledSpec(subsidy_id, spec_path, "flat")
        )

    errors.extend(_duplicate_messages(packs_by_id, "pack", repo_root))
    errors.extend(_duplicate_messages(flats_by_id, "flat", repo_root))
    if errors:
        raise ResolverError(errors)

    resolved: typing.List[BundledSpec] = []
    for subsidy_id in sorted(set(packs_by_id) | set(flats_by_id)):
        if subsidy_id in packs_by_id:
            resolved.append(packs_by_id[subsidy_id][0])
        else:
            resolved.append(flats_by_id[subsidy_id][0])
    return sorted(
        resolved,
        key=lambda candidate: repo_relative_path(candidate.spec_path, repo_root),
    )
