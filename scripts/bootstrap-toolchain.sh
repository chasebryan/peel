#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "${script_dir}/.." && pwd)"
lock_file="${repo_root}/toolchain.lock"
toolchain_dir="${repo_root}/.toolchain"
download_dir="${toolchain_dir}/downloads"
install_dir="${toolchain_dir}/fstar"
source_dir="${toolchain_dir}/fstar-src"
opam_root="${toolchain_dir}/opam-root"
ocaml_switch="${toolchain_dir}/ocaml"
bin_dir="${toolchain_dir}/bin"

readonly binary_archive_name="fstar-v2026.07.24-Linux-x86_64.tar.gz"
readonly binary_archive_url="https://github.com/FStarLang/FStar/releases/download/v2026.07.24/${binary_archive_name}"
readonly binary_archive_sha256="640443f12887f56e1decafb5891f47a22a8587b39a4774e0a7c64b57404cece6"
readonly source_archive_name="fstar-v2026.07.24-src.tar.gz"
readonly source_archive_url="https://github.com/FStarLang/FStar/releases/download/v2026.07.24/${source_archive_name}"
readonly source_archive_sha256="cf883f8964239d6ad28f66b7824cec141f5b1714e5fb38b2a192044a8522b2f0"
readonly opam_name="opam-2.5.2-x86_64-linux"
readonly opam_url="https://github.com/ocaml/opam/releases/download/2.5.2/${opam_name}"
readonly opam_sha256="edfca2630c373b44b7ee1c2f81cd8dcf67468d0db57d6c02158de553ac63dbd4"
readonly opam_version="2.5.2"
readonly opam_repository_url="https://opam.ocaml.org"

die() {
  printf 'bootstrap-toolchain: %s\n' "$*" >&2
  exit 1
}

[[ -f "${lock_file}" ]] || die "missing ${lock_file}"

for command_name in curl sha256sum tar mktemp mv ln mkdir rm rmdir grep sed uname make install chmod readlink git; do
  command -v "${command_name}" >/dev/null 2>&1 || die "required command not found: ${command_name}"
done

lock_value() {
  local key="$1"
  local value
  value="$(sed -n "s/^${key}=//p" "${lock_file}")"
  [[ -n "${value}" && "${value}" != *$'\n'* ]] \
    || die "toolchain.lock must contain exactly one nonempty ${key} assignment"
  printf '%s' "${value}"
}

# Parse only the seven expected data fields; never execute toolchain.lock.
PEEL_TOOLCHAIN_SCHEMA="$(lock_value PEEL_TOOLCHAIN_SCHEMA)"
FSTAR_TAG="$(lock_value FSTAR_TAG)"
FSTAR_COMMIT="$(lock_value FSTAR_COMMIT)"
KARAMEL_COMMIT="$(lock_value KARAMEL_COMMIT)"
Z3_VERSION="$(lock_value Z3_VERSION)"
OCAML_VERSION="$(lock_value OCAML_VERSION)"
KARAMEL_ENVIRONMENT_VARIABLE="$(lock_value KARAMEL_ENVIRONMENT_VARIABLE)"

[[ "${PEEL_TOOLCHAIN_SCHEMA}" == "1" ]] || die "unexpected toolchain schema"
[[ "${FSTAR_TAG}" == "v2026.07.24" ]] || die "unexpected F* tag in toolchain.lock"
[[ "${FSTAR_COMMIT}" == "60f60c05ccdb2caa31eb52395d7818ba2df3904e" ]] || die "unexpected F* commit in toolchain.lock"
[[ "${KARAMEL_COMMIT}" == "0a39f5a21cb79993c5780b5da24a2f28afbef634" ]] || die "unexpected KaRaMeL commit in toolchain.lock"
[[ "${Z3_VERSION}" == "4.13.3" ]] || die "unexpected Z3 version in toolchain.lock"
[[ "${OCAML_VERSION}" == "4.14.2" ]] || die "unexpected OCaml version in toolchain.lock"
[[ "${KARAMEL_ENVIRONMENT_VARIABLE}" == "KRML_EXE" ]] || die "toolchain.lock must select KRML_EXE"

