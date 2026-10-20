import { MotionModel, gainConfig, screenAxes } from './model.mjs';
import { SettingsInbox } from './settings.mjs';
import { setupWifi } from './wifi.mjs';

const $ = id => document.getElementById(id);
const all = selector => [...document.querySelectorAll(selector)];
const finite = value => typeof value === 'number' && Number.isFinite(value);
const fmt = (value, digits = 3) => finite(value) ? value.toFixed(digits) : 'null';
const gravity = 9.80665;
const FIXED_STEP = 1 / 60;
const model = new MotionModel();
const settings = { gain: gainConfig.default, invertX: gainConfig.invertX, invertY: gainConfig.invertY };
const minimumGain = gainConfig.MIN ?? gainConfig.min ?? .25;
const maximumGain = gainConfig.MAX ?? gainConfig.max ?? 20;
const gainStep = gainConfig.STEP ?? gainConfig.step ?? .25;
const parameterMode = new URLSearchParams(location.search).get('mode');
let mode = parameterMode === 'phone' ? 'device' : parameterMode === 'receiver' ? 'receiver' : 'simulation';
let info = null;
let events = null;
let enabled = false;
let pendingPermission = false;
let sensorWaitStarted = null;
let simulationKind = 'sine';
let simulationPaused = false;
let simulationTime = 0;
let graphAxis = 'x';
let sourceCount = 0;
let rateTimes = [];
let lastSampleAt = null;
let lastDeviceTime = null;
let lastRaw = null;
let sensorProblem = '';
let sourceDevice = '';
let trace = [];
let frameTime = null;
let frameAccumulator = 0;
let paintTime = 0;
let lastDvx = 0;
let lastDvy = 0;
let dragPointer = null;
let dragPosition = null;
let recording = false;
let recordingStarted = null;
let recordingRows = [];
let recordedMode = mode;
let relayBuffer = [];
let relayBusy = false;
let relayFailures = 0;
let relayPosted = 0;
let lastSettingsVersion = 0;
let settingsTimer = null;
const settingsInbox = new SettingsInbox(applySettings);
let disposal = false;
let sourceAccumulator = 0;
let sourceClockActive = false;
let sourceTimeline = 0;
let lastReceiverSequence = null;
let lastSourceSampleId = null;
let lastSourceTimestamp = null;
let streamNeedsCalibration = false;
let streamHasOpened = false;
let deviceSampleSequence = 0;
const maxRecordingRows = 72000;
const deviceId = `phone-${Math.random().toString(36).slice(2, 8)}`;
const colors = { grid: '#2b392f', subtle: '#6e8374', green: '#c4f179', blue: '#84b8cb', orange: '#eeae78' };

function setNotice(text, warning = false) {
  $('noticeText').textContent = text;
  $('notice').classList.toggle('warning', warning);
}

function screenAngle() {
  const value = window.screen?.orientation?.angle ?? window.orientation;
  return finite(value) ? value : 0;
}

function resetLocal() {
  model.reset();
  model.setGain(settings.gain);
  sourceCount = 0;
  rateTimes = [];
  lastSampleAt = null;
  lastDeviceTime = null;
  lastRaw = null;
  sourceDevice = '';
  trace = [];
  lastDvx = 0;
  lastDvy = 0;
  simulationTime = 0;
  frameAccumulator = 0;
  sourceAccumulator = 0;
  sourceClockActive = false;
  sourceTimeline = 0;
  lastReceiverSequence = null;
  lastSourceSampleId = null;
  lastSourceTimestamp = null;
  streamNeedsCalibration = false;
  relayBuffer = [];
  drawTelemetry();
}

function stopDevice() {
  window.removeEventListener('devicemotion', deviceMotion);
  enabled = false;
  sensorWaitStarted = null;
  lastDeviceTime = null;
  relayBuffer = [];
  $('enableSensor').disabled = false;
  $('stopSensor').disabled = true;
  $('enableSensor').textContent = '启用手机传感器';
  model.resetSensor();
  sourceClockActive = false;
  sourceAccumulator = 0;
}

function setMode(next) {
  if (mode === 'device' && next !== mode) stopDevice();
  if (recording) stopRecording();
  mode = next;
  document.body.dataset.mode = mode;
  resetLocal();
  sensorProblem = '';
  for (const button of all('button[data-mode]')) {
    const selected = button.dataset.mode === mode;
    button.classList.toggle('active', selected);
    button.setAttribute('aria-pressed', String(selected));
  }
  $('simulationPanel').hidden = mode !== 'simulation';
  $('devicePanel').hidden = mode !== 'device';
  $('receiverPanel').hidden = mode !== 'receiver';
  if (mode === 'simulation') {
    setNotice('当前是模拟信号，不是物理传感器。可切换到本机传感器，在手机上授权采样。');
    $('rawSource').textContent = '模拟';
    $('sensorExplanation').textContent = '模拟输入不产生真实陀螺仪读数。游戏当前以加速度计驱动体感。';
  } else if (mode === 'device') {
    $('rawSource').textContent = '等待本机';
    $('sensorExplanation').textContent = '此处读取浏览器真实传感器。角速度单独展示；加速度用于游戏的虚拟拖动模型。';
    if (!window.isSecureContext) {
      setNotice('当前页面不是安全上下文，浏览器通常不会提供体感。Android 可使用 USB + localhost；iPhone 请使用受信任的 HTTPS。', true);
    } else {
      setNotice('请点击“启用手机传感器”。仅检测到 API 不代表可用；收到有效样本后才会显示在线。');
    }
  } else {
    $('rawSource').textContent = '等待手机';
    $('sensorExplanation').textContent = '接收手机浏览器的真实传感器。这里有样本，不代表 Maker 原生体感接口已接通。';
    setNotice(info?.wifi?.enabled
      ? '手机与电脑连接同一 Wi-Fi，扫描下方二维码。首次连接请先按指引安装证书，再启用体感。'
      : '电脑正在等待手机数据。手机需打开此本地服务，启用真实传感器并勾选同步。普通局域网 HTTP 只能检查连接。');
  }
  const queryMode = mode === 'device' ? 'phone' : mode;
  const currentUrl = new URL(location.href);
  currentUrl.searchParams.set('mode', queryMode);
  history.replaceState(null, '', currentUrl);
  drawTelemetry();
}

