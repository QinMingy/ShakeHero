import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { MotionModel, screenAxes } from '../dist/model.mjs';
const path = new URL('../.local/oracle-vectors.json', import.meta.url);
const vectors = JSON.parse(await readFile(path, 'utf8'));
let checked = 0;
const decode = v => v && typeof v === 'object' && v.special ? ({ nan: NaN, infinity: Infinity, '-infinity': -Infinity })[v.special] : v;
function equal(actual, expected, context) {
  if (typeof expected === 'number') assert.ok(typeof actual === 'number' && Math.abs(actual - expected) <= 1e-10, `${context}: ${actual} != ${expected}`);
  else assert.equal(actual ?? null, expected, context);
}
for (const test of vectors.cases) {
  const model = new MotionModel();
  for (const [index, action] of test.actions.entries()) {
    const result = model[action.op](...action.args.map(decode));
    let values = result;
    if (action.op === 'sample') values = [result.dx, result.dy, result.dvx, result.dvy];
    if (action.op === 'sensor') values = [result.dx, result.dy];
    if (action.op === 'step') values = [result.dvx, result.dvy];
    const label = `${test.name}[${index}].${action.op}`;
    if (Array.isArray(action.returns)) action.returns.forEach((v, i) => equal(values[i], v, `${label}.returns[${i}]`));
    else equal(values, action.returns, label + '.returns');
    for (const [key, value] of Object.entries(action.state)) equal(model.state[key], value, label + '.' + key);
    checked++;
  }
}
const axes = screenAxes(1, 0, 90); equal(axes.x, 0, 'screen x 90'); equal(axes.y, 1, 'screen y 90');
console.log(JSON.stringify({ passed: true, luaCases: vectors.cases.length, luaOperations: checked, tolerance: 1e-10 }));
