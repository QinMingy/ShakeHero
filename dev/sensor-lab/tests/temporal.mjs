import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { MotionModel, gainConfig, screenAxes } from '../dist/model.mjs';

import { SettingsInbox } from '../dist/settings.mjs';

let now = 0;
const elements = new Map();
const element = id => {
  if (!elements.has(id)) elements.set(id, { textContent: '', innerHTML: '', value: '',
    classList: { toggle() {} }, style: { setProperty() {} } });
  return elements.get(id);
};
const context = vm.createContext({ MotionModel, gainConfig, screenAxes, SettingsInbox,
  document: { getElementById: element, querySelectorAll: () => [] },
  location: { search: '' }, URLSearchParams,
  performance: { now: () => now }, console, setTimeout, clearTimeout,
  window: {}, requestAnimationFrame() {}, Date, Number, Math,
});
let source = await readFile(new URL('../dist/app.js', import.meta.url), 'utf8');
source = source.replace(/^import .*;\r?$/gm, '');
source = source.slice(0, source.indexOf("\n// Bind controls."));
source += `
globalThis.test = {
  ingest,
  state: () => ({...model.state}),
  data: () => ({ count:sourceCount, trace, rateTimes, sourceTimeline, sourceAccumulator, sourceClockActive, recordingRows }),
  reconnect: () => {streamNeedsCalibration=true;},
  record: () => {recording=true;recordingStarted=performance.now();},
  reset: origin => {
    model.reset();model.setGain(4);mode=origin==='receiver'?'receiver':'device';
    sourceCount=0;rateTimes=[];lastSampleAt=null;lastRaw=null;trace=[];sourceDevice='';
    sourceAccumulator=0;sourceClockActive=false;sourceTimeline=0;
    lastReceiverSequence=null;lastSourceSampleId=null;lastSourceTimestamp=null;streamNeedsCalibration=false;
    recording=false;recordingRows=[];
  }
};`;
vm.runInContext(source, context);
const t = context.test;
const dt = 1 / 60;
const samples = Array.from({length: 64}, (_, i) => ({ax: i ? .7*Math.sin(i*Math.PI/8):0,
  ay: i ? .4*Math.sin(i*Math.PI/11):0, dt, timestamp: 100000+i*1000/60,
  rawX:0, rawY:0, screenAngle:0, deviceId:'fixture-phone', sampleId:i+1, seq:i+1}));
const reference = new MotionModel({gain:4});
for (const sample of samples) reference.sample(sample.ax,sample.ay,sample.dt);
function close(actual, expected, what) { assert.ok(Math.abs(actual-expected)<1e-10, `${what}: ${actual} != ${expected}`); }
function compare(expected) { for (const key of ['x','y','vx','vy','targetX','targetY','sensorBaseX','sensorBaseY','sensorX','sensorY']) close(t.state()[key],expected[key],key); }
t.reset('device');
for (const sample of samples) { now+=1000/60; t.ingest(sample,'device'); }
compare(reference.state);
t.reset('receiver');
for (let i=0;i<samples.length;i++) { if(i%32===0) now+=1000/60*32; t.ingest(samples[i],'receiver'); }
compare(reference.state);
let data=t.data();
assert.equal(data.count,64);
close(data.trace[31].t-data.trace[0].t,31/60,'source graph interval');
close((data.rateTimes.length-1)*1000/(data.rateTimes.at(-1)-data.rateTimes[0]),60,'source Hz');
t.ingest(samples.at(-1),'receiver');assert.equal(t.data().count,64,'same seq duplicate ignored');
t.ingest({...samples.at(-1),seq:65},'receiver');assert.equal(t.data().count,64,'same sampleId retry ignored');
t.record();
t.ingest({...samples.at(-1),ax:1,seq:66,sampleId:67,timestamp:101100},'receiver');
assert.equal(t.data().count,65);close(t.state().sensorX,0,'gap calibrates');close(t.state().targetX,0,'gap target');
assert.ok(t.data().trace.at(-1).breakBefore);assert.ok(t.data().recordingRows.at(-1).discontinuity);
t.ingest({...samples.at(-1),ax:1,seq:67,sampleId:68,timestamp:101117,screenAngle:90},'receiver');
close(t.state().sensorX,0,'rotation calibrates');
t.reconnect();
t.ingest({...samples[0],ax:-1,timestamp:102000},'receiver');
assert.equal(t.data().count,67,'reconnected reset sequence accepted');close(t.state().sensorX,0,'reconnect calibrates');
assert.equal(t.data().recordingRows.length,3,'records retain accepted real samples');
console.log('PASS: 64 live and 32-sample relay bursts match every model state; source trace/Hz, duplicate filtering, gap, orientation, reconnect and recording checks passed.');
