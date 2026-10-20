import http from 'node:http';
import https from 'node:https';
import { readFile, stat } from 'node:fs/promises';
import { networkInterfaces } from 'node:os';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { dirname, resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { spawn } from 'node:child_process';
import { normalizeGain, gainConfig } from './dist/model.mjs';
import qrcode from './vendor/qrcode.mjs';
import { isLoopback, isPrivateAddress, wifiAddresses } from './wifi-network.mjs';
import { createGameBridge } from './game-bridge.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, 'dist');
const { values } = parseArgs({ options: { port: { type: 'string', default: '8787' },
  host: { type: 'string', default: '127.0.0.1' }, lan: { type: 'boolean', default: false },
  open: { type: 'boolean', default: false }, 'tls-cert': { type: 'string' }, 'tls-key': { type: 'string' },
  wifi: { type: 'boolean', default: false }, 'wifi-port': { type: 'string', default: '8788' },
  game: { type: 'boolean', default: false },
  'cert-dir': { type: 'string' } } });
const port = Number(values.port);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('port must be 1..65535');
const host = values.lan || values.wifi ? '0.0.0.0' : values.host;
const secure = Boolean(values['tls-cert'] && values['tls-key']);
if (Boolean(values['tls-cert']) !== Boolean(values['tls-key'])) throw new Error('Provide both --tls-cert and --tls-key');
if (values.wifi && secure) throw new Error('Use --wifi or a custom --tls-cert/--tls-key, not both');
const wifiPort = Number(values['wifi-port']);
if (values.wifi && (!Number.isInteger(wifiPort) || wifiPort < 1 || wifiPort > 65535 || wifiPort === port)) throw new Error('wifi-port must be 1..65535 and different from port');
const protocol = secure ? 'https' : 'http';
const token = randomBytes(24).toString('hex');
const pairingCode = randomBytes(24).toString('hex');
const clients = new Set();
let settings = { gain: gainConfig.default, invertX: gainConfig.invertX, invertY: gainConfig.invertY, revision: 0 };
const gameBridge = values.game ? await createGameBridge({ projectDir: resolve(here, '../..'), settings }) : null;
let lastSample = null, sequence = 0;
const deviceSequences = new Map();
const ipv4s = Object.values(networkInterfaces()).flat().filter(n => n && n.family === 'IPv4' && !n.internal).map(n => n.address);
const wifiInterfaces = values.wifi ? wifiAddresses() : [];
const certificates = values.wifi ? await (await import('./wifi-certificates.mjs')).prepareWifiCertificates({
  directory: resolve(values['cert-dir'] || resolve(here, '.local', 'wifi')),
  addresses: wifiInterfaces.map(item => item.address),
}) : null;
const wifi = { enabled: Boolean(values.wifi), httpsPort: values.wifi ? wifiPort : null,
  addresses: wifiInterfaces.map(({ name, address }) => ({ name, address,
    setupUrl: `http://${address}:${port}/wifi/setup#pair=${pairingCode}`,
    phoneUrl: `https://${address}:${wifiPort}/?mode=phone#pair=${pairingCode}`,
  })),
  certificate: certificates ? { downloadUrl: '/wifi/certificate.cer', fingerprint: certificates.fingerprint,
    name: certificates.name, expiresAt: certificates.expiresAt } : null,
};
const allowedHostnames = ['localhost', '127.0.0.1', '[::1]', ...ipv4s];
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };
function json(res, status, data) { res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(data)); }
function event(res, name, data) { if (res.writableLength < 256000) res.write(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`); }
function broadcast(name, data) { for (const res of clients) event(res, name, data); }
function sameToken(input, secret = token) {
  if (typeof input !== 'string') return false;
  const incoming = Buffer.from(input), expected = Buffer.from(secret);
  return incoming.length === expected.length && timingSafeEqual(incoming, expected);
}
async function body(req) {
  if (!String(req.headers['content-type']).startsWith('application/json')) throw Object.assign(new Error('Expected application/json'), { status: 415 });
  let size = 0; const chunks = [];
  for await (const chunk of req) { size += chunk.length; if (size > 65536) throw Object.assign(new Error('Body exceeds 64 KiB'), { status: 413 }); chunks.push(chunk); }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw Object.assign(new Error('Invalid JSON'), { status: 400 }); }
}
function cleanSample(v) {
  if (!v || !['ax', 'ay', 'dt', 'timestamp'].every(k => typeof v[k] === 'number' && Number.isFinite(v[k]))
    || v.dt <= 0 || v.dt > 86400 || Math.abs(v.ax) > 100 || Math.abs(v.ay) > 100) throw Object.assign(new Error('Invalid finite sample'), { status: 400 });
  const gyro = v.rotationRate;
  const numberOrNull = x => typeof x === 'number' && Number.isFinite(x) ? x : null;
  return { ax: v.ax, ay: v.ay, az: numberOrNull(v.az), dt: v.dt, timestamp: v.timestamp,
    rawX: numberOrNull(v.rawX), rawY: numberOrNull(v.rawY), rawZ: numberOrNull(v.rawZ),
    rotationRate: gyro ? { alpha: numberOrNull(gyro.alpha), beta: numberOrNull(gyro.beta), gamma: numberOrNull(gyro.gamma) } : null,
    screenAngle: numberOrNull(v.screenAngle) ?? 0, source: 'phone', deviceId: String(v.deviceId || 'phone').slice(0, 80),
    sampleId: Number.isSafeInteger(v.sampleId) && v.sampleId > 0 ? v.sampleId : null };
}
async function handle(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Permissions-Policy', 'accelerometer=(self), gyroscope=(self), magnetometer=(self)');
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' blob: data:; frame-ancestors 'self'");
  const requestProtocol = req.socket.encrypted ? 'https' : 'http';
  const requestPort = req.socket.localPort;
  const loopback = isLoopback(req.socket.remoteAddress);
  if (!allowedHostnames.some(h => `${h}:${requestPort}` === req.headers.host)) return json(res, 403, { error: 'Unrecognized Host header' });
  if (values.wifi && !loopback && !isPrivateAddress(req.socket.remoteAddress)) return json(res, 403, { error: 'Wi-Fi mode accepts private LAN addresses only' });
  const url = new URL(req.url, `${requestProtocol}://${req.headers.host}`);
  if (values.wifi && req.method === 'GET' && url.pathname === '/wifi/certificate.cer') {
    res.writeHead(200, { 'Content-Type': 'application/pkix-cert',
      'Content-Disposition': 'attachment; filename="ShakeHero-Sensor-Lab-CA.cer"' });
    return res.end(certificates.caDer);
  }
  if (values.wifi && req.method === 'GET' && url.pathname === '/wifi/config') {
    const address = wifi.addresses.find(item => new URL(item.setupUrl).host === req.headers.host)?.address;
    return json(res, 200, { certificate: wifi.certificate,
      phoneUrl: address ? `https://${address}:${wifiPort}/?mode=phone` : null });
  }
  if (values.wifi && req.method === 'GET' && url.pathname === '/wifi/setup') {
    const content = await readFile(resolve(root, 'wifi-setup.html'));
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); return res.end(content);
  }
  const pairedCookie = String(req.headers.cookie || '').split(';').map(v => v.trim()).find(v => v.startsWith('shakehero_pair='))?.slice('shakehero_pair='.length);
  const paired = !values.wifi || loopback || (requestProtocol === 'https' && sameToken(pairedCookie, pairingCode));
  if (values.wifi && req.method === 'POST' && url.pathname === '/api/pair') {
    if (requestProtocol !== 'https') return json(res, 403, { error: 'Pairing requires HTTPS' });
    if (req.headers.origin && req.headers.origin !== `${requestProtocol}://${req.headers.host}`) return json(res, 403, { error: 'Cross-origin pairing is not allowed' });
    const data = await body(req);
    if (!sameToken(data?.pair, pairingCode)) return json(res, 403, { error: 'Pairing expired; scan the PC code again' });
    res.setHeader('Set-Cookie', `shakehero_pair=${pairingCode}; Path=/; Secure; HttpOnly; SameSite=Strict`);
    return json(res, 200, { ok: true });
  }
  if (!paired && url.pathname.startsWith('/api/')) return json(res, 403, { error: 'Scan the pairing QR code on the PC first' });
  if (values.wifi && !loopback && requestProtocol === 'http'
    && !['/wifi-setup.mjs', '/wifi-setup.css', '/style.css'].includes(url.pathname)) {
    if (req.method !== 'GET') return json(res, 403, { error: 'Phone sensor data requires HTTPS' });
    res.writeHead(302, { Location: '/wifi/setup' }); return res.end();
  }
  if (req.method === 'GET' && url.pathname === '/api/info') {
    return json(res, 200, { token, port, httpUrl: `${protocol}://localhost:${port}/`, secure: requestProtocol === 'https', wifi,
      lanUrls: host === '0.0.0.0' ? ipv4s.map(ip => `${protocol}://${ip}:${port}/?mode=phone`) : [],
      settings, gameBridge: gameBridge?.status() || { enabled: false },
      modelSource: 'scripts/Bottle/ShakeMotion.lua + scripts/Bottle/SensorTuning.lua', lastSample });
  }
  if (req.method === 'GET' && url.pathname === '/api/wifi/qr') {
    const address = wifi.addresses.find(item => item.address === url.searchParams.get('address'));
    if (!address) return json(res, 400, { error: 'Choose an available Wi-Fi address' });
    const target = url.searchParams.get('step') === 'setup' ? address.setupUrl : address.phoneUrl;
    const code = qrcode(0, 'M'); code.addData(target); code.make();
    res.writeHead(200, { 'Content-Type': 'image/svg+xml; charset=utf-8' });
    return res.end(code.createSvgTag({ cellSize: 6, margin: 24, scalable: true }));
  }
  if (req.method === 'GET' && url.pathname === '/api/events') {
    if (clients.size >= 16) return json(res, 429, { error: 'Too many viewers' });
    res.writeHead(200, { 'Content-Type': 'text/event-stream; charset=utf-8', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
    clients.add(res); event(res, 'hello', { settings, lastSample });
    const heartbeat = setInterval(() => res.write(': heartbeat\n\n'), 10000);
    req.on('close', () => { clearInterval(heartbeat); clients.delete(res); });
    return;
  }
  if (req.method === 'POST' && url.pathname.startsWith('/api/')) {
    const origin = req.headers.origin;
    if (origin && origin !== `${requestProtocol}://${req.headers.host}`) return json(res, 403, { error: 'Cross-origin writes are not allowed' });
    if (!sameToken(req.headers['x-lab-token'])) return json(res, 403, { error: 'Missing local lab token' });
    const data = await body(req);
    if (!data || typeof data !== 'object' || Array.isArray(data)) return json(res, 400, { error: 'Expected a JSON object' });
    if (url.pathname === '/api/settings') {
      const gain = data && 'gain' in data ? normalizeGain(data.gain) : settings.gain;
      if (gain === null || (data.invertX !== undefined && typeof data.invertX !== 'boolean')
        || (data.invertY !== undefined && typeof data.invertY !== 'boolean')) return json(res, 400, { error: 'Invalid settings' });
      settings = { gain, invertX: data.invertX ?? settings.invertX, invertY: data.invertY ?? settings.invertY,
        revision: settings.revision + 1 };
      gameBridge?.settings(settings);
      broadcast('settings', settings); return json(res, 200, settings);
    }
    if (url.pathname === '/api/sample') {
      const inputs = Array.isArray(data.samples) ? data.samples : [data];
      if (!inputs.length || inputs.length > 32) return json(res, 400, { error: 'Send 1..32 samples per batch' });
      const samples = inputs.map(cleanSample); // Validate a whole batch before broadcasting any sample.
      let accepted = 0;
      for (const sample of samples) {
        if (sample.sampleId !== null) {
          if (sample.sampleId <= (deviceSequences.get(sample.deviceId) ?? 0)) continue;
          deviceSequences.delete(sample.deviceId);
          deviceSequences.set(sample.deviceId, sample.sampleId);
          if (deviceSequences.size > 64) deviceSequences.delete(deviceSequences.keys().next().value);
        }
        sample.seq = ++sequence;
        accepted++;
        gameBridge?.sample(sample);
        lastSample = { sample, receivedAt: Date.now() }; broadcast('sample', lastSample);
      }
      return json(res, 200, { ok: true, accepted, seq: sequence });
    }
    if (url.pathname === '/api/reset') { lastSample = null; gameBridge?.reset(); broadcast('reset', { timestamp: Date.now() }); return json(res, 200, { ok: true }); }
    return json(res, 404, { error: 'Unknown endpoint' });
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') return json(res, 405, { error: 'Method not allowed' });
  const pathname = url.pathname === '/' ? '/index.html' : decodeURIComponent(url.pathname);
  const file = resolve(root, '.' + pathname);
  if (file !== root && !file.startsWith(root + sep)) return json(res, 403, { error: 'Outside static directory' });
  try {
    if (!(await stat(file)).isFile()) throw new Error('not file');
    const content = await readFile(file);
    res.writeHead(200, { 'Content-Type': mime[extname(file)] || 'application/octet-stream', 'Content-Length': content.length });
    res.end(req.method === 'HEAD' ? undefined : content);
  } catch { json(res, 404, { error: 'File not found' }); }
}
const listener = (req, res) => handle(req, res).catch(err => {
  if (!res.headersSent) json(res, err.status || 500, { error: err.status ? err.message : 'Local server error' });
  else res.end();
});
const server = secure ? https.createServer({ cert: await readFile(values['tls-cert']), key: await readFile(values['tls-key']) }, listener) : http.createServer(listener);
const wifiServer = values.wifi ? https.createServer({ cert: certificates.cert, key: certificates.key }, listener) : null;
server.requestTimeout = 15000; server.headersTimeout = 10000;
server.on('error', error => { console.error(`Cannot start sensor lab: ${error.message}`); process.exitCode = 1; });
async function listen(server, port, host) {
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, host, resolve); });
}
try {
  if (wifiServer) {
    wifiServer.requestTimeout = 15000; wifiServer.headersTimeout = 10000;
    await listen(wifiServer, wifiPort, '0.0.0.0');
  }
  await listen(server, port, host);
  const url = `${protocol}://localhost:${port}/`;
  console.log(JSON.stringify({ ready: true, url, phoneUrl: url + '?mode=phone', host, port, secure,
    wifi: { enabled: wifi.enabled, httpsPort: wifi.httpsPort, addresses: wifiInterfaces }, pid: process.pid }));
  if (values.open) {
    const openUrl = values.wifi ? url + '?mode=receiver' : url;
    const command = process.platform === 'win32' ? 'rundll32.exe' : process.platform === 'darwin' ? 'open' : 'xdg-open';
    const args = process.platform === 'win32' ? ['url.dll,FileProtocolHandler', openUrl] : [openUrl];
    const browser = spawn(command, args, { windowsHide: true, stdio: 'ignore' });
    browser.on('error', () => console.log('Open this address in your browser: ' + openUrl));
  }
} catch (error) { console.error(`Cannot start sensor lab: ${error.message}`); wifiServer?.close(); server.close(); await gameBridge?.close(); process.exitCode = 1; }
async function stop() { await gameBridge?.close(); for (const res of clients) res.end(); wifiServer?.close(); server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 2000).unref(); }
process.on('SIGINT', stop); process.on('SIGTERM', stop);
