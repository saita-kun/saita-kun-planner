#!/bin/bash
# Shared Python selection for the six planner wrappers (Bash 3.2 compatible).

planner_python_probe() {
  local output
  # Append a sentinel only on success to preserve unexpected trailing newlines.
  output="$("$@" -c 'import sys; sys.stdout.write("planner-python:%d.%d" % sys.version_info[:2])' 2>/dev/null && printf '.')" || return 1
  # Accept only Python 3 with a minor version of at least 7.
  [[ "$output" =~ ^planner-python:3\.(7|8|9|[1-9][0-9]+)\.$ ]]
}

planner_python_windows_shell() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

planner_resolve_python() {
  # Read the repository-local choice as data, never as shell code.
  local PLANNER_PYTHON_FILE="$1" PLANNER_SAVED
  if [ -z "${PLANNER_PYTHON:-}" ] && { [ -e "$PLANNER_PYTHON_FILE" ] || [ -L "$PLANNER_PYTHON_FILE" ]; }; then
    PLANNER_SAVED=""
    if [ ! -f "$PLANNER_PYTHON_FILE" ] || [ ! -r "$PLANNER_PYTHON_FILE" ]; then
      echo "FAIL: Python 3.7+ の保存設定を読めません。/setup で再保存または解除してください。" >&2
      return 1
    fi
    # A successful NUL-delimited read means the file contains a forbidden NUL.
    if IFS= read -r -d '' PLANNER_SAVED < "$PLANNER_PYTHON_FILE"; then
      echo "FAIL: Python 3.7+ の保存設定が不正です。/setup で再保存または解除してください。" >&2
      return 1
    fi
    PLANNER_SAVED="${PLANNER_SAVED%$'\n'}"
    case "$PLANNER_SAVED" in
      ""|*$'\n'*|*$'\r'*)
        echo "FAIL: Python 3.7+ の保存設定は実行ファイル1つを1行で記録します。/setup で再保存または解除してください。" >&2
        return 1 ;;
      /*) ;;
      */*)
        if [[ "$PLANNER_SAVED" != [a-zA-Z]:/* ]] || ! planner_python_windows_shell; then
          echo "FAIL: Python 3.7+ の保存設定にはコマンド名か絶対パスを使います。/setup で再保存または解除してください。" >&2
          return 1
        fi ;;
    esac
    PLANNER_PYTHON="$PLANNER_SAVED"
  fi

  if [ -n "${PLANNER_PYTHON:-}" ]; then
    if planner_python_probe "$PLANNER_PYTHON"; then
      PLANNER_PY=("$PLANNER_PYTHON")
    else
      echo "FAIL: Python 3.7+ not found (set PLANNER_PYTHON)。/setup で再設定または保存値を解除してください。" >&2
      return 1
    fi
  elif planner_python_probe python3; then
    PLANNER_PY=(python3)
  elif planner_python_probe python; then
    PLANNER_PY=(python)
  elif planner_python_probe py -3; then
    PLANNER_PY=(py -3)
  else
    echo "FAIL: Python 3.7+ not found (set PLANNER_PYTHON)" >&2
    return 1
  fi
}
