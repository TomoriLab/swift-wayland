#!/usr/bin/env python3
"""Compile and execute version-pinned ownership and native ABI experiments."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
PROBES = ROOT / "Tests" / "Toolchain"
COMMON_FLAGS = [
    "-swift-version", "6", "-strict-concurrency=complete", "-strict-memory-safety",
    "-warnings-as-errors", "-parse-as-library",
]


def compiler_path(requested):
    # The driver selects swiftc mode from argv[0], so retain the executable symlink name.
    if requested:
        return Path(requested).expanduser().absolute()
    selected = os.environ.get("SWIFTC") or shutil.which("swiftc")
    if selected:
        return Path(selected).absolute()
    # This fallback avoids mistaking OpenStack's swift CLI for the Swift compiler.
    candidate = Path.home() / ".local/share/swiftly/toolchains/6.4.2/usr/bin/swiftc"
    if candidate.is_file():
        return candidate
    raise RuntimeError("Swift 6.4.2 swiftc was not found; pass --swiftc or set SWIFTC.")


def invoke(command, environment, timeout=60):
    started = time.monotonic()
    result = subprocess.run(
        [str(item) for item in command], cwd=ROOT, env=environment,
        capture_output=True, text=True, timeout=timeout,
    )
    return {
        "command": [str(item) for item in command],
        "returncode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "seconds": round(time.monotonic() - started, 3),
    }


def require_success(result):
    if result["returncode"] != 0:
        raise RuntimeError(result["stdout"] + result["stderr"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swiftc", help="Path to the exact Swift 6.4.2 compiler.")
    parser.add_argument("--output", type=Path, default=ROOT / ".build/toolchain-probes")
    parser.add_argument("--configuration", choices=["debug", "release", "all"], default="all")
    parser.add_argument("--sanitize", choices=["none", "address", "thread"], default="none")
    arguments = parser.parse_args()
    compiler = compiler_path(arguments.swiftc)
    output = arguments.output.expanduser().resolve() / arguments.sanitize
    output.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    # Match the repository's Swift shell wrapper instead of inheriting foreign linker overrides.
    for name in ["CC", "CXX", "CPP", "LD", "AR", "NM", "RANLIB", "STRIP"]:
        environment.pop(name, None)
    sanitizer_options = {}
    if arguments.sanitize == "address":
        sanitizer_options = {
            "ASAN_OPTIONS": "detect_leaks=1:halt_on_error=1:abort_on_error=1",
            "LSAN_OPTIONS": "exitcode=23",
        }
    elif arguments.sanitize == "thread":
        sanitizer_options = {"TSAN_OPTIONS": "halt_on_error=1:exitcode=66"}
    environment.update(sanitizer_options)
    report = {"schema": 1, "compiler": str(compiler), "sanitize": arguments.sanitize, "results": []}
    report["sanitizer_options"] = sanitizer_options
    report_path = output / "report.json"
    try:
        target = invoke([compiler, "-print-target-info"], environment)
        require_success(target)
        report["target"] = json.loads(target["stdout"])
        if report["target"]["compilerVersion"] != "Swift version 6.4.2 (swift-6.4.2-RELEASE)":
            raise RuntimeError("This verification suite requires the exact Swift 6.4.2 release.")
        report["features"] = invoke([compiler, "-print-supported-features"], environment)
        require_success(report["features"])
        report["host"] = {"system": os.uname().sysname, "machine": os.uname().machine}
        if report["target"]["target"]["arch"] != os.uname().machine:
            raise RuntimeError("This runner executes native binaries; cross-target execution needs a separate runner.")
        versions = invoke(["pkg-config", "--modversion", "wayland-client", "wayland-server", "wayland-cursor", "wayland-egl"], environment)
        require_success(versions)
        report["native_versions"] = versions["stdout"].splitlines()
        if report["native_versions"][:3] != ["1.26.0", "1.26.0", "1.26.0"]:
            raise RuntimeError("Client, server and cursor development packages must match the 1.26.0 baseline.")
        manifest_path = PROBES / "manifest.json"
        manifest = json.loads(manifest_path.read_text())
        expected_files = {item["file"] for item in manifest}
        actual_files = {path.name for path in (PROBES / "Fixtures").glob("*.swift")}
        if not manifest or len({item["id"] for item in manifest}) != len(manifest) or len(expected_files) != len(manifest):
            raise RuntimeError("Probe IDs and fixture paths must be nonempty and unique.")
        if expected_files != actual_files:
            raise RuntimeError("The manifest must cover every Swift fixture exactly once.")
        for item in manifest:
            if item["expect"] not in {"run", "reject"}:
                raise RuntimeError("Unknown probe expectation: " + item["id"])
            if item["expect"] == "reject" and not item.get("diagnostics"):
                raise RuntimeError("Rejected probes require semantic diagnostic patterns.")
        report["inputs"] = {
            str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(PROBES.rglob("*")) if path.is_file()
        }
        configurations = ["debug", "release"] if arguments.configuration == "all" else [arguments.configuration]
        for configuration in configurations:
            directory = output / configuration
            directory.mkdir(exist_ok=True)
            optimization = "-Onone" if configuration == "debug" else "-O"
            flags = [*COMMON_FLAGS, optimization]
            if arguments.sanitize != "none":
                flags.append("-sanitize=" + arguments.sanitize)
            for probe in manifest:
                fixture = PROBES / "Fixtures" / probe["file"]
                result = {"id": probe["id"], "configuration": configuration, "expect": probe["expect"]}
                report["results"].append(result)
                executable = directory / fixture.stem
                command = [compiler, *flags, fixture]
                if probe.get("native"):
                    clang = compiler.parent / "clang"
                    native_flags = invoke(["pkg-config", "--cflags", "wayland-server"], environment)
                    require_success(native_flags)
                    native_object = directory / "probe.o"
                    native_command = [
                        clang, "-std=c11", "-Wall", "-Wextra", "-Werror", "-O0" if configuration == "debug" else "-O2",
                        *shlex.split(native_flags["stdout"]), "-c", PROBES / "CProbe/probe.c", "-o", native_object,
                    ]
                    if arguments.sanitize != "none":
                        native_command.append("-fsanitize=" + arguments.sanitize)
                    result["native_compile"] = invoke(native_command, environment)
                    require_success(result["native_compile"])
                    command += ["-I", PROBES / "CProbe", native_object, "-lwayland-server"]
                if probe["expect"] == "reject":
                    command += ["-c", "-o", directory / (fixture.stem + ".o")]
                else:
                    command += ["-o", executable]
                result["compile"] = invoke(command, environment)
                compilation = result["compile"]
                if probe["expect"] == "reject":
                    diagnostics = compilation["stderr"]
                    matches = all(re.search(pattern, diagnostics) for pattern in probe["diagnostics"])
                    result["passed"] = (
                        compilation["returncode"] == 1 and matches and "error:" in diagnostics
                        and "Stack dump:" not in diagnostics and "Please submit a bug report" not in diagnostics
                    )
                else:
                    if compilation["returncode"] == 0:
                        result["execution"] = invoke([executable], environment)
                        execution = result["execution"]
                        result["passed"] = execution["returncode"] == 0 and probe["output"] in execution["stdout"]
                    else:
                        result["passed"] = False
                print(("PASS" if result["passed"] else "FAIL") + " " + configuration + " " + probe["id"], flush=True)
                if not result["passed"]:
                    print(compilation["stderr"], file=sys.stderr)
                    if "execution" in result:
                        print(result["execution"]["stderr"], file=sys.stderr)
        current_inputs = {
            str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(PROBES.rglob("*")) if path.is_file()
        }
        if current_inputs != report["inputs"]:
            raise RuntimeError("Probe inputs changed during verification; rerun against a stable checkout.")
        report["passed"] = all(item["passed"] for item in report["results"])
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as error:
        report["passed"] = False
        report["error"] = str(error)
        print(str(error), file=sys.stderr)
    finally:
        report_path.write_text(json.dumps(report, indent=2) + "\n")
        print("Report: " + str(report_path), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
