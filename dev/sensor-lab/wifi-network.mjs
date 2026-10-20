import { networkInterfaces } from 'node:os';

export function isLoopback(address = '') {
  return address === '::1' || address === '127.0.0.1' || address.startsWith('::ffff:127.');
}

export function isPrivateAddress(address = '') {
  const parts = address.replace(/^::ffff:/, '').split('.').map(Number);
  if (parts.length !== 4 || parts.some(v => !Number.isInteger(v) || v < 0 || v > 255)) return false;
  return parts[0] === 10 || (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31)
    || (parts[0] === 192 && parts[1] === 168);
}

export function wifiAddresses() {
  const result = [];
  for (const [name, addresses] of Object.entries(networkInterfaces())) {
    if (/vpn|virtual|vethernet|docker|wsl|loopback|flclash/i.test(name)) continue;
    for (const address of addresses || []) {
      if (address.family === 'IPv4' && !address.internal && isPrivateAddress(address.address)) {
        result.push({ name, address: address.address });
      }
    }
  }
  return result.sort((a, b) => Number(/wlan|wi.?fi|wireless/i.test(b.name)) - Number(/wlan|wi.?fi|wireless/i.test(a.name)));
}
