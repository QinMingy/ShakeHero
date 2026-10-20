import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { X509Certificate } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import https from 'node:https';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { prepareWifiCertificates } from '../wifi-certificates.mjs';

const execute = promisify(execFile);
const temporaryParent = resolve(dirname(fileURLToPath(import.meta.url)), '../.local');
await mkdir(temporaryParent, { recursive: true });
const directory = await mkdtemp(join(temporaryParent, 'shakehero-wifi-certificates-'));
const opensslCandidates = process.platform === 'win32'
  ? [join(process.env.ProgramFiles || 'C:\\Program Files', 'Git', 'mingw64', 'bin', 'openssl.exe'), 'openssl']
  : ['openssl'];
let openssl;
for (const candidate of opensslCandidates) {
  try { await execute(candidate, ['version'], { windowsHide: true }); openssl = candidate; break; } catch { /* Next installed candidate. */ }
}
assert.ok(openssl, 'OpenSSL must already be installed for the certificate tests');

async function trustSnapshot() {
  if (process.platform !== 'win32') return null;
  const keys = ['HKCU', 'HKLM'].flatMap(hive => ['Root', 'CA'].map(store =>
    `${hive}\\Software\\Microsoft\\SystemCertificates\\${store}\\Certificates`));
  return Promise.all(keys.map(async key => {
    try { return (await execute('reg.exe', ['query', key], { windowsHide: true })).stdout.trim(); }
    catch (error) { return `${error.code}:${String(error.stdout || '').trim()}:${String(error.stderr || '').trim()}`; }
  }));
}

function request(port, ca) {
  return new Promise((resolveRequest, reject) => {
    const req = https.get({ hostname: '127.0.0.1', port, ca, rejectUnauthorized: true,
      // The real handshake verifies the 127.0.0.1 SAN, not only a hostname override.
      agent: false }, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('end', () => resolveRequest(Buffer.concat(chunks).toString()));
    });
    req.setTimeout(5000, () => req.destroy(new Error('TLS test timed out')));
    req.on('error', reject);
  });
}

