const $ = id => document.getElementById(id);
let currentInfo = null;
let currentStep = new URLSearchParams(location.search).get('wifi') === 'setup' ? 'setup' : 'phone';
let bound = false;
let copyReset = null;

function addresses() {
  return Array.isArray(currentInfo?.wifi?.addresses) ? currentInfo.wifi.addresses : [];
}

function selectedAddress() {
  const choices = addresses();
  return choices.find(choice => choice.address === $('wifiAddress').value) || choices[0];
}

function sameOriginUrl(value) {
  if (typeof value !== 'string' || !value) return null;
  try {
    const url = new URL(value, location.href);
    return url.origin === location.origin ? url.href : null;
  } catch { return null; }
}

function setStep(step) {
  currentStep = step;
  const phone = step === 'phone';
  $('wifiPhoneStep').classList.toggle('selected', phone);
  $('wifiSetupStep').classList.toggle('selected', !phone);
  $('wifiPhoneStep').setAttribute('aria-pressed', String(phone));
  $('wifiSetupStep').setAttribute('aria-pressed', String(!phone));
  $('wifiPhoneInstructions').hidden = !phone;
  $('wifiSetupInstructions').hidden = phone;
  $('wifiFirstNote').textContent = phone
    ? '首次使用这台电脑的证书？先选“首次连接 / 装证书”，完成信任后再开始测试。'
    : '先安装并信任此实验台的公开 CA 证书。首装引导使用 HTTP；安装完成后回到 HTTPS 测试。';
  $('wifiQrTitle').textContent = phone ? 'Chrome 扫码开始测试' : '扫码打开首次连接引导';
  $('wifiQrCaption').textContent = phone ? '已信任证书的手机可直接打开' : '首装引导页不采集传感器';
  if (!phone) $('wifiCertificate').open = true;
  updateConnection();
}

function updateConnection() {
  const address = selectedAddress();
  if (!address) return;
  const url = currentStep === 'phone' ? address.phoneUrl : address.setupUrl;
  $('wifiUrl').value = typeof url === 'string' ? url : '';
  $('wifiQr').hidden = false;
  $('wifiQrError').hidden = true;
  $('wifiQr').src = `/api/wifi/qr?${new URLSearchParams({ address: address.address, step: currentStep })}`;
  $('wifiQr').alt = `${currentStep === 'phone' ? 'HTTPS 手机传感器测试' : '首次连接及证书安装引导'}二维码，电脑地址 ${address.address}`;
  $('wifiCopyStatus').textContent = '电脑与手机连接同一 Wi-Fi；手机使用 Chrome 打开。';
  $('wifiCopy').textContent = '复制链接';
}

async function copyUrl() {
  const input = $('wifiUrl');
  if (!input.value) return;
  clearTimeout(copyReset);
  try {
    if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
    await navigator.clipboard.writeText(input.value);
    $('wifiCopy').textContent = '已复制';
    $('wifiCopyStatus').textContent = '链接已复制，可发送到自己的手机或直接扫码。';
    copyReset = setTimeout(() => { $('wifiCopy').textContent = '复制链接'; }, 2200);
  } catch {
    input.focus();
    input.select();
    input.setSelectionRange(0, input.value.length);
    $('wifiCopyStatus').textContent = '地址已选中，请按 Ctrl+C 复制，再在手机 Chrome 中打开。';
  }
}

/** Connect the local Wi-Fi setup UI; it never enables physical sensors. */
export function setupWifi(info) {
  currentInfo = info || {};
  const bridge = currentInfo.gameBridge;
  const bridgeEnabled = bridge?.enabled === true;
  const bridgeReady = bridgeEnabled && bridge.ready === true;
  $('wifiGameState').textContent = !bridgeEnabled ? '输入桥未开启' : bridgeReady ? '输入桥已就绪' : '输入桥异常';
  $('wifiGameState').dataset.state = !bridgeEnabled ? 'disabled' : bridgeReady ? 'ready' : 'error';
  $('wifiGameInstructions').textContent = bridgeEnabled
    ? '保持实验台运行，再打开或重开本地 ShakeHero，切到物理二并开始回合。实验台系数会同步到游戏；GM 中的系数只在游戏本地调整。'
    : '当前未开启游戏接入。使用 start-wifi.cmd 启动实验台，再重新打开此页面。';
  $('wifiGameError').hidden = !bridgeEnabled || bridgeReady;
  const wifi = currentInfo.wifi;
  $('wifiCard').hidden = false;
  const enabled = wifi?.enabled === true && addresses().length > 0;
  $('wifiDisabled').hidden = enabled;
  $('wifiEnabled').hidden = !enabled;
  $('wifiState').textContent = enabled ? `同 Wi-Fi · HTTPS ${wifi.httpsPort}` : 'Wi-Fi 服务未开启';
  if (!enabled) return;

  const previous = $('wifiAddress').value;
  const choices = addresses();
  $('wifiAddress').replaceChildren();
  for (const address of choices) {
    const option = document.createElement('option');
    option.value = address.address;
    option.textContent = `${address.name || '网络连接'} · ${address.address}`;
    $('wifiAddress').appendChild(option);
  }
  const preferred = choices.find(address => address.address === previous)
    || choices.find(address => /wlan|wi[\s-]?fi|wireless|无线/i.test(address.name || ''))
    || choices[0];
  $('wifiAddress').value = preferred.address;

  const certificate = wifi.certificate || {};
  $('wifiFingerprint').textContent = certificate.fingerprint || '服务尚未提供证书指纹，请先检查 Wi-Fi 服务。';
  $('wifiCertificateName').textContent = certificate.name ? `证书名称：${certificate.name}` : '';
  const expires = certificate.expiresAt ? new Date(certificate.expiresAt) : null;
  $('wifiCertificateExpiry').textContent = expires && !Number.isNaN(expires.valueOf())
    ? `有效期至 ${expires.toLocaleDateString('zh-CN')}` : '';
  const download = sameOriginUrl(certificate.downloadUrl);
  $('wifiCertificateDownload').hidden = !download;
  if (download) $('wifiCertificateDownload').href = download;

  if (!bound) {
    $('wifiPhoneStep').addEventListener('click', () => setStep('phone'));
    $('wifiSetupStep').addEventListener('click', () => setStep('setup'));
    $('wifiAddress').addEventListener('change', updateConnection);
    $('wifiCopy').addEventListener('click', copyUrl);
    $('wifiUrl').addEventListener('click', event => { event.currentTarget.select(); });
    $('wifiQr').addEventListener('error', () => { $('wifiQr').hidden = true; $('wifiQrError').hidden = false; });
    bound = true;
  }
  setStep(currentStep);
}