[[ "$(uname -s)" == "Linux" ]] || die "the P0 bootstrap currently supports Linux only"
[[ "$(uname -m)" == "x86_64" ]] || die "the recorded release assets are for Linux x86_64 only"

build_jobs="${PEEL_BUILD_JOBS:-2}"
[[ "${build_jobs}" =~ ^[1-9][0-9]*$ && "${build_jobs}" -le 32 ]] \
  || die "PEEL_BUILD_JOBS must be an integer from 1 through 32"

mkdir -p "${download_dir}" "${bin_dir}"

sources_file="${toolchain_dir}/SOURCES"
sources_tmp="${sources_file}.tmp.$$"
{
  printf 'FSTAR_BINARY_ARCHIVE_URL=%s\n' "${binary_archive_url}"
  printf 'FSTAR_BINARY_ARCHIVE_SHA256=%s\n' "${binary_archive_sha256}"
  printf 'FSTAR_SOURCE_ARCHIVE_URL=%s\n' "${source_archive_url}"
  printf 'FSTAR_SOURCE_ARCHIVE_SHA256=%s\n' "${source_archive_sha256}"
  printf 'OPAM_BINARY_URL=%s\n' "${opam_url}"
  printf 'OPAM_BINARY_SHA256=%s\n' "${opam_sha256}"
  printf 'OPAM_REPOSITORY_URL=%s\n' "${opam_repository_url}"
} >"${sources_tmp}"
mv -f -- "${sources_tmp}" "${sources_file}"

download_checked() {
  local url="$1"
  local expected_sha256="$2"
  local destination="$3"
  local partial="${destination}.partial.$$"

  if [[ ! -f "${destination}" ]]; then
    rm -f -- "${partial}"
    if ! curl --fail --location --proto '=https' --tlsv1.2 \
      --output "${partial}" "${url}"; then
      rm -f -- "${partial}"
      die "download failed: ${url}"
    fi
    if ! printf '%s  %s\n' "${expected_sha256}" "${partial}" | sha256sum --check --status; then
      rm -f -- "${partial}"
      die "downloaded file SHA-256 does not match its recorded digest: ${url}"
    fi
    mv -- "${partial}" "${destination}"
  fi

  printf '%s  %s\n' "${expected_sha256}" "${destination}" | sha256sum --check --status \
    || die "cached file SHA-256 does not match its recorded digest: ${destination}"
}

binary_archive_path="${download_dir}/${binary_archive_name}"
source_archive_path="${download_dir}/${source_archive_name}"
opam_exe="${download_dir}/${opam_name}"

download_checked "${binary_archive_url}" "${binary_archive_sha256}" "${binary_archive_path}"
download_checked "${source_archive_url}" "${source_archive_sha256}" "${source_archive_path}"
download_checked "${opam_url}" "${opam_sha256}" "${opam_exe}"
chmod 0755 "${opam_exe}"

[[ "$("${opam_exe}" --version)" == "${opam_version}" ]] \
  || die "downloaded opam executable did not report version ${opam_version}"

