#!/usr/bin/env python3
"""Emit canonical, deterministic evidence for PEEL Phase P0."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import NoReturn


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
BUILD_DIR = REPO_ROOT / "build"
GATE_DIR = BUILD_DIR / "gates"
EVIDENCE_DIR = BUILD_DIR / "evidence"
EVIDENCE_PATH = EVIDENCE_DIR / "peel-p0.json"
P09_PATH = GATE_DIR / "P0.9.status"

EXPECTED_LOCK = {
    "PEEL_TOOLCHAIN_SCHEMA": "1",
    "FSTAR_TAG": "v2026.07.24",
    "FSTAR_COMMIT": "60f60c05ccdb2caa31eb52395d7818ba2df3904e",
    "KARAMEL_COMMIT": "0a39f5a21cb79993c5780b5da24a2f28afbef634",
    "Z3_VERSION": "4.13.3",
    "OCAML_VERSION": "4.14.2",
    "KARAMEL_ENVIRONMENT_VARIABLE": "KRML_EXE",
}


class GatePrerequisiteError(RuntimeError):
    """A prior gate is absent or did not pass."""

    def __init__(self, message: str, status: str, exit_code: int) -> None:
        super().__init__(message)
        self.status = status
        self.exit_code = exit_code


def abort(message: str) -> NoReturn:
    raise RuntimeError(message)


def atomic_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def parse_lock() -> dict[str, str]:
    lock_path = REPO_ROOT / "toolchain.lock"
    try:
        lines = lock_path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        abort(f"cannot read toolchain.lock: {error}")

    result: dict[str, str] = {}
    for line in lines:
        if not line:
            continue
        if "=" not in line:
            abort(f"invalid toolchain.lock line: {line!r}")
        key, value = line.split("=", 1)
        if key in result:
            abort(f"duplicate toolchain.lock key: {key}")
        result[key] = value
    if result != EXPECTED_LOCK:
        abort("toolchain.lock does not contain the immutable P0 pins")
    return result


def prior_gate_statuses(expected_fingerprint: str) -> dict[str, str]:
    statuses: dict[str, str] = {}
    fingerprint_errors: list[str] = []
    for number in range(1, 9):
        gate = f"P0.{number}"
        path = GATE_DIR / f"{gate}.status"
        if not path.is_file():
            statuses[gate] = "MISSING"
            continue
        value = path.read_text(encoding="utf-8").strip()
        statuses[gate] = value if value in {"PASS", "FAIL", "BLOCKED"} else "INVALID"
        fingerprint_path = GATE_DIR / f"{gate}.sources.sha256"
        try:
            observed_fingerprint = fingerprint_path.read_text(encoding="ascii").strip()
        except OSError:
            observed_fingerprint = "MISSING"
        if observed_fingerprint != expected_fingerprint:
            fingerprint_errors.append(f"{gate}={observed_fingerprint}")

    nonpassing = {gate: status for gate, status in statuses.items() if status != "PASS"}
    if nonpassing:
        details = ", ".join(f"{gate}={status}" for gate, status in nonpassing.items())
        if any(status == "FAIL" or status == "INVALID" for status in nonpassing.values()):
            raise GatePrerequisiteError(
                f"cannot emit PASS evidence because prior gates did not pass: {details}",
                "FAIL",
                1,
            )
        if any(status == "BLOCKED" for status in nonpassing.values()):
            raise GatePrerequisiteError(
                f"cannot emit PASS evidence because prior gates are unavailable: {details}",
                "BLOCKED",
                2,
            )
        raise GatePrerequisiteError(
            f"cannot emit PASS evidence because prior gate results are missing: {details}",
            "FAIL",
            1,
        )
    if fingerprint_errors:
        details = ", ".join(fingerprint_errors)
        raise GatePrerequisiteError(
            "cannot emit PASS evidence because gate source fingerprints are stale or missing: "
            + details,
            "FAIL",
            1,
        )
    return statuses


def is_source_input(path: str) -> bool:
    suffix = Path(path).suffix
    if path in {"Makefile", "toolchain.lock"}:
        return True
    if path == ".github/workflows/verify.yml":
        return True
    if path.startswith("scripts/") and suffix in {".sh", ".py"}:
        return True
    if path.startswith(("src/", "examples/", "tests/")) and suffix in {".fst", ".fsti"}:
        return True
    return False


def source_paths() -> list[str]:
    # Include index entries plus non-ignored additions so evidence generated in an
    # uncommitted bootstrap covers the exact files that will become tracked.
    completed = subprocess.run(
        [
            "git",
            "-C",
            str(REPO_ROOT),
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    selected = {
        os.fsdecode(raw)
        for raw in completed.stdout.split(b"\0")
        if raw and is_source_input(os.fsdecode(raw))
    }
    paths = sorted(selected, key=os.fsencode)
    if not paths:
        abort("no tracked PEEL evidence inputs were found")
    return paths


def digest_sources(paths: list[str]) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    for relative in paths:
        candidate = (REPO_ROOT / relative).resolve()
        try:
            candidate.relative_to(REPO_ROOT)
        except ValueError as error:
            raise RuntimeError(f"source path escapes repository: {relative}") from error
        if not candidate.is_file():
            abort(f"evidence input is not a regular file: {relative}")
        digest = hashlib.sha256(candidate.read_bytes()).hexdigest()
        records.append({"path": relative, "sha256": digest})
    return records


def source_fingerprint(records: list[dict[str, str]]) -> str:
    """Bind gate results to the exact ordered path/digest evidence inputs."""
    fingerprint = hashlib.sha256()
    for record in records:
        path = record["path"].encode("utf-8")
        digest = bytes.fromhex(record["sha256"])
        fingerprint.update(len(path).to_bytes(8, "big"))
        fingerprint.update(path)
        fingerprint.update(digest)
    return fingerprint.hexdigest()


def compiler_identity() -> str:
    identity_path = BUILD_DIR / "toolchain" / "c-compiler.txt"
    try:
        lines = [line.strip() for line in identity_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    except OSError as error:
        abort(f"cannot read observed C compiler identity: {error}")
    if not lines:
        abort("observed C compiler identity is empty")
    return lines[0]


def build_record(lock: dict[str, str], sources: list[dict[str, str]]) -> dict[str, object]:
    return {
        "schema": "peel.evidence.p0.v1",
        "phase": "P0",
        "status": "PASS",
        "toolchain": {
            "fstar_tag": lock["FSTAR_TAG"],
            "fstar_commit": lock["FSTAR_COMMIT"],
            "karamel_commit": lock["KARAMEL_COMMIT"],
            "z3_version": lock["Z3_VERSION"],
            "ocaml_version": lock["OCAML_VERSION"],
            "c_compiler": compiler_identity(),
        },
        "gates": [{"id": f"P0.{number}", "status": "PASS"} for number in range(1, 10)],
        "sources": sources,
        "claims": [
            "F* verified the checked PEEL P0 modules.",
            "The expected illegal secret observations were rejected.",
            "KaRaMeL extracted the checked executable core to C.",
            "The generated C compiled and passed the public XOR smoke test.",
        ],
        "nonclaims": [
            "No cryptographic security property is established.",
            "No constant-time or side-channel property is established.",
            "No production-readiness claim is made.",
            "No external certification claim is made.",
            "No Orange compatibility claim is made.",
        ],
    }


def validate_written(record: dict[str, object], serialized: str) -> None:
    observed_bytes = EVIDENCE_PATH.read_bytes()
    expected_bytes = serialized.encode("utf-8")
    if observed_bytes != expected_bytes:
        abort("canonical evidence bytes changed during atomic write")
    if not observed_bytes.endswith(b"\n") or observed_bytes.endswith(b"\n\n"):
        abort("canonical evidence must have exactly one trailing newline")
    decoded = json.loads(observed_bytes.decode("utf-8"))
    if decoded != record:
        abort("canonical evidence failed JSON readback validation")
    gates = decoded.get("gates")
    if not isinstance(gates, list) or len(gates) != 9:
        abort("canonical evidence has an invalid gate list")
    if any(gate.get("status") != "PASS" for gate in gates if isinstance(gate, dict)):
        abort("canonical PASS evidence contains a nonpassing gate")


def main() -> int:
    if sys.argv[1:] == ["--source-fingerprint"]:
        try:
            records = digest_sources(source_paths())
            print(source_fingerprint(records))
        except BaseException as error:
            print(f"evidence fingerprint: FAIL: {error}", file=sys.stderr)
            return 1
        return 0

    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    GATE_DIR.mkdir(parents=True, exist_ok=True)
    P09_PATH.unlink(missing_ok=True)
    EVIDENCE_PATH.unlink(missing_ok=True)

    try:
        if len(sys.argv) != 1:
            abort("evidence.py accepts no status or gate arguments")
        lock = parse_lock()
        sources = digest_sources(source_paths())
        prior_gate_statuses(source_fingerprint(sources))
        record = build_record(lock, sources)
        serialized = json.dumps(record, ensure_ascii=False, indent=2) + "\n"
        atomic_text(EVIDENCE_PATH, serialized)
        validate_written(record, serialized)
        atomic_text(P09_PATH, "PASS\n")
    except GatePrerequisiteError as error:
        atomic_text(P09_PATH, f"{error.status}\n")
        print(f"evidence: {error}", file=sys.stderr)
        return error.exit_code
    except BaseException as error:
        EVIDENCE_PATH.unlink(missing_ok=True)
        atomic_text(P09_PATH, "FAIL\n")
        print(f"evidence: FAIL: {error}", file=sys.stderr)
        return 1

    print(f"P0.9 PASS: canonical evidence written to {EVIDENCE_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
