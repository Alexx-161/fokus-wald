// Canvas port of the Mac app's PlantPainter. Draws any plant at a growth `p` (0 = seedling, 1 = grown).
// `base` is where the plant meets the ground; `u` scales it (a grown tree is about 0.6·u tall).

import { TAU, smooth, rnd, rgba, PALETTE as P } from './data.js';

const BLOBS = [
  [0, 0.12, 0.95], [-0.62, 0.30, 0.62], [0.62, 0.30, 0.62],
  [-0.36, -0.42, 0.64], [0.37, -0.40, 0.60], [0, -0.62, 0.55],
];
const RAINBOW = ['#F7A8B8', '#FFC98B', '#FFE89A', '#A8E6A1', '#A8D2F5', '#C9B6F2'];

export function circle(ctx, x, y, r, fill) {
  if (r <= 0) return;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, TAU);
  ctx.fillStyle = fill;
  ctx.fill();
}

export function ellipse(ctx, x, y, w, h, fill) {
  if (w <= 0 || h <= 0) return;
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, TAU);
  ctx.fillStyle = fill;
  ctx.fill();
}

export function roundRect(ctx, x, y, w, h, r, fill) {
  if (w <= 0 || h <= 0) return;
  const rr = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.arcTo(x + w, y, x + w, y + h, rr);
  ctx.arcTo(x + w, y + h, x, y + h, rr);
  ctx.arcTo(x, y + h, x, y, rr);
  ctx.arcTo(x, y, x + w, y, rr);
  ctx.closePath();
  ctx.fillStyle = fill;
  ctx.fill();
}

