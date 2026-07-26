#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(CDPATH= cd -- "${script_dir}/.." && pwd -P)"
build_dir="${repo_root}/build"
gate_dir="${build_dir}/gates"
log_dir="${build_dir}/logs"
cache_dir="${build_dir}/fstar-cache"
negative_file="${repo_root}/tests/fail/Peel.Tests.RevealSecret.fst"
gate_file="${gate_dir}/P0.4.status"
fingerprint_file="${gate_dir}/P0.4.sources.sha256"
log_file="${log_dir}/negative.log"

mkdir -p "${gate_dir}" "${log_dir}" "${cache_dir}"
rm -f -- "${gate_file}" "${fingerprint_file}" "${log_file}"

outcome="FAIL"

write_gate() {
  local status="$1"
  local temporary
  temporary="$(mktemp "${gate_dir}/.P0.4.status.XXXXXX")"
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
  printf 'negative: BLOCKED: %s\n' "$*" >&2
  exit 2
}

fail() {
  printf 'negative: FAIL: %s\n' "$*" >&2
  exit 1
}

write_fingerprint() {
  local temporary
  temporary="$(mktemp "${gate_dir}/.P0.4.sources.sha256.XXXXXX")"
  if ! python3 "${repo_root}/scripts/evidence.py" --source-fingerprint >"${temporary}"; then
    rm -f -- "${temporary}"
    fail "could not fingerprint the checked repository inputs"
  fi
  mv -f -- "${temporary}" "${fingerprint_file}"
}

for command_name in awk env git grep mktemp mv python3 sed; do
  command -v "${command_name}" >/dev/null 2>&1 \
    || blocked "required command is unavailable: ${command_name}"
done

caller_fstar="${FSTAR_EXE:-}"
if [[ -f "${repo_root}/.toolchain/env" ]]; then
  # shellcheck disable=SC1091
  source "${repo_root}/.toolchain/env"
fi
[[ -n "${caller_fstar}" ]] && FSTAR_EXE="${caller_fstar}"

if [[ -z "${FSTAR_EXE:-}" ]]; then
  if [[ -x "${repo_root}/.toolchain/bin/fstar.exe" ]]; then
    FSTAR_EXE="${repo_root}/.toolchain/bin/fstar.exe"
  else
    FSTAR_EXE="$(command -v fstar.exe)" || blocked "F* executable is unavailable"
  fi
fi
[[ -x "${FSTAR_EXE}" ]] || blocked "FSTAR_EXE is not executable: ${FSTAR_EXE}"
[[ -f "${negative_file}" ]] || fail "missing negative test: ${negative_file}"

direct_line="$(awk '/observe \(secret 0xA5uy\)/ { print NR; exit }' "${negative_file}")"
derived_line="$(awk '/observe \(xor \(secret 0xA5uy\)/ { print NR; exit }' "${negative_file}")"
[[ -n "${direct_line}" ]] || fail "direct secret-observation attempt is missing"
[[ -n "${derived_line}" ]] || fail "derived secret-observation attempt is missing"

set +e
env -u GITHUB_ACTIONS "${FSTAR_EXE}" \
  --include "${repo_root}/src" \
  --cache_dir "${cache_dir}" \
  --z3version 4.13.3 \
  --print_expected_failures \
  "${negative_file}" >"${log_file}" 2>&1
verifier_status=$?
set -e

sed -n '1,320p' "${log_file}"

[[ -s "${log_file}" ]] || fail "the verifier produced no diagnostic; command execution is not established"
[[ ${verifier_status} -eq 1 ]] \
  || fail "expected verifier exit status 1 for a type error, observed ${verifier_status}"

if grep -Eiq 'fatal error|segmentation fault|uncaught exception|stack overflow|assertion failure|internal error' "${log_file}"; then
  fail "the verifier reported a crash rather than the expected type rejection"
fi

grep -Fq "(${direct_line}," "${log_file}" \
  || fail "diagnostic does not identify the direct observation expression"
grep -Fq 'Expected failure:' "${log_file}" \
  || fail "direct observation was not recorded as an expected type failure"
grep -Fq 'Expected type Peel.Byte.byte Peel.Label.Public' "${log_file}" \
  || fail "direct observation diagnostic does not require byte Public"
grep -Fq 'Peel.Byte.byte Peel.Label.Secret' "${log_file}" \
  || fail "direct observation diagnostic does not identify byte Secret"

grep -Fq "(${derived_line}," "${log_file}" \
  || fail "diagnostic does not identify the derived observation expression"
grep -Fq '* Error 19' "${log_file}" \
  || fail "derived observation did not produce the expected subtyping error"
grep -Fq 'Peel.Label.join Peel.Label.Secret Peel.Label.Public' "${log_file}" \
  || fail "derived observation diagnostic does not retain the secret XOR label"
grep -Fq 'Peel.Label.join Peel.Label.Secret Peel.Label.Public == Peel.Label.Public' "${log_file}" \
  || fail "derived observation diagnostic is not the Public/Secret mismatch"

write_fingerprint
write_gate PASS
printf '%s\n' 'P0.4 PASS: both illegal secret observations were rejected for the expected reason.'
