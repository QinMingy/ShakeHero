import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { X509Certificate } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rm } from 'node:fs/promises';
import http from 'node:http';
import https from 'node:https';
import { createServer } from 'node:net';
import { basename, dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isLoopback, isPrivateAddress, wifiAddresses } from '../wifi-network.mjs';
import qrcode from '../vendor/qrcode.mjs';

// Uses an explicit, per-run CA. Never disables TLS verification or installs trust.
let assertions = 0;
function check(value, message) { assertions++; assert.ok(value, message); }
for (const value of ['10.4.3.2', '172.16.0.1', '172.31.255.254', '192.168.1.1', '::ffff:192.168.1.1']) {
  check(isPrivateAddress(value), 'RFC1918 LAN address accepted');
}
for (const value of ['8.8.8.8', '172.15.1.1', '172.32.0.1', '127.0.0.1', '169.254.1.1', '192.168.1.999', '::1', 'invalid']) {
  check(!isPrivateAddress(value), 'non-private or malformed address rejected');
}
check(isLoopback('127.0.0.1') && isLoopback('::1') && isLoopback('::ffff:127.0.0.1'), 'local PC addresses recognized');
check(!isLoopback('192.168.1.1'), 'LAN address is not implicitly a PC');

const interfaces = wifiAddresses();
if (!interfaces.length) {
  console.log(JSON.stringify({ passed: true, assertions, skipped: 'No physical RFC1918 LAN interface; HTTPS phone-route integration requires one.' }));
  process.exit(0);
}
async function unusedPort() {
  const reserve = createServer();
  await new Promise((resolve, reject) => { reserve.once('error', reject); reserve.listen(0, '127.0.0.1', resolve); });
  const result = reserve.address().port;
  await new Promise(resolve => reserve.close(resolve));
  return result;
}

const here = dirname(fileURLToPath(import.meta.url));
const localRoot = resolve(here, '..', '.local');
await mkdir(localRoot, { recursive: true });
const directory = await mkdtemp(join(localRoot, 'wifi-server-test-'));
const port = await unusedPort();
let wifiPort;
do { wifiPort = await unusedPort(); } while (wifiPort === port);
let child;
const streams = [];

function request(url, { method = 'GET', data, headers = {}, ca, localAddress } = {}) {
  return new Promise((resolve, reject) => {
    const endpoint = new URL(url);
    const payload = data === undefined ? null : JSON.stringify(data);
    const client = endpoint.protocol === 'https:' ? https : http;
    const req = client.request(endpoint, { method, ca, localAddress, agent: false,
      headers: { ...(payload === null ? {} : { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }), ...headers } }, res => {
      const chunks = [];
      const authorized = res.socket.authorized;
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => {
        const buffer = Buffer.concat(chunks);
        resolve({ status: res.statusCode, headers: res.headers, buffer, text: buffer.toString('utf8'), authorized,
          json() { return JSON.parse(buffer.toString('utf8')); } });
      });
      res.on('error', reject);
    });
    req.setTimeout(10000, () => req.destroy(new Error('HTTP request timeout')));
    req.on('error', reject);
    req.end(payload);
  });
}

function stream(url, options = {}) {
  return new Promise((resolve, reject) => {
    const endpoint = new URL(url);
    const client = endpoint.protocol === 'https:' ? https : http;
    const packets = [], waiters = new Set();
    let buffer = '';
    const req = client.get(endpoint, { ...options, agent: false }, res => {
      if (res.statusCode !== 200) { res.resume(); reject(new Error(`SSE HTTP ${res.statusCode}`)); return; }
      check(String(res.headers['content-type']).includes('text/event-stream'), 'SSE content type');
      const reader = {
        waitFor(name, predicate = () => true) {
          const found = packets.find(packet => packet.name === name && predicate(packet.data));
          if (found) return Promise.resolve(found.data);
          return new Promise((accept, fail) => {
            const waiter = { name, predicate, accept, fail, timer: null };
            waiter.timer = setTimeout(() => { waiters.delete(waiter); fail(new Error(`Timed out waiting for SSE ${name}`)); }, 5000);
            waiters.add(waiter);
          });
        },
        close() {
          for (const waiter of waiters) { clearTimeout(waiter.timer); waiter.fail(new Error('SSE closed')); }
          waiters.clear(); req.destroy();
        },
      };
      res.on('data', chunk => {
        buffer += chunk.toString('utf8');
        let end;
        while ((end = buffer.indexOf('\n\n')) >= 0) {
          const block = buffer.slice(0, end); buffer = buffer.slice(end + 2);
          const name = block.match(/^event: (.+)$/m)?.[1];
          const raw = block.match(/^data: (.+)$/m)?.[1];
          if (!name || !raw) continue;
          const packet = { name, data: JSON.parse(raw) }; packets.push(packet);
          for (const waiter of waiters) {
            if (waiter.name === name && waiter.predicate(packet.data)) {
              clearTimeout(waiter.timer); waiters.delete(waiter); waiter.accept(packet.data);
            }
          }
        }
      });
      streams.push(reader); resolve(reader);
    });
    req.on('error', reject);
  });
}

