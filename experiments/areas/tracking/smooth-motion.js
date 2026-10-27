// Like smooth_motion.js, plus curved (Hermite) blending between tracker samples and an optional
// per-frame low-pass, to find smooth movement without the delay.
//   node smooth-motion.js recording.csv
const fs = require('fs');
const rec = fs.readFileSync(process.argv[2], 'utf8').trim().split(/\r?\n/).slice(1).map(l => l.split(',').map(Number))
  .filter(r => r[7] && r[8]).map(([t, yaw, pitch]) => ({ t, yaw, pitch }));
const SENS = 3, BLEND = 35, KEYS = ['yaw', 'pitch'];

function chain(samples, { oe = null, interp = 'linear', postTau = 0, jitter = 0.4, settle = 0.5 }) {
  const alpha = (hz, dt) => 1 / (1 + 1 / (2 * Math.PI * hz) / dt);
  const st = {}; let lastT = null;
  const sm = samples.map(r => {
    const dt = lastT === null ? 0.03 : (r.t - lastT) / 1000; lastT = r.t;
    const o = { t: r.t };
    for (const k of KEYS) {
      if (!oe) { o[k] = r[k]; continue; }
      let s = st[k];
      if (!s) { st[k] = { v: r[k], d: 0 }; o[k] = r[k]; continue; }
      s.d += alpha(1, dt) * ((r[k] - s.v) / dt - s.d);
      s.v += alpha(oe[0] + oe[1] * Math.abs(s.d), dt) * (r[k] - s.v);
      o[k] = s.v;
    }
    return o;
  });
  const fr = []; let j = 1;
  for (let t = sm[1].t + BLEND; t < sm[sm.length - 1].t; t += 1000 / 60) {
    const at = t - BLEND;
    while (j < sm.length - 2 && sm[j + 1].t < at) j++;
    const p = sm[j - 1], a = sm[j], b = sm[j + 1];
    const h = b.t - a.t, f = Math.min(Math.max((at - a.t) / h, 0), 1);
    const o = { t };
    for (const k of KEYS) {
      if (interp === 'linear') { o[k] = a[k] + (b[k] - a[k]) * f; continue; }
      // Cubic Hermite through the samples; tangents are each segment's incoming slope, so speed is
      // continuous across samples and nothing later than b is needed (no extra delay).
      const ma = (a[k] - p[k]) / (a.t - p.t) * h, mb = b[k] - a[k];
      const f2 = f * f, f3 = f2 * f;
      o[k] = (2 * f3 - 3 * f2 + 1) * a[k] + (f3 - 2 * f2 + f) * ma + (-2 * f3 + 3 * f2) * b[k] + (f3 - f2) * mb;
    }
    fr.push(o);
  }
  const lp = {}, out = {};
  return fr.map((f, i) => {
    const dt = i ? (f.t - fr[i - 1].t) / 1000 : 1 / 60;
    const c = { t: f.t };
    for (const k of KEYS) {
      let v = f[k];
      if (postTau > 0) { lp[k] = lp[k] === undefined ? v : lp[k] + (v - lp[k]) * (1 - Math.exp(-dt / postTau)); v = lp[k]; }
      let o = out[k];
      if (o === undefined || jitter <= 0) o = v;
      else {
        if (v - o > jitter) o = v - jitter; else if (o - v > jitter) o = v + jitter;
        if (settle > 0) o += (v - o) * (1 - Math.exp(-dt / settle));
      }
      out[k] = o; c[k] = o * SENS;
    }
    return c;
  });
}

