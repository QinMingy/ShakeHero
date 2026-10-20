"""Run isolated native A/B groups sequentially and compare them. No UI automation."""
import argparse
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

CODE_DIR = Path(__file__).resolve().parent
HERE = CODE_DIR
PROJECT = HERE.parents[1]
OUT = PROJECT / 'outputs/pooling-native-benchmark'
OUT.mkdir(parents=True, exist_ok=True)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime', help='Existing UrhoXRuntime.exe path or directory')
parser.add_argument('--repeat', type=int, default=1, help='Repeat pairs; alternate execution order')
parser.add_argument('--prepare-only', action='store_true', help='Freeze sources/configs without starting Runtime')
args = parser.parse_args()
assert args.repeat > 0
tag = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')
pairs = []


def run(variant, count, kind, name, extra=()):
    command = [sys.executable, str(HERE / 'native-run.py'), '--variant', variant,
               '--count', str(count), '--kind', kind, '--name', name, '--source-tag', tag, *extra]
    if args.runtime:
        command += ['--runtime', args.runtime]
    if args.prepare_only:
        command += ['--prepare-only']
    print(('Preparing ' if args.prepare_only else 'Running ') + name, flush=True)
    log = OUT / (name + '-driver.txt')
    with log.open('w', encoding='utf-8') as output:
        result = subprocess.run(command, cwd=PROJECT, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError('Benchmark failed; read ' + str(log))


for repeat in range(1, args.repeat + 1):
    for count, stress in [(20, False), (40, False), (20, True)]:
        label = str(count) + '-ball' + ('-fx-stress' if stress else '')
        names = {variant: tag + '-r' + str(repeat) + '-' + variant + '-' + label
                 for variant in ['baseline', 'candidate']}
        # Reverse alternate repetitions to expose order/temperature bias.
        order = ['baseline', 'candidate'] if repeat % 2 else ['candidate', 'baseline']
        for variant in order:
            run(variant, count, 'ball', names[variant], ['--fx-stress'] if stress else [])
        pairs += ['--pair', label + '-r' + str(repeat) + '=' + names['baseline'] + ',' + names['candidate']]

run('candidate', 20, 'mixed', tag + '-functional',
    ['--warmup', '5', '--measured', '20', '--functional'])
if not args.prepare_only:
    subprocess.run([sys.executable, str(HERE / 'compare.py'), '--results-root', str(OUT), *pairs,
                    '--output', tag + '-comparison.json'], cwd=PROJECT, check=True)
else:
    print('Prepared only; no Runtime or UI was started.')
