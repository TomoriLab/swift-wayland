#!/usr/bin/env python3
"""Build separate module archives, verify symbols, and merge detailed DocC documentation."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
MODULES = ['WaylandRuntime', 'WaylandProtocol', 'WaylandClient', 'WaylandServer']

def main():
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
    subprocess.run([str(swift), 'package', 'dump-symbol-graph', '--minimum-access-level', 'package'], cwd=ROOT, env=environment, check=True)
    graphs = ROOT / '.build/out/symbolgraph'
    catalog = ROOT / 'docs/WaylandKit.docc'
    inputs = [Path(__file__), *catalog.glob('*.md'), *(ROOT / 'Sources').rglob('*.swift')]
    hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    report = {'inputs': hashes, 'modules': {}}
    archives = []
    with tempfile.TemporaryDirectory(prefix='inputs-', dir=output) as temporary:
        for module in MODULES:
            directory = Path(temporary) / module
            directory.mkdir()
            module_catalog = directory / (module + '.docc')
            module_catalog.mkdir()
            for source in catalog.iterdir():
                if source.stem in MODULES and source.stem != module: continue
                if source.is_dir(): shutil.copytree(source, module_catalog / source.name)
                else: shutil.copy2(source, module_catalog / source.name)
            symbols_directory = directory / 'symbols'
            symbols_directory.mkdir()
            graph = graphs / (module + '.symbols.json')
            shutil.copy2(graph, symbols_directory / graph.name)
            symbols = json.loads(graph.read_text())['symbols']
            if any(not symbol.get('docComment') for symbol in symbols):
                raise RuntimeError('Undocumented package-access symbol in ' + module)
            archive = output / (module + '.doccarchive')
            command = [str(docc), 'convert', str(module_catalog), '--additional-symbol-graph-dir', str(symbols_directory),
                       '--output-dir', str(archive), '--fallback-display-name', module,
                       '--fallback-bundle-identifier', 'org.tomorilab.WaylandKit.' + module, '--warnings-as-errors',
                       '--enable-experimental-external-link-support']
            if module in ['WaylandClient', 'WaylandServer']:
                command += ['--dependency', str(output / 'WaylandRuntime.doccarchive')]
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
    report['symbols'] = sum(module['symbols'] for module in report['modules'].values())
    report['combinedPages'] = len(list((combined / 'data').rglob('*.json')))
    if hashes != {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}:
        raise RuntimeError('Documentation inputs changed during verification.')
    report['passed'] = True
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ['modules', 'symbols', 'combinedPages', 'passed']}, indent=2))

if __name__ == '__main__':
    main()
