#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(CDPATH= cd -- "${script_dir}/.." && pwd -P)"
build_dir="${repo_root}/build"
c_dir="${build_dir}/c"
smoke_dir="${build_dir}/smoke"
gate_dir="${build_dir}/gates"
log_dir="${build_dir}/logs"
toolchain_observed_dir="${build_dir}/toolchain"
compile_gate="${gate_dir}/P0.7.status"
runtime_gate="${gate_dir}/P0.8.status"
fingerprint_compile="${gate_dir}/P0.7.sources.sha256"
fingerprint_runtime="${gate_dir}/P0.8.sources.sha256"
compile_log="${log_dir}/smoke-compile.log"
runtime_log="${log_dir}/smoke-runtime.log"
nm_log="${log_dir}/generated-symbols-nm.log"

mkdir -p "${gate_dir}" "${log_dir}" "${smoke_dir}" "${toolchain_observed_dir}"
rm -f -- \
  "${compile_gate}" "${runtime_gate}" \
  "${fingerprint_compile}" "${fingerprint_runtime}" \
  "${compile_log}" "${runtime_log}" "${nm_log}"

compile_outcome="FAIL"
runtime_outcome="FAIL"

write_gate() {
  local gate="$1"
  local status="$2"
  local destination="${gate_dir}/${gate}.status"
  local temporary
  temporary="$(mktemp "${gate_dir}/.${gate}.status.XXXXXX")"
  printf '%s\n' "${status}" >"${temporary}"
  mv -f -- "${temporary}" "${destination}"
}

finish() {
  local status=$?
  if [[ ${status} -ne 0 ]]; then
    [[ -f "${compile_gate}" ]] || write_gate P0.7 "${compile_outcome}"
    [[ -f "${runtime_gate}" ]] || write_gate P0.8 "${runtime_outcome}"
  fi
}
trap finish EXIT

blocked() {
  compile_outcome="BLOCKED"
  runtime_outcome="BLOCKED"
  printf 'smoke: BLOCKED: %s\n' "$*" >&2
  exit 2
}

fail() {
  printf 'smoke: FAIL: %s\n' "$*" >&2
  exit 1
}

write_fingerprint() {
  local gate="$1"
  local destination="${gate_dir}/${gate}.sources.sha256"
  local temporary
  temporary="$(mktemp "${gate_dir}/.${gate}.sources.sha256.XXXXXX")"
  if ! python3 "${repo_root}/scripts/evidence.py" --source-fingerprint >"${temporary}"; then
    rm -f -- "${temporary}"
    fail "could not fingerprint the checked repository inputs for ${gate}"
  fi
  mv -f -- "${temporary}" "${destination}"
}

for command_name in awk cat find git mktemp mv nm python3 readlink sort; do
  command -v "${command_name}" >/dev/null 2>&1 \
    || blocked "required command is unavailable: ${command_name}"
done

caller_krml="${KRML_EXE:-}"
if [[ -f "${repo_root}/.toolchain/env" ]]; then
  # shellcheck disable=SC1091
  source "${repo_root}/.toolchain/env"
fi
[[ -n "${caller_krml}" ]] && KRML_EXE="${caller_krml}"

if [[ -z "${KRML_EXE:-}" ]]; then
  if [[ -x "${repo_root}/.toolchain/bin/krml" ]]; then
    KRML_EXE="${repo_root}/.toolchain/bin/krml"
  else
    blocked "KRML_EXE is unavailable"
  fi
fi
[[ -x "${KRML_EXE}" ]] || blocked "KRML_EXE is not executable: ${KRML_EXE}"

