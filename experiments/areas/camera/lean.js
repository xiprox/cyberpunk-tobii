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

const conj = q => ({ i: -q.i, j: -q.j, k: -q.k, r: q.r });
// Mirrors camera.lua leanShift.
function leanShift(base, axis, o, lean, follows) {
  if (follows === 1) return lean;
  let view = axisAngle(axis.x, axis.y, axis.z, o.yaw);
  if (follows === 3) view = mul(view, axisAngle(1, 0, 0, o.pitch));
  return rotate(base, rotate(view, rotate(conj(base), lean)));
}
const cm = v => `right ${(v.x * 100).toFixed(1).padStart(6)}  forward ${(v.y * 100).toFixed(1).padStart(6)}  up ${(v.z * 100).toFixed(1).padStart(6)} cm`;
const I = { i: 0, j: 0, k: 0, r: 1 }, UP = { x: 0, y: 0, z: 1 };
const fwd = { x: 0, y: 0.1, z: 0 }, left = { x: -0.1, y: 0, z: 0 };
console.log('lean forward 10 cm, looking right 90:   toward screen   ' + cm(leanShift(I, UP, { yaw: -90, pitch: 0 }, fwd, 1)));
console.log('                                        follow turning  ' + cm(leanShift(I, UP, { yaw: -90, pitch: 0 }, fwd, 2)));
console.log('lean left 10 cm, looking right 90:      follow turning  ' + cm(leanShift(I, UP, { yaw: -90, pitch: 0 }, left, 2)));
console.log('lean forward, looking right 45 + down 30: turning only  ' + cm(leanShift(I, UP, { yaw: -45, pitch: -30 }, fwd, 2)));
console.log('                                        turning + pitch ' + cm(leanShift(I, UP, { yaw: -45, pitch: -30 }, fwd, 3)));
const base = axisAngle(1, 0, 0, -10), axis = rotate(conj(base), UP);
console.log('game camera pitched 10 down, lean forward, look right 90 (should stay level): ' + cm(leanShift(base, axis, { yaw: -90, pitch: 0 }, fwd, 2)));
