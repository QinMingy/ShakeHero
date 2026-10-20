"""Real native main/UI/Box2D A/B; isolated storage, immutable frozen scripts."""
import argparse
import datetime
import hashlib
import io
import json
import re
import statistics
import subprocess
import tarfile
import time
from pathlib import Path

CODE_DIR = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'outputs/pooling-native-benchmark'
OUT.mkdir(parents=True, exist_ok=True)
RUNTIME = Path(r'C:/Users/qinmy/.taptap-maker/runtime/runtime-a98eedea-fd0f-4bff-91ec-819975e3c46c')
BASE = '0e2266e80a593cad0a4c93bc5a1e025f105df7be'
p = argparse.ArgumentParser()
p.add_argument('--variant', choices=['baseline', 'candidate'], required=True)
p.add_argument('--count', type=int, choices=[20, 40], default=20)
p.add_argument('--kind', choices=['ball','mixed'], default='mixed')
p.add_argument('--fx-stress', action='store_true', help='Explicit injected presentation-event stress; not natural game income')
p.add_argument('--warmup', type=int, default=30)
p.add_argument('--measured', type=int, default=300)
p.add_argument('--name')
p.add_argument('--source-tag', default='', help='Freeze into a new named source set for a later code revision')
p.add_argument('--runtime', help='Existing UrhoXRuntime.exe path or its directory; never downloads software')
p.add_argument('--prepare-only', action='store_true')
p.add_argument('--functional', action='store_true', help='Run post-measure functional checks if supplied')
args = p.parse_args()
assert args.warmup >= 0 and args.measured > 0
assert not args.source_tag or re.fullmatch(r'[A-Za-z0-9_-]+', args.source_tag), 'Invalid source tag'
if args.runtime:
    runtime_argument = Path(args.runtime).resolve()
    RUNTIME = runtime_argument.parent if runtime_argument.suffix.lower() == '.exe' else runtime_argument
assert (RUNTIME / 'UrhoXRuntime.exe').is_file(), 'Supply an installed Runtime with --runtime'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def hashes(base, directory, pattern='*'):
    return {q.relative_to(base).as_posix(): digest(q)
            for q in sorted((base / directory).rglob(pattern)) if q.is_file()}

def saves():
    return {q.name: digest(q) for q in ROOT.glob('bottle-save-*.json')}

production_before = hashes(ROOT, 'scripts')
assets_before = hashes(ROOT, 'assets')
saves_before = saves()
source = OUT / ('source-' + args.variant + ('-' + args.source_tag if args.source_tag else ''))
if not source.exists():
    source.mkdir(parents=True)
    if args.variant == 'baseline':
        archive = subprocess.run(['git', 'archive', BASE, 'scripts'], cwd=ROOT,
                                 capture_output=True, check=True).stdout
        with tarfile.open(fileobj=io.BytesIO(archive), mode='r:') as tar:
            for member in tar.getmembers():
                dest = (source / member.name).resolve()
                assert dest.is_relative_to(source.resolve()) and not member.issym() and not member.islnk()
                if member.isdir():
                    dest.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(tar.extractfile(member).read())
    else:
        for relative in production_before:
            dest = source / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes((ROOT / relative).read_bytes())
    (source / 'manifest.json').write_text(json.dumps({
        'base_commit': BASE if args.variant == 'baseline' else None,
        'scripts': hashes(source, 'scripts'), 'production_at_capture': production_before,
        'assets_at_capture': assets_before}, indent=2), encoding='utf-8')
manifest_path = source / 'manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
frozen_before = hashes(source, 'scripts')
assert frozen_before == manifest['scripts'], 'Frozen source payload changed'
assert assets_before == manifest['assets_at_capture'], 'Shared asset payload changed since freeze'
if args.variant == 'candidate':
    assert production_before == manifest['production_at_capture'], 'Candidate changed after freeze'
name = args.name or f'{args.variant}-{args.count}-{args.kind}'+('-fx-stress' if args.fx_stress else '')
work = (OUT / name).resolve()
assert work.is_relative_to(OUT.resolve()) and work != source.resolve()
work.mkdir(exist_ok=True)
harness = work / 'harness'
harness.mkdir(exist_ok=True)
for filename in ['native-entry.lua', 'native-functional.lua']:
    original = CODE_DIR / filename
    if original.exists():
        (harness / filename).write_bytes(original.read_bytes())
