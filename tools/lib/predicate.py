#!/usr/bin/env python3
import argparse
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


class PredicateInputError(ValueError):
    pass


def load_json(path: pathlib.Path) -> Json:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def load_current_application(path: pathlib.Path) -> typing.Dict[str, Json]:
    try:
        application_doc = load_json(path)
    except FileNotFoundError:
        raise PredicateInputError(f"current application not found: {path}")
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise PredicateInputError(f"current application invalid JSON: {path}: {exc}")
    except OSError as exc:
        raise PredicateInputError(f"current application could not be read: {path}: {exc}")

    if not isinstance(application_doc, dict):
        raise PredicateInputError(f"current application root must be an object: {path}")
    return application_doc


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


def compare_membership(actual: Json, candidates: typing.List[Json]) -> str:
    if comparison_category(actual) is None:
        return UNKNOWN
    saw_unknown = False
    for candidate in candidates:
        result = compare_values(actual, "eq", candidate)
        if result == TRUE:
            return TRUE
        if result == UNKNOWN:
            saw_unknown = True
    return UNKNOWN if saw_unknown else FALSE


def compare_values(actual: Json, op: str, expected: Json) -> str:
    try:
        if op in {"eq", "ne", "lt", "lte", "gt", "gte"}:
            category = comparison_category(actual)
            if category is None or category != comparison_category(expected):
                return UNKNOWN
            if op in {"lt", "lte", "gt", "gte"} and category not in {"number", "string"}:
                return UNKNOWN
        if op == "eq":
            return TRUE if actual == expected else FALSE
        if op == "ne":
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
            return compare_membership(actual, expected)
        if op == "contains":
            if isinstance(actual, list):
                return compare_membership(expected, actual)
            if isinstance(actual, str) and isinstance(expected, str):
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


def predicate_uses_application_scope(predicate: Json) -> bool:
    if not isinstance(predicate, dict):
        return False
    if predicate.get("scope") == "application":
        return True

    for operator in ("all", "any"):
        items = predicate.get(operator)
        if isinstance(items, list):
            for item in items:
                if predicate_uses_application_scope(item):
                    return True
    if "not" in predicate:
        return predicate_uses_application_scope(predicate.get("not"))
    return False


def validate_application_binding(
    spec: typing.Dict[str, Json], application_doc: typing.Dict[str, Json]
) -> None:
    for key in ("subsidy_id", "spec_version"):
        if key not in application_doc:
            continue
        spec_value = spec.get(key)
        application_value = application_doc.get(key)
        validate_binding_value("current application", key, application_value)
        validate_binding_value("spec", key, spec_value)
        if application_value != spec_value:
            raise PredicateInputError(
                f"current application {key} mismatch: "
                f"spec={spec_value!r}, current application={application_value!r}"
            )


def validate_binding_value(source: str, key: str, value: Json) -> None:
    if key == "subsidy_id" and not isinstance(value, str):
        raise PredicateInputError(f"{source} subsidy_id must be a string")
    if key == "spec_version" and (
        not isinstance(value, int) or isinstance(value, bool)
    ):
        raise PredicateInputError(f"{source} spec_version must be an integer")


def build_contexts(profile_doc: Json, application_doc: Json) -> typing.Dict[str, Json]:
    profile = profile_doc
    if isinstance(profile_doc, dict):
        if "application" in profile_doc:
            raise PredicateInputError(
                "profile must not contain top-level application; remove it and pass "
                "current-application.json with --current-application"
            )
        if isinstance(profile_doc.get("profile"), dict):
            profile = profile_doc["profile"]
    return {"profile": profile, "application": application_doc}


def normalize_args_for_parser(args: typing.List[str]) -> typing.List[str]:
    if args and args[0] in ("-h", "--help"):
        return args

    option_args: typing.List[str] = []
    positional_args: typing.List[str] = []
    index = 0
    while index < len(args):
        arg = args[index]
        is_rule_id_slot = len(positional_args) == 1
        if not is_rule_id_slot and arg == "--current-application":
            option_args.append(arg)
            if index + 1 < len(args):
                option_args.append(args[index + 1])
                index += 2
            else:
                index += 1
            continue
        if not is_rule_id_slot and arg.startswith("--current-application="):
            option_args.append(arg)
            index += 1
            continue
        positional_args.append(arg)
        index += 1

    return [*option_args, "--", *positional_args]


def parse_args(argv: typing.List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        usage=(
            "python3 tools/lib/predicate.py <spec.json> <rule_id> <profile.json> "
            "[--current-application <path>]"
        )
    )
    parser.add_argument("spec", metavar="<spec.json>", type=pathlib.Path)
    parser.add_argument("rule_id", metavar="<rule_id>")
    parser.add_argument("profile", metavar="<profile.json>", type=pathlib.Path)
    parser.add_argument(
        "--current-application",
        metavar="<path>",
        type=pathlib.Path,
        help="current-application.json used by application-scope predicates",
    )
    return parser.parse_args(normalize_args_for_parser(argv[1:]))


def main(argv: typing.List[str]) -> int:
    args = parse_args(argv)
    spec = load_json(args.spec)
    rule = find_rule(spec, args.rule_id)
    if rule is None:
        print(UNKNOWN)
        return 0

    predicate = rule.get("predicate")
    profile_doc = load_json(args.profile)
    try:
        contexts = build_contexts(profile_doc, {})
        if args.current_application is not None:
            application_doc = load_current_application(args.current_application)
            validate_application_binding(spec, application_doc)
            contexts["application"] = application_doc
        elif predicate_uses_application_scope(predicate):
            raise PredicateInputError(
                "application scope requires --current-application <path>"
            )
    except PredicateInputError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    print(eval_predicate(predicate, contexts))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
