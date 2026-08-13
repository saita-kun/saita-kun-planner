#!/usr/bin/env python3
import json
import pathlib
import sys
import typing


Json = typing.Any

TRUE = "true"
FALSE = "false"
UNKNOWN = "unknown"
MISSING = object()
VALID_SCOPES = {"profile", "application"}
VALID_OPS = {"eq", "ne", "lt", "lte", "gt", "gte", "in", "contains", "exists"}


def load_json(path: pathlib.Path) -> Json:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def find_rule(spec: Json, rule_id: str) -> typing.Optional[typing.Dict[str, Json]]:
    if not isinstance(spec, dict):
        return None
    eligibility = spec.get("eligibility")
    if not isinstance(eligibility, dict):
        return None
    rules = eligibility.get("rules")
    if not isinstance(rules, list):
        return None
    for rule in rules:
        if isinstance(rule, dict) and rule.get("rule_id") == rule_id:
            return rule
    return None


def get_path(root: Json, key: str) -> Json:
    current = root
    for part in key.split("."):
        if isinstance(current, dict) and part in current:
            current = current[part]
            continue
        return MISSING
    return current


def kleene_not(value: str) -> str:
    if value == TRUE:
        return FALSE
    if value == FALSE:
        return TRUE
    return UNKNOWN


def eval_all(items: typing.List[Json], contexts: typing.Dict[str, Json]) -> str:
    saw_unknown = False
    for item in items:
        value = eval_predicate(item, contexts)
        if value == FALSE:
            return FALSE
        if value == UNKNOWN:
            saw_unknown = True
    return UNKNOWN if saw_unknown else TRUE


def eval_any(items: typing.List[Json], contexts: typing.Dict[str, Json]) -> str:
    saw_unknown = False
    for item in items:
        value = eval_predicate(item, contexts)
        if value == TRUE:
            return TRUE
        if value == UNKNOWN:
            saw_unknown = True
    return UNKNOWN if saw_unknown else FALSE


def comparison_category(value: Json) -> typing.Optional[str]:
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, (int, float)):
        return "number"
    if isinstance(value, str):
        return "string"
    return None


def compare_values(actual: Json, op: str, expected: Json) -> str:
    try:
        if op == "eq":
            if comparison_category(actual) is None or comparison_category(actual) != comparison_category(expected):
                return UNKNOWN
            return TRUE if actual == expected else FALSE
        if op == "ne":
            if comparison_category(actual) is None or comparison_category(actual) != comparison_category(expected):
                return UNKNOWN
            return TRUE if actual != expected else FALSE
        if op == "lt":
            return TRUE if actual < expected else FALSE
        if op == "lte":
            return TRUE if actual <= expected else FALSE
        if op == "gt":
            return TRUE if actual > expected else FALSE
        if op == "gte":
            return TRUE if actual >= expected else FALSE
        if op == "in":
            if not isinstance(expected, list):
                return UNKNOWN
            return TRUE if actual in expected else FALSE
        if op == "contains":
            return TRUE if expected in actual else FALSE
    except (TypeError, ValueError):
        return UNKNOWN
    return UNKNOWN


def eval_leaf(predicate: typing.Dict[str, Json], contexts: typing.Dict[str, Json]) -> str:
    scope = predicate.get("scope")
    key = predicate.get("key")
    op = predicate.get("op")
    if scope not in VALID_SCOPES:
        return UNKNOWN
    if not isinstance(key, str) or not key:
        return UNKNOWN
    if op not in VALID_OPS:
        return UNKNOWN

    context = contexts.get(scope)
    if context is None:
        return UNKNOWN

    actual = get_path(context, key)
    if actual is MISSING or actual is None:
        return UNKNOWN
    if op == "exists":
        return TRUE
    if "value" not in predicate:
        return UNKNOWN
    return compare_values(actual, op, predicate.get("value"))


def eval_predicate(predicate: Json, contexts: typing.Dict[str, Json]) -> str:
    if predicate is None:
        return UNKNOWN
    if not isinstance(predicate, dict):
        return UNKNOWN

    keys = set(predicate)
    if keys == {"all"}:
        items = predicate.get("all")
        return eval_all(items, contexts) if isinstance(items, list) and items else UNKNOWN
    if keys == {"any"}:
        items = predicate.get("any")
        return eval_any(items, contexts) if isinstance(items, list) and items else UNKNOWN
    if keys == {"not"}:
        return kleene_not(eval_predicate(predicate.get("not"), contexts))

    allowed_leaf_keys = {"scope", "key", "op", "value"}
    if keys - allowed_leaf_keys:
        return UNKNOWN
    if not {"scope", "key", "op"}.issubset(keys):
        return UNKNOWN
    if predicate.get("op") != "exists" and "value" not in predicate:
        return UNKNOWN
    return eval_leaf(predicate, contexts)


def build_contexts(profile_doc: Json) -> typing.Dict[str, Json]:
    profile = profile_doc
    application: Json = {}
    if isinstance(profile_doc, dict):
        if isinstance(profile_doc.get("profile"), dict):
            profile = profile_doc["profile"]
        if isinstance(profile_doc.get("application"), dict):
            application = profile_doc["application"]
    return {"profile": profile, "application": application}


def main(argv: typing.List[str]) -> int:
    if len(argv) != 4:
        print("usage: python3 tools/lib/predicate.py <spec.json> <rule_id> <profile.json>", file=sys.stderr)
        return 1

    spec = load_json(pathlib.Path(argv[1]))
    rule = find_rule(spec, argv[2])
    if rule is None:
        print(UNKNOWN)
        return 0

    profile_doc = load_json(pathlib.Path(argv[3]))
    print(eval_predicate(rule.get("predicate"), build_contexts(profile_doc)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