function applySettings(value) {
  const previousInvertX = settings.invertX;
  const previousInvertY = settings.invertY;
  if (finite(value.gain)) model.setGain(value.gain);
  settings.gain = model.state.sensorGain;
  if (typeof value.invertX === 'boolean') settings.invertX = value.invertX;
  if (typeof value.invertY === 'boolean') settings.invertY = value.invertY;
  if (previousInvertX !== settings.invertX || previousInvertY !== settings.invertY) model.resetSensor();
  $('gainRange').value = settings.gain;
  // A server echo must not overwrite a number that the user is still typing.
  if (document.activeElement !== $('gainNumber')) $('gainNumber').value = settings.gain;
  $('gainValue').innerHTML = `${settings.gain.toFixed(2)}<span>×</span>`;
  $('invertX').checked = settings.invertX;
  $('invertY').checked = settings.invertY;
  for (const button of all('[data-gain]')) button.classList.toggle('selected', Number(button.dataset.gain) === settings.gain);
  updateRange($('gainRange'));
}

function changeSettings(value) {
  applySettings({ ...settings, ...value });
  const version = ++lastSettingsVersion;
  settingsInbox.setPending(true);
  clearTimeout(settingsTimer);
  settingsTimer = setTimeout(async () => {
    if (!info) { settingsInbox.setPending(false); return; }
    try {
      const response = await post('/api/settings', settings);
      settingsInbox.receive(await response.json());
      if (version !== lastSettingsVersion) return;
      settingsInbox.setPending(false);
    } catch (error) {
      if (version === lastSettingsVersion) settingsInbox.setPending(false);
      $('connectionStatus').textContent = `设置同步失败：${error.message}`;
    }
  }, 90);
}

