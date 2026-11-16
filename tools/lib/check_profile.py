#!/usr/bin/env python3
"""Validate company profiles and share the minimal JSON Schema interpreter."""
import argparse
import json
import pathlib
import re
import sys
import typing

Json = typing.Any

_TYPE_CHECKS = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "null": lambda v: v is None,
}


def validate_schema(value: Json, schema: Json, path: str, errors: typing.List[str]) -> None:
    expected_type = schema.get("type")
    if expected_type is not None:
        types = expected_type if isinstance(expected_type, list) else [expected_type]
        if not any(_TYPE_CHECKS[t](value) for t in types):
            errors.append(f"schema violation: {path} must be of type {'/'.join(types)}")
            return
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"schema violation: {path} must be one of {schema['enum']}")
        return
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"schema violation: {path}.{key} is required")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            for key in value:
                if key not in properties:
                    errors.append(f"schema violation: {path}.{key} is not an allowed key")
        for key, subschema in properties.items():
            if key in value:
                validate_schema(value[key], subschema, f"{path}.{key}", errors)
    elif isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append(f"schema violation: {path} must have at least {schema['minItems']} items")
        items = schema.get("items")
        if items is not None:
            for index, item in enumerate(value):
                validate_schema(item, items, f"{path}[{index}]", errors)



def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("profile", type=pathlib.Path)
    args = parser.parse_args()
    schema_path = pathlib.Path(__file__).resolve().parents[2] / "schemas/company-profile.schema.json"
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        print(f"FAIL: {schema_path}: キットの schema ファイルが欠けているか、読み取れません")
        return 1
    if not isinstance(schema, dict):
        print(f"FAIL: {schema_path}: キットの schema ファイルが不正です（JSON object ではありません）")
        return 1
    try:
        profile = json.loads(args.profile.read_text(encoding="utf-8"))
    except FileNotFoundError:
        print(f"FAIL: {args.profile} がありません（/intake で作成します）")
        return 1
    except OSError:
        print(f"FAIL: {args.profile} を読み取れません（ファイルを開けません）")
        return 1
    except ValueError:
        print(f"FAIL: {args.profile}: JSON の形式が不正です")
        return 1
    if not isinstance(profile, dict):
        print(f"FAIL: {args.profile}: JSON object ではありません")
        return 1
    errors = []
    validate_schema(profile, schema, "$", errors)
    for error in errors:
        diagnostic = re.sub(r"^schema violation: (\S+) (.*)$", r"\1: \2", error)
        print("FAIL: " + diagnostic)
    if isinstance(profile, dict) and schema.get("additionalProperties") is not False:
        for key in profile:
            if key not in schema.get("properties", {}):
                print(f"INFO: schema に無いキー: {key}")
    if errors:
        return 1
    print("OK: profile checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