fallback = '''local V=assert(_G.V)
local c=assert(_G.PoolingNative)
V.atFrame(10,function()
 V.assert(c.started and c.game and c.view and c.physics,"actual main initialized")
 V.assert(c.initialBodies==c.config.count,"exact mixed fixture count")
 V.assert(c.sim.budget.budgetMs==4,"default 4ms budget")
 V.assert(c.worldSettings.velocityIterations==12 and c.worldSettings.positionIterations==8 and c.worldSettings.continuousPhysics,"default CCD and 12/8 solver")
 V.assert(require("PublishConfig").PUBLISH_MODE==true,"production permissions")
 V.assert(c.dragging==true,"actual Board pan")
end)
V.atFrame(c.config.warmup+c.config.measured+2,function()
 c.Finish()
 V.assert(#c.samples==c.config.measured,"all measured frames captured")
 V.assert(c.sim.completedSteps>0,"real simulation advances")
 V.assert(c.nonFinite==0,"finite render state")
 V.finish()
end)
'''
checks = CODE_DIR / 'native-checks.lua'
(harness / 'native-checks.lua').write_text(checks.read_text(encoding='utf-8')
    if args.functional and checks.exists() else fallback, encoding='utf-8')
cfg = {'variant': args.variant, 'count': args.count, 'warmup': args.warmup,
       'kind':args.kind,'fxStress':args.fx_stress,'measured': args.measured, 'functional': args.functional}
lua_values = lambda v: str(v).lower() if isinstance(v, bool) else json.dumps(v)
(harness / 'native-config.lua').write_text('return {' + ','.join(
    k + '=' + lua_values(v) for k, v in cfg.items()) + '}\n', encoding='utf-8')
fixture = CODE_DIR / 'fixture-resources'
resources = [harness, source / 'scripts', ROOT / 'assets', fixture,
             RUNTIME / 'Res', RUNTIME / 'Data', RUNTIME / 'CoreData']
frame_count = args.warmup + args.measured + (1800 if args.functional else 5)
report = work / 'validation.json'
shot = work / 'screen.png'
command = [str(RUNTIME / 'UrhoXRuntime.exe'), 'native-entry.lua', '-p',
           ';'.join(str(q) for q in resources), '-w', '-width=402', '-height=874',
           '-validate', '-validate-frames=' + str(frame_count), '-validate-timeout=120',
           '-validate-test=' + str(harness / 'native-checks.lua'),
           '-validate-output=' + str(report)]
(work / 'command.json').write_text(json.dumps(command, indent=2), encoding='utf-8')
identity = {'name': name, 'source_manifest': str(manifest_path),
            'source_manifest_sha256': digest(manifest_path),
            'harness_hashes': hashes(work, 'harness'), 'command': command,
            'production_scripts_unchanged': production_before == hashes(ROOT, 'scripts'),
            'player_saves_unchanged': saves_before == saves()}
(work / 'prepared.json').write_text(json.dumps(identity, indent=2), encoding='utf-8')
if args.prepare_only:
    print(json.dumps(identity, indent=2))
    raise SystemExit(0)
started = time.perf_counter()
try:
    result = subprocess.run(command, cwd=work, capture_output=True, timeout=140)
    log = result.stdout.decode('utf-8', errors='replace') + result.stderr.decode('utf-8', errors='replace')
    code = result.returncode
except subprocess.TimeoutExpired as error:
    log = (error.stdout or b'').decode('utf-8', errors='replace') + (error.stderr or b'').decode('utf-8', errors='replace')
    code = 'TIMEOUT'
(work / 'runtime.txt').write_text(log, encoding='utf-8')
raw = json.loads(report.read_text(encoding='utf-8-sig')) if report.exists() else {}
data, samples, functional_result = {}, [], {}
for line in log.splitlines():
    if 'POOLING_NATIVE_META ' in line:
        data = json.loads(line.split('POOLING_NATIVE_META ', 1)[1])
    if 'POOLING_NATIVE_SAMPLE ' in line:
        samples.append(json.loads(line.split('POOLING_NATIVE_SAMPLE ', 1)[1]))
    if 'POOLING_NATIVE_FUNCTIONAL ' in line:
        functional_result=json.loads(line.split('POOLING_NATIVE_FUNCTIONAL ',1)[1])
