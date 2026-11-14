#!/usr/bin/env python3
"""Build public consumers outside the package and connect them through a temporary native socket."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parent.parent
specification=importlib.util.spec_from_file_location('toolchain',ROOT/'Scripts/verify-toolchain.py')
toolchain=importlib.util.module_from_spec(specification);specification.loader.exec_module(toolchain)
swift=Path(toolchain.compiler_path(None)).with_name('swift')
binaries={}
for name,product in [('Registry','RegistryExample'),('MinimalServer','MinimalServer')]:
    path=ROOT/'Examples'/name
    subprocess.run([str(swift),'build','--package-path',str(path),'-Xswiftc','-warnings-as-errors'],check=True)
    directory=Path(subprocess.check_output([str(swift),'build','--package-path',str(path),'--show-bin-path'],text=True).strip())
    binaries[name]=directory/product
with tempfile.TemporaryDirectory(prefix='waylandkit-example-') as directory:
    environment=os.environ.copy();environment['XDG_RUNTIME_DIR']=directory
    server=subprocess.Popen([str(binaries['MinimalServer'])],env=environment,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        socket=server.stdout.readline().strip()
        if not socket:raise RuntimeError('Server did not publish a socket: '+server.stderr.read())
        environment['WAYLAND_DISPLAY']=socket
        client=subprocess.run([str(binaries['Registry'])],env=environment,capture_output=True,text=True,timeout=15)
        output,errors=server.communicate(timeout=15)
        if client.returncode or server.returncode:raise RuntimeError(client.stdout+client.stderr+output+errors)
        if list(Path(directory).iterdir()):raise RuntimeError('Display destruction left socket or lock files.')
    finally:
        if server.poll() is None:server.terminate();server.wait(timeout=5)
report={'externalPublicConsumers':True,'client':client.stdout.strip(),'server':output.strip(),'socketFilesRetired':True,'passed':True}
(ROOT/'.build/examples-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
