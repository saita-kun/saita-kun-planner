"""Coordinate the finalize gates without duplicating the individual checkers."""
import argparse
import contextlib
import datetime
import hashlib
import io
import json
import os
import pathlib
import re
import sys
import tempfile

sys.dont_write_bytecode = True
import check_drafts
import check_quotes
import check_spec


def fenced(path, review=False):
    ending = r"(?:\n|$)" if review else r"\n"
    match = re.match(r"\A```json\n(.*?)\n```" + ending, path.read_text(encoding="utf-8"), re.S)
    if not match:
        raise ValueError("先頭 fenced json が見つかりません")
    value = json.loads(match.group(1))
    if not isinstance(value, dict):
        raise ValueError("JSON object が必要です")
    return value


def run(args):
    values = dict.fromkeys((
        "spec_check draft_check spec_path spec_version spec_sha256 actual_spec_sha256 "
        "spec_recheck_exit_code review_path reviewed_draft_bodies_sha256 review_record_exit_code "
        "review_quotes_exit_code draft_bodies_sha256 actual_draft_bodies_sha256 draft_hash_algorithm "
        "coverage_inputs_sha256 actual_coverage_inputs_sha256 coverage_recheck_exit_code "
        "spec_hash_match draft_hash_match coverage_hash_match generated_at state_before"
    ).split())
    values.update(verify_report_path="input/checks/verify-report.md", waived_sections=args.waive)
    gates = [{"id": name, "status": "BLOCKED", "reason": "", "evidence": []}
             for name in ("verify_report", "spec", "draft_hash", "coverage", "review")]
    report = {"report_version": 1, "result": "fail", "gates": gates,
              "checklist_values": values, "warnings": []}
    code = 1

    def call(module, argv, gate):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            result = module.main([module.__name__] + argv)
        lines = output.getvalue().splitlines()
        gate["evidence"].extend(lines)
        report["warnings"].extend(line for line in lines if line.startswith("WARN:") or "[要確認]" in line)
        return result, output.getvalue()

    def require(condition, message):
        if not condition:
            raise ValueError(message)

    gate = gates[0]
    route = ""
    verify_route = "/verify を再実行してください"
    try:
        try:
            app = json.loads(pathlib.Path(args.current_application).read_text(encoding="utf-8"))
            require(isinstance(app, dict), "状態ファイルには JSON object が必要です")
        except (OSError, ValueError, UnicodeError) as exc:
            code = 2
            detail = "がありません" if isinstance(exc, FileNotFoundError) else (
                "を読めません" if isinstance(exc, OSError) else "を JSON として読めません")
            raise ValueError("状態ファイル（{}）{}: /select-subsidy または /ingest-guidelines".format(args.current_application, detail))
        values["state_before"] = app.get("state")
        require(all(app.get(key) for key in ("subsidy_id", "spec_path", "spec_version")),
                "申請情報が不足しています。/select-subsidy または /ingest-guidelines")
        require(app.get("state") in ("verified", "finalized"),
                "先に /review と /verify を済ませてください（現在の状態: {}）".format(app.get("state")))
        route = verify_route
        saved = fenced(pathlib.Path(values["verify_report_path"]))
        for key in ("spec_check", "draft_check", "spec_path", "spec_version", "spec_sha256",
                    "draft_bodies_sha256", "draft_hash_algorithm", "generated_at"):
            require(key in saved, "verify-report.md missing key: " + key)
            values[key] = saved[key]
        require(saved["spec_check"] == saved["draft_check"] == "green", "verify checks are not green")
        gate["status"] = "PASS"
        gate = gates[1]
        require(saved["spec_path"] == app["spec_path"] and saved["spec_version"] == app["spec_version"],
                "verify-report.md と current-application.json の spec 情報が一致しません")
        spec = str(app["spec_path"])
        values["actual_spec_sha256"] = hashlib.sha256(pathlib.Path(spec).read_bytes()).hexdigest()
        values["spec_hash_match"] = values["actual_spec_sha256"] == saved["spec_sha256"]
        require(values["spec_hash_match"], "spec_sha256 mismatch: spec が /verify 後に更新されています")
        values["spec_recheck_exit_code"], _ = call(check_spec, [spec], gate)
        route = ""
        require(values["spec_recheck_exit_code"] == 0, "check-spec 不合格。confirmation は /confirm-spec で再突合してください")
        route = verify_route
        gate["status"] = "PASS"
        gate = gates[2]
        drafts = "input/drafts/{}/".format(app["subsidy_id"])
        actual, errors = check_drafts.draft_bodies_sha256(pathlib.Path(drafts))
        values["actual_draft_bodies_sha256"] = actual
        values["draft_hash_match"] = actual == saved["draft_bodies_sha256"]
        require(not errors and values["draft_hash_match"], "draft_bodies_sha256 mismatch" +
                (": " + "; ".join(errors) if errors else ""))
        gate["status"] = "PASS"
        gate = gates[3]
        common = [spec, drafts, "--profile", args.profile, "--current-application", args.current_application]
        waivers = [arg for section in args.waive for arg in ("--waive", section)]
        result, output = call(check_drafts, common + ["--require-coverage"] + waivers, gate)
        values["coverage_recheck_exit_code"] = result
        values["coverage_inputs_sha256"] = saved.get("coverage_inputs_sha256")
        hashes = re.findall(r"^INFO: coverage_inputs_sha256: ([0-9a-f]{64})$", output, re.M)
        values["actual_coverage_inputs_sha256"] = hashes[0] if len(hashes) == 1 else None
        values["coverage_hash_match"] = len(hashes) == 1 and hashes[0] == saved.get("coverage_inputs_sha256")
        route = ""
        require(result == 0, "必須 draft の欠落は /draft-section または本人の別作成の明示が必要です。draft 0 件なら /plan-deliverables を使ってください")
        route = verify_route
        require(values["coverage_hash_match"], "coverage_inputs_sha256 mismatch")
        gate["status"] = "PASS"
        gate = gates[4]
        route = "/review で全件を再点検してください"
        reviews = sorted(pathlib.Path("input/reviews").glob("*.md"))
        require(reviews, "review record absent: 記録なし")
        for path in reviews:
            record_code, _ = call(check_drafts, common + ["--review-record", str(path)], gate)
            if record_code:
                continue
            quote_code, _ = call(check_quotes, [spec, str(path)], gate)
            if quote_code:
                gate["evidence"].append("FAIL: review quote check failed: " + str(path))
                continue
            record = fenced(path, review=True)
            values.update(review_path=str(path), reviewed_draft_bodies_sha256=record["reviewed_draft_bodies_sha256"],
                          review_record_exit_code=record_code, review_quotes_exit_code=quote_code)
            gate["evidence"].append("INFO: adopted review record: " + str(path))
            break
        else:
            raise ValueError("全 draft のレビュー記録と引用の照合が同じファイルで合格する必要があります")
        gate["status"] = "PASS"
        if args.record_finalized:
            route = ""
            gate = {"id": "record_finalized", "status": "BLOCKED", "reason": "", "evidence": []}
            gates.append(gate)
            require(all(pathlib.Path("input", name).is_file() for name in ("final-checklist.md", "submission-summary.md")),
                    "final-checklist と提出用まとめを作成してください")
            now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
            app.update(state="finalized", final_checklist_path="input/final-checklist.md", finalized_at=now, updated_at=now)
            target = pathlib.Path(args.current_application)
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=str(target.parent), delete=False) as stream:
                    temporary = pathlib.Path(stream.name)
                    stream.write(json.dumps(app, ensure_ascii=False, indent=2) + "\n")
                os.replace(str(temporary), str(target))
            finally:
                if temporary is not None and temporary.exists():
                    temporary.unlink()
            gate["status"] = "PASS"
        report["result"] = "pass"
        code = 0
    except (OSError, UnicodeError, ValueError, TypeError, KeyError) as exc:
        gate["status"] = "FAIL"
        gate["reason"] = "{}: {}".format(exc, route) if route else str(exc)
        if isinstance(exc, OSError) and gate["id"] == "record_finalized":
            code = 2
    return code, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--current-application", default="input/current-application.json")
    parser.add_argument("--profile", default="input/company-profile.json")
    parser.add_argument("--waive", action="append", default=[])
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--record-finalized", action="store_true")
    parser.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parents[2]))
    args = parser.parse_args()
    try:
        os.chdir(args.root)
    except OSError as exc:
        parser.error(str(exc))
    code, report = run(args)
    if args.format == "json":
        print(json.dumps(report, ensure_ascii=False))
    else:
        seen_info = set()
        for gate in report["gates"]:
            print("{}: {}{}".format(gate["status"], gate["id"], ": " + gate["reason"] if gate["reason"] else ""))
            for line in gate["evidence"]:
                if line.startswith("INFO:"):
                    if line in seen_info:
                        continue
                    seen_info.add(line)
                print(line)
        for key, value in report["checklist_values"].items():
            rendered = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
            print("checklist: {}={}".format(key, rendered))
    return code


if __name__ == "__main__":
    sys.exit(main())