def stats(values):
    v = sorted(float(x) for x in values)
    return {'n': len(v), 'sum': sum(v), 'mean': statistics.mean(v),
            'median': statistics.median(v), 'p95': v[min(len(v)-1,int(.95*len(v)))],
            'p99': v[min(len(v)-1,int(.99*len(v)))], 'max': max(v), 'min': min(v)} if v else {}
summary = {'name': name, 'variant': args.variant, 'count': args.count,'kind':args.kind,'fx_stress':args.fx_stress,'screenshot_during_measurement':False,
    'warmup': args.warmup, 'measured': args.measured, 'measured_frames': len(samples),
    'exit_code': code, 'process_wall_ms': (time.perf_counter()-started)*1000,
    'result': raw.get('result'), 'test_result': raw.get('test_result'),
    'test_assertions': raw.get('test_assertions'), 'test_issues': raw.get('test_issues'),
    'runtime_errors': raw.get('summary'), 'missing_resources': raw.get('missing_resources'),
    'production_scripts_unchanged': production_before == hashes(ROOT, 'scripts'),
    'player_saves_unchanged': saves_before == saves(),
    'frozen_scripts_unchanged': frozen_before == hashes(source, 'scripts'),
    'shared_assets_unchanged': assets_before == hashes(ROOT, 'assets'),
    'source_manifest': str(manifest_path), 'source_manifest_sha256': digest(manifest_path),
    'metadata': data, 'fixed_validation_timestep': True,
    'post_measurement_functional':functional_result,
    'metrics': {key: stats(s[key] for s in samples if key in s) for key in [
        'wall_interval_ms','handle_update_cpu_ms','simulation_cpu_ms','physics_cpu_ms',
        'heap_kb','heap_delta_kb','heap_drop_kb','backlog_ms','bodies','particles','score_queue',
        'coins','coin_waiting','target_particles','completed_steps','dt_ms']},
    'actual_running_frames': sum(s.get('phase')=='running' for s in samples),
    'actual_dragging_frames': sum(s.get('dragging') is True for s in samples),
    'heap_note': 'Natural GC count is Lua heap including retained pools and fixed harness rows; not total allocation or GC pause time. Drops are only a reclamation proxy.',
    'timing_note': 'time:GetTimeSinceEpochMs is probed; if unavailable, os.clock()*1000 measures native Update intervals with independent log boundary timestamps. *_cpu_ms are os.clock duration proxies (about 1ms granularity), not independent CPU counters. Fixed validation TimeStep is not FPS.',
    'native_clock_boundaries': [line for line in log.splitlines() if 'POOLING_NATIVE_BOUNDARY ' in line],
    'gpu_lines': [line for line in log.splitlines() if any(k in line for k in ['Selected GPU','Direct3D','GPU 0 Name','Renderer:'])]}
calibrations=[]
for line in summary['native_clock_boundaries']:
    match=re.search(r'\[([0-9-]+ [0-9_]+)\].*POOLING_NATIVE_BOUNDARY (\d+) ([0-9.]+)',line)
    if match:
        stamp=datetime.datetime.strptime(match[1],'%Y-%m-%d %H_%M_%S_%f')
        calibrations.append({'frame':int(match[2]),'runtime_log_ms':stamp.timestamp()*1000,'os_clock_ms':float(match[3])})
summary['clock_calibration']=[{'from_frame':a['frame'],'to_frame':b['frame'],
    'runtime_log_span_ms':b['runtime_log_ms']-a['runtime_log_ms'],
    'os_clock_span_ms':b['os_clock_ms']-a['os_clock_ms'],
    'difference_ms':abs((b['runtime_log_ms']-a['runtime_log_ms'])-(b['os_clock_ms']-a['os_clock_ms']))}
    for a,b in zip(calibrations,calibrations[1:])]
(work / 'metrics.json').write_text(json.dumps({'metadata': data, 'samples': samples}, indent=2), encoding='utf-8')
(work / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print(json.dumps(summary, indent=2), flush=True)
assert summary['production_scripts_unchanged'] and summary['player_saves_unchanged']
assert summary['frozen_scripts_unchanged'] and summary['shared_assets_unchanged']
assert len(samples) == args.measured, 'Incomplete native sample capture'
assert data.get('defaultBudgetMs') == 4 and data.get('publishMode') is True
assert raw.get('test_result') == 'PASSED', 'Native functional assertions failed'