export function starPath(ctx, cx, cy, r) {
  ctx.beginPath();
  for (let i = 0; i < 10; i++) {
    const rr = i % 2 === 0 ? r : r * 0.45;
    const ang = -Math.PI / 2 + (i * Math.PI) / 5;
    const x = cx + Math.cos(ang) * rr, y = cy + Math.sin(ang) * rr;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.closePath();
}

function withAlpha(ctx, alpha, draw) {
  ctx.save();
  ctx.globalAlpha *= alpha;
  draw();
  ctx.restore();
}

export function drawPlant(ctx, s, base, u, p, seed, time, { ground = true, detail = true } = {}) {
  const g = smooth(0, 1, p);
  ctx.save();
  ctx.translate(base.x, base.y);

  if (ground) {
    const w = u * (0.34 + 0.14 * g), h = u * 0.075;
    ellipse(ctx, -w / 2, -h / 2, w, h, P.soil);
    ellipse(ctx, -w / 2 + u * 0.03, -h / 2, w - u * 0.06, h * 0.5, P.soilLight);
  }
  if (time !== 0) ctx.rotate(Math.sin(time * 1.3 + seed * 40) * 0.03 * g);

  let face = null;
  switch (s.kind) {
    case 'tulip': case 'sunflower': case 'daisy': case 'bell':
      face = drawFlower(ctx, s, u, g, p, seed);
      break;
    case 'toadstool': case 'porcini': case 'glowshroom':
      face = drawMushroom(ctx, s, u, g, p, time, detail);
      break;
    default:
      face = drawTree(ctx, s, u, g, p, seed, time, detail);
  }
  if (detail && face) drawFace(ctx, face.x, face.y, face.r, p, seed, time);
  ctx.restore();
}

// ---- Trees

function drawTree(ctx, s, u, g, p, seed, time, detail) {
  const trunkH = u * (0.05 + 0.22 * g);
  const trunkW = u * (0.024 + 0.04 * g);
  roundRect(ctx, -trunkW / 2, -trunkH, trunkW, trunkH + u * 0.012, trunkW / 2, s.kind === 'crystal' ? P.crystalTrunk : P.trunk);
  if (detail) {
    roundRect(ctx, -trunkW * 0.28, -trunkH * 0.9, trunkW * 0.2, trunkH * 0.75, trunkW * 0.1, 'rgba(255,255,255,0.18)');
  }
  drawSprout(ctx, 0, -trunkH + u * 0.005, u, p);

  if (smooth(0.18, 1, p) <= 0.001) return null;
  let crown;
  if (s.kind === 'pine') crown = drawPine(ctx, s, u, trunkH, p);
  else if (s.kind === 'crystal') crown = drawCrystal(ctx, s, u, trunkH, p, seed, time);
  else if (s.kind === 'rainbow') {
    crown = drawRound(ctx, u, trunkH, p, seed, (i) => {
      const c = RAINBOW[i % RAINBOW.length];
      return [c, c, 'rgba(255,255,255,0.45)'];
    });
  } else crown = drawRound(ctx, u, trunkH, p, seed, () => [s.main, s.shade, s.light]);

  if (detail && s.kind !== 'crystal') drawBlossoms(ctx, s.accent, crown, p, seed);
  return crown;
}

function drawSprout(ctx, x, y, u, p) {
  const alpha = 1 - smooth(0.2, 0.38, p);
  if (alpha <= 0.01) return;
  const ls = u * (0.06 + 0.06 * smooth(0, 0.2, p));
  for (const dir of [-1, 1]) {
    ctx.save();
    ctx.globalAlpha *= alpha;
    ctx.translate(x, y);
    ctx.rotate(-dir * 0.55);
    ellipse(ctx, dir > 0 ? 0 : -ls, -ls * 0.27, ls, ls * 0.54, P.sprout);
    ctx.restore();
  }
}

function drawRound(ctx, u, trunkH, p, seed, colors) {
  const R = u * 0.2;
  const cx = 0, cy = -trunkH - R * 0.35;
  const circles = [];
  BLOBS.forEach((b, i) => {
    const a = smooth(0.18 + i * 0.07, 0.55 + i * 0.07, p);
    if (a <= 0.001) return;
    const jx = (rnd(seed, i) - 0.5) * 0.14;
    const jy = (rnd(seed, i + 10) - 0.5) * 0.10;
    const spread = R * (0.35 + 0.65 * a);
    circles.push({ i, x: cx + (b[0] + jx) * spread, y: cy + (b[1] + jy) * spread, r: R * b[2] * a });
  });
  for (const c of circles) {
    circle(ctx, c.x, c.y + R * 0.09, c.r, colors(c.i)[1]);
    circle(ctx, c.x, c.y + R * 0.09, c.r, 'rgba(0,0,0,0.08)');
  }
  for (const c of circles) circle(ctx, c.x, c.y, c.r, colors(c.i)[0]);
  for (const c of circles) {
    if ([0, 3, 4, 5].includes(c.i)) circle(ctx, c.x - c.r * 0.32, c.y - c.r * 0.34, c.r * 0.3, colors(c.i)[2]);
  }
  return { x: cx, y: cy + R * 0.18, r: R };
}

function drawPine(ctx, s, u, trunkH, p) {
  let face = { x: 0, y: -trunkH };
  let apexY = -trunkH;
  ctx.lineJoin = 'round';
  ctx.lineWidth = u * 0.035;
  const tri = (w, h, baseY, dy, color) => {
    ctx.beginPath();
    ctx.moveTo(0, baseY - h + dy);
    ctx.lineTo(w / 2, baseY + dy);
    ctx.lineTo(-w / 2, baseY + dy);
    ctx.closePath();
    ctx.fillStyle = color;
    ctx.strokeStyle = color;
    ctx.fill();
    ctx.stroke();
  };
  for (let k = 0; k < 3; k++) {
    const a = smooth(0.18 + k * 0.14, 0.58 + k * 0.14, p);
    if (a <= 0.001) continue;
    const w = u * (0.44 - k * 0.1) * a;
    const h = u * (0.2 - k * 0.025) * a;
    const baseY = -trunkH * 0.55 - k * u * 0.11;
    tri(w, h, baseY, u * 0.018, s.shade);
    tri(w, h, baseY, 0, s.main);
    circle(ctx, -w * 0.14, baseY - h * 0.55, u * 0.016 * a, s.light);
    if (k === 0) face = { x: 0, y: baseY - h * 0.3 };
    apexY = baseY - h;
  }
  const starA = smooth(0.9, 1.0, p);
  if (starA > 0.01) {
    withAlpha(ctx, starA, () => {
      starPath(ctx, 0, apexY - u * 0.01, u * 0.045);
      ctx.fillStyle = P.star;
      ctx.fill();
    });
  }
  return { x: face.x, y: face.y, r: u * 0.16 };
}

function drawCrystal(ctx, s, u, trunkH, p, seed, time) {
  const R = u * 0.2;
  const cx = 0, cy = -trunkH - R * 0.25;
  const shards = [[-90, 1.75, 0.5], [-130, 1.4, 0.42], [-50, 1.4, 0.42], [-165, 0.95, 0.34], [-15, 0.95, 0.34]];
  for (const i of [3, 4, 1, 2, 0]) {
    const a = smooth(0.2 + i * 0.08, 0.6 + i * 0.08, p);
    if (a <= 0.001) continue;
    const [deg, len, wid] = shards[i];
    const ang = (deg * Math.PI) / 180;
    const dx = Math.cos(ang), dy = Math.sin(ang);
    const nx = -dy, ny = dx;
    const L = R * len * a, w = R * wid * a;
    const pt = (along, side) => [cx + dx * along + nx * side, cy + dy * along + ny * side];
    const poly = (points, fill) => {
      ctx.beginPath();
      points.forEach(([x, y], k) => (k === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)));
      ctx.closePath();
      ctx.fillStyle = fill;
      ctx.fill();
    };
    poly([pt(0, w / 2), pt(L * 0.78, w / 2), pt(L, 0), pt(L * 0.78, -w / 2), pt(0, -w / 2)], i % 2 === 0 ? s.main : s.shade);
    poly([pt(0, 0), pt(L * 0.78, w / 2), pt(L, 0)], rgba(s.light, 0.75));
  }
  const orbA = smooth(0.3, 0.7, p);
  if (orbA > 0.01) {
    const r = R * 0.62 * orbA;
    const grad = ctx.createRadialGradient(cx - r * 0.3, cy - r * 0.3, 0, cx - r * 0.3, cy - r * 0.3, r * 1.3);
    grad.addColorStop(0, s.light);
    grad.addColorStop(0.5, s.main);
    grad.addColorStop(1, s.accent);
    circle(ctx, cx, cy, r, grad);
  }
  const sparkle = smooth(0.8, 1.0, p);
  if (sparkle > 0.01) {
    for (let i = 0; i < 5; i++) {
      const ang = Math.PI * (1.0 + rnd(seed, 50 + i));
      const rr = R * (0.9 + 0.5 * rnd(seed, 60 + i));
      const twinkle = time === 0 ? 1 : 0.5 + 0.5 * Math.sin(time * 2.5 + i * 1.7);
      withAlpha(ctx, sparkle * twinkle, () => {
        starPath(ctx, cx + Math.cos(ang) * rr, cy + Math.sin(ang) * rr, R * 0.09);
        ctx.fillStyle = '#fff';
        ctx.fill();
      });
    }
  }
  return { x: cx, y: cy + R * 0.04, r: R };
}

