#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(CDPATH= cd -- "${script_dir}/.." && pwd -P)"
build_dir="${repo_root}/build"
c_dir="${build_dir}/c"
cache_dir="${build_dir}/fstar-cache"
gate_dir="${build_dir}/gates"
log_dir="${build_dir}/logs"
gate_extract="${gate_dir}/P0.5.status"
gate_erasure="${gate_dir}/P0.6.status"
fingerprint_extract="${gate_dir}/P0.5.sources.sha256"
fingerprint_erasure="${gate_dir}/P0.6.sources.sha256"
verify_log="${log_dir}/extract-verify.log"
fstar_log="${log_dir}/fstar-extract.log"
krml_log="${log_dir}/karamel.log"
symbol_log="${log_dir}/generated-symbols.txt"

mkdir -p "${gate_dir}" "${log_dir}" "${cache_dir}"
rm -f -- \
  "${gate_extract}" "${gate_erasure}" \
  "${fingerprint_extract}" "${fingerprint_erasure}"

extract_outcome="FAIL"
erasure_outcome="FAIL"

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
    [[ -f "${gate_extract}" ]] || write_gate P0.5 "${extract_outcome}"
    [[ -f "${gate_erasure}" ]] || write_gate P0.6 "${erasure_outcome}"
  fi
}
trap finish EXIT

blocked() {
  extract_outcome="BLOCKED"
  erasure_outcome="BLOCKED"
  printf 'extract: BLOCKED: %s\n' "$*" >&2
  exit 2
}

fail() {
  printf 'extract: FAIL: %s\n' "$*" >&2
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

for command_name in cat find git grep mktemp mv python3 sed; do
  command -v "${command_name}" >/dev/null 2>&1 \
    || blocked "required command is unavailable: ${command_name}"
done

run_logged() {
  local destination="$1"
  shift
  local status
  printf 'command:' >"${destination}"
  printf ' %q' "$@" >>"${destination}"
  printf '\n' >>"${destination}"
  set +e
  "$@" >>"${destination}" 2>&1
  status=$?
  set -e
  sed -n '1,360p' "${destination}"
  return "${status}"
}

run_appended() {
  local destination="$1"
  shift
  local status
  printf 'command:' >>"${destination}"
  printf ' %q' "$@" >>"${destination}"
  printf '\n' >>"${destination}"
  set +e
  "$@" >>"${destination}" 2>&1
  status=$?
  set -e
  return "${status}"
}

caller_fstar="${FSTAR_EXE:-}"
caller_krml="${KRML_EXE:-}"
if [[ -f "${repo_root}/.toolchain/env" ]]; then
  # shellcheck disable=SC1091
  source "${repo_root}/.toolchain/env"
fi
[[ -n "${caller_fstar}" ]] && FSTAR_EXE="${caller_fstar}"
[[ -n "${caller_krml}" ]] && KRML_EXE="${caller_krml}"

if [[ -z "${FSTAR_EXE:-}" ]]; then
  if [[ -x "${repo_root}/.toolchain/bin/fstar.exe" ]]; then
    FSTAR_EXE="${repo_root}/.toolchain/bin/fstar.exe"
  else
    FSTAR_EXE="$(command -v fstar.exe)" || blocked "F* executable is unavailable"
  fi
fi
if [[ -z "${KRML_EXE:-}" ]]; then
  if [[ -x "${repo_root}/.toolchain/bin/krml" ]]; then
    KRML_EXE="${repo_root}/.toolchain/bin/krml"
  else
    blocked "KRML_EXE is unset and the repository-local KaRaMeL executable is unavailable"
  fi
fi
[[ -x "${FSTAR_EXE}" ]] || blocked "FSTAR_EXE is not executable: ${FSTAR_EXE}"
[[ -x "${KRML_EXE}" ]] || blocked "KRML_EXE is not executable: ${KRML_EXE}"

case "${c_dir}" in
  "${repo_root}/build/c") ;;
  *) fail "refusing to replace invalid C output path: ${c_dir}" ;;
esac
if [[ -d "${c_dir}" ]]; then
  find "${c_dir}" -mindepth 1 -depth -delete
fi
mkdir -p "${c_dir}"

required_sources=(
  "${repo_root}/src/Peel.Label.fsti"
  "${repo_root}/src/Peel.Label.fst"
  "${repo_root}/src/Peel.Byte.fsti"
  "${repo_root}/src/Peel.Byte.fst"
)