async function post(path, data) {
  if (!info?.token) throw new Error('本地服务未连接');
  const response = await fetch(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Lab-Token': info.token },
    body: JSON.stringify(data),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response;
}

function ingest(sample, origin) {
  if (!finite(sample.ax) || !finite(sample.ay) || !finite(sample.dt) || sample.dt <= 0) return;
  const now = performance.now();
  const wasWaiting = lastSampleAt === null || now - lastSampleAt > 1500;
  let discontinuity = '';
  if (origin === 'receiver') {
    if (streamNeedsCalibration) {
      discontinuity = '连接恢复';
      lastReceiverSequence = null;
      lastSourceSampleId = null;
      lastSourceTimestamp = null;
    }
    if (Number.isSafeInteger(sample.seq)) {
      if (lastReceiverSequence !== null && sample.seq <= lastReceiverSequence) return;
      if (lastReceiverSequence !== null && sample.seq !== lastReceiverSequence + 1) discontinuity = '传输丢样';
      lastReceiverSequence = sample.seq;
    }
    if (sourceDevice && sourceDevice !== sample.deviceId) {
      discontinuity = '输入设备已切换';
      lastSourceSampleId = null;
      lastSourceTimestamp = null;
    }
    if (Number.isSafeInteger(sample.sampleId)) {
      if (lastSourceSampleId !== null && sample.sampleId <= lastSourceSampleId) return;
      if (lastSourceSampleId !== null && sample.sampleId !== lastSourceSampleId + 1) discontinuity = '手机采样丢失';
      lastSourceSampleId = sample.sampleId;
    } else if (finite(sample.timestamp) && lastSourceTimestamp !== null && sample.timestamp <= lastSourceTimestamp) {
      // Older clients have no sampleId. Do not apply a retried or out-of-order sample twice.
      return;
    }
  }
  if (sample.dt > .15 || (lastSourceTimestamp !== null && finite(sample.timestamp)
    && sample.timestamp - lastSourceTimestamp > 150)) discontinuity ||= '采样中断';
  if (lastRaw && lastRaw.screenAngle !== sample.screenAngle) discontinuity ||= '屏幕方向已变化';
  if (wasWaiting && lastSampleAt !== null) discontinuity ||= '采样恢复';
  if (discontinuity) {
    model.resetSensor();
    sourceAccumulator = 0;
    if (origin !== 'simulation') setNotice(`${discontinuity}，已重新建立基线；从当前样本继续测试。`);
  }
  streamNeedsCalibration = false;
  if (finite(sample.timestamp)) lastSourceTimestamp = sample.timestamp;
  const ax = sample.ax * (settings.invertX ? -1 : 1);
  const ay = sample.ay * (settings.invertY ? -1 : 1);
  const delta = model.sensor(ax, ay, sample.dt);
  model.move(delta.dx, delta.dy);
  // External samples keep their source clock. A network batch must execute every
  // intermediate target before the next sample overwrites it; receipt time only paints UI.
  if (origin !== 'simulation') {
    sourceClockActive = true;
    // Touch owns the wall clock while held; never integrate the same time twice.
    sourceAccumulator = model.state.holding ? 0 : sourceAccumulator + (sample.dt > .15 ? FIXED_STEP : sample.dt);
    while (sourceAccumulator + 1e-10 >= FIXED_STEP) {
      const impulse = model.step(FIXED_STEP);
      lastDvx = impulse.dvx; lastDvy = impulse.dvy;
      sourceAccumulator = Math.max(0, sourceAccumulator - FIXED_STEP);
    }
  }
  sourceTimeline += sample.dt;
  lastSampleAt = now;
  sourceCount++;
  rateTimes.push(sourceTimeline * 1000);
  while (rateTimes.length && sourceTimeline * 1000 - rateTimes[0] > 2000) rateTimes.shift();
  lastRaw = { ...sample, inputX: ax, inputY: ay, origin };
  if (wasWaiting && !discontinuity && origin === 'device') setNotice('已收到浏览器真实传感器数据。请摇动手机并调整系数；此结果仅验证浏览器输入链路。');
  if (wasWaiting && !discontinuity && origin === 'receiver') setNotice('正在接收手机浏览器的真实传感器数据。电脑修改系数会同步到手机；此结果不证明 Maker 原生接口已接通。');
  if (origin === 'receiver') sourceDevice = sample.deviceId || '手机';
  const state = model.state;
  trace.push({ t: sourceTimeline, breakBefore: !!discontinuity, ax, ay, fx: state.sensorX, fy: state.sensorY, tx: state.targetX, ty: state.targetY });
  while (trace.length && sourceTimeline - trace[0].t > 8.4) trace.shift();
  if (recording) {
    recordingRows.push({ elapsedMs: now - recordingStarted, sourceTimeMs: sourceTimeline * 1000,
      discontinuity: discontinuity || null, source: origin,
      input: { ...sample, appliedAx: ax, appliedAy: ay }, settings: { ...settings },
      virtualDrag: { dx: delta.dx, dy: delta.dy }, state: { ...state } });
    if (recordingRows.length >= maxRecordingRows) {
      stopRecording();
      setNotice('录制已达到 72,000 个样本，已自动停止。请导出本次 JSON。', true);
    }
  }
}

function deviceMotion(event) {
  if (!enabled || mode !== 'device') return;
  const acceleration = event.accelerationIncludingGravity;
  // Missing sensor components remain null: never convert a missing value to zero.
  if (!acceleration || !finite(acceleration.x) || !finite(acceleration.y)) {
    sensorProblem = '已收到事件，但加速度 X / Y 为 null；尚无有效样本';
    return;
  }
  const timestamp = finite(event.timeStamp) ? event.timeStamp : performance.now();
  const intervalSeconds = finite(event.interval) && event.interval > 0 ? event.interval / 1000 : FIXED_STEP;
  const dt = lastDeviceTime === null ? intervalSeconds : (timestamp - lastDeviceTime) / 1000;
  if (!(dt > 0)) return;
  lastDeviceTime = timestamp;
  const angle = screenAngle();
  const rawX = acceleration.x / gravity;
  const rawY = acceleration.y / gravity;
  const axes = screenAxes(rawX, rawY, angle);
  const rotation = event.rotationRate;
  const rotationRate = rotation ? {
    alpha: finite(rotation.alpha) ? rotation.alpha : null,
    beta: finite(rotation.beta) ? rotation.beta : null,
    gamma: finite(rotation.gamma) ? rotation.gamma : null,
  } : null;
  const sample = { ax: axes.x, ay: axes.y, az: finite(acceleration.z) ? acceleration.z / gravity : null,
    rawX, rawY, dt, timestamp: Date.now(), sampleId: ++deviceSampleSequence, rotationRate, screenAngle: angle, deviceId, source: 'phone' };
  sensorProblem = '';
  ingest(sample, 'device');
  if ($('relayPhone').checked) {
    relayBuffer.push(sample);
    if (relayBuffer.length > 512) {
      relayBuffer = [];
      relayFailures++;
      $('relayStatus').textContent = '连接中断，缓存已满；请重新连接后校准。';
      model.resetSensor();
    }
  }
}

async function enableDevice() {
  if (pendingPermission) return;
  if (!window.isSecureContext) {
    setNotice('请先使用安全上下文：Android 用 USB + localhost；iPhone 用受信任的 HTTPS。连接指南在页面下方。', true);
    $('connectionGuide').open = true;
    return;
  }
  if (typeof window.DeviceMotionEvent === 'undefined') {
    sensorProblem = '此浏览器没有 DeviceMotionEvent API';
    $('permissionLabel').textContent = 'API 不支持';
    setNotice('浏览器没有提供运动传感器 API。PC 可用模拟模式；真实输入请在支持的手机浏览器测试。', true);
    return;
  }
  pendingPermission = true;
  $('enableSensor').disabled = true;
  $('permissionLabel').textContent = '正在请求';
  try {
    // DeviceMotion includes acceleration and angular velocity. Request only what this page reads.
    const permissions = [];
    if (typeof window.DeviceMotionEvent.requestPermission === 'function') permissions.push(window.DeviceMotionEvent.requestPermission());
    const results = await Promise.all(permissions);
    if (mode !== 'device') return;
    if (results.some(result => result !== 'granted')) {
      $('permissionLabel').textContent = '权限未获准';
      sensorProblem = '运动与方向权限未获准';
      setNotice('运动与方向权限未获准。请在浏览器的网站权限中允许，然后再次启用。', true);
      return;
    }
    resetLocal();
    enabled = true;
    sensorWaitStarted = performance.now();
    window.addEventListener('devicemotion', deviceMotion);
    $('permissionLabel').textContent = '已启用 · 等待样本';
    $('enableSensor').textContent = '等待有效传感器样本…';
    $('stopSensor').disabled = false;
    setNotice('浏览器采样已启用，正在等待有效样本。若始终为 0 次，说明此运行端尚未提供实际传感器数据。');
  } catch (error) {
    sensorProblem = `权限请求失败：${error.message}`;
    $('permissionLabel').textContent = '请求失败';
    setNotice(sensorProblem, true);
  } finally {
    pendingPermission = false;
    $('enableSensor').disabled = enabled;
  }
}

async function flushRelay() {
  if (relayBusy || !relayBuffer.length || !info || !enabled || !$('relayPhone').checked) return;
  relayBusy = true;
  const samples = relayBuffer.splice(0, 32);
  try {
    const response = await post('/api/sample', { samples });
    const result = await response.json();
    relayPosted += Number.isInteger(result.accepted) ? result.accepted : samples.length;
    relayFailures = 0;
    $('relayStatus').textContent = `已同步 ${relayPosted} 个样本到电脑；保持此页在前台。`;
  } catch (error) {
    relayFailures++;
    $('relayStatus').textContent = `同步失败（${error.message}）；请检查本地服务连接。`;
    // Retain order after a failed request, bounded to avoid unlimited memory growth.
    if (relayBuffer.length + samples.length <= 512) relayBuffer.unshift(...samples);
  } finally {
    relayBusy = false;
  }
}

function updateRange(input) {
  input.style.setProperty('--fill', `${(Number(input.value) - Number(input.min)) / (Number(input.max) - Number(input.min)) * 100}%`);
}

function updateSimulationControls() {
  $('amplitudeValue').textContent = `${Number($('amplitudeRange').value).toFixed(2)} g`;
  $('frequencyValue').textContent = `${Number($('frequencyRange').value).toFixed(2)} Hz`;
  $('manualXValue').textContent = `${Number($('manualX').value).toFixed(2)} g`;
  $('manualYValue').textContent = `${Number($('manualY').value).toFixed(2)} g`;
  all('input[type="range"]').forEach(updateRange);
}

function setSimulationKind(kind) {
  simulationKind = kind;
  $('sineControls').hidden = kind !== 'sine';
  $('manualControls').hidden = kind !== 'manual';
  $('sineButton').classList.toggle('selected', kind === 'sine');
  $('manualButton').classList.toggle('selected', kind === 'manual');
  $('sineButton').setAttribute('aria-pressed', String(kind === 'sine'));
  $('manualButton').setAttribute('aria-pressed', String(kind === 'manual'));
  resetLocal();
}

function simulate(dt) {
  if (simulationPaused) return;
  simulationTime += dt;
  let ax, ay;
  if (simulationKind === 'sine') {
    const amplitude = Number($('amplitudeRange').value);
    const phase = simulationTime * Number($('frequencyRange').value) * Math.PI * 2;
    ax = Math.sin(phase) * amplitude;
    ay = Math.sin(phase * .7) * amplitude * .45;
  } else {
    ax = Number($('manualX').value);
    ay = Number($('manualY').value);
  }
  ingest({ ax, ay, az: null, rawX: ax, rawY: ay, dt, timestamp: Date.now(), rotationRate: null, screenAngle: 0, source: 'simulation' }, 'simulation');
}

function drawTelemetry() {
  const now = performance.now();
  const state = model.state;
  const age = lastSampleAt === null ? null : now - lastSampleAt;
  const current = age !== null && age < 1500;
  if (mode !== 'simulation' && age !== null && age > 1500 && model.state.sensorHolding) model.resetSensor();
  let status = '等待样本';
  let badge = mode === 'receiver' ? '等待手机' : '尚未启用';
  if (mode === 'simulation') {
    status = simulationPaused ? '模拟已暂停' : '模拟信号';
    badge = `模拟 · ${simulationKind === 'sine' ? '正弦波' : '手动滑条'}${simulationPaused ? ' / 暂停' : ''}`;
  } else if (mode === 'device') {
    status = current && enabled ? '真实传感器在线' : enabled ? age === null ? '等待有效样本' : '样本已中断' : '未启用传感器';
    badge = current && enabled ? '浏览器真实传感器' : enabled ? '等待 · 无当前数据' : '尚未启用';
    if (current && enabled) {
      $('permissionLabel').textContent = '已收到有效样本';
      $('enableSensor').textContent = '传感器采样中';
      $('rawSource').textContent = '浏览器真实数据';
    }
  } else {
    status = current ? '手机数据在线' : age === null ? '等待手机样本' : '手机数据已中断';
    badge = current ? '手机 · 浏览器真实传感器' : '等待手机';
    $('receiverStatus').textContent = current ? '正在接收' : '等待手机';
    $('receiverDevice').textContent = sourceDevice ? `设备 ${sourceDevice} · ${current ? '接收中' : '暂无新样本'}` : '尚未接收手机样本';
    $('rawSource').textContent = current ? '手机真实数据' : '等待手机';
  }
  $('sourceBadge').textContent = badge;
  $('inputStatus').replaceChildren();
  const dot = document.createElement('i');
  dot.className = `status-dot${current && !(mode === 'simulation' && simulationPaused) ? '' : ' waiting'}`;
  $('inputStatus').append(dot, document.createTextNode(status));
  $('inputStatus').title = sensorProblem || status;
  $('sampleCount').innerHTML = `${sourceCount.toLocaleString()} <small>次</small>`;
  const recentTimes = rateTimes.filter(t => sourceTimeline * 1000 - t <= 2000);
  const span = recentTimes.length > 1 ? recentTimes.at(-1) - recentTimes[0] : 0;
  const rate = current && span > 0 ? (recentTimes.length - 1) * 1000 / span : null;
  $('sampleRate').innerHTML = `${rate === null ? '—' : rate.toFixed(1)} <small>Hz</small>`;
  $('sampleAge').textContent = age === null ? '尚无样本' : age < 1000 ? `${Math.round(age)} ms` : `${(age / 1000).toFixed(1)} s`;
  $('secureValue').textContent = window.isSecureContext ? 'true · 安全' : 'false · 普通 HTTP';
  $('positionValue').innerHTML = `${fmt(state.x)} / ${fmt(state.y)} <small>m</small>`;
  $('targetValue').innerHTML = `${fmt(state.targetX)} / ${fmt(state.targetY)} <small>m</small>`;
  const length = Math.hypot(state.sensorX, state.sensorY);
  $('deadzoneValue').textContent = !lastRaw ? '等待输入' : model.state.holding ? '手指拖动优先' : length > .035 ? '已越过死区' : '死区内 · 回中';
  $('deadzoneValue').classList.toggle('active-value', !!lastRaw && length > .035);
  $('filteredMagnitude').textContent = `${length.toFixed(4)} g`;
  const saturated = [Math.abs(state.targetX) >= .52 - 1e-8 ? 'X' : '', Math.abs(state.targetY) >= .36 - 1e-8 ? 'Y' : ''].filter(Boolean);
  $('saturationValue').textContent = saturated.length ? `${saturated.join(' / ')} 已限幅` : '未限幅';
  $('saturationValue').classList.toggle('limit-active', saturated.length > 0);
  $('baselineValue').textContent = `${fmt(state.sensorBaseX)} / ${fmt(state.sensorBaseY)} g`;
  $('rawX').textContent = lastRaw ? fmt(lastRaw.rawX) : '—';
  $('rawY').textContent = lastRaw ? fmt(lastRaw.rawY) : '—';
  $('rawZ').textContent = lastRaw ? fmt(lastRaw.az) : '—';
  $('gyroAlpha').textContent = fmt(lastRaw?.rotationRate?.alpha, 1);
  $('gyroBeta').textContent = fmt(lastRaw?.rotationRate?.beta, 1);
  $('gyroGamma').textContent = fmt(lastRaw?.rotationRate?.gamma, 1);
  $('screenValue').textContent = lastRaw ? `${fmt(lastRaw.inputX)} / ${fmt(lastRaw.inputY)}` : '— / —';
  $('screenAngle').textContent = `${lastRaw?.screenAngle ?? screenAngle()}°`;
  $('graphEmpty').hidden = trace.length > 1;
  if (recording) $('recordingStatus').textContent = `${((now - recordingStarted) / 1000).toFixed(1)} s · ${recordingRows.length} 样本`;
  $('exportButton').disabled = recordingRows.length === 0;
  if (mode === 'device' && enabled && age === null && sensorProblem) setNotice(sensorProblem, true);
  else if (mode === 'device' && enabled && age === null && sensorWaitStarted !== null && now - sensorWaitStarted > 2500) {
    setNotice('采样已启用，但仍为 0 个有效样本。请确认在真实手机浏览器打开、已允许运动权限，且地址为 localhost 或受信任的 HTTPS。', true);
  }
}

function fitCanvas(canvas) {
  const rect = canvas.getBoundingClientRect();
  const ratio = Math.min(window.devicePixelRatio || 1, 3);
  const width = Math.round(rect.width * ratio);
  const height = Math.round(rect.height * ratio);
  if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
  const context = canvas.getContext('2d');
  context.setTransform(ratio, 0, 0, ratio, 0, 0);
  context.clearRect(0, 0, rect.width, rect.height);
  return { ctx: context, w: rect.width, h: rect.height };
}

function roundedRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}