function drawBlossoms(ctx, color, crown, p, seed) {
  const a = smooth(0.78, 1.0, p);
  if (a <= 0.01) return;
  const R = crown.r;
  for (let i = 0; i < 7; i++) {
    const ang = Math.PI * (0.95 + 1.1 * rnd(seed, 30 + i));
    const rr = R * (0.55 + 0.4 * rnd(seed, 40 + i));
    circle(ctx, crown.x + Math.cos(ang) * rr, crown.y - R * 0.25 + Math.sin(ang) * rr, R * 0.075 * a, color);
  }
}

// ---- Flowers

function drawFlower(ctx, s, u, g, p, seed) {
  const stemH = u * (0.05 + 0.33 * g);
  const bend = u * 0.04 * (rnd(seed, 1) - 0.5);
  const bell = s.kind === 'bell';
  const tip = bell ? { x: u * 0.11 * g, y: -stemH * 0.85 } : { x: bend, y: -stemH };
  const control = bell ? { x: -u * 0.02, y: -stemH * 1.2 } : { x: -bend, y: -stemH * 0.5 };

  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.quadraticCurveTo(control.x, control.y, tip.x, tip.y);
  ctx.strokeStyle = P.stem;
  ctx.lineWidth = Math.max(1, u * 0.022);
  ctx.lineCap = 'round';
  ctx.stroke();

  const leafA = smooth(0.12, 0.45, p);
  if (leafA > 0.01) {
    for (const [t, dir] of [[0.3, -1], [0.5, 1]]) {
      const mt = 1 - t;
      const ax = 2 * mt * t * control.x + t * t * tip.x;
      const ay = 2 * mt * t * control.y + t * t * tip.y;
      const ls = u * 0.1 * leafA;
      ctx.save();
      ctx.translate(ax, ay);
      ctx.rotate(-dir * 0.5);
      ellipse(ctx, dir > 0 ? 0 : -ls, -ls * 0.22, ls, ls * 0.44, P.leaf);
      ctx.restore();
    }
  }
  drawSprout(ctx, tip.x, tip.y, u, p);

  const bud = smooth(0.28, 0.55, p);
  const open = smooth(0.55, 0.95, p);
  if (bud <= 0.01) return null;

  if (s.kind === 'tulip') {
    const h = u * 0.19 * (0.45 + 0.55 * bud);
    const w = h * 0.62;
    const cx = tip.x, cy = tip.y - h * 0.4;
    for (const dir of [-1, 1]) {
      ctx.save();
      ctx.translate(cx, cy + h * 0.15);
      ctx.rotate(dir * (0.18 + 0.32 * open));
      ellipse(ctx, -w / 2 + dir * w * 0.25, -h * 0.6, w, h, s.shade);
      ctx.restore();
    }
    ellipse(ctx, cx - w * 0.55, cy - h * 0.5, w * 1.1, h, s.main);
    ellipse(ctx, cx - w * 0.35, cy - h * 0.38, w * 0.28, h * 0.3, s.light);
    return { x: cx, y: cy + h * 0.05, r: w * 0.95 };
  }

  if (s.kind === 'sunflower' || s.kind === 'daisy') {
    const sun = s.kind === 'sunflower';
    const diskR = u * (sun ? 0.09 : 0.065) * (0.5 + 0.5 * bud);
    const petalL = u * (sun ? 0.11 : 0.105) * open;
    const petalW = u * (sun ? 0.055 : 0.04);
    const count = sun ? 14 : 12;
    if (open > 0.01) {
      for (let i = 0; i < count; i++) {
        ctx.save();
        ctx.translate(tip.x, tip.y);
        ctx.rotate((i * TAU) / count + seed);
        const x = diskR * 0.6, y = -petalW / 2, w = petalL + diskR * 0.4;
        if (!sun) {
          const d = u * 0.005;
          ellipse(ctx, x - d, y - d, w + 2 * d, petalW + 2 * d, s.shade);
        }
        ellipse(ctx, x, y, w, petalW, sun && i % 2 === 0 ? s.shade : s.main);
        ctx.restore();
      }
    }
    if (open < 0.99) withAlpha(ctx, 1 - open, () => circle(ctx, tip.x, tip.y, diskR * 1.3, P.leaf));
    circle(ctx, tip.x, tip.y, diskR, s.accent);
    if (sun) {
      for (let i = 0; i < 6; i++) {
        const ang = (i * Math.PI) / 3 + 0.3;
        circle(ctx, tip.x + Math.cos(ang) * diskR * 0.7, tip.y + Math.sin(ang) * diskR * 0.7, diskR * 0.08, 'rgba(0,0,0,0.15)');
      }
    }
    return { x: tip.x, y: tip.y + diskR * 0.05, r: diskR * 1.55 };
  }

  // Bellflower
  const bh = u * 0.19 * (0.45 + 0.55 * bud);
  const flare = 0.8 + 0.2 * open;
  const bw = bh * 0.95;
  const bottomY = tip.y + bh * 0.9;
  ctx.beginPath();
  ctx.moveTo(tip.x + bw * 0.3, tip.y);
  ctx.quadraticCurveTo(tip.x, tip.y - bh * 0.18, tip.x - bw * 0.3, tip.y);
  ctx.quadraticCurveTo(tip.x - bw * 0.5, tip.y + bh * 0.25, tip.x - bw * 0.5 * flare, bottomY);
  const xs = [-0.5, -0.17, 0.17, 0.5];
  for (let i = 0; i < 3; i++) {
    const x0 = xs[i] * flare, x1 = xs[i + 1] * flare;
    ctx.quadraticCurveTo(tip.x + (bw * (x0 + x1)) / 2, bottomY + bh * 0.16, tip.x + bw * x1, bottomY);
  }
  ctx.quadraticCurveTo(tip.x + bw * 0.5, tip.y + bh * 0.25, tip.x + bw * 0.3, tip.y);
  ctx.closePath();
  ctx.fillStyle = s.main;
  ctx.fill();
  ellipse(ctx, tip.x - bw * 0.36, tip.y + bh * 0.12, bw * 0.18, bh * 0.38, s.light);
  return { x: tip.x, y: tip.y + bh * 0.5, r: bw * 0.85 };
}

