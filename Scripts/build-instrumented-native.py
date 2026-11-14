#!/usr/bin/env python3
"""Build an isolated libwayland 1.26.0 with optional instrumentation."""
import argparse
import hashlib
import importlib.util
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tarfile
import urllib.request
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
ARCHIVE_HASH = '56b3a985cbfe17a926e3bcf037e4d374f44eaa33f3a4b364549dddf0d324cebc'
URL = 'https://gitlab.freedesktop.org/wayland/wayland/-/archive/1.26.0/wayland-1.26.0.tar.gz'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sanitizer', choices=['none', 'address', 'thread'], required=True)
    parser.add_argument('--pending-constructor-fix', action='store_true', help='Apply the local native ownership candidate only to an isolated build.')
    arguments = parser.parse_args()
    specification = importlib.util.spec_from_file_location('toolchain', ROOT / 'Scripts/verify-toolchain.py')
    toolchain = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(toolchain)
    compiler = Path(toolchain.compiler_path(None)).with_name('clang')
    source_parent = ROOT / '.build/native-source'
    source_parent.mkdir(parents=True, exist_ok=True)
    archive = source_parent / 'wayland-1.26.0.tar.gz'
    if not archive.exists():
        with urllib.request.urlopen(URL, timeout=60) as response:
            archive.write_bytes(response.read(16 * 1024 * 1024))
    if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_HASH:
        raise RuntimeError('Native source archive differs from the recorded review input.')
    source = source_parent / 'wayland-1.26.0'
    if not source.exists():
        with tarfile.open(archive) as bundle:
            bundle.extractall(source_parent, filter='data')
    with tarfile.open(archive) as bundle:
        for member in bundle.getmembers():
            if member.isfile():
                expected = bundle.extractfile(member).read()
                path = source_parent / member.name
                if not path.is_file() or path.read_bytes() != expected:
                    raise RuntimeError('Extracted native source differs from the pinned archive: ' + member.name)
    if (source / 'protocol/wayland.xml').read_bytes() != (ROOT / 'Protocols/wayland.xml').read_bytes():
        raise RuntimeError('Native protocol differs from the checked-in schema baseline.')
    suffix = '-pending' if arguments.pending_constructor_fix else ''
    if arguments.pending_constructor_fix:
        replacement = ROOT/'.build/native-pending-source/wayland-1.26.0'
        if replacement.exists(): shutil.rmtree(replacement)
        replacement.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, replacement)
        subprocess.run(['patch','--batch','--forward','-p1','-i',str(ROOT/'Patches/libwayland-1.26.0-pending-proxy-ownership.patch')], cwd=replacement, check=True)
        source = replacement
    build = ROOT / ('.build/native-' + arguments.sanitizer + suffix + '-build')
    prefix = ROOT / ('.build/native-' + arguments.sanitizer + suffix + '-install')
    environment = os.environ.copy()
    environment['CC'] = str(compiler)
    environment.pop('CFLAGS', None)
    environment.pop('LDFLAGS', None)
    if arguments.sanitizer == 'thread':
        # Swift's TSan runtime includes dispatch interceptors requiring these toolchain libraries.
        runtime = compiler.parent.parent / 'lib/swift/linux'
        environment['LDFLAGS'] = '-L' + str(runtime) + ' -Wl,-rpath,' + str(runtime) + ' -ldispatch -lBlocksRuntime'
    command = ['meson', 'setup', str(build), str(source), '--prefix', str(prefix), '--libdir', 'lib',
               '-Dscanner=' + ('true' if arguments.sanitizer == 'none' else 'false'), '-Dtests=false', '-Ddocumentation=false', '-Ddtd_validation=false',
               '-Db_sanitize=' + arguments.sanitizer, '-Db_lundef=false']
    if (build / 'meson-private/coredata.dat').exists(): command.append('--reconfigure')
    subprocess.run(command, env=environment, check=True)
    subprocess.run(['meson', 'compile', '-C', str(build)], env=environment, check=True)
    subprocess.run(['meson', 'install', '-C', str(build)], env=environment, check=True)
    print('Isolated native library directory:', prefix / 'lib')

if __name__ == '__main__':
    main()
