import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createGameBridge } from '../game-bridge.mjs';

const local = resolve(dirname(fileURLToPath(import.meta.url)), '../.local');
await mkdir(local, { recursive: true });
const projectDir = await mkdtemp(join(local, 'game-bridge-test-'));
const bridge = await createGameBridge({ projectDir,
  settings: { gain: 4, invertX: false, invertY: false, revision: 0 } });
const file = resolve(projectDir, 'dev/sensor-lab/.local/game-bridge/shakehero-sensor-bridge.json');
const read = async () => JSON.parse(await readFile(file, 'utf8'));
async function until(predicate) {
  const deadline = Date.now() + 1500;
  while (Date.now() < deadline) {
    const value = await read();
    if (predicate(value)) return value;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  throw new Error('Bridge heartbeat did not update');
}
let assertions = 0;
function check(value, message) { assertions++; assert.ok(value, message); }
try {
  const initial = await read();
  check(initial.format === 'shakehero-sensor-bridge/v1' && initial.samples.length === 0, 'initial frame is safe and empty');
  const config = JSON.parse(await readFile(resolve(projectDir, 'assets/SensorLab/connection.json'), 'utf8'));
  check(config.directory.endsWith('/dev/sensor-lab/.local/game-bridge'), 'config points to this project development directory');
  for (let i = 1; i <= 140; i++) bridge.sample({ seq: i, sampleId: i, deviceId: 'fixture',
    screenAngle: 0, ax: .2, ay: -.1, dt: 1 / 60, token: 'must-never-enter-game' });
  bridge.settings({ gain: 8, invertX: true, invertY: false, revision: 2 });
  const frame = await until(value => value.samples.length === 128);
  check(frame.samples[0].seq === 13 && frame.samples.at(-1).seq === 140, 'bounded ring preserves ordered recent inputs');
  check(frame.settings.gain === 8 && frame.settings.revision === 2, 'experiment coefficients reach the game frame');
  check(frame.generation > initial.generation && frame.sampleAgeMs >= 0, 'heartbeat and age distinguish stale input');
  check(!JSON.stringify(frame).includes('must-never-enter-game'), 'no pairing or HTTP credentials in the input frame');
  bridge.reset();
  const reset = await until(value => value.resetRevision === 1);
  check(reset.samples.length === 0 && reset.sampleAgeMs === null, 'calibration removes old phone inputs');
  await bridge.close();
  check((await read()).stopped === true, 'stopping service explicitly releases the game input');
  console.log(JSON.stringify({ passed: true, assertions }));
} finally {
  await bridge.close();
  if (dirname(resolve(projectDir)) !== local) throw new Error('Refusing cleanup outside the test directory');
  await rm(projectDir, { recursive: true, force: true });
}
