// Jitter at rest after the plugin's One Euro filter, to pick stillness thresholds.
//   node noise.js file.csv minCutoff beta
const fs = require('fs');
const [file, minCutoff = 0.4, beta = 0.4] = process.argv.slice(2);
const rows = fs.readFileSync(file, 'utf8').trim().split(/\r?\n/).slice(1).map(l => l.split(',').map(Number))
  .filter(r => r[7] && r[8]).map(([t, yaw, pitch, roll, x, y, z]) => ({ t, yaw, pitch, roll, x: x / 10, y: y / 10, z: z / 10 }));
const KEYS = ['yaw', 'pitch', 'roll', 'x', 'y', 'z'];
const alpha = (hz, dt) => 1 / (1 + 1 / (2 * Math.PI * hz) / dt);
const state = {};
let lastT = null;
const smoothed = rows.map(r => {
  const dt = lastT === null ? 0.03 : (r.t - lastT) / 1000; lastT = r.t;
  const out = { t: r.t };
  for (const k of KEYS) {
    let s = state[k];
    if (!s) { s = state[k] = { v: r[k], d: 0 }; out[k] = r[k]; continue; }
    const d = (r[k] - s.v) / dt;
    s.d += alpha(1, dt) * (d - s.d);
    s.v += alpha(Number(minCutoff) + Number(beta) * Math.abs(s.d), dt) * (r[k] - s.v);
    out[k] = s.v;
  }
  return out;
});
// Quiet windows: 1.5 s stretches where raw yaw stays within 3 degrees.
const W = 1500;
const pp = Object.fromEntries(KEYS.map(k => [k, []]));
for (let i = 0; i < smoothed.length; i += 10) {
  const win = smoothed.filter(r => r.t >= smoothed[i].t && r.t < smoothed[i].t + W);
  const rawWin = rows.filter(r => r.t >= smoothed[i].t && r.t < smoothed[i].t + W);
  if (win.length < 30) continue;
  const yaws = rawWin.map(r => r.yaw);
  if (Math.max(...yaws) - Math.min(...yaws) > 3) continue;
  for (const k of KEYS) { const v = win.map(r => r[k]); pp[k].push(Math.max(...v) - Math.min(...v)); }
}
const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(s.length * p))]; };
console.log(`smoothing minCutoff ${minCutoff} beta ${beta}; ${pp.yaw.length} quiet 1.5 s windows`);
console.log('peak-to-peak while still (deg / cm):   median    90th pct');
for (const k of KEYS) console.log(`  ${k.padEnd(6)} ${pct(pp[k], 0.5).toFixed(2).padStart(30)} ${pct(pp[k], 0.9).toFixed(2).padStart(10)}`);
