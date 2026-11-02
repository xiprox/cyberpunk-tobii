// Mirrors how camera.lua's applyImpl takes up a value it didn't write, with the rule it had before
// and the rule it has now, while the game writes the camera for 2 s at 60 fps and the head is held
// turned. The game's behaviours are constructed: this shows what the math does, not what the game does.
const rad = d => d * Math.PI / 180, deg = r => r * 180 / Math.PI;
const axisAngle = (x, y, z, d) => { const h = rad(d) / 2, s = Math.sin(h); return { i: x * s, j: y * s, k: z * s, r: Math.cos(h) }; };
const mul = (a, b) => ({
  i: a.r * b.i + a.i * b.r + a.j * b.k - a.k * b.j, j: a.r * b.j - a.i * b.k + a.j * b.r + a.k * b.i,
  k: a.r * b.k + a.i * b.j - a.j * b.i + a.k * b.r, r: a.r * b.r - a.i * b.i - a.j * b.j - a.k * b.k });
const conj = q => ({ i: -q.i, j: -q.j, k: -q.k, r: q.r });
const rotate = (q, v) => {
  const tx = 2 * (q.j * v.z - q.k * v.y), ty = 2 * (q.k * v.x - q.i * v.z), tz = 2 * (q.i * v.y - q.j * v.x);
  return { x: v.x + q.r * tx + (q.j * tz - q.k * ty), y: v.y + q.r * ty + (q.k * tx - q.i * tz), z: v.z + q.r * tz + (q.i * ty - q.j * tx) };
};
const norm = q => { const l = Math.hypot(q.i, q.j, q.k, q.r); return { i: q.i / l, j: q.j / l, k: q.k / l, r: q.r / l }; };
const nlerp = (a, b, t) => {
  const s = a.i * b.i + a.j * b.j + a.k * b.k + a.r * b.r < 0 ? -1 : 1;
  return norm({ i: a.i + (s * b.i - a.i) * t, j: a.j + (s * b.j - a.j) * t, k: a.k + (s * b.k - a.k) * t, r: a.r + (s * b.r - a.r) * t });
};
const lerpV = (a, b, t) => ({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, z: a.z + (b.z - a.z) * t });
const angleBetween = (a, b) => { const d = mul(conj(a), b); return deg(2 * Math.asin(Math.min(Math.hypot(d.i, d.j, d.k), 1))); };
const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z);

const EPSILON = 1e-4, RATIO = 2, FPS = 60;
const EYES = { x: 0, y: 0.08, z: 0.075 }, I = { i: 0, j: 0, k: 0, r: 1 }, ZERO = { x: 0, y: 0, z: 0 };
const sameRot = (q, w) => ['i', 'j', 'k', 'r'].every(c => Math.abs(q[c] - w[c]) < EPSILON) || ['i', 'j', 'k', 'r'].every(c => Math.abs(q[c] + w[c]) < EPSILON);
const samePos = (p, w) => ['x', 'y', 'z'].every(c => Math.abs(p[c] - w[c]) < EPSILON);

const rules = {
  before: { rot: (q, w) => sameRot(q, w), pos: (p, w) => samePos(p, w) },
  now: {
    rot: (q, w, b) => sameRot(q, w) || angleBetween(q, w) * RATIO < angleBetween(q, b),
    pos: (p, w, b) => samePos(p, w) || distance(p, w) * RATIO < distance(p, b),
  },
};

