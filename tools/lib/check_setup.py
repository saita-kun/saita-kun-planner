#!/usr/bin/env python3
"""Read-only validation of the local setup completion record (Python 3.7+)."""

import datetime
import hashlib
import json
import pathlib
import re
import sys


def valid_datetime(value):
    if not isinstance(value, str):
        return False
    # Limit parsing to the same calendar datetime syntax on every Python version.
    match = re.fullmatch(
        r"([0-9]{4}-[0-9]{2}-[0-9]{2})[Tt ]"
        r"([0-9]{2}:[0-9]{2})(?::([0-9]{2})(?:[.,]([0-9]+))?)?"
        r"(?:([Zz])|([+-])([0-9]{2}):?([0-9]{2}))?", value
    )
    if match is None:
        return False
    date, time, seconds, fraction, utc, sign, hours, minutes = match.groups()
    if int(time[:2]) > 23:
        return False
    if sign and (int(hours) > 23 or int(minutes) > 59):
        return False
    normalized = date + "T" + time + ":" + (seconds or "00")
    if fraction:
        normalized += "." + (fraction + "000000")[:6]
    try:
        datetime.datetime.fromisoformat(normalized)
    except ValueError:
        return False
    return True


def inspect_setup(root):
    """Return missing, invalid, renewal, or done with the existing diagnostics."""
    try:
        state = json.loads((root / "input/setup-state.json").read_text(encoding="utf-8"))
    except FileNotFoundError:
        return "missing", ["input/setup-state.json がまだありません（初回はこの状態が正常です）"]
    except OSError:
        return "invalid", ["input/setup-state.json: JSON を読み取れません（ファイルを開けません）"]
    except UnicodeError:
        return "invalid", ["input/setup-state.json: JSON を読み取れません（UTF-8 の文字コードではありません）"]
    except ValueError:
        return "invalid", ["input/setup-state.json: JSON を読み取れません（JSON の形式が不正です）"]
    if not isinstance(state, dict):
        return "invalid", ["input/setup-state.json: JSON object が必要です"]

    errors = []
    validators = {
        "setup_state_version": lambda value: type(value) is int and value == 1,
        "setup_completed_at": valid_datetime,
        "result_report_choice": lambda value: value in ("提出する", "提出しない", "保留"),
    }
    for key, validate in validators.items():
        if key not in state:
            errors.append("{}: 必須項目がありません".format(key))
        elif not validate(state[key]):
            errors.append("{}: 値が不正です".format(key))
    invalid = bool(errors)
    for key, filename in (("terms_sha256", "TERMS.md"),
                          ("data_policy_sha256", "docs/data-policy.md")):
        if key not in state:
            errors.append("{}: 必須項目がありません".format(key))
            invalid = True
            continue
        value = state[key]
        if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", value):
            errors.append("{}: 64桁の16進文字列が必要です".format(key))
            invalid = True
            continue
        try:
            actual = hashlib.sha256((root / filename).read_bytes()).hexdigest()
        except FileNotFoundError:
            errors.append("{}: {} がありません".format(key, filename))
            invalid = True
            continue
        except OSError:
            errors.append("{}: {} を読み取れません（ファイルを開けません）".format(key, filename))
            invalid = True
            continue
        if value.lower() != actual:
            errors.append("{}: {} の現行 SHA-256 と一致しません".format(key, filename))
    return ("invalid" if invalid else "renewal" if errors else "done"), errors


def check(root):
    return inspect_setup(root)[1]


def main():
    if len(sys.argv) != 1:
        print("使い方: リポジトリのルートで bash tools/check-setup.sh", file=sys.stderr)
        return 1
    errors = check(pathlib.Path.cwd())
    for error in errors:
        print("FAIL: " + error, file=sys.stderr)
    if errors:
        print("/setup を実行（または再実行）してください。記録は変更していません。", file=sys.stderr)
        return 1
    print("OK: setup-state")
    return 0


if __name__ == "__main__":
    sys.exit(main())