// ---- Mushrooms

function drawMushroom(ctx, s, u, g, p, time, detail) {
  const porcini = s.kind === 'porcini';
  const stemH = u * (0.03 + 0.17 * g);
  const stemW = u * (0.05 + 0.07 * g) * (porcini ? 1.35 : 1);
  const capR = u * (0.07 + 0.16 * g) * (porcini ? 1.05 : 1);
  const capBottom = -stemH;

  if (s.kind === 'glowshroom') {
    const glowR = capR * 2.4, gy = capBottom - capR * 0.3;
    const grad = ctx.createRadialGradient(0, gy, 0, 0, gy, glowR);
    grad.addColorStop(0, rgba(s.accent, 0.55));
    grad.addColorStop(1, rgba(s.accent, 0));
    circle(ctx, 0, gy, glowR, grad);
  }

  roundRect(ctx, -stemW / 2, capBottom - capR * 0.2, stemW, stemH + capR * 0.2 + u * 0.01, stemW * 0.45,
    porcini ? s.accent : P.mushroomStem);
  ellipse(ctx, -capR * 0.92, capBottom - capR * 0.16, capR * 1.84, capR * 0.34, P.gills);

  const grad = ctx.createLinearGradient(0, capBottom - capR, 0, capBottom + capR * 0.15);
  grad.addColorStop(0, s.light);
  grad.addColorStop(0.5, s.main);
  grad.addColorStop(1, s.shade);
  ctx.beginPath();
  ctx.moveTo(-capR, capBottom);
  ctx.bezierCurveTo(-capR * 1.02, capBottom - capR * 1.35, capR * 1.02, capBottom - capR * 1.35, capR, capBottom);
  ctx.quadraticCurveTo(0, capBottom + capR * 0.22, -capR, capBottom);
  ctx.closePath();
  ctx.fillStyle = grad;
  ctx.fill();
  ellipse(ctx, -capR * 0.62, capBottom - capR * 0.82, capR * 0.36, capR * 0.2, 'rgba(255,255,255,0.45)');

  if (s.kind === 'toadstool') {
    const dots = [[-0.62, -0.42, 0.11], [-0.3, -0.85, 0.12], [0.2, -0.93, 0.1], [0.6, -0.6, 0.12], [0.75, -0.25, 0.07], [-0.82, -0.15, 0.06]];
    for (const d of dots) circle(ctx, d[0] * capR, capBottom + d[1] * capR, d[2] * capR, s.accent);
  }
  if (s.kind === 'glowshroom' && detail) {
    const xs = [-1.5, 1.4, -0.9, 1.0], ys = [0.9, 1.2, 1.7, 0.2];
    for (let i = 0; i < 4; i++) {
      const twinkle = time === 0 ? 1 : 0.5 + 0.5 * Math.sin(time * 2 + i * 1.9);
      withAlpha(ctx, twinkle * smooth(0.6, 1, p), () => {
        starPath(ctx, capR * xs[i], capBottom - capR * ys[i], capR * 0.13);
        ctx.fillStyle = s.accent;
        ctx.fill();
      });
    }
  }
  return { x: 0, y: capBottom - capR * 0.36, r: capR * 0.85 };
}

