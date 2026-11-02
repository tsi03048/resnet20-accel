"""Run an original package in a new directory, preserving archived evidence."""
import argparse
import json
from pathlib import Path
import platform
import os
import shutil
import subprocess
import sys
import zipfile
from verify_historical import BASE, ROOT, verify

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', choices=[f'E{i}' for i in range(12, 22)])
    parser.add_argument('--output', required=True, type=Path, help='New directory for this execution')
    parser.add_argument('--reference-only', action='store_true')
    args = parser.parse_args()
    verify()
    output = args.output.resolve()
    if output.exists():
        parser.error('output must be a new directory; archived results are never overwritten')
    # The checked manifest fixes the ZIP member set and prohibits traversal.
    manifest = json.loads((BASE / 'manifest.json').read_text(encoding='utf-8'))
    output.mkdir(parents=True)
    if args.stage == 'E15':
        package = output / 'e15_reference'
        shutil.copytree(BASE / 'packages/e15_reference', package)
        command = [sys.executable, 'reference.py']
    else:
        archive = next(a for a in manifest['archives'] if a['stage'] == args.stage)
        with zipfile.ZipFile(ROOT / archive['path']) as z:
            z.extractall(output)
        package = output / archive['package']
        # Keep original execution evidence separate from fresh results.
        (package / 'results').rename(package / 'original_results')
        (package / 'results').mkdir()
        if args.reference_only:
            reference = package / 'reference/make_vectors.py'
            if args.stage == 'E19':
                command = [sys.executable, 'test_packages.py']
            elif args.stage == 'E20':
                command = [sys.executable, 'software/build_vectors.py']
            elif reference.exists():
                command = [sys.executable, 'reference/make_vectors.py']
            else:
                parser.error('this package has no standalone reference generator; run the full RTL script')
        else:
            command = ['bash', 'run.sh']
    # Original byte-level fixture mutation tests assume Linux LF writes.
    # Keep archived code unchanged while reproducing that I/O contract on Windows.
    newline_adapter = os.name == 'nt' and command[0] == sys.executable
    if newline_adapter:
        script = command[1]
        command = [sys.executable, '-c',
                   "import pathlib,runpy; original=pathlib.Path.write_text; "
                   "pathlib.Path.write_text=lambda self,data,encoding=None,errors=None,newline=None: "
                   "original(self,data,encoding=encoding,errors=errors,newline='\\n' if newline is None else newline); "
                   f"runpy.run_path({script!r},run_name='__main__')"]
    result = subprocess.run(command, cwd=package, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    results = package / 'results'
    results.mkdir(exist_ok=True)
    (results / 'migration_run.log').write_text(result.stdout, encoding='utf-8')
    report = {'stage': args.stage, 'exit_code': result.returncode, 'python': platform.python_version(),
              'platform': platform.platform(), 'command': command, 'reference_only': args.reference_only,
              'windows_lf_write_adapter': newline_adapter,
              'note': 'Original report scripts may contain historical tool labels. This report and actual tool output identify this new run.'}
    for name in ('verilator', 'c++'):
        executable = shutil.which(name)
        if executable:
            report[name] = subprocess.check_output([executable, '--version'], text=True).splitlines()[0]
    (results / 'migration_environment.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(result.stdout)
    raise SystemExit(result.returncode)

if __name__ == '__main__':
    main()
