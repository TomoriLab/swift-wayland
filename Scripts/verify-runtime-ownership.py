#!/usr/bin/env python3
"""Check ownership boundaries against the actual package-access runtime module."""

import importlib.util
import hashlib
import os
import re
import subprocess
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
specification = importlib.util.spec_from_file_location("toolchain_probes", ROOT / "Scripts/verify-toolchain.py")
sys.dont_write_bytecode = True
assert specification is not None and specification.loader is not None
toolchain = importlib.util.module_from_spec(specification)
specification.loader.exec_module(toolchain)


def main():
    compiler = toolchain.compiler_path(None)
    output = ROOT / ".build/runtime-compiler"
    output.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    for name in ["CC", "CXX", "CPP", "LD", "AR", "NM", "RANLIB", "STRIP"]:
        environment.pop(name, None)
    inputs = [Path(__file__), ROOT / "Scripts/verify-toolchain.py",
              *(ROOT / "Sources").rglob("*.swift"), *(ROOT / "Sources").rglob("*.h"), *(ROOT / "Sources").rglob("*.c"),
              *(ROOT / "Tests/RuntimeCompileChecks").glob("*.swift")]
    hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    report = {"results": [], "inputs": hashes}
    try:
        target = toolchain.invoke([compiler, "-print-target-info"], environment)
        toolchain.require_success(target)
        report["target"] = json.loads(target["stdout"])
        if report["target"]["compilerVersion"] != "Swift version 6.4.2 (swift-6.4.2-RELEASE)":
            raise RuntimeError("Swift 6.4.2 is required.")
        if report["target"]["target"]["arch"] != "x86_64":
            raise RuntimeError("The current runtime validation milestone targets x86_64.")
        header = ROOT / "Sources/CWaylandRuntime/include/CWaylandRuntime.h"
        (output / "module.modulemap").write_text(
            "module CWaylandRuntime { header " + json.dumps(str(header)) + " export * }\n"
        )
        patterns = {
            "Accepted": [],
            "DoubleClose": ["'owner' consumed more than once"],
            "CopyProxyOwner": ["'copy' cannot be applied to noncopyable types"],
            "CopyDescriptor": ["'copy' cannot be applied to noncopyable types"],
            "CopyReceivedDescriptor": ["'copy' cannot be applied to noncopyable types"],
            "CopySubscription": ["'copy' cannot be applied to noncopyable types"],
            "DoubleDescriptorClose": ["'owner' consumed more than once"],
            "UnauditedDescriptorBorrow": ["expression uses unsafe constructs but is not marked with 'unsafe'"],
            "CopyOwner": ["'copy' cannot be applied to noncopyable types"],
            "ReferenceCannotClose": ["value of type 'ObjectHandle' has no member 'close'"],
            "SendReference": ["capture of 'handle' with non-Sendable type 'ObjectHandle'"],
            "UnauditedAdoption": ["expression uses unsafe constructs but is not marked with 'unsafe'"],
        }
        fixtures = ROOT / "Tests/RuntimeCompileChecks"
        if {path.stem for path in fixtures.glob("*.swift")} != patterns.keys():
            raise RuntimeError("Every runtime compile fixture must be classified exactly once.")
        for configuration, optimization in [("debug", "-Onone"), ("release", "-O")]:
            directory = output / configuration
            directory.mkdir(exist_ok=True)
            flags = [*toolchain.COMMON_FLAGS, optimization, "-package-name", "swift_wayland", "-I", output]
            module = toolchain.invoke([
                compiler, *flags, "-emit-module", "-module-name", "WaylandRuntime",
                *sorted((ROOT / "Sources/WaylandRuntime").glob("*.swift")),
                "-o", directory / "WaylandRuntime.swiftmodule",
            ], environment)
            toolchain.require_success(module)
            report[configuration + "_module"] = module
            for name, diagnostics in patterns.items():
                compilation = toolchain.invoke([
                    compiler, *flags, "-I", directory, "-c", fixtures / (name + ".swift"),
                    "-o", directory / (name + ".o"),
                ], environment)
                if diagnostics:
                    passed = compilation["returncode"] == 1 and all(
                        re.search(pattern, compilation["stderr"]) for pattern in diagnostics
                    ) and "error:" in compilation["stderr"] and "Stack dump:" not in compilation["stderr"]
                    passed = passed and "Please submit a bug report" not in compilation["stderr"]
                else:
                    passed = compilation["returncode"] == 0
                report["results"].append({"id": name, "configuration": configuration, "passed": passed, "compile": compilation})
                print(("PASS" if passed else "FAIL") + " " + configuration + " " + name, flush=True)
                if not passed:
                    print(compilation["stderr"], file=sys.stderr)
        if hashes != {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}:
            raise RuntimeError("Runtime compiler inputs changed during verification.")
        report["passed"] = all(result["passed"] for result in report["results"])
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as error:
        report["passed"] = False
        report["error"] = str(error)
        print(str(error), file=sys.stderr)
    finally:
        path = output / "report.json"
        path.write_text(json.dumps(report, indent=2) + "\n")
        print("Report: " + str(path))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