// ---- Face

function drawFace(ctx, cx, cy, R, p, seed, time) {
  const a = smooth(0.45, 0.7, p);
  if (a <= 0.01) return;
  ctx.save();
  ctx.globalAlpha *= a;
  const er = R * 0.075;
  const blinking = time !== 0 && (time + seed * 11) % 4.5 < 0.13;
  for (const d of [-1, 1]) {
    const x = cx + d * R * 0.3, y = cy;
    if (blinking) {
      roundRect(ctx, x - er, y - er * 0.2, er * 2, er * 0.4, er * 0.2, P.face);
    } else {
      circle(ctx, x, y, er, P.face);
      circle(ctx, x - er * 0.3, y - er * 0.35, er * 0.35, '#fff');
    }
    ellipse(ctx, x + d * R * 0.12 - R * 0.11, y + R * 0.1, R * 0.22, R * 0.12, rgba(P.blush, 0.75));
  }
  ctx.beginPath();
  ctx.moveTo(cx - R * 0.07, cy + R * 0.08);
  ctx.quadraticCurveTo(cx, cy + R * 0.19, cx + R * 0.07, cy + R * 0.08);
  ctx.strokeStyle = P.face;
  ctx.lineWidth = Math.max(0.8, R * 0.035);
  ctx.lineCap = 'round';
  ctx.stroke();
  ctx.restore();
}