: >"${verify_log}"
for source_file in "${required_sources[@]}"; do
  [[ -f "${source_file}" ]] || fail "missing required source: ${source_file}"
  run_appended "${verify_log}" \
    "${FSTAR_EXE}" \
    --include "${repo_root}/src" \
    --cache_dir "${cache_dir}" \
    --z3version 4.13.3 \
    --cache_checked_modules \
    "${source_file}" \
    || {
      sed -n '1,360p' "${verify_log}"
      fail "required source verification failed"
    }
done
sed -n '1,360p' "${verify_log}"

krml_file="${c_dir}/Peel.Byte.krml"
run_logged "${fstar_log}" \
  "${FSTAR_EXE}" \
  --include "${repo_root}/src" \
  --cache_dir "${cache_dir}" \
  --z3version 4.13.3 \
  --codegen krml \
  --extract 'krml:Peel.Byte' \
  --output_to "${krml_file}" \
  "${repo_root}/src/Peel.Byte.fst" \
  || fail "F* failed to generate KaRaMeL input for Peel.Byte"
if grep -Eiq '(^|[[:space:]*-])warning([[:space:]:]|$)' "${fstar_log}"; then
  fail "F* reported an extraction warning; the required subset must extract warning-free"
fi
[[ -s "${krml_file}" ]] || fail "F* did not generate nonempty Peel.Byte KaRaMeL input"

run_logged "${krml_log}" \
  "${KRML_EXE}" \
  -skip-compilation \
  -skip-makefiles \
  -warn-error '@1..28' \
  -tmpdir "${c_dir}" \
  "${krml_file}" \
  || fail "KaRaMeL failed to translate Peel.Byte"

generated_c="${c_dir}/Peel_Byte.c"
generated_h="${c_dir}/Peel_Byte.h"
[[ -s "${generated_c}" ]] || fail "KaRaMeL did not generate Peel_Byte.c"
[[ -s "${generated_h}" ]] || fail "KaRaMeL did not generate Peel_Byte.h"
write_fingerprint P0.5
write_gate P0.5 PASS

python3 - "${c_dir}" "${symbol_log}" <<'PY'
from __future__ import annotations

from pathlib import Path
import re
import sys


output_dir = Path(sys.argv[1])
log_path = Path(sys.argv[2])
files = sorted([*output_dir.glob("*.c"), *output_dir.glob("*.h")], key=lambda item: item.name.encode())


def remove_comments(text: str) -> str:
    return re.sub(r"/\*.*?\*/|//[^\n]*", " ", text, flags=re.DOTALL)


identifier_pattern = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
function_pattern = re.compile(r"\b(Peel_(?:Byte|Label)_[A-Za-z_][A-Za-z0-9_]*)\s*\(")
identifiers: set[str] = set()
functions: set[str] = set()
for generated in files:
    stripped = remove_comments(generated.read_text(encoding="utf-8"))
    identifiers.update(identifier_pattern.findall(stripped))
    functions.update(function_pattern.findall(stripped))

peel_symbols = {
    identifier
    for identifier in identifiers
    if identifier.startswith(("Peel_Byte_", "Peel_Label_"))
}
ordered = sorted(peel_symbols, key=str.encode)
log_path.write_text("".join(f"{symbol}\n" for symbol in ordered), encoding="utf-8")

required = {
    "Peel_Byte_public",
    "Peel_Byte_secret",
    "Peel_Byte_xor",
    "Peel_Byte_observe",
}
missing = sorted(required - functions)
if missing:
    raise SystemExit("missing executable symbols: " + ", ".join(missing))

forbidden = {
    "Peel_Byte_view",
    "Peel_Byte_xor_view",
    "Peel_Label_join_commutative",
    "Peel_Label_join_associative",
    "Peel_Label_join_idempotent",
    "Peel_Label_join_public_identity",
    "Peel_Label_join_secret_absorbing",
}
present = sorted(forbidden & identifiers)
if present:
    raise SystemExit("proof-only symbols reached generated C: " + ", ".join(present))

proof_components = {"ghost", "lemma", "proof", "view"}
wrappers = []
for symbol in sorted(identifiers, key=str.encode):
    components = {component.lower() for component in symbol.split("_") if component}
    if components & proof_components:
        wrappers.append(symbol)
if wrappers:
    raise SystemExit("proof wrapper symbols reached generated C: " + ", ".join(wrappers))
PY

cat "${symbol_log}"
write_fingerprint P0.6
write_gate P0.6 PASS
printf '%s\n' 'P0.5 PASS: Peel.Byte extracted through KaRaMeL.'
printf '%s\n' 'P0.6 PASS: proof-only definitions are absent from generated C symbols.'
