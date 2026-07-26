#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(CDPATH= cd -- "${script_dir}/.." && pwd -P)"
build_dir="${repo_root}/build"
gate_dir="${build_dir}/gates"
log_dir="${build_dir}/logs"
cache_dir="${build_dir}/fstar-cache"
gate_file="${gate_dir}/P0.3.status"
fingerprint_file="${gate_dir}/P0.3.sources.sha256"
log_file="${log_dir}/verify.log"

mkdir -p "${gate_dir}" "${log_dir}" "${cache_dir}"
rm -f -- "${gate_file}" "${fingerprint_file}"
exec > >(tee "${log_file}") 2>&1

outcome="FAIL"

write_gate() {
  local status="$1"
  local temporary
  temporary="$(mktemp "${gate_dir}/.P0.3.status.XXXXXX")"
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
  printf 'verify: BLOCKED: %s\n' "$*" >&2
  exit 2
}

write_fingerprint() {
  local temporary
  temporary="$(mktemp "${gate_dir}/.P0.3.sources.sha256.XXXXXX")"
  if ! python3 "${repo_root}/scripts/evidence.py" --source-fingerprint >"${temporary}"; then
    rm -f -- "${temporary}"
    printf '%s\n' 'verify: FAIL: could not fingerprint the checked repository inputs' >&2
    exit 1
  fi
  mv -f -- "${temporary}" "${fingerprint_file}"
}

for command_name in git mktemp mv python3; do
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

sources=(
  "${repo_root}/src/Peel.Label.fsti"
  "${repo_root}/src/Peel.Label.fst"
  "${repo_root}/src/Peel.Byte.fsti"
  "${repo_root}/src/Peel.Byte.fst"
  "${repo_root}/examples/Peel.Example.Xor.fst"
  "${repo_root}/tests/pass/Peel.Tests.Labels.fst"
)

for source_file in "${sources[@]}"; do
  [[ -f "${source_file}" ]] || {
    printf 'verify: missing required source: %s\n' "${source_file}" >&2
    exit 1
  }
  printf 'verify: %s\n' "${source_file#"${repo_root}/"}"
  "${FSTAR_EXE}" \
    --include "${repo_root}/src" \
    --include "${repo_root}/examples" \
    --include "${repo_root}/tests/pass" \
    --cache_dir "${cache_dir}" \
    --z3version 4.13.3 \
    --cache_checked_modules \
    "${source_file}"
done

write_fingerprint
write_gate PASS
printf '%s\n' 'P0.3 PASS: all positive F* modules verified.'
