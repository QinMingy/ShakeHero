"""Compare explicit native runs, preserving raw failures and workload checks."""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

CODE_DIR = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--pair', action='append', required=True,
                    help='label=baseline-directory,candidate-directory (repeatable)')
parser.add_argument('--output', default='comparison.json')
parser.add_argument('--results-root', type=Path, default=ROOT / 'outputs/pooling-native-benchmark',
                    help='Directory containing generated run data; never writes benchmark sources')
args = parser.parse_args()
RESULTS_ROOT = args.results_root.resolve()


def read(directory, name):
    path = (RESULTS_ROOT / directory / name).resolve()
    assert path.is_relative_to(RESULTS_ROOT), 'Run must stay inside benchmark directory'
    return json.loads(path.read_text(encoding='utf-8-sig'))


def checks(summary, command):
    return {
        'all_measured_frames': summary['measured_frames'] == summary['measured'] == 300,
        'actual_running_and_dragging': summary['actual_running_frames'] == 300
            and summary['actual_dragging_frames'] == 300,
        'functional_checks_passed': summary['test_result'] == 'PASSED',
        'zero_lua_errors': summary['runtime_errors']['lua_errors'] == 0,
        'production_and_assets_unchanged': summary['production_scripts_unchanged']
            and summary['shared_assets_unchanged'] and summary['frozen_scripts_unchanged'],
        'player_saves_unchanged': summary['player_saves_unchanged'],
        'no_screenshot_in_measurement': not any(str(arg).startswith('-screenshot') for arg in command),
        'clock_calibrated_against_log': bool(summary.get('clock_calibration'))
            and all(row['difference_ms'] <= 2 for row in summary['clock_calibration']),
        'default_budget': summary['metadata']['defaultBudgetMs'] == 4,
        'production_permissions': summary['metadata']['publishMode'] is True,
    }


def metric(before, after, key):
    a, b = before['metrics'][key], after['metrics'][key]
    return {'before': a, 'after': b,
            'mean_change_percent': (b['mean'] / a['mean'] - 1) * 100 if a['mean'] else None,
            'p95_change_percent': (b['p95'] / a['p95'] - 1) * 100 if a['p95'] else None}


result = {
    'recorded_at': datetime.now(timezone.utc).isoformat(),
    'scope': 'Windows native Runtime with actual main, Box2D, NanoVG and post effects; natural GC; no Computer Use',
    'baseline_revision': '0e2266e80a593cad0a4c93bc5a1e025f105df7be',
    'method': 'Same assets, fixed seed/input, 30 warmup frames then 300 measured frames per run. '
        'Clock intervals are independently calibrated against Runtime log timestamps. '
        'The fixed validation TimeStep is simulation input, not measured FPS.',
    'limitations': [
        'The fields ending in cpu_ms use os.clock interval timing in this Windows Runtime; they are not independent CPU counters.',
        'Natural GC Lua heap includes retained pools and native-wrapper bookkeeping; heap deltas are not total allocated bytes or measured GC pause duration.',
        'Windows desktop results do not establish browser or phone performance.',
        'Raw Runtime result/error reports are preserved even when business assertions pass.',
    ],
    'pairs': [],
}
for pair in args.pair:
    label, dirs = pair.split('=', 1)
    baseline, candidate = dirs.split(',', 1)
    a, b = read(baseline, 'summary.json'), read(candidate, 'summary.json')
    am, bm = read(baseline, 'metrics.json'), read(candidate, 'metrics.json')
    quality = {'baseline': checks(a, read(baseline, 'command.json')),
               'candidate': checks(b, read(candidate, 'command.json'))}
    workload = {
        'same_initial_count': a['count'] == b['count'],
        'same_body_count_each_frame': [s['bodies'] for s in am['samples']]
            == [s['bodies'] for s in bm['samples']],
        'same_fixed_step_each_frame': [s['dt_ms'] for s in am['samples']]
            == [s['dt_ms'] for s in bm['samples']],
        'same_solver': a['metadata']['worldSettings'] == b['metadata']['worldSettings'],
    }
    metrics = {key: metric(a, b, key) for key in
               ['wall_interval_ms', 'handle_update_cpu_ms', 'simulation_cpu_ms',
                'physics_cpu_ms', 'heap_kb', 'heap_drop_kb', 'particles', 'coins', 'backlog_ms']}
    row = {'label': label, 'baseline': baseline, 'candidate': candidate,
           'quality_checks': quality, 'workload_checks': workload, 'metrics': metrics,
           'raw_runtime': {name: {'result': summary['result'], 'errors': summary['runtime_errors'],
                                'missing_resources': summary['missing_resources']}
                           for name, summary in [('baseline', a), ('candidate', b)]},
           'frames_over_33_33_ms': {name: sum(s['wall_interval_ms'] > 1000/30 for s in data['samples'])
                                     for name, data in [('baseline', am), ('candidate', bm)]},
           'frames_over_50_ms': {name: sum(s['wall_interval_ms'] > 50 for s in data['samples'])
                               for name, data in [('baseline', am), ('candidate', bm)]}}
    row['comparable'] = all(all(group.values()) for group in quality.values()) and all(workload.values())
    result['pairs'].append(row)
    print(json.dumps({'label': label, 'comparable': row['comparable'],
        'frame_p95_ms': [a['metrics']['wall_interval_ms']['p95'], b['metrics']['wall_interval_ms']['p95']],
        'update_mean_ms': [a['metrics']['handle_update_cpu_ms']['mean'], b['metrics']['handle_update_cpu_ms']['mean']],
        'heap_peak_kb': [a['metrics']['heap_kb']['max'], b['metrics']['heap_kb']['max']],
        'particles_peak': [a['metrics']['particles']['max'], b['metrics']['particles']['max']],
        'coins_peak': [a['metrics']['coins']['max'], b['metrics']['coins']['max']]}, ensure_ascii=False))

result['all_comparable'] = all(row['comparable'] for row in result['pairs'])
destination = (RESULTS_ROOT / args.output).resolve()
assert destination.is_relative_to(RESULTS_ROOT)
destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Report:', destination)
assert result['all_comparable'], 'Read quality/workload checks before interpreting changes'
