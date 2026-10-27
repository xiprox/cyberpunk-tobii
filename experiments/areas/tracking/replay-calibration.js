// Replays a tobii_probe recording through ports of the plugin smoother and the Lua pipeline
// (turns.lua, stillness.lua, curves.lua) with the user's settings, old vs new.
//   node replay-calibration.js file.csv
const fs = require('fs');
const rows = fs.readFileSync(process.argv[2], 'utf8').trim().split(/\r?\n/).slice(1).map(l => l.split(',').map(Number))
  .filter(r => r[7] && r[8]).map(([t, yaw, pitch, roll, x, y, z]) => ({ t, yaw, pitch, roll, x, y, z }));
const KEYS = ['yaw', 'pitch', 'roll', 'x', 'y', 'z'];

// --- plugin: One Euro (pose_smoother.cpp), user's settings 0.4 / 0.4
const alpha = (hz, dt) => 1 / (1 + 1 / (2 * Math.PI * hz) / dt);
const oe = {};
let lastT = null;
const frames = rows.map(r => {
  const dt = lastT === null ? 0.03 : (r.t - lastT) / 1000; lastT = r.t;
  const out = { t: r.t, dt };
  for (const k of KEYS) {
    let s = oe[k];
    if (!s) { s = oe[k] = { v: r[k], d: 0 }; out[k] = r[k]; continue; }
    s.d += alpha(1, dt) * ((r[k] - s.v) / dt - s.d);
    s.v += alpha(0.4 + 0.4 * Math.abs(s.d), dt) * (r[k] - s.v);
    out[k] = s.v;
  }
  return out;
});
const median = a => { const s = [...a].sort((p, q) => p - q); return s[Math.floor(s.length / 2)]; };
const center = Object.fromEntries(KEYS.map(k => [k, median(frames.filter(f => f.t < 2500).map(f => f[k]))]));

// --- curves.lua
const deltas = h => ({ yaw: h.yaw - center.yaw, pitch: h.pitch - center.pitch, roll: h.roll - center.roll,
  x: (h.x - center.x) / 10, y: (h.y - center.y) / 10, z: (h.z - center.z) / 10 });
function shape(delta, axis, deadzone = 0) {
  if (!axis.enabled) return 0;
  const mag = Math.abs(delta) - deadzone;
  if (mag <= 0) return 0;
  const limit = Math.max(axis.limit, 0.001);
  let out = Math.pow(Math.min(mag * axis.sensitivity / limit, 1), Math.max(axis.curve, 0.1)) * limit;
  return delta < 0 ? -out : out;
}
// User's settings.json (deadzones are the old behaviour)
const S = {
  rotation: { yaw: { enabled: true, sensitivity: 3, curve: 1, limit: 136, dz: 0.5, threshold: 0.75 },
              pitch: { enabled: true, sensitivity: 3, curve: 1, limit: 65, dz: 0.5, threshold: 0.75 },
              roll: { enabled: false, sensitivity: 1, curve: 1, limit: 25, dz: 2, threshold: 1 } },
  position: { x: { enabled: true, sensitivity: 3, curve: 1, limit: 30, dz: 0.2, threshold: 0.25 },
              y: { enabled: true, sensitivity: 3, curve: 1, limit: 20, dz: 0.2, threshold: 0.25 },
              z: { enabled: true, sensitivity: 3, curve: 1, limit: 30, dz: 0.2, threshold: 0.25 } },
  turnCorrection: 1,
};
const camera = (d, old) => {
  const r = S.rotation, p = S.position, dz = a => old ? a.dz : 0;
  return { yaw: shape(d.yaw, r.yaw, dz(r.yaw)), pitch: shape(d.pitch, r.pitch, dz(r.pitch)),
    x: -shape(d.x, p.x, dz(p.x)), fwd: -shape(d.z, p.z, dz(p.z)), up: shape(d.y, p.y, dz(p.y)) }; // cm
};

