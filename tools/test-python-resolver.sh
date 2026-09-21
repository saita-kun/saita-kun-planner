#!/bin/bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import ast
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
bash = shutil.which("bash")
wrappers = {
    "check-spec.sh": "check_spec.py",
    "check-pack.sh": "check_pack.py",
    "check-drafts.sh": "check_drafts.py",
    "check-quotes.sh": "check_quotes.py",
    "journey-map.sh": "journey_map.py",
    "draft-hash.sh": None,
}
passed = 0
failed = 0


def check(label, condition, detail):
    global passed, failed
    if condition:
        passed += 1
    else:
        failed += 1
        print("FAIL: {}: {}".format(label, detail))


with tempfile.TemporaryDirectory(prefix="planner python resolver ") as directory:
    temp = pathlib.Path(directory)
    bin_dir = temp / "bin"
    bin_dir.mkdir()
    driver = temp / "fake.py"
    log = temp / "calls.jsonl"
    spec = temp / "spec with spaces.json"
    spec.write_text("{}", encoding="utf-8")
    arguments = [str(spec), str(temp / "drafts with spaces [1]")]
    # Execute the wrapper's actual probe against fake version information.
    driver.write_text('''import json
import os
import pathlib
import sys

candidate = pathlib.Path(sys.argv[1]).name
original_args = sys.argv[2:]
args = original_args[1:] if candidate == "py" and original_args[:1] == ["-3"] else original_args
probe = args[:1] == ["-c"]
with open(os.environ["PYTHON_RESOLVER_TEST_LOG"], "a", encoding="utf-8") as stream:
    stream.write(json.dumps({"candidate": candidate, "args": original_args, "probe": probe}) + "\\n")
version = json.loads(os.environ["PYTHON_RESOLVER_TEST_VERSIONS"]).get(candidate)
if version is None:
    sys.exit(127)
if candidate == "py" and original_args[:1] != ["-3"]:
    sys.exit(2)
if probe:
    sys.version_info = tuple(version) + (0, "final", 0)
    exec(args[1], {"__name__": "__main__"})
else:
    sys.exit(int(os.environ["PYTHON_RESOLVER_TEST_EXIT"]))
''', encoding="utf-8")
    for candidate in ("python3", "python", "py", "custom python"):
        executable = bin_dir / candidate
        executable.write_text(
            '#!/bin/bash\nexec "$PYTHON_RESOLVER_TEST_HOST" -I '
            '"$PYTHON_RESOLVER_TEST_DRIVER" "$0" "$@"\n', encoding="utf-8"
        )
        executable.chmod(0o755)
    env = os.environ.copy()
    env.pop("PLANNER_PYTHON", None)
    env.update({
        "PATH": str(bin_dir) + os.pathsep + env.get("PATH", ""),
        "PYTHON_RESOLVER_TEST_HOST": sys.executable,
        "PYTHON_RESOLVER_TEST_DRIVER": str(driver),
        "PYTHON_RESOLVER_TEST_LOG": str(log),
    })

    def run_case(label, versions, probes, selected=None, override=None, status=0):
        case_env = env.copy()
        case_env["PYTHON_RESOLVER_TEST_VERSIONS"] = json.dumps(versions)
        case_env["PYTHON_RESOLVER_TEST_EXIT"] = str(status)
        if override is not None:
            case_env["PLANNER_PYTHON"] = str(bin_dir / override)
        for wrapper, library in wrappers.items():
            log.write_text("", encoding="utf-8")
            result = subprocess.run(
                [bash, str(root / "tools" / wrapper)] + arguments,
                env=case_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                universal_newlines=True,
            )
            calls = [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()]
            probe_calls = [call for call in calls if call["probe"]]
            run_calls = [call for call in calls if not call["probe"]]
            expected_calls = []
            if selected is not None:
                target_args = ([str(root / "tools/lib" / library)] + arguments
                               if library else ["-", arguments[1]])
                if selected == "py":
                    target_args = ["-3"] + target_args
                expected_calls = [{"candidate": selected, "args": target_args, "probe": False}]
            correct_probes = [call["candidate"] for call in probe_calls] == probes and all(
                call["args"][:-1] == (["-3", "-c"] if call["candidate"] == "py" else ["-c"])
                for call in probe_calls
            )
            check(
                label + ": " + wrapper,
                result.returncode == status and correct_probes and run_calls == expected_calls
                and (selected is not None or "Python 3.7+" in result.stderr),
                "status={} probes={} runs={} stderr={!r}".format(
                    result.returncode, [call["candidate"] for call in probe_calls],
                    run_calls, result.stderr,
                ),
            )

    run_case("python36_falls_through_to_python311",
             {"python3": [3, 6], "python": [3, 11]}, ["python3", "python"], "python")
    run_case("python37_is_supported",
             {"python3": [3, 7], "python": [3, 11]}, ["python3"], "python3")
    run_case("fallback_to_py3_preserves_launcher_arguments",
             {"python3": [3, 6], "python": [3, 6], "py": [3, 11]},
             ["python3", "python", "py"], "py")
    run_case("no_supported_python_stops",
             {"python3": [3, 6], "python": [2, 7], "py": [3, 6]},
             ["python3", "python", "py"], status=1)
    run_case("no_python_stops", {}, ["python3", "python", "py"], status=1)
    run_case("explicit_python_invalid_stops",
             {"custom python": [3, 6], "python3": [3, 11]}, ["custom python"],
             override="custom python", status=1)
    run_case("explicit_python_path_and_arguments",
             {"custom python": [3, 7], "python3": [3, 11]}, ["custom python"],
             "custom python", override="custom python")
    run_case("explicit_python_missing_stops", {"python3": [3, 11]}, [],
             override="missing python", status=1)
    run_case("selected_exit_status_propagates",
             {"python3": [3, 11]}, ["python3"], "python3", status=37)

quotes = root / "tools/lib/check_quotes.py"
tree = ast.parse(quotes.read_text(encoding="utf-8"))
check("quotes_no_future_import",
      not any(isinstance(node, ast.ImportFrom) and node.module == "__future__"
              for node in ast.walk(tree)),
      "future imports must not prevent the version guard from running")
result = subprocess.run(
    [sys.executable, "-I", "-c",
     "import runpy, sys; sys.version_info = (3, 6, 15, 'final', 0); "
     "sys.version = '3.6.15'; runpy.run_path(sys.argv[1], run_name='__main__')",
     str(quotes)],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
)
check("quotes_version_guard_reachable",
      result.returncode != 0 and "Python 3.7+ required (running 3.6.15)" in result.stderr
      and "Traceback" not in result.stderr and "SyntaxError" not in result.stderr,
      "status={} stderr={!r}".format(result.returncode, result.stderr))

print("=== test-python-resolver: {} pass / {} fail ===".format(passed, failed))
sys.exit(1 if failed else 0)
PY
