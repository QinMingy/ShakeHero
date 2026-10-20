import { randomUUID } from 'node:crypto';
import { mkdir, rename, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

// Local development transport: the Maker client cannot issue arbitrary HTTP.
// Only sanitized sensor values enter this file; no pairing/session credentials.
export async function createGameBridge({ projectDir, settings }) {
  const directory = resolve(projectDir, 'dev/sensor-lab/.local/game-bridge');
  const resourceDirectory = resolve(projectDir, 'assets/SensorLab');
  const file = resolve(directory, 'shakehero-sensor-bridge.json');
  await Promise.all([mkdir(directory, { recursive: true }), mkdir(resourceDirectory, { recursive: true })]);
  await writeFile(resolve(resourceDirectory, 'connection.json'), JSON.stringify({
    format: 'shakehero-sensor-connection/v1', directory: directory.replaceAll('\\', '/'),
  }) + '\n');
  const sessionId = randomUUID();
  let samples = [], currentSettings = { ...settings }, generation = 0, resetRevision = 0;
  let lastSampleAt = null, stopped = false, writing = null, lastError = '';
  async function flush() {
    if (writing) return writing;
    writing = (async () => {
      const temporary = file + '.tmp';
      try {
        const payload = { format: 'shakehero-sensor-bridge/v1', sessionId, generation: ++generation,
          resetRevision, stopped, sampleAgeMs: lastSampleAt === null ? null : Date.now() - lastSampleAt,
          settings: currentSettings, samples };
        await writeFile(temporary, JSON.stringify(payload) + '\n');
        await rename(temporary, file);
        lastError = '';
      } catch (error) {
        lastError = error.message;
        await rm(temporary, { force: true }).catch(() => {});
      }
    })().finally(() => { writing = null; });
    return writing;
  }
  await flush();
  if (lastError) throw new Error('Cannot prepare ShakeHero input bridge: ' + lastError);
  const timer = setInterval(flush, 33);
  timer.unref();
  return {
    sample(value) {
      const { seq, sampleId, deviceId, screenAngle, ax, ay, dt } = value;
      samples.push({ seq, sampleId, deviceId, screenAngle, ax, ay, dt });
      if (samples.length > 128) samples = samples.slice(-128);
      lastSampleAt = Date.now();
    },
    settings(value) { currentSettings = { ...value }; },
    reset() { samples = []; lastSampleAt = null; resetRevision++; },
    status() { return { enabled: true, ready: !lastError && !stopped,
      message: lastError || '游戏输入桥已就绪，等待 ShakeHero 读取', bufferedSamples: samples.length }; },
    async close() {
      clearInterval(timer);
      if (writing) await writing;
      stopped = true; samples = []; lastSampleAt = null;
      await flush();
    },
  };
}