// --- turns.lua
const FROM = -60, TO = 60, STEP = 2.5, CH = ['pitch', 'roll', 'x', 'y', 'z'], BINS = Math.floor((TO - FROM) / STEP + 0.5) + 1;
function lookup(values, from, step, yaw) {
  const n = values.length, pos = (yaw - from) / step + 1; // 1-based like Lua
  if (pos <= 1) return values[0];
  if (pos >= n) return values[n - 1];
  const i = Math.floor(pos);
  return values[i - 1] + (values[i] - values[i - 1]) * (pos - i);
}
function calibrate(ds) {
  const sums = {}, counts = {};
  for (const d of ds) {
    const bin = Math.floor((d.yaw - FROM) / STEP + 0.5) + 1;
    if (bin < 1 || bin > BINS) continue;
    sums[bin] = sums[bin] || { pitch: 0, roll: 0, x: 0, y: 0, z: 0 };
    for (const k of CH) sums[bin][k] += d[k];
    counts[bin] = (counts[bin] || 0) + 1;
  }
  let lo, hi;
  for (let i = 1; i <= BINS; i++) if ((counts[i] || 0) >= 3) { lo = lo || i; hi = i; }
  const result = { from: FROM, step: STEP, reach: [FROM + (lo - 1) * STEP, FROM + (hi - 1) * STEP] };
  for (const k of CH) {
    const raw = {}; let last = null;
    for (let i = lo; i <= hi; i++) {
      const c = counts[i] || 0;
      if (c >= 3) {
        raw[i] = sums[i][k] / c;
        for (let j = (last ?? i) + 1; j <= i - 1; j++) raw[j] = raw[last] + (raw[i] - raw[last]) * (j - last) / (i - last);
        last = i;
      }
    }
    const values = [];
    for (let i = 1; i <= BINS; i++) {
      const c = Math.min(Math.max(i, lo), hi);
      values.push((raw[Math.max(c - 1, lo)] + 2 * raw[c] + raw[Math.min(c + 1, hi)]) / 4);
    }
    const zero = lookup(values, FROM, STEP, 0);
    result[k] = values.map(v => v - zero);
  }
  return result;
}
const correct = (d, cal) => {
  const out = { yaw: d.yaw };
  for (const k of CH) out[k] = d[k] - lookup(cal[k], cal.from, cal.step, d.yaw) * S.turnCorrection;
  return out;
};

// --- stillness.lua
function makeStillness() {
  const ch = {};
  const filter = (key, value, threshold, dt) => {
    const c = ch[key];
    if (!c || threshold <= 0) { ch[key] = { held: value, moving: false, slack: 0, anchor: value, stillFor: 0 }; return value; }
    if (c.moving) {
      c.slack *= Math.exp(-dt / 0.1);
      c.held = value - c.slack;
      if (Math.abs(value - c.anchor) > threshold * 0.5) { c.anchor = value; c.stillFor = 0; }
      else { c.stillFor += dt; if (c.stillFor >= 0.3) c.moving = false; }
    } else if (Math.abs(value - c.held) > threshold) {
      c.moving = true; c.slack = value - c.held; c.anchor = value; c.stillFor = 0;
    }
    return c.held;
  };
  return (d, dt) => {
    const out = {};
    for (const k of ['yaw', 'pitch', 'roll']) out[k] = filter(k, d[k], S.rotation[k].threshold, dt);
    for (const k of ['x', 'y', 'z']) out[k] = filter(k, d[k], S.position[k].threshold, dt);
    return out;
  };
}

// --- run
const cal = calibrate(frames.filter(f => f.t >= 8000 && f.t < 20000).map(deltas));
console.log(`calibrated on turns 8-20 s: reach ${cal.reach[0]} .. ${cal.reach[1]} deg`);
console.log('table at head yaw -20 / -10 / +10 / +20:');
for (const k of CH) console.log(`  ${k.padEnd(6)} ${[-20, -10, 10, 20].map(y => lookup(cal[k], FROM, STEP, y).toFixed(2).padStart(7)).join(' ')}   ${k === 'pitch' || k === 'roll' ? 'deg' : 'cm'}`);