ensure_distribution() {
  local marker="${install_dir}/.peel-binary-archive.sha256"
  local stage

  if [[ ! -d "${install_dir}" ]]; then
    stage="$(mktemp -d "${toolchain_dir}/.binary.XXXXXX")"
    if ! tar -xzf "${binary_archive_path}" -C "${stage}"; then
      rm -rf -- "${stage}"
      die "could not extract the verified F* binary archive"
    fi
    [[ -d "${stage}/fstar" ]] || {
      rm -rf -- "${stage}"
      die "F* binary archive has an unexpected layout"
    }
    mv -- "${stage}/fstar" "${install_dir}"
    rmdir "${stage}"
  fi

  [[ -x "${install_dir}/bin/fstar.exe" ]] || die "F* distribution lacks bin/fstar.exe"
  [[ -x "${install_dir}/bin/krml" ]] || die "F* distribution lacks bin/krml"
  [[ -x "${install_dir}/lib/fstar/z3-${Z3_VERSION}/bin/z3" ]] \
    || die "F* distribution lacks bundled Z3 ${Z3_VERSION}"
  [[ -d "${install_dir}/lib/fstar" ]] || die "F* distribution lacks checked libraries"
  [[ -d "${install_dir}/share/krml" ]] || die "F* distribution lacks KaRaMeL runtime files"

  if [[ -f "${marker}" ]]; then
    [[ "$(sed -n '1p' "${marker}")" == "${binary_archive_sha256}" ]] \
      || die "F* distribution marker does not match the locked binary archive"
  else
    printf '%s\n' "${binary_archive_sha256}" >"${marker}.tmp.$$"
    mv -f -- "${marker}.tmp.$$" "${marker}"
  fi
}

ensure_source_tree() {
  local marker="${source_dir}/.peel-source-archive.sha256"
  local stage

  if [[ ! -d "${source_dir}" ]]; then
    stage="$(mktemp -d "${toolchain_dir}/.source.XXXXXX")"
    if ! tar -xzf "${source_archive_path}" -C "${stage}"; then
      rm -rf -- "${stage}"
      die "could not extract the verified F* source archive"
    fi
    [[ -d "${stage}/fstar" ]] || {
      rm -rf -- "${stage}"
      die "F* source archive has an unexpected layout"
    }
    mv -- "${stage}/fstar" "${source_dir}"
    rmdir "${stage}"
  fi

  [[ -f "${source_dir}/fstar.opam" ]] || die "F* source tree lacks fstar.opam"
  [[ -f "${source_dir}/karamel/karamel.opam" ]] || die "F* source tree lacks karamel.opam"
  grep -Fqx "export FSTAR_COMMIT=${FSTAR_COMMIT}" "${source_dir}/Makefile" \
    || die "F* source tree does not record commit ${FSTAR_COMMIT}"

  if [[ -f "${marker}" ]]; then
    [[ "$(sed -n '1p' "${marker}")" == "${source_archive_sha256}" ]] \
      || die "F* source marker does not match the locked source archive"
  else
    printf '%s\n' "${source_archive_sha256}" >"${marker}.tmp.$$"
    mv -f -- "${marker}.tmp.$$" "${marker}"
  fi
}

ensure_distribution
ensure_source_tree

run_opam() {
  env OPAMROOT="${opam_root}" OPAMYES=1 OPAMCOLOR=never "${opam_exe}" "$@"
}

if [[ ! -f "${opam_root}/config" ]]; then
  mkdir -p "${opam_root}"
  run_opam init \
    --bare \
    --no-setup \
    --yes \
    --no-opamrc \
    --disable-sandboxing \
    default "${opam_repository_url}"
fi

ocamlc_switch="${ocaml_switch}/_opam/bin/ocamlc"
if [[ ! -x "${ocamlc_switch}" ]]; then
  if [[ -e "${ocaml_switch}" ]]; then
    die "incomplete local OCaml switch exists at ${ocaml_switch}; remove that generated directory and retry"
  fi
  run_opam switch create "${ocaml_switch}" "ocaml-base-compiler.${OCAML_VERSION}" --yes
fi

observed_ocaml="$(run_opam exec --switch="${ocaml_switch}" -- ocamlc -version)"
[[ "${observed_ocaml}" == "${OCAML_VERSION}" ]] \
  || die "local OCaml reports ${observed_ocaml}; expected ${OCAML_VERSION}"

ln -sfn "../fstar/bin/fstar.exe" "${bin_dir}/fstar.exe"
ln -sfn "../fstar/bin/krml" "${bin_dir}/krml"
ln -sfn "../fstar/lib/fstar/z3-${Z3_VERSION}/bin/z3" "${bin_dir}/z3"
ln -sfn "../fstar/lib/fstar/z3-${Z3_VERSION}/bin/z3" "${bin_dir}/z3-${Z3_VERSION}"
ln -sfn "../ocaml/_opam/bin/ocamlc" "${bin_dir}/ocamlc"