// Returns how fast the view spins while the game writes, how far it strays from where it belongs, and
// what's left of that once the game stops. restAfter: the pose the game leaves behind.
function run(rule, yaw, write, restAfter = { rot: I, pos: ZERO }) {
  const o = axisAngle(0, 0, 1, yaw), moved = rotate(o, EYES);
  const shift = { x: moved.x - EYES.x, y: moved.y - EYES.y, z: moved.z - EYES.z };
  const draw = base => ({
    rot: mul(base.rot, o),
    pos: (s => ({ x: base.pos.x + s.x, y: base.pos.y + s.y, z: base.pos.z + s.z }))(rotate(base.rot, shift)),
  });
  let base = { rot: I, pos: ZERO }, written = draw(base), comp = written, spin = 0, peak = 0;
  const frames = 2 * FPS, should = draw({ rot: I, pos: ZERO });
  for (let f = 0; f < frames + 60; f++) {
    if (f < frames) comp = write(comp, f);
    base = {
      rot: rules[rule].rot(comp.rot, written.rot, base.rot) ? base.rot : comp.rot,
      pos: rules[rule].pos(comp.pos, written.pos, base.pos) ? base.pos : comp.pos,
    };
    const next = draw(base);
    if (f < frames) {
      spin += angleBetween(written.rot, next.rot);
      peak = Math.max(peak, distance(next.pos, should.pos) * 100);
    }
    written = next;
    comp = next;
  }
  const end = draw(restAfter);
  return { spin: spin / (frames / FPS), peak, deg: angleBetween(written.rot, end.rot), cm: distance(written.pos, end.pos) * 100 };
}

const own = (rot, pos) => () => ({ rot, pos });
const blend = a => c => ({ rot: nlerp(c.rot, I, a), pos: lerpV(c.pos, ZERO, a) });
const nudge = c => ({ rot: norm({ ...c.rot, j: c.rot.j + 3e-4 }), pos: { ...c.pos, y: c.pos.y + 3e-4 } });
const row = (label, r) => `${label.padEnd(46)} ${r.spin.toFixed(0).padStart(6)} deg/s  ${r.peak.toFixed(1).padStart(5)} cm  left ${r.deg.toFixed(1).padStart(5)} deg ${r.cm.toFixed(1).padStart(5)} cm`;

for (const yaw of [5, 15, 30]) {
  for (const rule of ['before', 'now']) {
    console.log(`\nHead held ${yaw} deg, rule ${rule}: spin, peak position error, left once the game stops`);
    console.log(row('game writes its own resting pose', run(rule, yaw, own(I, ZERO))));
    console.log(row('game blends the value 75% toward rest a frame', run(rule, yaw, blend(0.75))));
    console.log(row('game blends the value 50% toward rest a frame', run(rule, yaw, blend(0.5))));
    console.log(row('game blends the value 34% toward rest a frame', run(rule, yaw, blend(0.34))));
    console.log(row('game blends the value 33% toward rest a frame', run(rule, yaw, blend(0.33))));
    console.log(row('game blends the value 10% toward rest a frame', run(rule, yaw, blend(0.1))));
    console.log(row('game blends the value 2% toward rest a frame', run(rule, yaw, blend(0.02))));
    console.log(row('game nudges the value slightly', run(rule, yaw, nudge)));
  }
}

const pitched = { rot: axisAngle(1, 0, 0, -40), pos: { x: 0, y: 0.1, z: -0.2 } };
const sameWay = { rot: axisAngle(0, 0, 1, 40), pos: { x: 0, y: 0.1, z: -0.2 } };
const near = { rot: axisAngle(0, 0, 1, 20), pos: ZERO };
const once = pose => (c, f) => (f === 0 ? pose : c);
for (const rule of ['before', 'now']) {
  console.log(`\nHead held 15 deg, the game moves to a new pose and stays, rule ${rule}: left is how far the view ends up from that pose`);
  console.log(row('own pose 40 deg pitched away, written once', run(rule, 15, once(pitched), pitched)));
  console.log(row('own pose 40 deg pitched away, every frame', run(rule, 15, own(pitched.rot, pitched.pos), pitched)));
  console.log(row('own pose 40 deg the way the head turns, once', run(rule, 15, once(sameWay), sameWay)));
  console.log(row('own pose 20 deg the way the head turns, once', run(rule, 15, once(near), near)));
}
