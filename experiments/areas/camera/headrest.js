// Mirrors camera.lua neckShift (seated twist + headrest lean) and init.lua seatSide.
const rad = d => d * Math.PI / 180;
const axisAngle = (x, y, z, d) => { const h = rad(d) / 2, s = Math.sin(h); return { i: x * s, j: y * s, k: z * s, r: Math.cos(h) }; };
const rotate = (q, v) => {
  const tx = 2 * (q.j * v.z - q.k * v.y), ty = 2 * (q.k * v.x - q.i * v.z), tz = 2 * (q.i * v.y - q.j * v.x);
  return { x: v.x + q.r * tx + (q.j * tz - q.k * ty), y: v.y + q.r * ty + (q.k * tx - q.i * tz), z: v.z + q.r * tz + (q.i * ty - q.j * tx) };
};
const dot = (a, b) => a.x * b.x + a.y * b.y + a.z * b.z;
const cross = (a, b) => ({ x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x });
const scaled = (v, s) => ({ x: v.x * s, y: v.y * s, z: v.z * s });
function softClamp(v, limit, blend) {
  blend = Math.min(blend, limit); const a = Math.abs(v), lo = limit - blend;
  if (a <= lo) return v; let out = limit;
  if (a < limit + blend) out = a - (a - lo) * (a - lo) / (4 * blend);
  return v < 0 ? -out : out;
}
function neckShift(o, yaw, neck, u = { x: 0, y: 0, z: 1 }) {
  const eyes = neck.eyes, moved = rotate(o, eyes);
  const shift = { x: moved.x - eyes.x, y: moved.y - eyes.y, z: moved.z - eyes.z };
  const twist = neck.twist, torso = twist ? yaw - softClamp(yaw, twist.limit, 15) : 0;
  if (torso !== 0) {
    let forward = { x: -u.y * u.x, y: 1 - u.y * u.y, z: -u.y * u.z }; forward = scaled(forward, 1 / Math.sqrt(dot(forward, forward)));
    const spin = axisAngle(u.x, u.y, u.z, torso), spine = scaled(forward, -twist.spineBehind), swung = rotate(spin, spine);
    let swing = { x: spine.x - swung.x, y: spine.y - swung.y, z: spine.z - swung.z };
    let lean = scaled(forward, twist.lean * Math.abs(torso) / 45);
    if (twist.seated) {
      const back = dot(swing, forward);
      if (back < 0) swing = { x: swing.x - forward.x * back, y: swing.y - forward.y * back, z: swing.z - forward.z * back };
      const h = twist.headrest;
      if (h) {
        const looking = torso > 0 ? -1 : 1;
        let amount = h.door; if (h.seatSide !== 0 && looking !== h.seatSide) amount = h.middle;
        const t = Math.min(Math.abs(torso) / 35, 1);
        const side = scaled(cross(forward, u), looking * amount * t * t * (3 - 2 * t));
        lean = { x: lean.x + side.x, y: lean.y + side.y, z: lean.z + side.z };
      }
    } else lean = rotate(spin, lean);
    shift.x += swing.x + lean.x; shift.y += swing.y + lean.y; shift.z += swing.z + lean.z;
  }
  return shift;
}
const eyes = { x: 0, y: 0.08, z: 0.075 };
const car = side => ({ eyes, twist: { limit: 85, spineBehind: 0.04, lean: 0.08, seated: true, headrest: { door: 0.08, middle: 0.16, seatSide: side } } });
const noHeadrest = { eyes, twist: { limit: 85, spineBehind: 0.04, lean: 0.08, seated: true } };
const f = v => `${(v.x * 100).toFixed(1).padStart(6)} ${(v.y * 100).toFixed(1).padStart(6)}`;
console.log('camera yaw | seat, no headrest lean | driver (left seat)    | passenger (right seat)   (right / forward cm)');
for (const yaw of [-135, -120, -105, -90, -75, 0, 75, 90, 105, 120, 135]) {
  const o = axisAngle(0, 0, 1, yaw);
  console.log(`${String(yaw).padStart(6)} ${yaw > 0 ? 'L' : yaw < 0 ? 'R' : ' '}   | ${f(neckShift(o, yaw, noHeadrest))}          | ${f(neckShift(o, yaw, car(-1)))}        | ${f(neckShift(o, yaw, car(1)))}`);
}
let maxStep = 0, maxKink = 0, prev = null, prevStep = null;
for (let yaw = -135; yaw <= 135; yaw += 0.5) {
  const p = neckShift(axisAngle(0, 0, 1, yaw), yaw, car(-1));
  if (prev) { const s = { x: p.x - prev.x, y: p.y - prev.y, z: p.z - prev.z }; maxStep = Math.max(maxStep, Math.sqrt(dot(s, s)));
    if (prevStep) { const k = { x: s.x - prevStep.x, y: s.y - prevStep.y, z: s.z - prevStep.z }; maxKink = Math.max(maxKink, Math.sqrt(dot(k, k))); } prevStep = s; }
  prev = p;
}
console.log(`\ndriver, whole turn: biggest eye move per 0.5 deg ${(maxStep * 1000).toFixed(2)} mm, biggest change in that ${(maxKink * 1000).toFixed(3)} mm`);

// seatSide: car's right axis from its orientation, player position relative to the car.
function seatSide(p, v, q) {
  const right = { x: 1 - 2 * (q.j * q.j + q.k * q.k), y: 2 * (q.i * q.j + q.r * q.k), z: 2 * (q.i * q.k - q.r * q.j) };
  const side = (p.x - v.x) * right.x + (p.y - v.y) * right.y + (p.z - v.z) * right.z;
  return Math.abs(side) < 0.1 ? 0 : side < 0 ? -1 : 1;
}
const q = axisAngle(0, 0, 1, 70), carPos = { x: 100, y: 50, z: 3 };
const at = local => { const w = rotate(q, local); return { x: carPos.x + w.x, y: carPos.y + w.y, z: carPos.z + w.z }; };
console.log(`seatSide with the car turned 70 deg: driver (0.4 m left) ${seatSide(at({ x: -0.4, y: 0.2, z: 0.5 }), carPos, q)}, passenger (0.4 m right) ${seatSide(at({ x: 0.4, y: 0.2, z: 0.5 }), carPos, q)}, centre ${seatSide(at({ x: 0.02, y: -0.5, z: 0.5 }), carPos, q)}`);