const still = makeStillness();
const test = frames.filter(f => f.t >= 0);
const out = test.map(f => {
  const d = deltas(f);
  const oldCam = camera(d, true);
  const newCam = camera(still(correct(d, cal), f.dt), false);
  return { t: f.t, d, oldCam, newCam };
});

// Camera pitch / forward-back / up against camera yaw, on the held-out turns.
const bins = new Map();
for (const o of out.filter(o => o.t >= 20000 && o.t < 31500)) {
  const b = Math.round(o.oldCam.yaw / 15) * 15;
  if (!bins.has(b)) bins.set(b, []);
  bins.get(b).push(o);
}
const avg = (a, f) => a.reduce((s, o) => s + f(o), 0) / a.length;
console.log('\ncamera, held-out turns 20-31 s:  cam yaw | pitch deg old -> new | fwd/back cm old -> new | up cm old -> new');
for (const b of [...bins.keys()].sort((p, q) => p - q)) {
  const a = bins.get(b);
  if (a.length < 8) continue;
  console.log(`  ${String(b).padStart(5)} (${String(a.length).padStart(4)})  ${avg(a, o => o.oldCam.pitch).toFixed(1).padStart(6)} -> ${avg(a, o => o.newCam.pitch).toFixed(1).padStart(5)}   ${avg(a, o => o.oldCam.fwd).toFixed(1).padStart(6)} -> ${avg(a, o => o.newCam.fwd).toFixed(1).padStart(5)}   ${avg(a, o => o.oldCam.up).toFixed(1).padStart(5)} -> ${avg(a, o => o.newCam.up).toFixed(1).padStart(5)}`);
}

// Stillness: camera wobble in quiet 1.5 s windows (raw head yaw within 3 deg), anywhere you look.
const wob = { old: [], new: [] };
for (let i = out.findIndex(o => o.t >= 32000); i < out.length; i += 5) {
  const win = out.filter(o => o.t >= out[i].t && o.t < out[i].t + 1500);
  const rawY = rows.filter(r => r.t >= out[i].t && r.t < out[i].t + 1500).map(r => r.yaw);
  if (win.length < 30 || Math.max(...rawY) - Math.min(...rawY) > 3) continue;
  const pp = (f) => Math.max(...win.map(f)) - Math.min(...win.map(f));
  wob.old.push(Math.hypot(pp(o => o.oldCam.yaw), pp(o => o.oldCam.pitch)));
  wob.new.push(Math.hypot(pp(o => o.newCam.yaw), pp(o => o.newCam.pitch)));
}
const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(s.length * p))]; };
console.log(`\ncamera wobble while holding still (${wob.old.length} windows), deg: median old ${pct(wob.old, 0.5).toFixed(2)} new ${pct(wob.new, 0.5).toFixed(2)} | 90th pct old ${pct(wob.old, 0.9).toFixed(2)} new ${pct(wob.new, 0.9).toFixed(2)}`);

// Following: how far the new camera yaw trails the head once moving (deg of camera).
let worstTrail = 0, sumTrail = 0, nTrail = 0;
for (const o of out) {
  if (Math.abs(o.d.yaw) < 3) continue;
  const exact = shape(o.d.yaw, S.rotation.yaw);
  const trail = Math.abs(exact - o.newCam.yaw);
  worstTrail = Math.max(worstTrail, trail); sumTrail += trail; nTrail++;
}
console.log(`camera yaw vs head while turned (>3 deg): mean gap ${(sumTrail / nTrail).toFixed(2)} deg, worst ${worstTrail.toFixed(2)} deg`);

