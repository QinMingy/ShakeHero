import assert from 'node:assert/strict';
import { SettingsInbox } from '../dist/settings.mjs';

let displayed;
const inbox = new SettingsInbox(value => { displayed = value.gain; });
inbox.receive({ gain: 4, revision: 0 });
assert.equal(displayed, 4);

// Regression: PC's newer edit arrives while the phone awaits its own POST.
inbox.setPending(true);
displayed = 6.5; // Optimistic local input remains stable during typing.
inbox.receive({ gain: 6.5, revision: 1 });
inbox.receive({ gain: 12, revision: 2 });
assert.equal(displayed, 6.5);
inbox.receive({ gain: 6.5, revision: 1 }); // Delayed acknowledgement is older.
inbox.setPending(false);
assert.equal(displayed, 12);

// Multiple local edits and late network responses still converge to the server.
inbox.setPending(true);
displayed = 8;
inbox.receive({ gain: 8, revision: 4 });
inbox.receive({ gain: 20, revision: 3 });
inbox.setPending(false);
assert.equal(displayed, 8);
inbox.receive({ gain: 1, revision: 2 });
assert.equal(displayed, 8);
inbox.receive({ gain: 4, revision: 5 });
assert.equal(displayed, 4);
console.log(JSON.stringify({ passed: true, scenarios: 3 }));
