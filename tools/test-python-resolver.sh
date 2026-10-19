#!/bin/bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import ast
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap

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
    repo = temp / "repo"
    (repo / "tools").mkdir(parents=True)
    (repo / "input").mkdir()
    for wrapper in wrappers:
        shutil.copyfile(str(root / "tools" / wrapper), str(repo / "tools" / wrapper))
    shutil.copytree(str(root / "tools/lib"), str(repo / "tools/lib"))
    saved_file = repo / "input/.planner-python"
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

    def run_case(label, versions, probes, selected=None, override=None, status=0,
                 saved=None, setup_error=False, cwd=None, environment=None):
        if saved_file.exists() or saved_file.is_symlink():
            saved_file.unlink()
        if saved is not None:
            saved_file.write_bytes(saved)
        case_env = env.copy()
        if environment is not None:
            case_env.update(environment)
        case_env["PYTHON_RESOLVER_TEST_VERSIONS"] = json.dumps(versions)
        case_env["PYTHON_RESOLVER_TEST_EXIT"] = str(status)
        if override is not None:
            case_env["PLANNER_PYTHON"] = str(bin_dir / override) if override else ""
        for wrapper, library in wrappers.items():
            log.write_text("", encoding="utf-8")
            result = subprocess.run(
                [bash, str(repo / "tools" / wrapper)] + arguments,
                cwd=str(temp if cwd is None else cwd),
                env=case_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                universal_newlines=True,
            )
            calls = [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()]
            probe_calls = [call for call in calls if call["probe"]]
            run_calls = [call for call in calls if not call["probe"]]
            expected_calls = []
            if selected is not None:
                target_args = ([str(repo / "tools/lib" / library)] + arguments
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
                and (selected is not None or "Python 3.7+" in result.stderr)
                and (not setup_error or "/setup" in result.stderr),
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

    saved_path = str(bin_dir / "custom python").encode("utf-8")
    versions = {"custom python": [3, 7], "python3": [3, 11]}
    run_case("python_selection_survives_new_process", versions,
             ["custom python"], "custom python", saved=saved_path + b"\n")
    run_case("python_selection_precedence", versions, ["python3"], "python3",
             override="python3", saved=saved_path + b"\n")
    run_case("environment_overrides_invalid_saved", versions, ["python3"], "python3",
             override="python3", saved=b"invalid\nmultiple lines\n")
    run_case("invalid_environment_does_not_use_saved", versions, [],
             override="missing python", saved=saved_path, status=1, setup_error=True)
    run_case("saved_path_without_final_newline", versions,
             ["custom python"], "custom python", saved=saved_path)
    run_case("saved_command_name", versions, ["custom python"], "custom python",
             saved=b"custom python\n")
    if os.name == "nt":
        drive_path = (bin_dir / "custom python").as_posix()
    else:
        drive_bin = temp / "C:/bin"
        drive_bin.mkdir(parents=True)
        shutil.copy2(str(bin_dir / "custom python"), str(drive_bin / "custom python"))
        drive_path = "C:/bin/custom python"
    run_case("saved_windows_drive_path", versions,
             ["custom python"] if os.name == "nt" else [],
             "custom python" if os.name == "nt" else None,
             saved=(drive_path + "\n").encode("utf-8"),
             status=0 if os.name == "nt" else 1, setup_error=os.name != "nt")
    if os.name != "nt":
        # Both cwd trees contain executable drive-like relative paths.
        for cwd_name in ("cwd1", "cwd2"):
            case_cwd = temp / cwd_name
            for drive in ("C", "c"):
                relative_path = drive + ":/bin/python"
                executable = case_cwd / relative_path
                executable.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(str(bin_dir / "python"), str(executable))
                run_case("saved_drive_path_rejected_on_posix_" + cwd_name + "_" + drive,
                         {"python": [3, 7], "python3": [3, 11]}, [],
                         saved=(relative_path + "\n").encode("utf-8"),
                         status=1, setup_error=True, cwd=case_cwd)

        # Simulate uname, without adding a test-only resolver override.
        uname_bin = temp / "uname-bin"
        uname_bin.mkdir()
        uname = uname_bin / "uname"
        for system in ("MINGW64_NT-10.0", "MSYS_NT-10.0", "CYGWIN_NT-10.0",
                       "Darwin", "Linux", "unknown", ""):
            uname.write_text("#!/bin/sh\nprintf '%s\\n' '{}'\nexit {}\n".format(
                system, 0 if system else 1), encoding="utf-8")
            uname.chmod(0o755)
            windows = system.startswith(("MINGW", "MSYS", "CYGWIN"))
            run_case("saved_drive_path_shell_detection_" + (system or "uname_failure"),
                     versions, ["custom python"] if windows else [],
                     "custom python" if windows else None,
                     saved=(drive_path + "\n").encode("utf-8"),
                     status=0 if windows else 1, setup_error=not windows,
                     environment={"PATH": str(uname_bin) + os.pathsep + env["PATH"]})
    run_case("empty_environment_uses_saved", versions, ["custom python"],
             "custom python", saved=saved_path, override="")
    run_case("saved_old_python_stops", {"custom python": [3, 6], "python3": [3, 11]},
             ["custom python"], saved=saved_path, status=1, setup_error=True)
    non_executable = bin_dir / "not executable"
    non_executable.write_text("exit 0\n", encoding="utf-8")
    invalid_values = {
        "empty": b"",
        "blank_line": b"\n",
        "multiple_lines": saved_path + b"\npython3\n",
        "extra_blank_line": saved_path + b"\n\n",
        "carriage_return": saved_path + b"\r\n",
        "nul": saved_path + b"\0\n",
        "missing": b"missing python\n",
        "non_executable": str(non_executable).encode("utf-8"),
        "relative_path": b"../bin/custom python\n",
        "launcher_arguments": b"py -3\n",
        "colon": b":\n",
        "true_builtin": b"true\n",
        "true_executable": b"/usr/bin/true\n",
        "echo_executable": b"/bin/echo\n",
        "shell_executable": b"/bin/sh\n",
    }
    for name, value in invalid_values.items():
        run_case("invalid_saved_" + name, versions, [], saved=value,
                 status=1, setup_error=True)
    for name, output, exit_code in (
            ("empty", "", 0), ("wrong_marker", "Python 3.7", 0),
            ("old", "planner-python:3.6", 0), ("major", "planner-python:4.7", 0),
            ("suffix", "planner-python:3.7junk", 0),
            ("newline", "planner-python:3.7\n", 0),
            ("nonzero", "planner-python:3.7", 1)):
        fake = bin_dir / "ignores-c"
        fake.write_text("#!/bin/sh\nprintf '%s' '{}'\nexit {}\n".format(output, exit_code),
                        encoding="utf-8")
        fake.chmod(0o755)
        run_case("invalid_probe_output_" + name, versions, [],
                 saved=str(fake).encode("utf-8"), status=1, setup_error=True)

    # Real interpreters must execute the checker, including its failure path.
    real_env = dict(env, PYTHONDONTWRITEBYTECODE="1")
    for wrapper in wrappers:
        saved_file.write_text(sys.executable + "\n", encoding="utf-8")
        result = subprocess.run(
            [bash, str(repo / "tools" / wrapper)] + arguments,
            cwd=str(temp), env=real_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True)
        check("real_saved_python_executes_" + wrapper,
              bool(result.stdout or result.stderr) and "/setup" not in result.stderr,
              "status={} stdout={!r} stderr={!r}".format(
                  result.returncode, result.stdout, result.stderr))
    spec_statuses = []
    for candidate in (sys.executable, "/usr/bin/true"):
        saved_file.write_text(candidate + "\n", encoding="utf-8")
        result = subprocess.run(
            [bash, str(repo / "tools/check-spec.sh"), str(spec)], cwd=str(temp),
            env=real_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True)
        spec_statuses.append(result.returncode)
    check("invalid_spec_never_passes_with_saved_true", spec_statuses == [1, 1],
          str(spec_statuses))
    marker = temp / "executed"
    for payload in ("$(touch '{}')", "`touch '{}'`", "python3; touch '{}'",
                    "PLANNER_PYTHON=python3\ntouch '{}'"):
        run_case("python_selection_is_data", versions, [],
                 saved=payload.format(marker.name).encode("utf-8"), status=1, setup_error=True)
        check("saved_value_never_executed", not marker.exists(), str(marker))

    # Execute the complete documented Bash call, starting without saved state.
    setup = (root / ".claude/commands/setup.md").read_text(encoding="utf-8")
    blocks = [textwrap.dedent(block) for block in
              re.findall(r'     ```bash\n(.*?)\n     ```', setup, re.S)]
    save_blocks = [block for block in blocks if 'write_bytes' in block]
    check("setup_selection_and_save_share_bash_call", len(save_blocks) == 1
          and 'export PLANNER_PYTHON=' in save_blocks[0], str(save_blocks))
    save_block = save_blocks[0]
    setup_driver = temp / "setup-driver.py"
    setup_driver.write_text('''import json
import os
import pathlib
import sys

args = sys.argv[1:]
saved = pathlib.Path("input/.planner-python")
with open(os.environ["SETUP_LOG"], "a", encoding="utf-8") as stream:
    stream.write(json.dumps({"args": args,
        "override": os.environ.get("PLANNER_PYTHON"),
        "saved": saved.read_text(encoding="utf-8") if saved.is_file() else None}) + "\\n")
if args[:1] == ["--bash"]:
    os.execv(os.environ["SETUP_BASH"], [os.environ["SETUP_BASH"]] + args[1:])
if args == ["-"]:
    sys.executable = os.environ["SETUP_EXECUTABLE"]
    mode = os.environ["SETUP_MODE"]
    if mode == "empty_path":
        sys.executable = ""
    elif mode == "invalid_path":
        sys.executable += "\\ninvalid"
    elif mode == "relative_path":
        sys.executable = "relative/python"
    elif mode == "missing_executable":
        sys.executable += "-missing"
    elif mode in ("write_failure", "mismatched_save", "missing_save"):
        original_write = pathlib.Path.write_bytes
        def altered_write(path, data):
            if mode == "write_failure":
                raise PermissionError("save denied by test")
            if mode == "missing_save":
                return len(data)
            return original_write(path, (os.environ["SETUP_HOST"] + "\\n").encode("utf-8"))
        pathlib.Path.write_bytes = altered_write
    exec(sys.stdin.read(), {"__name__": "__main__"})
else:
    os.execv(os.environ["SETUP_HOST"], [os.environ["SETUP_HOST"]] + args)
''', encoding="utf-8")
    setup_bin = temp / "setup-bin"
    setup_bin.mkdir()
    for name, prefix in (("python3.12", ""), ("bash", "--bash ")):
        launcher = setup_bin / name
        launcher.write_text('#!/bin/bash\nexec "$SETUP_HOST" -I "$SETUP_DRIVER" '
                            + prefix + '"$@"\n', encoding="utf-8")
        launcher.chmod(0o755)
    # The saved executable logs actual reuse, then runs a real interpreter.
    virtual_python = temp / "venv with spaces/bin/python"
    virtual_python.parent.mkdir(parents=True)
    shutil.copy2(str(setup_bin / "python3.12"), str(virtual_python))
    setup_env = os.environ.copy()
    setup_env.pop("PLANNER_PYTHON", None)
    setup_env.update({"PATH": str(setup_bin) + os.pathsep + setup_env.get("PATH", ""),
                      "SETUP_HOST": sys.executable, "SETUP_DRIVER": str(setup_driver),
                      "SETUP_BASH": bash, "SETUP_EXECUTABLE": virtual_python.as_posix(),
                      "PYTHONDONTWRITEBYTECODE": "1"})
    for mode in ("success", "write_failure", "blocked_input", "empty_path", "invalid_path",
                 "relative_path", "missing_executable", "mismatched_save", "missing_save"):
        case_root = temp / ("setup-" + mode)
        (case_root / "tools").mkdir(parents=True)
        shutil.copy2(str(root / "tools/check-spec.sh"), str(case_root / "tools/check-spec.sh"))
        for name in ("tools/lib", "specs"):
            shutil.copytree(str(root / name), str(case_root / name))
        home = case_root / "home"
        home.mkdir()
        if mode == "blocked_input":
            (case_root / "input").write_text("not a directory", encoding="utf-8")
        case_log = case_root / "calls.jsonl"
        case_env = dict(setup_env, HOME=str(home), SETUP_MODE=mode, SETUP_LOG=str(case_log))
        result = subprocess.run([bash, "-c", save_block], cwd=str(case_root), env=case_env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                universal_newlines=True)
        calls = [json.loads(line) for line in case_log.read_text(encoding="utf-8").splitlines()]
        validations = [call for call in calls if call["args"][:1] == ["--bash"]]
        saved = case_root / "input/.planner-python"
        detail = "status={} calls={} stderr={!r}".format(result.returncode, calls, result.stderr)
        if mode == "success":
            expected = virtual_python.as_posix() + "\n"
            check("setup_saved_value_matches_selection", result.returncode == 0
                  and saved.read_text(encoding="utf-8") == expected, detail)
            check("setup_revalidation_reads_saved_value", len(validations) == 2
                  and validations[0]["override"] == "python3.12"
                  and validations[0]["saved"] is None
                  and validations[1]["override"] is None
                  and validations[1]["saved"] == expected
                  and calls[-1]["args"][-1:] == ["--list-bundled"]
                  and calls[-1]["override"] is None
                  and calls[-1]["saved"] == expected, detail)
        else:
            check("setup_save_failure_stops_revalidation_" + mode,
                  result.returncode != 0 and len(validations) == 1, detail)

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