cc_name="${CC:-cc}"
if [[ "${cc_name}" == */* ]]; then
  [[ -x "${cc_name}" ]] || blocked "CC is not executable: ${cc_name}"
  cc_exe="$(readlink -f -- "${cc_name}")"
else
  cc_exe="$(command -v "${cc_name}")" || blocked "C compiler is unavailable: ${cc_name}"
  cc_exe="$(readlink -f -- "${cc_exe}")"
fi
[[ -s "${c_dir}/Peel_Byte.c" ]] || fail "generated Peel_Byte.c is missing; run make extract first"
[[ -s "${c_dir}/Peel_Byte.h" ]] || fail "generated Peel_Byte.h is missing; run make extract first"

krml_include="$("${KRML_EXE}" -locate-include)" || blocked "KaRaMeL include directory could not be located"
krml_library="$("${KRML_EXE}" -locate-krmllib)" || blocked "KaRaMeL runtime directory could not be located"
[[ -d "${krml_include}" ]] || blocked "KaRaMeL include directory is missing: ${krml_include}"
[[ -d "${krml_library}/c" ]] || blocked "KaRaMeL C runtime directory is missing"
[[ -d "${krml_library}/dist/generic" ]] || blocked "KaRaMeL generic runtime directory is missing"

driver="${smoke_dir}/peel_xor_smoke.c"
binary="${smoke_dir}/peel_xor_smoke"
cat >"${driver}" <<'C'
#include <stdint.h>
#include <stdio.h>

#include "Peel_Byte.h"

int main(void)
{
  Peel_Byte_byte left = Peel_Byte_public(UINT8_C(0xAA));
  Peel_Byte_byte right = Peel_Byte_public(UINT8_C(0x55));
  Peel_Byte_byte combined = Peel_Byte_xor(left, right);
  uint8_t observed = Peel_Byte_observe(combined);
  if (observed != UINT8_C(0xFF)) {
    return 1;
  }
  if (printf("0x%02X\n", (unsigned int)observed) < 0) {
    return 2;
  }
  return 0;
}
C

mapfile -d '' generated_sources < <(find "${c_dir}" -maxdepth 1 -type f -name '*.c' -print0 | sort -z)
[[ ${#generated_sources[@]} -gt 0 ]] || fail "no generated C translation units were found"

strict_flags=(-std=c11 -O2 -Wall -Wextra -Werror -Wpedantic)
include_flags=(
  -I "${c_dir}"
  -isystem "${krml_include}"
  -isystem "${krml_library}/c"
  -isystem "${krml_library}/dist/generic"
)
objects=()
: >"${compile_log}"

for generated_source in "${generated_sources[@]}"; do
  object="${smoke_dir}/$(basename "${generated_source}" .c).o"
  objects+=("${object}")
  printf 'command:' >>"${compile_log}"
  printf ' %q' "${cc_exe}" "${strict_flags[@]}" "${include_flags[@]}" -c "${generated_source}" -o "${object}" >>"${compile_log}"
  printf '\n' >>"${compile_log}"
  "${cc_exe}" "${strict_flags[@]}" "${include_flags[@]}" \
    -c "${generated_source}" -o "${object}" >>"${compile_log}" 2>&1 \
    || {
      sed -n '1,360p' "${compile_log}"
      fail "strict compilation of generated C failed"
    }
done

printf 'command:' >>"${compile_log}"
printf ' %q' "${cc_exe}" "${strict_flags[@]}" "${include_flags[@]}" "${driver}" "${objects[@]}" -o "${binary}" >>"${compile_log}"
printf '\n' >>"${compile_log}"
"${cc_exe}" "${strict_flags[@]}" "${include_flags[@]}" \
  "${driver}" "${objects[@]}" -o "${binary}" >>"${compile_log}" 2>&1 \
  || {
    sed -n '1,360p' "${compile_log}"
    fail "strict smoke-driver compilation or link failed"
  }

sed -n '1,360p' "${compile_log}"
nm -g --defined-only "${objects[@]}" >"${nm_log}"
cat "${nm_log}"
for expected_symbol in Peel_Byte_public Peel_Byte_secret Peel_Byte_xor Peel_Byte_observe; do
  awk -v expected="${expected_symbol}" '$NF == expected { found = 1 } END { exit(found ? 0 : 1) }' "${nm_log}" \
    || fail "compiled generated object lacks symbol ${expected_symbol}"
done

cc_identity="$("${cc_exe}" --version)" || fail "could not record C compiler identity"
printf '%s\n' "${cc_identity}" >"${toolchain_observed_dir}/c-compiler.txt"
write_fingerprint P0.7
write_gate P0.7 PASS

set +e
"${binary}" >"${runtime_log}" 2>&1
runtime_status=$?
set -e
cat "${runtime_log}"
[[ ${runtime_status} -eq 0 ]] || fail "generated XOR smoke executable returned ${runtime_status}"
[[ "$(<"${runtime_log}")" == '0xFF' ]] || fail "generated XOR smoke output was not 0xFF"

write_fingerprint P0.8
write_gate P0.8 PASS
printf '%s\n' 'P0.7 PASS: generated C compiled under strict warnings-as-errors.'
printf '%s\n' 'P0.8 PASS: generated executable produced 0xFF for 0xAA XOR 0x55.'
