import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
const reserve = createServer();
await new Promise(r => reserve.listen(0, '127.0.0.1', r));
const port = reserve.address().port;
await new Promise(r => reserve.close(r));
const child = spawn(process.execPath, [new URL('../server.mjs', import.meta.url).pathname.replace(/^\/(\w:)/, '$1'), '--port', String(port)], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
let err = ''; child.stderr.on('data', c => err += c);
const ready = await new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('Server readiness timeout: ' + err)), 5000);
  child.stdout.once('data', () => { clearTimeout(timeout); resolve(true); });
  child.once('error', reject); child.once('exit', code => { if (code) reject(new Error('Server failed: ' + err)); });
});
const base = `http://127.0.0.1:${port}`;
const streamAbort = new AbortController();
let assertions = 0;
function check(value, message) { assertions++; assert.ok(value, message); }
try {
  check(ready, 'server starts');
  const info = await (await fetch(base + '/api/info')).json();
  check(info.settings.gain === 6 && info.settings.invertX === true && info.settings.invertY === true,
    'startup uses gain 6 with both sensor axes reversed');
  const send = (path, body, extra = {}) => fetch(base + path, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Lab-Token': info.token, ...extra }, body: JSON.stringify(body) });
  const page = await fetch(base); check(page.status === 200 && (await page.text()).includes('html'), 'real UI served');
  const model = await fetch(base + '/model.mjs'); check(model.headers.get('content-type').includes('javascript'), 'JS MIME');
  check((await send('/api/settings', { gain: 8.125 })).status === 200, 'gain accepts finite values');
  const updated = await (await fetch(base + '/api/info')).json(); check(updated.settings.gain === 8.25, 'same gain quantization as game');
  check(updated.settings.revision === info.settings.revision + 1, 'settings have monotonic server revisions');
  const concurrentSettings = await Promise.all([send('/api/settings', { gain: 4 }), send('/api/settings', { gain: 12 })]);
  const revisions = await Promise.all(concurrentSettings.map(response => response.json()));
  const newestSettings = revisions.sort((a, b) => b.revision - a.revision)[0];
  const finalSettings = (await (await fetch(base + '/api/info')).json()).settings;
  check(finalSettings.revision === newestSettings.revision && finalSettings.gain === newestSettings.gain, 'latest server revision identifies winning concurrent settings');
  check((await send('/api/settings', { gain: null })).status === 400, 'null is not a gain');
  check((await send('/api/settings', null)).status === 400, 'null payload rejected');
  check((await send('/api/settings', {}, { 'X-Lab-Token': 'wrong' })).status === 403, 'writes require lab token');
  check((await send('/api/settings', {}, { Origin: 'https://example.com' })).status === 403, 'cross-origin writes rejected');
  const response = await fetch(base + '/api/events', { signal: streamAbort.signal });
  check(response.headers.get('content-type').includes('event-stream'), 'receiver stream active');
  const reader = response.body.getReader();
  let text = new TextDecoder().decode((await reader.read()).value);
  check(text.includes('event: hello'), 'viewer receives initial state');
  const samples = [{ ax: .2, ay: -.4, az: .1, rawX: .4, rawY: .2, dt: 1 / 60, timestamp: Date.now(), deviceId: 'test-phone' },
    { ax: .8, ay: -.2, az: .1, rawX: .2, rawY: .8, dt: 1 / 60, timestamp: Date.now() + 17, deviceId: 'test-phone' }];
  const accepted = await (await send('/api/sample', { samples })).json(); check(accepted.accepted === 2, 'all phone samples in batch accepted');
  const deadline = Date.now() + 3000;
  while ((text.match(/event: sample/g) || []).length < 2 && Date.now() < deadline) text += new TextDecoder().decode((await reader.read()).value);
  check((text.match(/event: sample/g) || []).length === 2, 'PC receives both samples without dropping');
  check(text.includes('test-phone'), 'data source preserved');
  check((await send('/api/sample', { ax: null, ay: 0, dt: .016, timestamp: Date.now() })).status === 400, 'missing sensor fields are not zero readings');
  const latest = await (await fetch(base + '/api/info')).json(); check(latest.lastSample.sample.ax === .8, 'last real sample exposed');
  check(latest.lastSample.sample.rawX === .2 && latest.lastSample.sample.rawY === .8, 'unrotated raw readings preserved separately');
  check((await send('/api/sample', { ...samples[0], dt: 3600 })).status === 200, 'a paused phone can trigger model recalibration after resuming');
  const identifiedSamples = samples.map((sample, index) => ({ ...sample, sampleId: index + 1 }));
  const firstAttempt = await (await send('/api/sample', { samples: identifiedSamples })).json();
  const retried = await (await send('/api/sample', { samples: identifiedSamples })).json();
  check(firstAttempt.accepted === 2 && retried.accepted === 0 && retried.seq === firstAttempt.seq, 'retrying an acknowledged phone batch does not duplicate motion');
  const afterRetry = (await (await fetch(base + '/api/info')).json()).lastSample;
  check(afterRetry.sample.sampleId === 2, 'phone source sequence is preserved for dropout detection');
  check((await send('/api/reset', {})).status === 200, 'calibration/reset can be shared');
  check((await (await fetch(base + '/api/info')).json()).lastSample === null, 'reset clears stale sample');
  check((await fetch(base + '/..%2Fserver.mjs')).status === 403, 'static path cannot escape tool assets');
  console.log(JSON.stringify({ passed: true, assertions }));
} finally {
  streamAbort.abort(); child.kill();
}
