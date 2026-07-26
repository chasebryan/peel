# PEEL

**Proof-Embedded Expression Language**

> Orange stripped to proof.

PEEL is an extremely small, proof-oriented cryptographic expression language embedded in F*. Its executable subset is intended to pass through KaRaMeL into readable, portable C. PEEL is an independent experimental companion to Orange: it is not a replacement, subset, implementation, or compatibility layer.

Status: **P0 research prototype**.

## P0 claim boundary

A `PASS` evidence record establishes only that, in the recorded environment, F* verified the checked P0 modules, the expected illegal secret observations were rejected for a `Public`/`Secret` type mismatch, KaRaMeL extracted the checked executable byte-XOR core, and the generated C compiled under strict warnings and returned `0xFF` for `0xAA XOR 0x55`.

PEEL does **not** claim cryptographic security, constant-time or side-channel behavior, production readiness, external certification, or Orange compatibility. It does not claim that F*, Z3, KaRaMeL, the C compiler, or any other part of the trusted computing base is formally certified by this repository.

## Architecture

P0 contains two semantic modules. `Peel.Label` defines `Public`, `Secret`, their join, and its algebraic laws. `Peel.Byte` hides the representation of label-indexed bytes, permits observation only at label `Public`, and provides fixed-width `UInt8` XOR plus an erased specification view. Examples and tests exercise accepted programs and expected rejections; scripts verify, extract, compile, run, and record evidence. Generated artifacts live only under `build/`.

PEEL currently uses ordinary `.fst` and `.fsti` modules. No custom `.peel` parser exists yet, and custom syntax is explicitly deferred.

## Locked toolchain

- F*: tag `v2026.07.24`, commit `60f60c05ccdb2caa31eb52395d7818ba2df3904e`
- KaRaMeL: commit `0a39f5a21cb79993c5780b5da24a2f28afbef634`
- Z3: `4.13.3`
- OCaml: `4.14.2`
- KaRaMeL executable variable: `KRML_EXE`

The immutable values are canonical in `toolchain.lock`. Tool acquisition is an explicit, networked step; `make check` itself performs no network access. On Linux x86_64, the bootstrap creates a repository-local OCaml 4.14.2 switch, builds the pinned F* and KaRaMeL sources with that compiler, and combines those executables with the bundled Z3 and checked/runtime files from the verified F* distribution. All acquired and built tools stay beneath `.toolchain/`; no global package installation or shell-startup edit is performed. See [Trust and tool provenance](docs/TRUST.md) for the recorded inputs and trust boundary.

## Quick start

```bash
./scripts/bootstrap-toolchain.sh
source .toolchain/env
make doctor
make check
```

The first command is the separate networked acquisition and source-build step; later invocations are idempotent. Run `make help` for the contract of every build target. A complete P0 run writes canonical evidence to `build/evidence/peel-p0.json`. The evidence status, rather than the presence of files, determines whether P0 passed.

## Repository structure

- `src/`: verified semantic interfaces and implementations
- `examples/`: positive executable examples
- `tests/pass/`: positive verification tests
- `tests/fail/`: expected verifier rejection tests
- `scripts/`: offline verification, extraction, smoke, policy, and evidence automation
- `docs/`: [semantics](docs/SEMANTICS.md) and [trust boundary](docs/TRUST.md)
- `.github/workflows/verify.yml`: Ubuntu 24.04 verification workflow
- `toolchain.lock`: immutable toolchain pins

PEEL is licensed under the [Apache License 2.0](LICENSE). PEEL is not advertised as production cryptography.