is_exact_toolchain() {
  local fstar_output
  local krml_output

  [[ -x "${install_dir}/bin/fstar.exe" && -x "${install_dir}/bin/krml" ]] || return 1
  fstar_output="$("${install_dir}/bin/fstar.exe" --version 2>/dev/null)" || return 1
  krml_output="$("${install_dir}/bin/krml" -version 2>/dev/null)" || return 1
  grep -Fqx "F* 2026.07.24" <<<"${fstar_output}" || return 1
  grep -Fqx "compiler=OCaml ${OCAML_VERSION}" <<<"${fstar_output}" || return 1
  grep -Fqx "commit=${FSTAR_COMMIT}" <<<"${fstar_output}" || return 1
  grep -Fq "KaRaMeL version: ${KARAMEL_COMMIT}" <<<"${krml_output}" || return 1
}

if ! is_exact_toolchain; then
  (
    cd "${source_dir}"
    run_opam install --switch="${ocaml_switch}" --deps-only . --yes --no-depexts
  )

  run_opam exec --switch="${ocaml_switch}" --set-switch -- \
    make -C "${source_dir}" -j"${build_jobs}" install_bin

  env \
    GIT_CEILING_DIRECTORIES="${source_dir}" \
    GIT_REV="${KARAMEL_COMMIT}" \
    OPAMROOT="${opam_root}" \
    OPAMYES=1 \
    OPAMCOLOR=never \
    "${opam_exe}" exec --switch="${ocaml_switch}" --set-switch -- \
    make -C "${source_dir}/karamel" -j"${build_jobs}" minimal

  source_fstar="${source_dir}/out/bin/fstar.exe"
  source_krml="${source_dir}/karamel/_build/default/src/Karamel.exe"
  [[ -x "${source_fstar}" ]] || die "source build did not produce F*"
  [[ -x "${source_krml}" ]] || die "source build did not produce KaRaMeL"
  grep -Fqx "let version = \"${KARAMEL_COMMIT}\"" "${source_dir}/karamel/lib/Version.ml" \
    || die "KaRaMeL build did not embed the locked commit"

  built_fstar_output="$("${source_fstar}" --version)"
  built_krml_output="$("${source_krml}" -version)"
  grep -Fqx "compiler=OCaml ${OCAML_VERSION}" <<<"${built_fstar_output}" \
    || die "source-built F* does not report OCaml ${OCAML_VERSION}"
  grep -Fqx "commit=${FSTAR_COMMIT}" <<<"${built_fstar_output}" \
    || die "source-built F* does not report commit ${FSTAR_COMMIT}"
  grep -Fq "KaRaMeL version: ${KARAMEL_COMMIT}" <<<"${built_krml_output}" \
    || die "source-built KaRaMeL does not report commit ${KARAMEL_COMMIT}"

  install -m 0755 "${source_fstar}" "${install_dir}/bin/fstar.exe"
  install -m 0755 "${source_krml}" "${install_dir}/bin/krml"
fi

fstar_exe="${install_dir}/bin/fstar.exe"
krml_exe="${install_dir}/bin/krml"
z3_exe="${install_dir}/lib/fstar/z3-${Z3_VERSION}/bin/z3"

fstar_output="$("${fstar_exe}" --version)"
krml_output="$("${krml_exe}" -version)"
z3_output="$("${z3_exe}" -version)"

grep -Fqx "F* 2026.07.24" <<<"${fstar_output}" \
  || die "installed F* did not report version 2026.07.24"
grep -Fqx "compiler=OCaml ${OCAML_VERSION}" <<<"${fstar_output}" \
  || die "installed F* did not report compiler=OCaml ${OCAML_VERSION}"
