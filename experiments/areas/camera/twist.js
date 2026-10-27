// Mirrors camera.lua softClamp + neckShift (with twist) and walks the eyes through a full turn.
const rad = d => d * Math.PI / 180;
const axisAngle = (x, y, z, d) => { const h = rad(d) / 2, s = Math.sin(h); return { i: x * s, j: y * s, k: z * s, r: Math.cos(h) }; };
const mul = (a, b) => ({
  i: a.r * b.i + a.i * b.r + a.j * b.k - a.k * b.j, j: a.r * b.j - a.i * b.k + a.j * b.r + a.k * b.i,
  k: a.r * b.k + a.i * b.j - a.j * b.i + a.k * b.r, r: a.r * b.r - a.i * b.i - a.j * b.j - a.k * b.k });
const rotate = (q, v) => {
  const tx = 2 * (q.j * v.z - q.k * v.y), ty = 2 * (q.k * v.x - q.i * v.z), tz = 2 * (q.i * v.y - q.j * v.x);
  return { x: v.x + q.r * tx + (q.j * tz - q.k * ty), y: v.y + q.r * ty + (q.k * tx - q.i * tz), z: v.z + q.r * tz + (q.i * ty - q.j * tx) };
};
const dot = (a, b) => a.x * b.x + a.y * b.y + a.z * b.z;
const scaled = (v, s) => ({ x: v.x * s, y: v.y * s, z: v.z * s });
const conj = q => ({ i: -q.i, j: -q.j, k: -q.k, r: q.r });
function softClamp(v, limit, blend) {
  blend = Math.min(blend, limit);
  const a = Math.abs(v), lo = limit - blend;
  if (a <= lo) return v;
  let out = limit;
  if (a < limit + blend) out = a - (a - lo) * (a - lo) / (4 * blend);
  return v < 0 ? -out : out;
}
function neckShift(base, turnAxis, o, yaw, neck) {
  const eyes = neck.eyes, moved = rotate(o, eyes);
  const shift = { x: moved.x - eyes.x, y: moved.y - eyes.y, z: moved.z - eyes.z };
  const twist = neck.twist;
  const torso = twist ? yaw - softClamp(yaw, twist.limit, 15) : 0;
  if (torso !== 0) {
    const u = turnAxis;
    let forward = { x: -u.y * u.x, y: 1 - u.y * u.y, z: -u.y * u.z };
    forward = scaled(forward, 1 / Math.sqrt(dot(forward, forward)));
    const spin = axisAngle(u.x, u.y, u.z, torso);
    const spine = scaled(forward, -twist.spineBehind), swung = rotate(spin, spine);
    let swing = { x: spine.x - swung.x, y: spine.y - swung.y, z: spine.z - swung.z };
    let lean = scaled(forward, twist.lean * Math.abs(torso) / 45);
    if (twist.seated) { const back = dot(swing, forward); if (back < 0) swing = { x: swing.x - forward.x * back, y: swing.y - forward.y * back, z: swing.z - forward.z * back }; }
    else lean = rotate(spin, lean);
    shift.x += swing.x + lean.x; shift.y += swing.y + lean.y; shift.z += swing.z + lean.z;
  }
  return rotate(base, shift);
}
const I = { i: 0, j: 0, k: 0, r: 1 }, UP = { x: 0, y: 0, z: 1 };
const neckOnly = { eyes: { x: 0, y: 0.08, z: 0.075 } };
const withTwist = { eyes: neckOnly.eyes, twist: { limit: 85, spineBehind: 0.04, lean: 0.08 } };
const seated = { eyes: neckOnly.eyes, twist: { limit: 85, spineBehind: 0.04, lean: 0.08, seated: true } };
const f = v => `${(v.x * 100).toFixed(1).padStart(6)} ${(v.y * 100).toFixed(1).padStart(6)} ${(v.z * 100).toFixed(1).padStart(5)}`;
console.log('turn left | neck only (right fwd up cm) | twist on foot (right fwd up cm) | twist in car seat | neck / torso');
for (let yaw = 0; yaw <= 135; yaw += 15) {
  const o = axisAngle(0, 0, 1, yaw), neckPart = softClamp(yaw, 85, 15);
  console.log(`${String(yaw).padStart(5)}     | ${f(neckShift(I, UP, o, yaw, neckOnly))}        | ${f(neckShift(I, UP, o, yaw, withTwist))}            | ${f(neckShift(I, UP, o, yaw, seated))} | ${neckPart.toFixed(0)} / ${(yaw - neckPart).toFixed(0)}`);
}
// Smoothness: biggest eye movement per 0.5 deg of turn, and biggest change in that rate.
let maxStep = 0, maxKink = 0, prev = null, prevStep = null;
for (let yaw = -135; yaw <= 135; yaw += 0.5) {
  const p = neckShift(I, UP, axisAngle(0, 0, 1, yaw), yaw, withTwist);
  if (prev) {
    const step = { x: p.x - prev.x, y: p.y - prev.y, z: p.z - prev.z }, len = Math.sqrt(dot(step, step));
    maxStep = Math.max(maxStep, len);
    if (prevStep) maxKink = Math.max(maxKink, Math.sqrt(dot({ x: step.x - prevStep.x, y: step.y - prevStep.y, z: step.z - prevStep.z }, { x: step.x - prevStep.x, y: step.y - prevStep.y, z: step.z - prevStep.z })));
    prevStep = step;
  }
  prev = p;
}
console.log(`\nwhole turn -135..135: biggest eye move per 0.5 deg ${(maxStep * 1000).toFixed(2)} mm, biggest change in that ${(maxKink * 1000).toFixed(3)} mm (no jumps if tiny)`);
const r = neckShift(I, UP, axisAngle(0, 0, 1, -135), -135, withTwist), l = neckShift(I, UP, axisAngle(0, 0, 1, 135), 135, withTwist);
console.log(`mirror check at +-135: left ${f(l)} | right ${f(r)}`);
const base = axisAngle(1, 0, 0, -10), axis = rotate(conj(base), UP);
console.log(`game camera pitched 10 down, turn left 135: ${f(neckShift(base, axis, axisAngle(axis.x, axis.y, axis.z, 135), 135, withTwist))} (twist part should stay level)`);