const reference = chain(rec, { jitter: 0 });
const turning = c => c.t >= 8000 && c.t < 31000;
function lag(cam) { // ms, by best alignment at 1 ms resolution (linear interpolation of the shift)
  const a = cam.filter(turning), r = reference.filter(turning);
  let best = 0, bestErr = Infinity;
  for (let ms = 0; ms <= 150; ms += 1) {
    const s = ms / (1000 / 60), i0 = Math.floor(s), fr = s - i0; let e = 0, n = 0;
    for (let i = i0 + 1; i < Math.min(a.length, r.length); i++) { const ref = r[i - i0].yaw * (1 - fr) + r[i - i0 - 1].yaw * fr; e += (a[i].yaw - ref) ** 2; n++; }
    if (e / n < bestErr) { bestErr = e / n; best = ms; }
  }
  return best;
}
function jank(cam) {
  const w = cam.filter(turning); let sum = 0, n = 0;
  for (let i = 1; i < w.length - 1; i++) {
    const a = (w[i + 1].yaw - 2 * w[i].yaw + w[i - 1].yaw) * 3600, b = (w[i + 1].pitch - 2 * w[i].pitch + w[i - 1].pitch) * 3600;
    sum += a * a + b * b; n++;
  }
  return Math.sqrt(sum / n);
}
function stillMotion(cam) {
  const w = cam.filter(c => c.t >= 40000 && c.t < 70000); let len = 0;
  for (let i = 1; i < w.length; i++) len += Math.hypot(w[i].yaw - w[i - 1].yaw, w[i].pitch - w[i - 1].pitch);
  return len / ((w[w.length - 1].t - w[0].t) / 1000);
}
// Overshoot: how far past the final position the camera goes when a turn stops (max over turns).
function overshoot(cam) {
  const w = cam.filter(turning), r = reference.filter(turning); let worst = 0;
  for (let i = 30; i < Math.min(w.length, r.length) - 30; i++) {
    const before = r[i - 30].yaw, after = r[i + 30].yaw, dir = Math.sign(after - before);
    if (Math.abs(after - before) < 20) continue;
    const peak = dir > 0 ? Math.max(...w.slice(i, i + 30).map(c => c.yaw)) : Math.min(...w.slice(i, i + 30).map(c => c.yaw));
    const settled = w[i + 29].yaw;
    worst = Math.max(worst, (peak - settled) * dir);
  }
  return worst;
}

const variants = [
  ['installed: no One Euro, linear, settle 0.8', { settle: 0.8 }],
  ['earlier: OE 0.4/0.4, linear', { oe: [0.4, 0.4] }],
  ['old defaults: OE 1.0/0.05, linear', { oe: [1.0, 0.05] }],
  ['OE 0.5/0.1, linear', { oe: [0.5, 0.1] }],
  ['OE 1.0/0.1, linear', { oe: [1.0, 0.1] }],
  ['no OE, curved', { interp: 'hermite' }],
  ['OE 0.4/0.4, curved', { oe: [0.4, 0.4], interp: 'hermite' }],
  ['OE 1.0/0.2, curved', { oe: [1.0, 0.2], interp: 'hermite' }],
  ['OE 1.0/0.1, curved', { oe: [1.0, 0.1], interp: 'hermite' }],
  ['no OE, linear, frame low-pass 25 ms', { postTau: 0.025 }],
  ['no OE, curved, frame low-pass 15 ms', { interp: 'hermite', postTau: 0.015 }],
  ['no OE, curved, frame low-pass 25 ms', { interp: 'hermite', postTau: 0.025 }],
  ['OE 0.4/0.4, curved, frame low-pass 15 ms', { oe: [0.4, 0.4], interp: 'hermite', postTau: 0.015 }],
];
console.log('setup'.padEnd(44) + '  lag   jank (deg/s2)   still (deg/s)   overshoot (deg)');
for (const [name, opts] of variants) {
  const cam = chain(rec, opts);
  console.log(`${name.padEnd(44)}${String(lag(cam)).padStart(4)} ms ${jank(cam).toFixed(0).padStart(8)}        ${stillMotion(cam).toFixed(2).padStart(6)}        ${overshoot(cam).toFixed(2).padStart(6)}`);
}
