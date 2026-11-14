#!/usr/bin/env python3
"""Build separate module archives, verify symbols, and merge detailed DocC documentation."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
MODULES = ['WaylandRuntime', 'WaylandProtocol', 'WaylandClient', 'WaylandServer', 'WaylandCursor', 'WaylandEGL', 'WaylandUtilities', 'WaylandKit']

def native_compiler_flags(environment):
    # Swift Build's C API extraction does not inherit system-library search paths.
    # Pass native flags explicitly so standalone header extraction uses the same baseline.
    pkg_config_environment = environment | {'PKG_CONFIG_ALLOW_SYSTEM_CFLAGS': '1'}
    native_flags = shlex.split(subprocess.check_output(
        ['pkg-config', '--cflags', 'wayland-client', 'wayland-server', 'wayland-cursor', 'wayland-egl'],
        env=pkg_config_environment, text=True))
    return [argument for flag in native_flags for argument in ['-Xcc', flag]]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hosting-base-path', help='Transform the merged archive for static hosting at this URL path; use an empty value for a domain root.')
    arguments = parser.parse_args()
    specification = importlib.util.spec_from_file_location('toolchain', ROOT / 'Scripts/verify-toolchain.py')
    toolchain = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(toolchain)
    swift = Path(toolchain.compiler_path(None)).with_name('swift')
    docc = swift.with_name('docc')
    output = ROOT / '.build/documentation'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'report.json').write_text(json.dumps({'passed': False, 'status': 'building'}) + '\n')
    environment = os.environ.copy()
    for name in ['CC', 'CXX', 'CPP', 'LD', 'AR', 'NM', 'RANLIB', 'STRIP']: environment.pop(name, None)
    catalog = ROOT / 'docs/WaylandKit.docc'
    def input_snapshot():
        paths=[Path(__file__),ROOT/'Package.swift',*[path for path in catalog.rglob('*') if path.is_file()],
               *[path for path in (ROOT/'Sources').rglob('*') if path.is_file()]]
        return {str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    hashes=input_snapshot()
    compiler_flags = native_compiler_flags(environment)
    # Swift 6.4.2 Swift Build drops explicit include flags in C ExtractAPI tasks.
    # The native backend emits the Swift graphs required here without those tasks.
    build_options = ['--build-system', 'native', '--scratch-path', str(ROOT / '.build/documentation-native')]
    subprocess.run([str(swift), 'build', *build_options, *compiler_flags, '--build-tests'],
                   cwd=ROOT, env=environment, check=True)
    subprocess.run([str(swift), 'package', *build_options, *compiler_flags, 'dump-symbol-graph',
                    '--minimum-access-level', 'package', '--emit-extension-block-symbols'], cwd=ROOT, env=environment, check=True)
    binary_directory = Path(subprocess.check_output(
        [str(swift), 'build', *build_options, '--show-bin-path'], cwd=ROOT, env=environment, text=True).strip())
    graphs = binary_directory.parent / 'symbolgraph'
    report = {'inputs': hashes, 'modules': {}}
    archives = []
    with tempfile.TemporaryDirectory(prefix='inputs-', dir=output) as temporary:
        for module in [*MODULES, 'Project']:
            directory = Path(temporary) / module
            directory.mkdir()
            module_catalog = directory / (module + '.docc')
            module_catalog.mkdir()
            for source in catalog.iterdir():
                if module != 'Project' and source.stem != module: continue
                if module == 'Project' and source.stem in MODULES: continue
                if source.is_dir(): shutil.copytree(source, module_catalog / source.name)
                else: shutil.copy2(source, module_catalog / source.name)
            symbols_directory = directory / 'symbols'
            symbols_directory.mkdir()
            module_graphs = [] if module == 'Project' else [graphs / (module + '.symbols.json'), *sorted(graphs.glob(module + '@*.symbols.json'))]
            symbols_by_identifier = {}
            for graph in module_graphs:
                graph_data = json.loads(graph.read_text())
                for symbol in graph_data['symbols']:
                    precise = symbol['identifier']['precise']
                    if symbol.get('docComment') or not (precise.startswith('s:s9OptionSetP') and '::SYNTHESIZED::' in precise):
                        continue
                    # Swift emits an undocumented integer-specialized overload alongside
                    # the documented standard OptionSet default with the same signature.
                    inherited = [candidate for candidate in graph_data['symbols']
                                 if candidate.get('docComment') and candidate['pathComponents'] == symbol['pathComponents']
                                 and candidate.get('declarationFragments') == symbol.get('declarationFragments')]
                    if inherited:
                        symbol['docComment'] = inherited[0]['docComment']
                (symbols_directory / graph.name).write_text(json.dumps(graph_data) + '\n')
                for symbol in graph_data['symbols']:
                    symbols_by_identifier[symbol['identifier']['precise']] = symbol
            symbols = list(symbols_by_identifier.values())
            if any(not symbol.get('docComment') for symbol in symbols):
                raise RuntimeError('Undocumented symbol in ' + module + ': ' + ', '.join('.'.join(symbol['pathComponents']) for symbol in symbols if not symbol.get('docComment')))
            archive = output / (module + '.doccarchive')
            command = [str(docc), 'convert', str(module_catalog), '--additional-symbol-graph-dir', str(symbols_directory),
                       '--output-dir', str(archive), '--fallback-display-name', module,
                       '--fallback-bundle-identifier', 'org.tomorilab.WaylandKit.' + module, '--warnings-as-errors',
                       '--enable-experimental-external-link-support']
            dependencies = {'WaylandClient': ['WaylandRuntime', 'WaylandProtocol'], 'WaylandServer': ['WaylandRuntime', 'WaylandProtocol'],
                            'WaylandCursor': ['WaylandRuntime', 'WaylandProtocol', 'WaylandClient'],
                            'WaylandEGL': ['WaylandRuntime', 'WaylandProtocol', 'WaylandClient'], 'WaylandUtilities': ['WaylandRuntime'], 'WaylandKit': ['WaylandRuntime', 'WaylandProtocol', 'WaylandClient']}
            for dependency in (MODULES if module == 'Project' else dependencies.get(module, [])):
                command += ['--dependency', str(output / (dependency + '.doccarchive'))]
            subprocess.run(command, cwd=ROOT, env=environment, check=True)
            pages = list((archive / 'data/documentation').rglob('*.json'))
            identifiers = {json.loads(page.read_text()).get('metadata', {}).get('externalID') for page in pages}
            if not all(symbol['identifier']['precise'] in identifiers for symbol in symbols):
                raise RuntimeError('A documented symbol has no rendered page in ' + module)
            report['modules'][module] = {'symbols': len(symbols), 'pages': len(pages)}
            archives.append(archive)
    combined = output / 'WaylandKit.doccarchive'
    with tempfile.TemporaryDirectory(prefix='merge-', dir=output) as temporary:
        replacement = Path(temporary) / 'WaylandKit.doccarchive'
        subprocess.run([str(docc), 'merge', *map(str, archives), '--output-path', str(replacement),
                        '--synthesized-landing-page-name', 'WaylandKit'], env=environment, check=True)
        if combined.exists(): shutil.rmtree(combined)
        shutil.move(replacement, combined)
    if arguments.hosting_base_path is not None:
        subprocess.run([str(docc), 'process-archive', 'transform-for-static-hosting', str(combined),
                        '--hosting-base-path', arguments.hosting_base_path], env=environment, check=True)
        # The package landing page lives at /documentation, including under a repository base path.
        (combined / 'index.html').write_text(
            '<!doctype html><html lang="en"><head><meta charset="utf-8">'
            '<meta http-equiv="refresh" content="0; url=documentation/project/">'
            '<title>WaylandKit Documentation</title></head><body>'
            '<a href="documentation/project/">WaylandKit Documentation</a></body></html>\n')
        (combined / '.nojekyll').touch()
        if not (combined / 'documentation/project/index.html').is_file():
            raise RuntimeError('The static documentation landing page is missing.')
        report['hostingBasePath'] = arguments.hosting_base_path
    report['symbols'] = sum(module['symbols'] for module in report['modules'].values())
    report['combinedPages'] = len(list((combined / 'data').rglob('*.json')))
    if hashes != input_snapshot():
        raise RuntimeError('Documentation inputs changed during verification.')
    report['passed'] = True
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ['modules', 'symbols', 'combinedPages', 'passed']}, indent=2))

if __name__ == '__main__':
    main()
