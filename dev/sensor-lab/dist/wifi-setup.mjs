const status = document.getElementById('setupStatus');
try {
  const response = await fetch('/wifi/config', { cache: 'no-store' });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const { certificate, phoneUrl } = await response.json();
  document.getElementById('setupName').textContent = certificate.name;
  document.getElementById('setupFingerprint').textContent = certificate.fingerprint;
  document.getElementById('downloadCertificate').href = certificate.downloadUrl;
  const pair = new URLSearchParams(location.hash.slice(1)).get('pair');
  if (phoneUrl && /^[a-f0-9]{48}$/.test(pair || '')) {
    const open = document.getElementById('openPhone');
    open.href = phoneUrl + '#pair=' + pair;
    open.removeAttribute('aria-disabled');
    status.textContent = '首次连接需要手动安装一次证书。请先核对电脑上显示的指纹。';
  } else {
    status.textContent = '请扫描电脑上“首次连接 / 装证书”的二维码打开本页，才能保留本次配对信息。';
  }
} catch (error) {
  status.textContent = `未能连接实验台：${error.message}。请确认电脑服务运行中、两端连接同一 Wi-Fi，然后重新扫码。`;
}
