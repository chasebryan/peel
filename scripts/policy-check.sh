#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(CDPATH= cd -- "${script_dir}/.." && pwd -P)"
build_dir="${repo_root}/build"
gate_dir="${build_dir}/gates"
log_dir="${build_dir}/logs"
gate_file="${gate_dir}/P0.2.status"
fingerprint_file="${gate_dir}/P0.2.sources.sha256"
log_file="${log_dir}/policy.log"

mkdir -p "${gate_dir}" "${log_dir}"
rm -f -- "${gate_file}" "${fingerprint_file}"
exec > >(tee "${log_file}") 2>&1

outcome="FAIL"

write_gate() {
  local status="$1"
  local temporary
  temporary="$(mktemp "${gate_dir}/.P0.2.status.XXXXXX")"
  printf '%s\n' "${status}" >"${temporary}"
  mv -f -- "${temporary}" "${gate_file}"
}

finish() {
  local status=$?
  if [[ ${status} -ne 0 && ! -f "${gate_file}" ]]; then
    write_gate "${outcome}"
  fi
}
trap finish EXIT

blocked() {
  outcome="BLOCKED"
  printf 'policy: BLOCKED: %s\n' "$*" >&2
  exit 2
}

write_fingerprint() {
  local temporary
  temporary="$(mktemp "${gate_dir}/.P0.2.sources.sha256.XXXXXX")"
  if ! python3 "${repo_root}/scripts/evidence.py" --source-fingerprint >"${temporary}"; then
    rm -f -- "${temporary}"
    printf '%s\n' 'policy: FAIL: could not fingerprint the checked repository inputs' >&2
    exit 1
  fi
  mv -f -- "${temporary}" "${fingerprint_file}"
}

command -v python3 >/dev/null 2>&1 || blocked "Python 3 is unavailable"
command -v git >/dev/null 2>&1 || blocked "Git is unavailable"

python3 - "${repo_root}" <<'PY'
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(sys.argv[1]).resolve()

# Encoded policy data keeps this checker from matching its own rule table.
RULE_HEX = {
    "P001": "61646d6974",
    "P002": "61646d69745f736d745f71756572696573",
    "P003": "617373756d65",
    "P004": "736f727279",
    "P005": "2d2d6c6178",
    "P006": "756e736166655f7461637469635f65786563",
    "P007": "636f6e74696e75652d6f6e2d6572726f72",
    "P008": "7c7c2074727565",
}
RULES = {rule: bytes.fromhex(encoded).decode("ascii") for rule, encoded in RULE_HEX.items()}

# A future exception must name a rule and repository-relative file here, with a
# nearby justification. P0 deliberately has no exceptions.
ALLOWLIST: dict[tuple[str, str], set[int]] = {}


def repository_files() -> list[str]:
    completed = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        check=True,
        stdout=subprocess.PIPE,
    )
    paths = completed.stdout.split(b"\0")
    selected: list[str] = []
    for raw in paths:
        if not raw:
            continue
        path = os.fsdecode(raw)
        suffix = Path(path).suffix
        if path == "Makefile":
            selected.append(path)
        elif path == ".github/workflows/verify.yml":
            selected.append(path)
        elif path.startswith("scripts/") and suffix in {".sh", ".py"}:
            selected.append(path)
        elif path.startswith(("src/", "examples/", "tests/")) and suffix in {".fst", ".fsti"}:
            selected.append(path)
    return sorted(set(selected), key=os.fsencode)


def strip_fstar_comments(text: str) -> str:
    output: list[str] = []
    index = 0
    depth = 0
    while index < len(text):
        pair = text[index : index + 2]
        if depth == 0 and pair == "//":
            while index < len(text) and text[index] != "\n":
                output.append(" ")
                index += 1
            continue
        if pair == "(*":
            depth += 1
            output.extend("  ")
            index += 2
            continue
        if depth and pair == "*)":
            depth -= 1
            output.extend("  ")
            index += 2
            continue
        character = text[index]
        output.append(character if depth == 0 or character == "\n" else " ")
        index += 1
    return "".join(output)


def strip_full_line_build_comments(text: str) -> str:
    lines = []
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith("#"):
            lines.append("\n" if line.endswith("\n") else "")
        else:
            lines.append(line)
    return "".join(lines)


def occurrences(path: str, text: str) -> list[tuple[str, int, str]]:
    is_fstar = Path(path).suffix in {".fst", ".fsti"}
    executable_text = strip_fstar_comments(text) if is_fstar else strip_full_line_build_comments(text)
    findings: list[tuple[str, int, str]] = []
    applicable_rules = RULES.items()
    for rule, token in applicable_rules:
        if token[0].isalnum() or token[0] == "_":
            boundary = r"A-Za-z0-9_" if is_fstar or rule in {"P002", "P006", "P007"} else r"A-Za-z0-9_-"
            pattern = re.compile(
                rf"(?<![{boundary}])" + re.escape(token) + rf"(?![{boundary}])",
                re.IGNORECASE,
            )
        elif rule == "P008":
            left, right = token.split(" ", 1)
            shell_space = r"(?:[ \t]|\\\r?\n|\r?\n)*"
            pattern = re.compile(
                re.escape(left) + shell_space + re.escape(right) + r"(?![A-Za-z0-9_])"
            )
        else:
            pattern = re.compile(re.escape(token), re.IGNORECASE)
        for match in pattern.finditer(executable_text):
            line_number = executable_text.count("\n", 0, match.start()) + 1
            if line_number in ALLOWLIST.get((rule, path), set()):
                continue
            source_line = text.splitlines()[line_number - 1].strip()
            findings.append((rule, line_number, source_line))
    return findings


violations: list[tuple[str, str, int, str]] = []
files = repository_files()
if not files:
    raise SystemExit("policy: no relevant repository files were found")

for relative in files:
    candidate = (ROOT / relative).resolve()
    try:
        candidate.relative_to(ROOT)
    except ValueError as error:
        raise SystemExit(f"policy: path escapes repository: {relative}") from error
    text = candidate.read_text(encoding="utf-8")
    for rule, line_number, source_line in occurrences(relative, text):
        violations.append((rule, relative, line_number, source_line))

if violations:
    print("policy: forbidden proof or failure-masking mechanism detected:", file=sys.stderr)
    for rule, path, line_number, source_line in violations:
        print(f"  {rule} {path}:{line_number}: {source_line}", file=sys.stderr)
    raise SystemExit(1)

print(f"policy: scanned {len(files)} relevant files; no exceptions and no violations")
PY

write_fingerprint
write_gate PASS
printf '%s\n' 'P0.2 PASS: proof-bypass policy scan passed.'
