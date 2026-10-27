// The user's complaint, simulated: look left, hold, nudge ~1 deg further, hold, nudge again...
// Head path + real jitter from the recording -> plugin One Euro (33 Hz) + 35 ms blend -> 60 fps
// filter -> x3 camera. Then the same filters on the real recorded turns for lag.
//   node nudge.js recording.csv
const fs = require('fs');
const rec = fs.readFileSync(process.argv[2], 'utf8').trim().split(/\r?\n/).slice(1).map(l => l.split(',').map(Number))
  .filter(r => r[7] && r[8]).map(([t, yaw]) => ({ t, yaw }));
const SENS = 3, SIZE = 0.75;

// Jitter: a still stretch of the recording (40-70 s) minus its own slow trend.
const still = rec.filter(r => r.t >= 40000 && r.t < 70000);
const jitter = still.map((r, i) => {
  const w = still.slice(Math.max(0, i - 15), i + 16);
  return r.yaw - w.reduce((s, x) => s + x.yaw, 0) / w.length;
});

// Head yaw path (deg) over time (s).
const phases = [[0, 0], [0.6, 20], [2.6, 20], [2.9, 21], [4.4, 21], [4.7, 22], [6.2, 22], [6.6, 20], [8.1, 20], [8.3, 21], [10, 21]];
const path = t => { for (let i = 1; i < phases.length; i++) if (t <= phases[i][0]) { const [t0, a] = phases[i - 1], [t1, b] = phases[i]; const f = (t - t0) / (t1 - t0); return a + (b - a) * (f * f * (3 - 2 * f)); } return phases[phases.length - 1][1]; };
const synth = [];
for (let i = 0, t = 0; t < 10; i++, t += 0.0302) synth.push({ t: t * 1000, yaw: path(t) + jitter[i % jitter.length] });

function plugin(samples, minCutoff, beta) {
  const alpha = (hz, dt) => 1 / (1 + 1 / (2 * Math.PI * hz) / dt);
  let s = null, lastT = null;
  const sm = samples.map(r => {
    const dt = lastT === null ? 0.03 : (r.t - lastT) / 1000; lastT = r.t;
    if (!s) { s = { v: r.yaw, d: 0 }; return { t: r.t, yaw: r.yaw }; }
    s.d += alpha(1, dt) * ((r.yaw - s.v) / dt - s.d);
    s.v += alpha(minCutoff + beta * Math.abs(s.d), dt) * (r.yaw - s.v);
    return { t: r.t, yaw: s.v };
  });
  const out = []; let j = 0;
  for (let t = sm[0].t + 35; t < sm[sm.length - 1].t; t += 1000 / 60) {
    const at = t - 35;
    while (j < sm.length - 2 && sm[j + 1].t < at) j++;
    const a = sm[j], b = sm[j + 1], f = Math.min(Math.max((at - a.t) / (b.t - a.t), 0), 1);
    out.push({ t, yaw: a.yaw + (b.yaw - a.yaw) * f });
  }
  return out;
}

const filters = {
  'deadzone 0.5 (old)': () => v => Math.sign(v) * Math.max(Math.abs(v) - 0.5, 0),
  'stillness gate (current)': () => { let c = null; return (v, dt) => {
    if (!c) { c = { held: v, moving: false, slack: 0, anchor: v, stillFor: 0 }; return v; }
    if (c.moving) { c.slack *= Math.exp(-dt / 0.1); c.held = v - c.slack;
      if (Math.abs(v - c.anchor) > SIZE * 0.5) { c.anchor = v; c.stillFor = 0; } else if ((c.stillFor += dt) >= 0.3) c.moving = false; }
    else if (Math.abs(v - c.held) > SIZE) { c.moving = true; c.slack = v - c.held; c.anchor = v; c.stillFor = 0; }
    else c.held += (v - c.held) * (1 - Math.exp(-dt / 3));
    return c.held; }; },
  'follower (gap-based)': () => { let o = null; return (v, dt) => {
    if (o === null) return (o = v); const r = Math.abs(v - o) / SIZE;
    o += (v - o) * (1 - Math.exp(-dt / (0.02 + 0.98 / (1 + r ** 4)))); return o; }; },
  'slack 0.4': () => slack(0.4, 0),
  'slack 0.4 + settle 0.5 s': () => slack(0.4, 0.5),
  'slack 0.6 + settle 0.5 s': () => slack(0.6, 0.5),
  'slack 0.4 + settle 1 s': () => slack(0.4, 1.0),
  'slack 0.4 + moving settle 1deg': () => slackMove(0.4, 1.0),
  'slack 0.4 + moving settle 0.5deg': () => slackMove(0.4, 0.5),
  'slack 0.3 + moving settle 0.5deg': () => slackMove(0.3, 0.5),
  'slack 0.5 + moving settle 0.5deg': () => slackMove(0.5, 0.5),
};
// Slack (backlash): the camera only moves when the head pushes past the edge of a band around it,
// and then exactly as fast as the head. Optional settle eases the leftover slack out once the head
// slows down, so the camera ends up where you're looking. Settle speed is capped below head speed.
function slack(width, settle) {
  let o = null, prev = null;
  return (v, dt) => {
    if (o === null) { prev = v; return (o = v); }
    let e = v - o;
    if (e > width) o = v - width; else if (e < -width) o = v + width;
    if (settle > 0) o += (v - o) * (1 - Math.exp(-dt / settle));
    prev = v;
    return o;
  };
}