try {
  child = spawn(process.execPath, [resolve(here, '..', 'server.mjs'), '--wifi', '--port', String(port),
    '--wifi-port', String(wifiPort), '--cert-dir', directory], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let stderr = '', stdout = '';
  child.stderr.on('data', chunk => { stderr += chunk; });
  await new Promise((accept, reject) => {
    const timer = setTimeout(() => reject(new Error('Wi-Fi server readiness timeout: ' + stderr)), 40000);
    const failed = error => { clearTimeout(timer); reject(error); };
    child.once('error', failed);
    child.once('exit', code => failed(new Error(`Wi-Fi server exited (${code}): ${stderr}`)));
    child.stdout.on('data', chunk => {
      stdout += chunk;
      if (stdout.split('\n').some(line => { try { return JSON.parse(line).ready; } catch { return false; } })) {
        clearTimeout(timer); accept();
      }
    });
  });
  check(true, 'HTTP PC and HTTPS LAN listeners start');
  const pc = `http://127.0.0.1:${port}`;
  const pcInfoResponse = await request(pc + '/api/info');
  const info = pcInfoResponse.json();
  check(pcInfoResponse.status === 200 && info.wifi.enabled, 'loopback HTTP PC obtains Wi-Fi pairing metadata');
  check(info.wifi.httpsPort === wifiPort && info.wifi.addresses.length > 0, 'actual HTTPS port and available interfaces exposed');
  const address = info.wifi.addresses[0];
  const lanHttp = `http://${address.address}:${port}`;
  const lanHttps = `https://${address.address}:${wifiPort}`;
  const phoneUrl = new URL(address.phoneUrl), setupUrl = new URL(address.setupUrl);
  const pair = new URLSearchParams(phoneUrl.hash.slice(1)).get('pair');
  check(phoneUrl.hostname === address.address && phoneUrl.port === String(wifiPort) && phoneUrl.protocol === 'https:', 'phone URL uses allowlisted local HTTPS');
  check(typeof pair === 'string' && /^[a-f0-9]{48}$/.test(pair), 'pairing secret carried in URL fragment');
  check(new URLSearchParams(setupUrl.hash.slice(1)).get('pair') === pair, 'setup and phone QR codes share the per-run pairing secret');
  const ca = await readFile(join(directory, 'ca.pem'));
  const rootCertificate = new X509Certificate(ca);
  const caKey = await readFile(join(directory, 'ca-key.pem'), 'utf8');
  const serverKey = await readFile(join(directory, 'server-key.pem'), 'utf8');
  const phone = (path, options = {}) => request(lanHttps + path, { ca, localAddress: address.address, ...options });
  const bootstrap = (path, options = {}) => request(lanHttp + path, { localAddress: address.address, ...options });
  const noSecret = response => !response.text.includes(pair) && !response.text.includes(info.token)
    && !response.text.includes('PRIVATE KEY') && !response.text.includes(caKey) && !response.text.includes(serverKey);

  for (const path of ['/', '/app.js', '/model.mjs']) {
    const result = await bootstrap(path);
    check(result.status === 302 && result.headers.location === '/wifi/setup', 'LAN HTTP sensor application redirects to bootstrap');
  }
  for (const path of ['/api/info', '/api/events', '/api/wifi/qr?address=' + address.address]) {
    const result = await bootstrap(path);
    check(result.status === 403 && noSecret(result), 'LAN HTTP APIs cannot bypass pairing or transport security');
  }
  for (const path of ['/wifi/setup', '/wifi-setup.mjs', '/wifi-setup.css', '/style.css', '/wifi/config']) {
    const result = await bootstrap(path);
    check(result.status === 200 && noSecret(result), 'LAN HTTP bootstrap exposes no pairing/token/private key');
  }
  const downloaded = await bootstrap('/wifi/certificate.cer');
  check(downloaded.status === 200 && downloaded.buffer.equals(rootCertificate.raw), 'LAN HTTP certificate download is exactly the public CA DER');
  check(new X509Certificate(downloaded.buffer).ca, 'downloaded certificate is a CA');
  check(info.wifi.certificate.fingerprint === rootCertificate.fingerprint256, 'PC fingerprint matches downloadable public CA');
  check((await bootstrap('/api/pair', { method: 'POST', data: { pair } })).status === 403, 'pairing refuses plaintext HTTP');
  check((await bootstrap('/api/settings', { method: 'POST', data: { gain: 20 }, headers: { 'X-Lab-Token': info.token } })).status === 403, 'known PC token cannot permit plaintext LAN writes');

  for (const path of ['/api/info', '/api/events', '/api/wifi/qr?address=' + address.address]) {
    const result = await phone(path);
    check(result.status === 403 && result.authorized && noSecret(result), 'verified HTTPS still requires pairing before API access');
  }
  const sample = { ax: .7, ay: -.3, az: .1, rawX: .7, rawY: -.3, dt: 1 / 60,
    timestamp: Date.now(), deviceId: 'wifi-regression-phone', sampleId: 1, screenAngle: 0 };
  check((await phone('/api/sample', { method: 'POST', data: sample, headers: { 'X-Lab-Token': info.token } })).status === 403, 'unpaired phone cannot submit data even with token');
  check((await phone('/api/pair', { method: 'POST', data: { pair: 'invalid' } })).status === 403, 'wrong pairing secret denied');
  check((await phone('/api/pair', { method: 'POST', data: { pair }, headers: { Origin: 'https://example.invalid' } })).status === 403, 'cross-origin pairing denied');
  const pairing = await phone('/api/pair', { method: 'POST', data: { pair } });
  const cookieHeader = pairing.headers['set-cookie']?.[0] || '';
  check(pairing.status === 200 && pairing.json().ok, 'fragment pairing secret establishes HTTPS session');
  check(/; Secure/i.test(cookieHeader) && /; HttpOnly/i.test(cookieHeader) && /; SameSite=Strict/i.test(cookieHeader), 'pairing cookie is Secure HttpOnly SameSite Strict');
  const cookie = cookieHeader.split(';')[0];
  const paired = (path, options = {}) => phone(path, { ...options, headers: { Cookie: cookie, ...options.headers } });
  const pairedInfoResponse = await paired('/api/info');
  const pairedInfo = pairedInfoResponse.json();
  check(pairedInfoResponse.status === 200 && pairedInfoResponse.authorized && pairedInfo.secure, 'paired phone uses a verified HTTPS connection');
  check(pairedInfo.token === info.token && pairedInfo.settings.revision === info.settings.revision, 'PC and paired HTTPS phone share service state');
  check((await phone('/api/info', { headers: { Cookie: 'shakehero_pair=wrong' } })).status === 403, 'forged pairing cookie denied');
  check((await bootstrap('/api/info', { headers: { Cookie: cookie } })).status === 403, 'pairing cookie cannot downgrade API transport to HTTP');

  const pcEvents = await stream(pc + '/api/events');
  const phoneEvents = await stream(lanHttps + '/api/events', { ca, localAddress: address.address, headers: { Cookie: cookie } });
  check((await pcEvents.waitFor('hello')).settings.revision === info.settings.revision, 'PC SSE starts from current shared settings');
  check((await phoneEvents.waitFor('hello')).settings.revision === info.settings.revision, 'paired HTTPS SSE starts from same settings');
  const changedResponse = await paired('/api/settings', { method: 'POST', data: { gain: 8.125 }, headers: { 'X-Lab-Token': info.token, Origin: lanHttps } });
  const changed = changedResponse.json();
  check(changedResponse.status === 200 && changed.gain === 8.25, 'paired HTTPS settings use game gain quantization');
  check((await pcEvents.waitFor('settings', value => value.revision === changed.revision)).gain === 8.25, 'phone HTTPS settings reach local HTTP PC SSE');
  const pcChanged = (await request(pc + '/api/settings', { method: 'POST', data: { gain: 12 }, headers: { 'X-Lab-Token': info.token } })).json();
  check((await phoneEvents.waitFor('settings', value => value.revision === pcChanged.revision)).gain === 12, 'local HTTP PC settings reach paired HTTPS SSE');
  check((await paired('/api/info')).json().settings.gain === 12, 'phone HTTP snapshot sees final shared settings');
  const accepted = (await paired('/api/sample', { method: 'POST', data: sample, headers: { 'X-Lab-Token': info.token } })).json();
  check(accepted.accepted === 1 && accepted.seq === 1, 'paired phone sample is accepted once');
  const received = await pcEvents.waitFor('sample', value => value.sample.deviceId === sample.deviceId);
  check(received.sample.ax === sample.ax && received.sample.sampleId === 1 && received.sample.seq === 1, 'real HTTPS phone sample reaches local HTTP PC without losing source identity');
  check((await request(pc + '/api/info')).json().lastSample.sample.deviceId === sample.deviceId, 'PC snapshot contains HTTPS phone sample');
  check((await paired('/api/sample', { method: 'POST', data: sample, headers: { 'X-Lab-Token': info.token } })).json().accepted === 0, 'paired phone batch retry does not duplicate motion');
  check((await paired('/api/settings', { method: 'POST', data: { gain: 20 } })).status === 403, 'paired writes also require local lab token');
  check((await paired('/api/settings', { method: 'POST', data: { gain: 20 }, headers: { 'X-Lab-Token': info.token, Origin: 'https://example.invalid' } })).status === 403, 'paired writes reject a foreign origin');
  check((await request(pc + '/api/reset', { method: 'POST', data: {}, headers: { 'X-Lab-Token': info.token } })).status === 200, 'PC can reset shared capture');
  check(typeof (await phoneEvents.waitFor('reset')).timestamp === 'number', 'PC reset reaches HTTPS phone SSE');

  for (const step of ['phone', 'setup']) {
    const code = qrcode(0, 'M'); code.addData(step === 'setup' ? address.setupUrl : address.phoneUrl); code.make();
    const expected = code.createSvgTag({ cellSize: 6, margin: 24, scalable: true });
    const result = await request(pc + `/api/wifi/qr?address=${address.address}&step=${step}&url=https%3A%2F%2Fexample.invalid`);
    check(result.status === 200 && String(result.headers['content-type']).includes('image/svg+xml'), 'allowlisted pairing QR is an SVG');
    check(result.text === expected, 'QR encodes exactly the allowlisted local URL, ignoring arbitrary URL parameter');
  }
  for (const invalid of ['8.8.8.8', 'example.invalid', address.address + '@example.invalid', '127.0.0.1']) {
    check((await request(pc + '/api/wifi/qr?address=' + encodeURIComponent(invalid))).status === 400, 'QR refuses non-allowlisted destinations');
  }
  for (const path of ['/server-key.pem', '/ca-key.pem', '/.local/' + basename(directory) + '/server-key.pem', '/..%2F.local%2F' + basename(directory) + '%2Fca-key.pem']) {
    const result = await paired(path);
    check([403, 404].includes(result.status) && noSecret(result), 'HTTPS static routes cannot expose a private key');
  }
  check((await request(pc + '/api/info', { headers: { Host: `example.invalid:${port}` } })).status === 403, 'unrecognized Host is rejected');
  console.log(JSON.stringify({ passed: true, assertions, lanInterface: address.name,
    coverage: 'CA-verified LAN HTTPS pairing, HTTP bootstrap isolation, shared settings/SSE, source samples, allowlisted QR and private-key isolation' }));
} finally {
  for (const connection of streams) connection.close();
  if (child && child.exitCode === null) {
    const exited = new Promise(resolve => child.once('exit', resolve));
    child.kill();
    await Promise.race([exited, new Promise(resolve => setTimeout(resolve, 3000))]);
  }
  const cleanupTarget = resolve(directory);
  if (!cleanupTarget.startsWith(localRoot + sep) || !basename(cleanupTarget).startsWith('wifi-server-test-')) {
    throw new Error('Refusing cleanup outside the dedicated test certificate directory');
  }
  await rm(cleanupTarget, { recursive: true, force: true });
}