const beforeTrust = await trustSnapshot();
try {
  const input = { directory, addresses: ['192.168.33.4', '10.20.30.40', '172.17.1.2', '192.168.33.4'] };
  const first = await prepareWifiCertificates(input);
  const root = new X509Certificate(first.caPem), leaf = new X509Certificate(first.cert);
  assert.equal(root.ca, true);
  assert.ok(root.verify(root.publicKey));
  assert.equal(root.publicKey.asymmetricKeyDetails.modulusLength, 3072);
  assert.equal(leaf.publicKey.asymmetricKeyDetails.modulusLength, 2048);
  assert.equal(leaf.ca, false);
  assert.ok(leaf.verify(root.publicKey));
  assert.ok(leaf.checkIssued(root));
  assert.ok(leaf.keyUsage.includes('1.3.6.1.5.5.7.3.1'), 'leaf has the serverAuth EKU');
  assert.equal(leaf.checkHost('localhost'), 'localhost');
  for (const address of ['127.0.0.1', ...input.addresses]) assert.equal(leaf.checkIP(address), address);
  assert.equal(leaf.checkIP('192.168.99.99'), undefined);
  assert.ok(first.caDer.equals(root.raw));
  assert.equal(first.fingerprint, root.fingerprint256);
  assert.equal(first.expiresAt, new Date(root.validTo).toISOString());
  assert.match(first.name, /^ShakeHero Sensor Lab WiFi [A-F0-9]{8}$/);
  assert.ok(Math.abs((Date.parse(root.validTo) - Date.parse(root.validFrom)) / 86400000 - 365) < .01);
  assert.ok(Math.abs((Date.parse(leaf.validTo) - Date.parse(leaf.validFrom)) / 86400000 - 30) < .01);
  const rootDescription = (await execute(openssl, ['x509', '-in', first.paths.caPem, '-noout', '-text'])).stdout;
  assert.match(rootDescription, /CA:TRUE, pathlen:0/);
  assert.match(rootDescription, /Certificate Sign, CRL Sign/);
  assert.match(rootDescription, /X509v3 Name Constraints: critical/);
  assert.match(rootDescription, /192\.168\.0\.0\/255\.255\.0\.0/);
  for (const [field, path] of Object.entries(first.paths)) assert.ok((await readFile(path)).equals(first[field]));
  if (process.platform !== 'win32') {
    assert.equal((await stat(first.paths.key)).mode & 0o777, 0o600);
    assert.equal((await stat(join(directory, 'ca-key.pem'))).mode & 0o777, 0o600);
  }

  const [same, concurrent] = await Promise.all([prepareWifiCertificates(input), prepareWifiCertificates(input)]);
  assert.ok(same.cert.equals(first.cert), 'same addresses reuse the leaf');
  assert.ok(concurrent.cert.equals(first.cert), 'concurrent setup reuses the same leaf and CA');
  assert.ok(same.key.equals(first.key));
  assert.equal(same.fingerprint, first.fingerprint);

  const changed = await prepareWifiCertificates({ directory, addresses: ['192.168.34.5'] });
  assert.equal(changed.fingerprint, first.fingerprint, 'a changed LAN IP must not replace the trusted CA');
  assert.ok(changed.caPem.equals(first.caPem));
  assert.ok(changed.key.equals(first.key), 'address changes reuse the leaf key');
  assert.ok(!changed.cert.equals(first.cert));
  const changedLeaf = new X509Certificate(changed.cert);
  assert.equal(changedLeaf.checkIP('192.168.34.5'), '192.168.34.5');
  assert.equal(changedLeaf.checkIP('192.168.33.4'), undefined, 'removed LAN addresses disappear from the SAN');

  const server = https.createServer({ key: changed.key, cert: changed.cert }, (_req, res) => res.end('verified local TLS'));
  try {
    await new Promise((resolveListen, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolveListen); });
    assert.equal(await request(server.address().port, changed.caPem), 'verified local TLS');
    await assert.rejects(request(server.address().port), error =>
      ['UNABLE_TO_VERIFY_LEAF_SIGNATURE', 'UNABLE_TO_GET_ISSUER_CERT_LOCALLY', 'SELF_SIGNED_CERT_IN_CHAIN'].includes(error.code),
    'the same server remains untrusted without explicitly providing the test CA');
  } finally { await new Promise(resolveClose => server.close(resolveClose)); }

  // Actually sign an out-of-scope leaf to verify the CA restrictions, rather than merely reading extension text.
  const badCsr = join(directory, 'outside.csr'), badPem = join(directory, 'outside.pem'), badConfig = join(directory, 'outside.cnf');
  await writeFile(badConfig, '[outside]\nbasicConstraints=CA:false\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:example.com,IP:198.51.100.5\n');
  await execute(openssl, ['req', '-new', '-key', changed.paths.key, '-subj', '/CN=example.com', '-out', badCsr]);
  await execute(openssl, ['x509', '-req', '-in', badCsr, '-CA', changed.paths.caPem,
    '-CAkey', join(directory, 'ca-key.pem'), '-set_serial', '0x1234', '-days', '1', '-sha256',
    '-extfile', badConfig, '-extensions', 'outside', '-out', badPem]);
  await assert.rejects(execute(openssl, ['verify', '-CAfile', changed.paths.caPem, '-purpose', 'sslserver', badPem]),
    error => /permitted subtree violation/i.test(error.stderr), 'name constraints reject public DNS/IP names');

  for (const addresses of [['8.8.8.8'], ['192.168.1.2\nDNS.2=example.com'], ['::1'], ['172.32.0.1'], [null]]) {
    await assert.rejects(prepareWifiCertificates({ directory, addresses }), TypeError);
  }
  const incomplete = join(directory, 'incomplete');
  await mkdir(incomplete);
  await writeFile(join(incomplete, 'ca.pem'), first.caPem);
  await assert.rejects(prepareWifiCertificates({ directory: incomplete, addresses: [] }), /incomplete/);
  assert.deepEqual(await trustSnapshot(), beforeTrust, 'Windows user and machine Root/CA certificate stores remain unchanged');
  console.log('Wi-Fi certificate tests passed: SANs, CA/leaf reuse, constrained trust, real TLS, unchanged trust stores.');
} finally {
  if (dirname(resolve(directory)) !== temporaryParent || !basename(directory).startsWith('shakehero-wifi-certificates-')) {
    throw new Error('Refusing to remove a test directory outside the temporary directory');
  }
  await rm(directory, { recursive: true, force: true });
}
