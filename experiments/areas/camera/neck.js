// Mirrors camera.lua's neckShift and checks the eyes move the way a real head's would.
const rad = d => d * Math.PI / 180;
const axisAngle = (x, y, z, d) => { const h = rad(d) / 2, s = Math.sin(h); return { i: x * s, j: y * s, k: z * s, r: Math.cos(h) }; };
const mul = (a, b) => ({
  i: a.r * b.i + a.i * b.r + a.j * b.k - a.k * b.j, j: a.r * b.j - a.i * b.k + a.j * b.r + a.k * b.i,
  k: a.r * b.k + a.i * b.j - a.j * b.i + a.k * b.r, r: a.r * b.r - a.i * b.i - a.j * b.j - a.k * b.k });
const rotate = (q, v) => {
  const tx = 2 * (q.j * v.z - q.k * v.y), ty = 2 * (q.k * v.x - q.i * v.z), tz = 2 * (q.i * v.y - q.j * v.x);
  return { x: v.x + q.r * tx + (q.j * tz - q.k * ty), y: v.y + q.r * ty + (q.k * tx - q.i * tz), z: v.z + q.r * tz + (q.i * ty - q.j * tx) };
};
const offsetRotation = (o, a) => mul(mul(axisAngle(a.x, a.y, a.z, o.yaw), axisAngle(1, 0, 0, o.pitch)), axisAngle(0, 1, 0, o.roll));
const neckShift = (base, o, neck) => { const m = rotate(o, neck); return rotate(base, { x: m.x - neck.x, y: m.y - neck.y, z: m.z - neck.z }); };

const neck = { x: 0, y: 0.08, z: 0.075 };
const UP = { x: 0, y: 0, z: 1 };
const cm = v => `right ${(v.x * 100).toFixed(1).padStart(6)}  forward ${(v.y * 100).toFixed(1).padStart(6)}  up ${(v.z * 100).toFixed(1).padStart(6)} cm`;
const cases = [
  ['turn left 60', { yaw: 60, pitch: 0, roll: 0 }], ['turn right 60', { yaw: -60, pitch: 0, roll: 0 }],
  ['turn left 135 (look behind)', { yaw: 135, pitch: 0, roll: 0 }], ['look down 30', { yaw: 0, pitch: -30, roll: 0 }],
  ['look up 30', { yaw: 0, pitch: 30, roll: 0 }], ['tilt (roll) 20', { yaw: 0, pitch: 0, roll: 20 }],
];
console.log('base camera level:');
for (const [n, o] of cases) console.log(`  ${n.padEnd(28)} ${cm(neckShift({ i: 0, j: 0, k: 0, r: 1 }, offsetRotation(o, UP), neck))}`);
// Game camera pitched 10 down in its local orientation; level turn axis = base^-1 * up.
const base = axisAngle(1, 0, 0, -10), inv = { i: -base.i, j: -base.j, k: -base.k, r: base.r };
const axis = rotate(inv, UP);
console.log('base camera pitched 10 down (parent-frame result; turning should stay horizontal):');
for (const [n, o] of cases.slice(0, 2)) console.log(`  ${n.padEnd(28)} ${cm(neckShift(base, offsetRotation(o, axis), neck))}`);