// Leftover slack is taken up only as the head moves: per degree of head movement, 1/settleDeg of it.
function slackMove(width, settleDeg) {
  let o = null, prev = null;
  return (v) => {
    if (o === null) { prev = v; return (o = v); }
    const e = v - o;
    if (e > width) o = v - width; else if (e < -width) o = v + width;
    o += (v - o) * Math.min(1, Math.abs(v - prev) / settleDeg);
    prev = v;
    return o;
  };
}

function run(minCutoff, beta) {
  console.log(`\n=== plugin smoothing: steadiness ${minCutoff}, responsiveness ${beta} ===`);
  const syn = plugin(synth, minCutoff, beta);
  const recd = plugin(rec, minCutoff, beta);
  console.log('nudge test (camera deg): biggest single-frame move during the nudges, back-and-forth shake while holding, how far the camera is off after each hold');
  for (const [name, make] of Object.entries(filters)) {
    const f = make();
    let maxStep = 0, maxHeadStep = 0, prevO = null, prevV = null;
    const holdErr = [], holdWob = [];
    const holds = [[2.0, 2.6], [3.8, 4.4], [5.6, 6.2], [7.5, 8.1], [9.4, 10]];
    const traj = syn.map((fr, i) => {
      const dt = i ? (fr.t - syn[i - 1].t) / 1000 : 1 / 60;
      const o = f(fr.yaw, dt) * SENS, v = fr.yaw * SENS;
      if (fr.t > 2200 && prevO !== null) { maxStep = Math.max(maxStep, Math.abs(o - prevO)); maxHeadStep = Math.max(maxHeadStep, Math.abs(v - prevV)); }
      prevO = o; prevV = v;
      return { t: fr.t / 1000, o, target: path(fr.t / 1000 - 0.035) * SENS };
    });
    for (const [a, b] of holds) {
      const w = traj.filter(p => p.t >= a && p.t < b);
      let len = 0; for (let k = 1; k < w.length; k++) len += Math.abs(w[k].o - w[k - 1].o); holdWob.push(len - Math.abs(w[w.length - 1].o - w[0].o));
      holdErr.push(Math.abs(w[w.length - 1].o - w[w.length - 1].target));
    }
    // Real turns: rms error vs unfiltered camera, and best time shift.
    const g = make(); const cam = recd.map((fr, i) => ({ o: g(fr.yaw, i ? (fr.t - recd[i - 1].t) / 1000 : 1 / 60) * SENS, e: fr.yaw * SENS, t: fr.t }))
      .filter(c => c.t >= 8000 && c.t < 31000);
    let best = 0, bestErr = Infinity;
    for (let s = 0; s <= 20; s++) { let err = 0; for (let i = s; i < cam.length; i++) err += (cam[i].o - cam[i - s].e) ** 2; err /= cam.length - s; if (err < bestErr) { bestErr = err; best = s; } }
    console.log(`  ${name.padEnd(26)} step ${maxStep.toFixed(2).padStart(5)} (head ${maxHeadStep.toFixed(2)})  shake ${holdWob.map(x => x.toFixed(2)).join(' ')}  off ${holdErr.map(x => x.toFixed(1)).join(' ')}   turns: lag ${(best * 1000 / 60).toFixed(0).padStart(3)} ms`);
  }
}
run(0.4, 0.4);
run(1.0, 0.4);
console.log('\nOne Euro alone, stronger (no extra filter):');
for (const [mc, b] of [[0.15, 1.0], [0.1, 2.0]]) {
  const syn = plugin(synth, mc, b);
  const holds = [[2.0, 2.6], [3.8, 4.4], [5.6, 6.2], [7.5, 8.1], [9.4, 10]];
  const w = holds.map(([a, bb]) => { const s = syn.filter(p => p.t / 1000 >= a && p.t / 1000 < bb).map(p => p.yaw * SENS); return (Math.max(...s) - Math.min(...s)).toFixed(2); });
  let maxStep = 0; for (let i = 1; i < syn.length; i++) if (syn[i].t > 2200) maxStep = Math.max(maxStep, Math.abs(syn[i].yaw - syn[i - 1].yaw) * SENS);
  const recd = plugin(rec, mc, b).filter(c => c.t >= 8000 && c.t < 31000), raw = plugin(rec, 50, 0).filter(c => c.t >= 8000 && c.t < 31000);
  let best = 0, bestErr = Infinity;
  for (let s = 0; s <= 20; s++) { let err = 0; for (let i = s; i < Math.min(recd.length, raw.length); i++) err += (recd[i].yaw - raw[i - s].yaw) ** 2; if (err < bestErr) { bestErr = err; best = s; } }
  console.log(`  steadiness ${mc} responsiveness ${b}   step ${maxStep.toFixed(2)}  wobble ${w.join(' ')}   turns: lag ${(best * 1000 / 60).toFixed(0)} ms more than light smoothing`);
}