function drawBottle(now) {
  const { ctx, w, h } = fitCanvas($('bottleCanvas'));
  if (!w || !h) return;
  const cx = w / 2, cy = h / 2 - 8;
  const scale = Math.min((w - 65) / 1.6, (h - 100) / 1.18, 255);
  const s = model.state;
  ctx.strokeStyle = '#26372a'; ctx.lineWidth = 1;
  const gridSize = 26;
  for (let x = cx % gridSize; x < w; x += gridSize) { ctx.beginPath(); ctx.moveTo(x, 20); ctx.lineTo(x, h - 40); ctx.stroke(); }
  for (let y = cy % gridSize; y < h - 40; y += gridSize) { ctx.beginPath(); ctx.moveTo(8, y); ctx.lineTo(w - 8, y); ctx.stroke(); }
  ctx.strokeStyle = '#3a4c3d'; ctx.setLineDash([3, 5]);
  ctx.strokeRect(cx - .52 * scale, cy - .36 * scale, 1.04 * scale, .72 * scale);
  ctx.setLineDash([]);
  ctx.strokeStyle = '#506143'; ctx.beginPath(); ctx.arc(cx, cy, 5, 0, Math.PI * 2); ctx.stroke();
  const tx = cx + s.targetX * scale, ty = cy - s.targetY * scale;
  ctx.strokeStyle = colors.orange; ctx.lineWidth = 1.1;
  ctx.beginPath(); ctx.moveTo(tx - 8, ty); ctx.lineTo(tx + 8, ty); ctx.moveTo(tx, ty - 8); ctx.lineTo(tx, ty + 8); ctx.stroke();
  const bx = cx + s.x * scale, by = cy - s.y * scale;
  ctx.strokeStyle = '#6b7c4a'; ctx.lineWidth = 1; ctx.setLineDash([2, 4]);
  ctx.beginPath(); ctx.moveTo(tx, ty); ctx.lineTo(bx, by); ctx.stroke(); ctx.setLineDash([]);
  const bh = Math.min(174, h * .51), bw = bh * .59;
  ctx.save(); ctx.translate(bx, by); ctx.rotate(Math.max(-.11, Math.min(.11, -s.vx * .025)));
  // The container translates with the exact input model; contents are illustrative.
  ctx.shadowColor = '#00000042'; ctx.shadowBlur = 22; ctx.shadowOffsetY = 13;
  const glass = ctx.createLinearGradient(-bw / 2, 0, bw / 2, 0);
  glass.addColorStop(0, '#2f4231'); glass.addColorStop(.24, '#23372a'); glass.addColorStop(1, '#1b2c22');
  ctx.fillStyle = glass; roundedRect(ctx, -bw / 2, -bh / 2 + 12, bw, bh - 12, [21, 21, 23, 23]); ctx.fill(); ctx.shadowColor = 'transparent';
  ctx.strokeStyle = '#93ac73'; ctx.lineWidth = 1.6; ctx.stroke();
  ctx.fillStyle = '#213025'; roundedRect(ctx, -bw * .32, -bh / 2 - 9, bw * .64, 25, 5); ctx.fill();
  ctx.strokeStyle = '#a6bd83'; ctx.stroke();
  ctx.fillStyle = colors.green; roundedRect(ctx, -bw * .35, -bh / 2 - 15, bw * .7, 13, 3); ctx.fill();
  ctx.fillStyle = '#456039'; for (let i = 0; i < 6; i++) ctx.fillRect(-bw * .27 + i * bw * .105, -bh / 2 - 13, 2, 9);
  ctx.save(); roundedRect(ctx, -bw / 2 + 3, -bh / 2 + 16, bw - 6, bh - 21, 19); ctx.clip();
  const ballColors = ['#c4f179', '#eeb47c', '#a0c5b2', '#d3d993', '#789f73', '#d2b885'];
  const balls = [[-.24,.20,.11],[.02,.31,.125],[.26,.22,.11],[-.19,.36,.105],[.20,.39,.105],[.01,.09,.095]];
  balls.forEach((ball, index) => {
    const sway = Math.max(-.12, Math.min(.12, -s.vx * .028)) + Math.sin(now / 900 + index * 1.3) * Math.min(.015, Math.abs(s.vx) * .004);
    const xx = (ball[0] + sway) * bw;
    const yy = ball[1] * bh + Math.max(-8, Math.min(8, s.vy * 2));
    const radius = ball[2] * bw;
    ctx.fillStyle = ballColors[index]; ctx.beginPath(); ctx.arc(xx, yy, radius, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#263b29'; ctx.beginPath(); ctx.arc(xx - radius * .26, yy - 1, 1.2, 0, Math.PI * 2); ctx.arc(xx + radius * .26, yy - 1, 1.2, 0, Math.PI * 2); ctx.fill();
  }); ctx.restore();
  ctx.fillStyle = '#263829'; roundedRect(ctx, -bw * .37, -bh * .15, bw * .74, bh * .25, 4); ctx.fill();
  ctx.strokeStyle = '#516943'; ctx.lineWidth = .7; ctx.stroke();
  ctx.textAlign = 'center'; ctx.fillStyle = colors.green; ctx.font = `600 ${Math.round(bw * .11)}px Consolas, monospace`; ctx.fillText('SHAKE', 0, -bh * .035);
  ctx.fillStyle = '#93a580'; ctx.font = `${Math.round(bw * .068)}px Consolas, monospace`; ctx.fillText('INPUT LAB / 02', 0, bh * .03);
  ctx.strokeStyle = '#b6d58b32'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(-bw * .36, -bh * .27); ctx.lineTo(-bw * .36, bh * .20); ctx.stroke();
  ctx.restore();
  ctx.textAlign = 'left'; ctx.fillStyle = '#61745f'; ctx.font = '9px Consolas, monospace'; ctx.fillText('±0.52 m', cx - .52 * scale, cy + .36 * scale + 17);
  ctx.textAlign = 'right'; ctx.fillText('±0.36 m', cx + .52 * scale, cy + .36 * scale + 17);
  $('stageHint').textContent = s.holding ? '手指拖动中 · 体感暂停接管' : '按住瓶子区域可测试手指拖动';
}

function drawGraph(now) {
  const { ctx, w, h } = fitCanvas($('signalCanvas'));
  if (!w || !h) return;
  const left = 36, right = w - 36, top = 13, bottom = h - 21;
  const latest = trace.length ? trace.at(-1).t + (lastSampleAt === null ? 0 : Math.max(0, now - lastSampleAt) / 1000) : 0;
  const points = trace.filter(p => latest - p.t < 8);
  const rawKey = graphAxis === 'x' ? 'ax' : 'ay';
  const filteredKey = graphAxis === 'x' ? 'fx' : 'fy';
  const targetKey = graphAxis === 'x' ? 'tx' : 'ty';
  let largest = .25;
  for (const point of points) largest = Math.max(largest, Math.abs(point[rawKey]), Math.abs(point[filteredKey]));
  const rawScale = Math.ceil(largest * 1.12 * 4) / 4;
  const targetScale = graphAxis === 'x' ? .6 : .4;
  const yAt = (value, scale) => (top + bottom) / 2 - value / scale * (bottom - top) / 2;
  ctx.font = '8px Consolas, monospace';
  for (let i = 0; i < 5; i++) {
    const y = top + (bottom - top) * i / 4;
    ctx.strokeStyle = i === 2 ? '#435542' : '#29382d'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(right, y); ctx.stroke();
    ctx.fillStyle = '#6e8374'; ctx.textAlign = 'right'; ctx.fillText((rawScale * (1 - i / 2)).toFixed(2), left - 7, y + 3);
    ctx.fillStyle = '#9b805f'; ctx.textAlign = 'left'; ctx.fillText((targetScale * (1 - i / 2)).toFixed(2), right + 7, y + 3);
  }
  for (let i = 0; i <= 8; i += 2) {
    const x = left + (right - left) * i / 8;
    ctx.strokeStyle = '#29382d'; ctx.beginPath(); ctx.moveTo(x, top); ctx.lineTo(x, bottom); ctx.stroke();
    ctx.fillStyle = '#617563'; ctx.textAlign = 'center'; ctx.fillText(i === 8 ? '现在' : `${i - 8}s`, x, h - 5);
  }
  ctx.save(); ctx.beginPath(); ctx.rect(left, top, right - left, bottom - top); ctx.clip();
  ctx.fillStyle = '#c4f17906'; ctx.fillRect(left, yAt(.035, rawScale), right - left, yAt(-.035, rawScale) - yAt(.035, rawScale));
  [[rawKey, colors.blue, rawScale, 1], [filteredKey, colors.green, rawScale, 1.6], [targetKey, colors.orange, targetScale, 1.4]].forEach(([key, color, scale, width]) => {
    ctx.strokeStyle = color; ctx.lineWidth = width; ctx.beginPath();
    let previous = null;
    for (const point of points) {
      const x = right - (latest - point.t) / 8 * (right - left);
      const y = yAt(point[key], scale);
      if (!previous || point.breakBefore || point.t - previous.t > .2) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      previous = point;
    }
    ctx.stroke();
  }); ctx.restore();
  $('graphScale').textContent = `左轴 ±${rawScale.toFixed(2)} g · 右轴 ±${targetScale.toFixed(2)} m`;
}

function animate(now) {
  if (disposal) return;
  const elapsed = frameTime === null ? FIXED_STEP : Math.max(0, Math.min(.1, (now - frameTime) / 1000));
  frameTime = now;
  frameAccumulator += elapsed;
  if (mode !== 'simulation' && sourceClockActive && lastSampleAt !== null && now - lastSampleAt > 1500) {
    sourceClockActive = false;
    sourceAccumulator = 0;
    model.resetSensor();
    if (mode === 'receiver') streamNeedsCalibration = true;
  }
  while (frameAccumulator >= FIXED_STEP) {
    if (mode === 'simulation') simulate(FIXED_STEP);
    // Source-clock stepping already happened in ingest. Wall-clock steps only
    // animate simulation, direct touch, or the return to center after a disconnect.
    if (mode === 'simulation' || !sourceClockActive || model.state.holding) {
      const impulse = model.step(FIXED_STEP);
      lastDvx = impulse.dvx;
      lastDvy = impulse.dvy;
    }
    frameAccumulator -= FIXED_STEP;
  }
  drawBottle(now);
  if (now - paintTime > 70) {
    drawTelemetry();
    drawGraph(now);
    paintTime = now;
  }
  requestAnimationFrame(animate);
}

function beginRecording() {
  recordingRows = [];
  recording = true;
  recordingStarted = performance.now();
  recordedMode = mode;
  $('recordButton').innerHTML = '<span class="record-dot"></span>停止录制';
  $('recordButton').classList.add('recording');
  $('exportButton').disabled = true;
}

function stopRecording() {
  recording = false;
  $('recordButton').innerHTML = '<span class="record-dot"></span>开始录制';
  $('recordButton').classList.remove('recording');
  $('recordingStatus').textContent = `已录制 ${recordingRows.length.toLocaleString()} 样本`;
  $('exportButton').disabled = !recordingRows.length;
}

function exportRecording() {
  if (!recordingRows.length) return;
  const payload = { schema: 'shakehero-sensor-lab/v1', createdAt: new Date().toISOString(), mode: recordedMode,
    note: recordedMode === 'simulation' ? '合成模拟信号，不是真实物理传感器。' : '浏览器真实传感器，不证明 Maker 原生传感器接口可用。',
    units: { acceleration: 'g', angularVelocity: 'degree/second', position: 'meter', dt: 'second' },
    modelSource: info?.modelSource ?? 'scripts/Bottle/ShakeMotion.lua',
    environment: { secureContext: window.isSecureContext, userAgent: navigator.userAgent },
    fixedPhysicsStep: FIXED_STEP, sampleCount: recordingRows.length, samples: recordingRows };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `shakehero-${recordedMode}-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

async function connectServer() {
  try {
    const pair = new URLSearchParams(location.hash.slice(1)).get('pair');
    if (pair) {
      if (location.protocol !== 'https:' || !/^[a-f0-9]{48}$/.test(pair)) throw new Error('请重新扫描电脑上的 HTTPS 测试二维码');
      const paired = await fetch('/api/pair', { method: 'POST',
        headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ pair }) });
      if (!paired.ok) throw new Error('配对已失效，请重新扫描电脑上的二维码');
      const cleanUrl = new URL(location.href); cleanUrl.hash = '';
      history.replaceState(null, '', cleanUrl);
    }
    const response = await fetch('/api/info', { cache: 'no-store' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    info = await response.json();
    setupWifi(info);
    if (info.wifi?.enabled) {
      $('receiverGuideLink').textContent = '扫码连接手机 ↗';
      $('receiverGuideLink').href = '#wifiCard';
      if (mode === 'receiver') setNotice('手机与电脑连接同一 Wi-Fi，扫描下方二维码。首次连接请先按指引安装证书，再启用体感。');
    }
    settingsInbox.receive(info.settings);
    const port = info.port || 8787;
    const receiverUrl = new URL(location.href); receiverUrl.searchParams.set('mode', 'receiver');
    $('receiverLink').href = receiverUrl.href; $('receiverLink').textContent = receiverUrl.href;
    $('adbCommand').textContent = `adb reverse tcp:${port} tcp:${port}`;
    $('phoneLocalUrl').textContent = new URL('?mode=phone', info.httpUrl).href;
    $('chromeForward').textContent = `${port} → localhost:${port}`;
    $('serverConnection').textContent = `${info.secure ? 'HTTPS' : 'HTTP'} 本地服务已连接 · 端口 ${port}`;
    $('lanAddresses').textContent = (info.lanUrls || []).length ? `局域网连通性地址：${info.lanUrls.join(' / ')}` : '';
    events = new EventSource('/api/events');
    events.onopen = () => {
      if (streamHasOpened) streamNeedsCalibration = true;
      streamHasOpened = true;
      $('connectionStatus').textContent = '本地服务已连接';
    };
    events.onerror = () => {
      streamNeedsCalibration = true;
      $('connectionStatus').textContent = '本地服务重连中…';
    };
    events.addEventListener('hello', event => {
      try { settingsInbox.receive(JSON.parse(event.data).settings); }
      catch { $('connectionStatus').textContent = '服务初始数据格式错误'; }
    });
    events.addEventListener('settings', event => {
      try {
        const value = JSON.parse(event.data);
        settingsInbox.receive(value);
      } catch { $('connectionStatus').textContent = '设置数据格式错误'; }
    });
    events.addEventListener('reset', () => { resetLocal(); });
    events.addEventListener('sample', event => {
      if (mode !== 'receiver') return;
      try {
        const message = JSON.parse(event.data);
        ingest(message.sample, 'receiver');
      } catch { $('connectionStatus').textContent = '手机数据格式错误'; }
    });
  } catch (error) {
    $('connectionStatus').textContent = '本地服务未连接';
    $('serverConnection').textContent = `服务连接失败：${error.message}。请使用启动脚本打开本页，不要直接双击 HTML。`;
    if (mode === 'receiver') setNotice('本地服务未连接，无法接收手机数据。请用工具目录内的启动脚本运行服务后再打开。', true);
  }
}

// Bind controls.
all('button[data-mode]').forEach(button => button.addEventListener('click', () => setMode(button.dataset.mode)));
$('receiverGuideLink').addEventListener('click', () => {
  if (!info?.wifi?.enabled) $('connectionGuide').open = true;
});
all('[data-gain]').forEach(button => button.addEventListener('click', () => changeSettings({ gain: Number(button.dataset.gain) })));
$('gainRange').min = minimumGain; $('gainRange').max = maximumGain; $('gainRange').step = gainStep;
$('gainNumber').min = minimumGain; $('gainNumber').max = maximumGain; $('gainNumber').step = gainStep;
$('gainRange').addEventListener('input', event => changeSettings({ gain: Number(event.target.value) }));
function changeNumber(event) {
  const gain = event.target.valueAsNumber;
  if (finite(gain)) changeSettings({ gain });
}
$('gainNumber').addEventListener('input', changeNumber);
$('gainNumber').addEventListener('change', changeNumber);
$('gainNumber').addEventListener('blur', () => { $('gainNumber').value = settings.gain; });
$('gainMinus').addEventListener('click', () => changeSettings({ gain: settings.gain - gainStep }));
$('gainPlus').addEventListener('click', () => changeSettings({ gain: settings.gain + gainStep }));
$('invertX').addEventListener('change', event => changeSettings({ invertX: event.target.checked }));
$('invertY').addEventListener('change', event => changeSettings({ invertY: event.target.checked }));
$('calibrateButton').addEventListener('click', async () => {
  resetLocal();
  if (mode === 'simulation') return;
  try { await post('/api/reset', {}); } catch (error) { setNotice(`本页已回中；共享校准未同步（${error.message}）。`, true); }
});
$('sineButton').addEventListener('click', () => setSimulationKind('sine'));
$('manualButton').addEventListener('click', () => setSimulationKind('manual'));
['amplitudeRange', 'frequencyRange', 'manualX', 'manualY'].forEach(id => $(id).addEventListener('input', updateSimulationControls));
$('pauseSimulation').addEventListener('click', () => { simulationPaused = !simulationPaused; $('pauseSimulation').textContent = simulationPaused ? '继续模拟' : '暂停模拟'; if (simulationPaused) model.resetSensor(); });
$('enableSensor').addEventListener('click', enableDevice);
$('stopSensor').addEventListener('click', () => { stopDevice(); $('permissionLabel').textContent = '采样已停止'; setNotice('已停止浏览器传感器采样。点击“启用手机传感器”可重新开始。'); });
$('relayPhone').checked = parameterMode === 'phone';
$('relayPhone').addEventListener('change', () => {
  relayBuffer = []; relayPosted = 0;
  $('relayStatus').textContent = $('relayPhone').checked ? '已开启同步，启用传感器后会发送到电脑。' : '仅在本机页面查看。';
});
$('relayStatus').textContent = $('relayPhone').checked ? '已开启同步，启用传感器后会发送到电脑。' : '仅在本机页面查看。';
all('[data-axis]').forEach(button => button.addEventListener('click', () => { graphAxis = button.dataset.axis; all('[data-axis]').forEach(other => { const selected = other === button; other.classList.toggle('selected', selected); other.setAttribute('aria-pressed', String(selected)); }); }));
$('recordButton').addEventListener('click', () => recording ? stopRecording() : beginRecording());
$('exportButton').addEventListener('click', exportRecording);
$('bottleCanvas').addEventListener('pointerdown', event => {
  if (event.button !== 0 || dragPointer !== null) return;
  dragPointer = event.pointerId; dragPosition = { x: event.clientX, y: event.clientY };
  event.currentTarget.setPointerCapture(event.pointerId); model.begin();
});
$('bottleCanvas').addEventListener('pointermove', event => {
  if (event.pointerId !== dragPointer || !dragPosition) return;
  const bounds = event.currentTarget.getBoundingClientRect();
  const scale = Math.min((bounds.width - 65) / 1.6, (bounds.height - 100) / 1.18, 255);
  model.move((event.clientX - dragPosition.x) / scale, -(event.clientY - dragPosition.y) / scale);
  dragPosition = { x: event.clientX, y: event.clientY };
});
function finishDrag(event) { if (event.pointerId !== dragPointer) return; dragPointer = null; dragPosition = null; model.end(); }
$('bottleCanvas').addEventListener('pointerup', finishDrag);
$('bottleCanvas').addEventListener('pointercancel', finishDrag);
$('bottleCanvas').addEventListener('lostpointercapture', finishDrag);
document.addEventListener('visibilitychange', () => {
  frameTime = null; frameAccumulator = 0;
  if (document.hidden && dragPointer !== null) { dragPointer = null; dragPosition = null; model.end(); }
});
window.addEventListener('pagehide', () => { disposal = true; events?.close(); stopDevice(); });

updateSimulationControls();
applySettings(settings);
setMode(mode);
connectServer();
setInterval(flushRelay, 33);
requestAnimationFrame(animate);
