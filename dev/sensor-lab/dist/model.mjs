// Math port of scripts/Bottle/ShakeMotion.lua. The parity test reads the live Lua source.
export const gainConfig = Object.freeze({ min: .25, max: 20, step: .25, default: 6, invertX: true, invertY: true });
export const motionConfig = Object.freeze({ limitX: .52, limitY: .36, followRate: 24,
  inertiaGain: 1.8, baselineSeconds: .18, smoothingSeconds: .035, deadZone: .035, metersPerG: 1.2 });
const finite = value => typeof value === 'number' && Number.isFinite(value);
const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
export function normalizeGain(value) {
  if (!finite(value)) return null;
  return Math.floor(clamp(value, gainConfig.min, gainConfig.max) / gainConfig.step + .5) * gainConfig.step;
}

export class MotionModel {
  constructor({ gain = gainConfig.default } = {}) {
    this.state = { sensorGain: normalizeGain(gain) ?? gainConfig.default };
    this.reset();
  }
  setGain(value) {
    const gain = normalizeGain(value);
    if (gain === null) return false;
    this.state.sensorGain = gain;
    return true;
  }
  reset() {
    Object.assign(this.state, { targetX: 0, targetY: 0, x: 0, y: 0, vx: 0, vy: 0, holding: false });
    this.resetSensor();
  }
  resetSensor() {
    Object.assign(this.state, { sensorBaseX: 0, sensorBaseY: 0, sensorX: 0, sensorY: 0,
      sensorReady: false, sensorHolding: false });
    if (!this.state.holding) this.state.targetX = this.state.targetY = 0;
  }
  begin() {
    const s = this.state;
    s.targetX = s.x; s.targetY = s.y; s.holding = true;
    this.resetSensor();
  }
  move(dx, dy) {
    const s = this.state;
    if (!(s.holding || s.sensorHolding) || !finite(dx) || !finite(dy)) return;
    s.targetX = clamp(s.targetX + dx, -.52, .52);
    s.targetY = clamp(s.targetY + dy, -.36, .36);
  }
  end() {
    this.state.holding = false;
    this.state.targetX = this.state.targetY = 0;
    this.resetSensor();
  }
  sensor(ax, ay, dt) {
    const s = this.state;
    if (!finite(ax) || !finite(ay) || !finite(dt) || dt <= 0) return { dx: 0, dy: 0 };
    if (s.holding) { this.resetSensor(); return { dx: 0, dy: 0 }; }
    if (dt > .15) this.resetSensor();
    if (!s.sensorReady) {
      s.sensorBaseX = ax; s.sensorBaseY = ay; s.sensorReady = true;
      return { dx: 0, dy: 0 };
    }
    const baseline = 1 - Math.exp(-dt / .18);
    s.sensorBaseX += (ax - s.sensorBaseX) * baseline;
    s.sensorBaseY += (ay - s.sensorBaseY) * baseline;
    const smoothing = 1 - Math.exp(-dt / .035);
    s.sensorX += (ax - s.sensorBaseX - s.sensorX) * smoothing;
    s.sensorY += (ay - s.sensorBaseY - s.sensorY) * smoothing;
    const length = Math.sqrt(s.sensorX * s.sensorX + s.sensorY * s.sensorY);
    const gain = length > .035 ? (1 - .035 / length) * 1.2 * s.sensorGain : 0;
    const x = clamp(s.sensorX * gain, -.52, .52);
    const y = clamp(s.sensorY * gain, -.36, .36);
    s.sensorHolding = true;
    return { dx: x - s.targetX, dy: y - s.targetY };
  }
  step(dt) {
    if (!finite(dt) || dt <= 0) return { dvx: 0, dvy: 0 };
    const s = this.state;
    function follow(position, velocity, target) {
      const error = position - target;
      const c = velocity + 24 * error;
      const decay = Math.exp(-24 * dt);
      return [target + (error + c * dt) * decay, (velocity - 24 * c * dt) * decay];
    }
    const [x, vx] = follow(s.x, s.vx, s.targetX);
    const [y, vy] = follow(s.y, s.vy, s.targetY);
    const result = { dvx: -(vx - s.vx) * 1.8, dvy: -(vy - s.vy) * 1.8 };
    Object.assign(s, { x, y, vx, vy });
    return result;
  }
  sample(ax, ay, dt) {
    const delta = this.sensor(ax, ay, dt);
    this.move(delta.dx, delta.dy);
    return { ...delta, ...this.step(dt) };
  }
}

// Browser device axes are physical-device axes; display angle describes the screen frame.
// Manual X/Y inversions remain exposed because browser and SDL native signs are separate contracts.
export function screenAxes(x, y, angle = 0) {
  const a = (finite(angle) ? angle : 0) * Math.PI / 180;
  const c = Math.cos(a), s = Math.sin(a);
  return { x: c * x - s * y, y: s * x + c * y };
}
