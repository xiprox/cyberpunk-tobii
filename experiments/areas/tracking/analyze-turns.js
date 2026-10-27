// How pitch, roll and position move with yaw in a tobii_probe recording.
//   node analyze-turns.js file.csv
const fs = require('fs');
const lines = fs.readFileSync(process.argv[2], 'utf8').trim().split(/\r?\n/).slice(1);
const rows = lines.map(l => l.split(',').map(Number))
  .map(([t, yaw, pitch, roll, x, y, z, rok, pok]) => ({ t, yaw, pitch, roll, x, y, z, ok: rok && pok }))
  .filter(r => r.ok);
const median = a => { const s = [...a].sort((p, q) => p - q); return s[Math.floor(s.length / 2)]; };

console.log(`${rows.length} valid samples over ${(rows[rows.length - 1].t / 1000).toFixed(1)} s`);
const yaws = rows.map(r => r.yaw);
console.log(`yaw range ${Math.min(...yaws).toFixed(1)} .. ${Math.max(...yaws).toFixed(1)}`);

// Rest pose: samples with |yaw - median yaw| small and slow, from the quiet start.
const start = rows.filter(r => r.t < 2500);
const c = {};
for (const k of ['yaw', 'pitch', 'roll', 'x', 'y', 'z']) c[k] = median(start.map(r => r[k]));
console.log('rest pose (first 2.5 s):', Object.entries(c).map(([k, v]) => `${k} ${v.toFixed(2)}`).join('  '));

// Average each channel in yaw bins relative to rest.
const BIN = 5;
const bins = new Map();
for (const r of rows) {
  const b = Math.round((r.yaw - c.yaw) / BIN) * BIN;
  if (!bins.has(b)) bins.set(b, []);
  bins.get(b).push(r);
}
console.log('\n dyaw   n   dpitch   droll     dx      dy      dz   (deg / mm, relative to rest)');
for (const b of [...bins.keys()].sort((p, q) => p - q)) {
  const rs = bins.get(b);
  if (rs.length < 5) continue;
  const m = k => rs.reduce((s, r) => s + r[k], 0) / rs.length - c[k];
  console.log(`${String(b).padStart(5)} ${String(rs.length).padStart(4)} ${m('pitch').toFixed(2).padStart(8)} ${m('roll').toFixed(2).padStart(7)} ${m('x').toFixed(1).padStart(7)} ${m('y').toFixed(1).padStart(7)} ${m('z').toFixed(1).padStart(7)}`);
}

// Fit each channel against yaw as a + b*yaw + c*|yaw| + d*yaw^2 near center (|dyaw| < 30) to tell
// a V (|yaw| term) from a U (yaw^2 term).
function fit(k) {
  const pts = rows.filter(r => Math.abs(r.yaw - c.yaw) < 30).map(r => [r.yaw - c.yaw, r[k] - c[k]]);
  const f = y => [1, y, Math.abs(y), y * y];
  const n = 4, A = Array.from({ length: n }, () => Array(n).fill(0)), B = Array(n).fill(0);
  for (const [yw, v] of pts) { const fv = f(yw); for (let i = 0; i < n; i++) { B[i] += fv[i] * v; for (let j = 0; j < n; j++) A[i][j] += fv[i] * fv[j]; } }
  for (let i = 0; i < n; i++) { let p = i; for (let r = i + 1; r < n; r++) if (Math.abs(A[r][i]) > Math.abs(A[p][i])) p = r;
    [A[i], A[p]] = [A[p], A[i]]; [B[i], B[p]] = [B[p], B[i]];
    for (let r = 0; r < n; r++) if (r !== i) { const q = A[r][i] / A[i][i]; for (let j = i; j < n; j++) A[r][j] -= q * A[i][j]; B[r] -= q * B[i]; } }
  return B.map((v, i) => v / A[i][i]);
}
console.log('\nfit near center (|dyaw| < 30):  value = a + b*dyaw + c*|dyaw| + d*dyaw^2');
for (const k of ['pitch', 'roll', 'x', 'y', 'z']) {
  const [a, b, cc, d] = fit(k);
  console.log(`${k.padEnd(6)} a ${a.toFixed(2).padStart(7)}  b ${b.toFixed(3).padStart(7)}  c(|yaw|) ${cc.toFixed(3).padStart(7)}  d(yaw^2) ${d.toFixed(4).padStart(8)}   at 20 deg: ${(b * 20 + cc * 20 + d * 400).toFixed(2)} / ${(-b * 20 + cc * 20 + d * 400).toFixed(2)}`);
}