grep -Fqx "commit=${FSTAR_COMMIT}" <<<"${fstar_output}" \
  || die "installed F* did not report commit ${FSTAR_COMMIT}"
grep -Fq "KaRaMeL version: ${KARAMEL_COMMIT}" <<<"${krml_output}" \
  || die "installed KaRaMeL did not report commit ${KARAMEL_COMMIT}"
grep -Fq "Z3 version ${Z3_VERSION}" <<<"${z3_output}" \
  || die "installed bundled solver is not Z3 ${Z3_VERSION}"

located_z3="$(PATH="${bin_dir}:${PATH}" "${fstar_exe}" --locate_z3 "${Z3_VERSION}")"
[[ "$(readlink -f -- "${located_z3}")" == "$(readlink -f -- "${z3_exe}")" ]] \
  || die "installed F* did not select the validated bundled Z3 ${Z3_VERSION}"

env_file="${toolchain_dir}/env"
env_tmp="${env_file}.tmp.$$"
{
  printf 'export FSTAR_EXE=%q\n' "${bin_dir}/fstar.exe"
  printf 'export KRML_EXE=%q\n' "${bin_dir}/krml"
  printf 'export Z3_EXE=%q\n' "${bin_dir}/z3"
  printf 'export OCAMLC=%q\n' "${bin_dir}/ocamlc"
  printf 'export PATH=%q:"${PATH}"\n' "${bin_dir}"
} >"${env_tmp}"
mv -f -- "${env_tmp}" "${env_file}"

manifest_file="${toolchain_dir}/manifest.env"
manifest_tmp="${manifest_file}.tmp.$$"
{
  printf 'PEEL_TOOLCHAIN_SCHEMA=%q\n' "${PEEL_TOOLCHAIN_SCHEMA}"
  printf 'FSTAR_TAG=%q\n' "${FSTAR_TAG}"
  printf 'FSTAR_COMMIT=%q\n' "${FSTAR_COMMIT}"
  printf 'KARAMEL_COMMIT=%q\n' "${KARAMEL_COMMIT}"
  printf 'Z3_VERSION=%q\n' "${Z3_VERSION}"
  printf 'OCAML_VERSION=%q\n' "${OCAML_VERSION}"
  printf 'FSTAR_BUILD_OCAML_VERSION=%q\n' "${observed_ocaml}"
  printf 'KARAMEL_BUILD_OCAML_VERSION=%q\n' "${observed_ocaml}"
  printf 'FSTAR_BUILD_MODE=%q\n' source
  printf 'FSTAR_ARCHIVE_URL=%q\n' "${binary_archive_url}"
  printf 'FSTAR_ARCHIVE_SHA256=%q\n' "${binary_archive_sha256}"
  printf 'FSTAR_SOURCE_ARCHIVE_URL=%q\n' "${source_archive_url}"
  printf 'FSTAR_SOURCE_ARCHIVE_SHA256=%q\n' "${source_archive_sha256}"
  printf 'OPAM_VERSION=%q\n' "${opam_version}"
  printf 'OPAM_BINARY_URL=%q\n' "${opam_url}"
  printf 'OPAM_BINARY_SHA256=%q\n' "${opam_sha256}"
  printf 'FSTAR_EXE=%q\n' "${bin_dir}/fstar.exe"
  printf 'KRML_EXE=%q\n' "${bin_dir}/krml"
  printf 'Z3_EXE=%q\n' "${bin_dir}/z3"
  printf 'OCAMLC=%q\n' "${bin_dir}/ocamlc"
} >"${manifest_tmp}"
mv -f -- "${manifest_tmp}" "${manifest_file}"

printf 'Installed source-built F* %s and KaRaMeL %s under OCaml %s.\n' \
  "${FSTAR_TAG}" "${KARAMEL_COMMIT}" "${OCAML_VERSION}"
printf 'Using bundled Z3 %s and checked/runtime files from the verified binary release.\n' \
  "${Z3_VERSION}"
printf 'Environment: source %s\n' "${env_file}"
