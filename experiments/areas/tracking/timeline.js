const fs = require('fs');
const rows = fs.readFileSync(process.argv[2], 'utf8').trim().split(/\r?\n/).slice(1).map(l => l.split(',').map(Number)).filter(r => r[7]);
let out = [];
for (let s = 0; s < 122; s += 2) {
  const w = rows.filter(r => r[0] >= s * 1000 && r[0] < (s + 2) * 1000);
  if (!w.length) continue;
  const y = w.map(r => r[1]), p = w.map(r => r[2]), z = w.map(r => r[6]);
  const mn = Math.min(...y), mx = Math.max(...y);
  out.push(`${String(s).padStart(3)}s yaw ${mn.toFixed(0).padStart(4)}..${mx.toFixed(0).padStart(4)}  pitch ${(p.reduce((a, b) => a + b) / p.length).toFixed(1).padStart(5)} (${Math.min(...p).toFixed(1)}..${Math.max(...p).toFixed(1)})  z ${(z.reduce((a, b) => a + b) / z.length).toFixed(0)}`);
}
console.log(out.join('\n'));
