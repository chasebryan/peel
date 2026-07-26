# PEEL P0 trust boundary

PEEL separates the source checked by F* from the machinery trusted to check, erase, extract, compile, and execute it. A successful P0 run is evidence about the checked source under one concrete toolchain; it is not independent certification of that toolchain.

## Verified PEEL source

The verified portion is the two-module semantic kernel in `src/`, together with its examples and positive tests. F* checks label propagation, the public-observation boundary, the label algebra lemmas, and the XOR specification theorem. The negative test is deliberately outside the accepted source set: its rejection demonstrates that the public interface does not type an attempted secret observation.

The interface hides the concrete representation of `Peel.Byte.byte`. There is no declassification or executable secret-reveal operation. These facts constrain programs that use the checked interface; they do not establish cryptographic security, constant-time execution, memory safety for arbitrary surrounding C, or protection from a compromised toolchain.

## Trusted computing base

P0 trusts all of the following:

- The F* compiler at tag `v2026.07.24`, commit `60f60c05ccdb2caa31eb52395d7818ba2df3904e`, to parse, elaborate, type-check, discharge obligations, and erase proof-only terms correctly.
- Z3 `4.13.3`, selected from the F* binary distribution when that distribution is used, to answer the SMT queries F* sends it correctly.
- KaRaMeL at commit `0a39f5a21cb79993c5780b5da24a2f28afbef634` to translate the extracted executable subset into C correctly.
- The OCaml toolchain used to build F* and KaRaMeL. `toolchain.lock` requires OCaml `4.14.2`, and the bootstrap requires both installed executables to come from the source build under that compiler. The official Linux x86_64 release executable reports OCaml `5.3.0`, so it is not used as the final verifier; the release distribution supplies the checked libraries, runtime files, and bundled solver around the locally built executables.
- The pinned opam `2.5.2` acquisition executable, the opam package repository state, and the resolved OCaml build dependencies used to create the repository-local compiler switch and build the two tools.
- The selected C compiler, linker, C runtime, and process environment to compile and execute generated C correctly. Their observed identities belong in run evidence.
- The repository build scripts, the Python interpreter and standard library, and the standard-library-only evidence generator to invoke each tool, interpret results, enforce the negative-test expectation, inspect erasure, and record evidence correctly.
- The operating system and hardware executing the verifier, solver, extractor, compiler, and smoke binary.

Successful F* verification does not independently certify the F* verifier, Z3, KaRaMeL, the OCaml toolchain, C compiler, linker, runtime, build scripts, evidence generator, operating system, or hardware.

## Acquisition provenance

For Linux x86_64, `scripts/bootstrap-toolchain.sh` records and verifies these inputs before executing downloaded code:

```text
F* binary distribution
URL: https://github.com/FStarLang/FStar/releases/download/v2026.07.24/fstar-v2026.07.24-Linux-x86_64.tar.gz
SHA-256: 640443f12887f56e1decafb5891f47a22a8587b39a4774e0a7c64b57404cece6

F* source distribution
URL: https://github.com/FStarLang/FStar/releases/download/v2026.07.24/fstar-v2026.07.24-src.tar.gz
SHA-256: cf883f8964239d6ad28f66b7824cec141f5b1714e5fb38b2a192044a8522b2f0

opam 2.5.2 Linux x86_64
URL: https://github.com/ocaml/opam/releases/download/2.5.2/opam-2.5.2-x86_64-linux
SHA-256: edfca2630c373b44b7ee1c2f81cd8dcf67468d0db57d6c02158de553ac63dbd4
```

The bootstrap initializes opam without changing shell startup files, creates an OCaml `4.14.2` switch beneath `.toolchain/`, and installs only the dependencies declared by the source package. System dependency installation is disabled; a missing host package makes acquisition fail. It runs the source archive's `make install_bin` target and KaRaMeL's `minimal` target directly. KaRaMeL's source archive contains no nested Git metadata, so the build sets `GIT_CEILING_DIRECTORIES` to prevent discovery of PEEL's own `.git` directory and supplies the exact locked KaRaMeL revision through `GIT_REV`. Both locally built executables must report the locked provenance before they replace the corresponding executables in the extracted official distribution.

The official distribution supplies matching checked F* libraries, KaRaMeL runtime files, and several solver builds. PEEL selects its bundled Z3 `4.13.3`. The bootstrap installs only under `.toolchain/`, records both F* and KaRaMeL build compiler versions, and exports the extractor through `KRML_EXE`. Acquisition is separate from `make check`; the check path is offline.

## Extraction and erasure

P0 uses exactly one F* extraction attribute: `[@@ erasable]`, placed immediately on the `noeq type label` declaration in `src/Peel.Label.fsti`. Labels are static classification indices rather than runtime data. Marking this inductive erasable lets F* erase the label arguments carried by the indexed byte API so that KaRaMeL can emit the executable XOR as a byte-to-byte C operation instead of retaining runtime classification arguments. `noeq` is a type qualifier, not a second extraction attribute; F* requires it on this erasable inductive, and it prevents generation of computational equality for labels.

No other extraction attributes are used. `view` is declared specification-only with `GTot`, and the XOR specification and label-algebra properties are lemmas; their proof content is erased by the ordinary F*/KaRaMeL extraction path. The extraction gate additionally inspects the actual emitted C symbols and rejects proof-only definitions that should not be executable.

No hidden constructor is exposed for extraction, no secret observation function is introduced, and generated C is never manually edited. The C smoke test is only a functional extraction check. It is not a constant-time or cryptographic-security test.
