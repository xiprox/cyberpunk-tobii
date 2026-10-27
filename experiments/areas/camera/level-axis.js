// Mirrors camera.lua's level-turn math and simulates the camera to check it.
const rad = d => d * Math.PI / 180, deg = r => r * 180 / Math.PI;
const axisAngle = (x, y, z, d) => { const h = rad(d) / 2, s = Math.sin(h); return { i: x * s, j: y * s, k: z * s, r: Math.cos(h) }; };
const mul = (a, b) => ({
  i: a.r * b.i + a.i * b.r + a.j * b.k - a.k * b.j,
  j: a.r * b.j - a.i * b.k + a.j * b.r + a.k * b.i,
  k: a.r * b.k + a.i * b.j - a.j * b.i + a.k * b.r,
  r: a.r * b.r - a.i * b.i - a.j * b.j - a.k * b.k,
});
const rotate = (q, v) => {
  const tx = 2 * (q.j * v.z - q.k * v.y), ty = 2 * (q.k * v.x - q.i * v.z), tz = 2 * (q.i * v.y - q.j * v.x);
  return { x: v.x + q.r * tx + (q.j * tz - q.k * ty), y: v.y + q.r * ty + (q.k * tx - q.i * tz), z: v.z + q.r * tz + (q.i * ty - q.j * tx) };
};
const dot = (a, b) => a.x * b.x + a.y * b.y + a.z * b.z;
const cross = (a, b) => ({ x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x });
const UP = { x: 0, y: 0, z: 1 }, IDENTITY = { i: 0, j: 0, k: 0, r: 1 };
const offsetRotation = (o, a) => mul(mul(axisAngle(a.x, a.y, a.z, o.yaw), axisAngle(1, 0, 0, o.pitch)), axisAngle(0, 1, 0, o.roll));

function run(name, { car, outer, base, lag, frames = 240, headYaw, headPitch = () => 0, mode = 'car' }) {
  let inEffect = IDENTITY, turnAxis = UP, applied = false;
  const history = [IDENTITY, IDENTITY]; // offsets the camera showed in earlier frames
  let worst = 0, last;
  for (let n = 0; n < frames; n++) {
    const dt = 1 / 60;
    // What the camera system reports: last drawn view, with the offset from 1 (or 2 if lagging) frames ago.
    const shown = lag ? history[0] : history[1];
    const W = mul(mul(mul(car, outer), base), shown);
    const right = rotate(W, { x: 1, y: 0, z: 0 }), forward = rotate(W, { x: 0, y: 1, z: 0 });
    // measureAxis
    const reference = mode === 'car' ? car : IDENTITY;
    const up = cross(right, forward), levelUp = rotate(reference, UP);
    const measured = rotate(inEffect, { x: dot(levelUp, right), y: dot(levelUp, forward), z: dot(levelUp, up) });
    let len = Math.sqrt(dot(measured, measured));
    if (len >= 0.5 && measured.z / len >= 0.2) {
      const q1 = history[1], q2 = history[0]; const d = Math.abs(q1.i*q2.i + q1.j*q2.j + q1.k*q2.k + q1.r*q2.r); const moved = deg(2 * Math.acos(Math.min(d, 1))); const t = applied ? (1 - Math.exp(-dt / 0.08)) / (1 + moved) : 1;
      const b = { x: turnAxis.x + (measured.x / len - turnAxis.x) * t, y: turnAxis.y + (measured.y / len - turnAxis.y) * t, z: turnAxis.z + (measured.z / len - turnAxis.z) * t };
      len = Math.sqrt(dot(b, b));
      turnAxis = { x: b.x / len, y: b.y / len, z: b.z / len };
    }
    const o = { yaw: headYaw(n), pitch: headPitch(n), roll: 0 };
    const O = offsetRotation(o, turnAxis);
    inEffect = O; applied = true;
    history[0] = history[1]; history[1] = O;
    // Result this frame: how far the horizon is rolled relative to the reference up.
    const Wn = mul(mul(mul(car, outer), base), O);
    const r = rotate(Wn, { x: 1, y: 0, z: 0 });
    const rollDeg = deg(Math.asin(dot(r, rotate(reference, UP))));
    if (n > 30) worst = Math.max(worst, Math.abs(rollDeg));
    last = { rollDeg, fwd: rotate(Wn, { x: 0, y: 1, z: 0 }) };
  }
  // Old behaviour for comparison: yaw around the camera's own up.
  const Oold = offsetRotation({ yaw: headYaw(frames - 1), pitch: headPitch(frames - 1), roll: 0 }, UP);
  const rOld = rotate(mul(mul(mul(car, outer), base), Oold), { x: 1, y: 0, z: 0 });
  const reference = mode === 'car' ? car : IDENTITY;
  const oldRoll = deg(Math.asin(dot(rOld, rotate(reference, UP))));
  const rBase = rotate(mul(mul(car, outer), base), { x: 1, y: 0, z: 0 });
  const baseRoll = deg(Math.asin(dot(rBase, rotate(reference, UP))));
  console.log(`${name.padEnd(46)} roll before turning ${baseRoll.toFixed(2).padStart(6)} | after: old ${oldRoll.toFixed(2).padStart(7)}  new ${last.rollDeg.toFixed(3).padStart(7)}  worst ${worst.toFixed(3)}`);
}

const car = mul(axisAngle(0, 0, 1, 30), mul(axisAngle(1, 0, 0, 6), axisAngle(0, 1, 0, -4))); // yawed, uphill, banked
const lookDown = mul(axisAngle(0, 0, 1, 15), axisAngle(1, 0, 0, -12)); // mouse look 15 left, 12 down
const still = () => 90, sweep = n => 120 * Math.sin(n / 20), nod = n => 15 * Math.sin(n / 7);

run('tilt outside local, head held 90 left', { car, outer: lookDown, base: IDENTITY, headYaw: still });
run('tilt in local orientation, head held 90 left', { car, outer: IDENTITY, base: lookDown, headYaw: still });
run('tilt outside local, fast sweeps + nods', { car, outer: lookDown, base: IDENTITY, headYaw: sweep, headPitch: nod });
run('same, camera report one frame late', { car, outer: lookDown, base: IDENTITY, headYaw: sweep, headPitch: nod, lag: true });
run('horizon mode, held 90 left', { car, outer: lookDown, base: IDENTITY, headYaw: still, mode: 'horizon' });
run('no tilt at all (should match old)', { car, outer: IDENTITY, base: IDENTITY, headYaw: still });

