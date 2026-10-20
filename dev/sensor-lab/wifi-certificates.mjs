import { spawn } from 'node:child_process';
import { X509Certificate, createPrivateKey, randomBytes } from 'node:crypto';
import { chmod, mkdir, mkdtemp, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { isIP } from 'node:net';
import { basename, dirname, join, resolve } from 'node:path';

const DAY = 86400000;
const NAME_PREFIX = 'ShakeHero Sensor Lab WiFi';
const queues = new Map();
let opensslPromise;

function run(command, args, timeout = 30000) {
  return new Promise((resolveRun, reject) => {
    const child = spawn(command, args, { shell: false, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '', stderr = '', timedOut = false;
    const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeout);
    child.stdout.on('data', data => { stdout = (stdout + data).slice(-8192); });
    child.stderr.on('data', data => { stderr = (stderr + data).slice(-8192); });
    child.once('error', error => { clearTimeout(timer); reject(error); });
    child.once('close', code => {
      clearTimeout(timer);
      if (code === 0 && !timedOut) resolveRun(stdout);
      else reject(new Error(timedOut ? 'OpenSSL timed out' : `OpenSSL ${args[0]} failed (${code}): ${stderr.trim().slice(-1800)}`));
    });
  });
}

function findOpenSSL() {
  if (!opensslPromise) opensslPromise = (async () => {
    const candidates = process.platform === 'win32'
      ? [join(process.env.ProgramFiles || 'C:\\Program Files', 'Git', 'mingw64', 'bin', 'openssl.exe'), 'openssl']
      : ['openssl'];
    for (const command of candidates) {
      try {
        if (/^(OpenSSL|LibreSSL) /m.test(await run(command, ['version'], 10000))) return command;
      } catch { /* Try only an already installed executable; never install or alter PATH. */ }
    }
    throw new Error('OpenSSL is unavailable. Install it separately or add an existing OpenSSL executable to PATH; certificate trust has not been changed.');
  })();
  return opensslPromise;
}

function localAddresses(addresses) {
  if (!Array.isArray(addresses)) throw new TypeError('addresses must be an array of local IPv4 strings');
  const unique = new Set(['127.0.0.1']);
  for (const address of addresses) {
    if (typeof address !== 'string' || isIP(address) !== 4) throw new TypeError('Each address must be an IPv4 literal');
    const [a, b] = address.split('.').map(Number);
    if (!(a === 10 || a === 127 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168))) {
      throw new TypeError('Wi-Fi certificates cover only RFC1918 or loopback IPv4 addresses');
    }
    unique.add(address);
  }
  return [...unique].sort();
}

async function optionalFile(path) {
  try { return await readFile(path); } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}

async function atomicFile(path, content, mode) {
  const temporary = `${path}.${randomBytes(8).toString('hex')}.tmp`;
  try {
    await writeFile(temporary, content, { flag: 'wx', mode });
    await chmod(temporary, mode);
    await rename(temporary, path);
  } finally { await rm(temporary, { force: true }); }
}

function parseCertificate(pem, key) {
  try {
    const cert = new X509Certificate(pem);
    if (!cert.checkPrivateKey(createPrivateKey(key))) return null;
    return cert;
  } catch { return null; }
}

function rootConfiguration(name) {
  return `[req]
prompt = no
distinguished_name = subject
x509_extensions = ca_ext
[subject]
CN = ${name}
O = ShakeHero local development
[ca_ext]
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
nameConstraints = critical, @permitted_names
[permitted_names]
permitted;DNS.1 = localhost
permitted;IP.1 = 10.0.0.0/255.0.0.0
permitted;IP.2 = 172.16.0.0/255.240.0.0
permitted;IP.3 = 192.168.0.0/255.255.0.0
permitted;IP.4 = 127.0.0.0/255.0.0.0
`;
}

function leafConfiguration(addresses) {
  return `[req]
prompt = no
distinguished_name = subject
[subject]
CN = ${NAME_PREFIX}
O = ShakeHero local development
[server_ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid, issuer
subjectAltName = @subject_alt_names
[subject_alt_names]
DNS.1 = localhost
${addresses.map((address, i) => `IP.${i + 1} = ${address}`).join('\n')}
`;
}

function reusableLeaf(cert, root, addresses) {
  if (!cert || cert.ca || Date.parse(cert.validTo) <= Date.now() + DAY
    || Date.parse(cert.validFrom) > Date.now() || !cert.checkIssued(root) || !cert.verify(root.publicKey)) return false;
  const names = cert.subjectAltName?.split(', ').sort();
  const expected = ['DNS:localhost', ...addresses.map(address => `IP Address:${address}`)].sort();
  return JSON.stringify(names) === JSON.stringify(expected);
}

async function prepare(directory, addresses) {
  const openssl = await findOpenSSL();
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await chmod(directory, 0o700);
  const paths = { key: join(directory, 'server-key.pem'), cert: join(directory, 'server.pem'),
    caDer: join(directory, 'ca.cer'), caPem: join(directory, 'ca.pem') };
  const rootKeyPath = join(directory, 'ca-key.pem');
  let [caKey, caPem, key, cert] = await Promise.all([
    optionalFile(rootKeyPath), optionalFile(paths.caPem), optionalFile(paths.key), optionalFile(paths.cert),
  ]);
  if (Boolean(caKey) !== Boolean(caPem)) {
    throw new Error('The local Wi-Fi CA is incomplete. Restore its ca-key.pem/ca.pem pair before retrying; no certificate trust was changed.');
  }
  let root = caPem && parseCertificate(caPem, caKey);
  if (caPem && (!root || !root.ca || root.subject !== root.issuer || !root.verify(root.publicKey))) {
    throw new Error('The saved Wi-Fi CA is invalid or its key does not match. No certificate trust was changed.');
  }
  if (root && Date.parse(root.validFrom) > Date.now()) throw new Error('The saved Wi-Fi CA is not valid yet; check the computer clock.');
  const work = await mkdtemp(join(directory, '.pending-'));
  try {
    if (!root || Date.parse(root.validTo) <= Date.now() + 32 * DAY) {
      const name = `${NAME_PREFIX} ${randomBytes(4).toString('hex').toUpperCase()}`;
      const config = join(work, 'ca.cnf'), newKey = join(work, 'ca-key.pem'), newPem = join(work, 'ca.pem');
      await writeFile(config, rootConfiguration(name));
      await run(openssl, ['req', '-x509', '-newkey', 'rsa:3072', '-nodes', '-sha256', '-days', '365',
        '-set_serial', `0x${randomBytes(16).toString('hex')}`, '-config', config, '-keyout', newKey, '-out', newPem]);
      [caKey, caPem] = await Promise.all([readFile(newKey), readFile(newPem)]);
      root = new X509Certificate(caPem);
      await atomicFile(rootKeyPath, caKey, 0o600);
      await atomicFile(paths.caPem, caPem, 0o644);
    }
    await chmod(rootKeyPath, 0o600);
    const previousLeaf = key && cert && parseCertificate(cert, key);
    if (!reusableLeaf(previousLeaf, root, addresses)) {
      const config = join(work, 'server.cnf'), csr = join(work, 'server.csr');
      const pendingKey = join(work, 'server-key.pem'), pendingCert = join(work, 'server.pem');
      await writeFile(config, leafConfiguration(addresses));
      if (key) {
        try { createPrivateKey(key); } catch { throw new Error('The saved Wi-Fi server private key is invalid.'); }
        await writeFile(pendingKey, key, { mode: 0o600 });
        await run(openssl, ['req', '-new', '-sha256', '-key', pendingKey, '-out', csr, '-config', config]);
      } else {
        await run(openssl, ['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-keyout', pendingKey,
          '-out', csr, '-config', config]);
        key = await readFile(pendingKey);
      }
      await run(openssl, ['x509', '-req', '-in', csr, '-CA', paths.caPem, '-CAkey', rootKeyPath,
        '-set_serial', `0x${randomBytes(16).toString('hex')}`, '-days', '30', '-sha256',
        '-extfile', config, '-extensions', 'server_ext', '-out', pendingCert]);
      cert = await readFile(pendingCert);
      await atomicFile(paths.key, key, 0o600);
      await atomicFile(paths.cert, cert, 0o644);
    }
    await chmod(paths.key, 0o600);
    const caDer = root.raw;
    if (!(await optionalFile(paths.caDer))?.equals(caDer)) await atomicFile(paths.caDer, caDer, 0o644);
    return { key, cert, caDer, caPem, fingerprint: root.fingerprint256,
      name: root.subject.split('\n').find(part => part.startsWith('CN='))?.slice(3) || NAME_PREFIX,
      expiresAt: new Date(root.validTo).toISOString(), paths };
  } finally {
    if (dirname(resolve(work)) !== directory || !basename(work).startsWith('.pending-')) {
      throw new Error('Refusing to remove a temporary directory outside the Wi-Fi certificate directory');
    }
    await rm(work, { recursive: true, force: true });
  }
}

// Creates files only in directory. It never imports a root into any trust store.
// On Windows chmod mode bits do not replace filesystem ACLs; files inherit the directory ACL.
export function prepareWifiCertificates({ directory, addresses }) {
  if (typeof directory !== 'string' || !directory) return Promise.reject(new TypeError('directory is required'));
  let normalized;
  try { normalized = localAddresses(addresses); } catch (error) { return Promise.reject(error); }
  const absolute = resolve(directory);
  const pending = (queues.get(absolute) || Promise.resolve()).catch(() => {}).then(() => prepare(absolute, normalized));
  queues.set(absolute, pending);
  const cleanup = () => { if (queues.get(absolute) === pending) queues.delete(absolute); };
  pending.then(cleanup, cleanup);
  return pending;
}
