// Canvas port of the Mac app's island. Plants sit on a sunflower spiral, so the island grows outward
// from the middle and earlier plants never move when new ones are added.

import { TAU, clamp, rnd, rgba, findSpecies, PALETTE as P } from './data.js';
import { drawPlant, circle, starPath, roundRect } from './painter.js';

export function islandShape(count) {
  const rx = 0.85 * Math.sqrt(Math.max(count, 1)) + 1.1;
  return { rx, ry: rx * 0.42 + 0.25, depth: rx * 0.5 + 0.4 };
}

export function plantPosition(index) {
  const r = 0.85 * Math.sqrt(index);
  const a = index * 2.399963;
  return { x: r * Math.cos(a), y: r * Math.sin(a) * 0.42 };
}

/** Pulls a point back onto the grass if it lies outside the island's top ellipse. */
export function clampToIsland(shape, p, margin = 0.94) {
  const k = Math.hypot(p.x / shape.rx, p.y / shape.ry);
  return k <= margin ? p : { x: (p.x * margin) / k, y: (p.y * margin) / k };
}

/** Maps island world coordinates to canvas coordinates, including zoom and pan. */
export function viewport(width, height, shape, zoom = 1, pan = { x: 0, y: 0 }, bob = 0) {
  const treeTop = 1.35;
  const minX = -shape.rx, maxX = shape.rx;
  const minY = -shape.ry - treeTop, maxY = shape.ry + shape.depth;
  const fit = Math.min((width * 0.84) / (maxX - minX), (height * 0.8) / (maxY - minY));
  const scale = fit * zoom;
  const ox = width / 2 - ((minX + maxX) / 2) * scale + pan.x;
  const oy = height / 2 - ((minY + maxY) / 2) * scale + pan.y + bob;
  return {
    scale,
    view: (p) => ({ x: ox + p.x * scale, y: oy + p.y * scale }),
    world: (v) => ({ x: (v.x - ox) / scale, y: (v.y - oy) / scale }),
  };
}

export function drawIsland(ctx, width, height, vp, shape, opts) {
  // `sky: false` leaves the background transparent so the island can float on a page.
  const { plants = [], growing = null, decorations = [], draft = null, complete = false, time = 0, theme, sky = true } = opts;
  if (sky) {
    const gradient = ctx.createLinearGradient(0, 0, 0, height);
    gradient.addColorStop(0, theme.skyTop);
    gradient.addColorStop(1, theme.skyBottom);
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, width, height);
    if (theme.particles === 'stars') drawStars(ctx, width, height, time);
    drawClouds(ctx, width, height, time, theme);
  }

  const s = vp.scale;
  const { rx, ry, depth } = shape;
  const pt = (x, y) => vp.view({ x, y });
  const ell = (x, y, ex, ey, fill) => {
    const c = pt(x, y);
    ctx.beginPath();
    ctx.ellipse(c.x, c.y, ex * s, ey * s, 0, 0, TAU);
    ctx.fillStyle = fill;
    ctx.fill();
  };

  ell(0, ry + depth + 0.55, rx * 0.55, 0.12, 'rgba(0,0,0,0.06)');
  const a = pt(-rx, 0), b = pt(0, ry + depth), c = pt(rx, 0);
  const c1 = pt(-rx * 0.75, ry + depth * 0.95), c2 = pt(rx * 0.75, ry + depth * 0.95);
  const earth = ctx.createLinearGradient(0, pt(0, 0).y, 0, b.y);
  earth.addColorStop(0, theme.earth);
  earth.addColorStop(1, theme.earthDark);
  ctx.beginPath();
  ctx.moveTo(a.x, a.y);
  ctx.quadraticCurveTo(c1.x, c1.y, b.x, b.y);
  ctx.quadraticCurveTo(c2.x, c2.y, c.x, c.y);
  ctx.closePath();
  ctx.fillStyle = earth;
  ctx.fill();
  for (let k = 0; k < 6; k++) {
    const x = (rnd(7, k) - 0.5) * rx;
    const y = ry * 0.55 + rnd(8, k) * depth * 0.45 * (1 - Math.abs(x) / rx);
    ell(x, y, 0.13, 0.08, rgba(theme.pebble, 0.7));
  }

  ell(0, 0.14, rx, ry, theme.grassDark);
  ell(0, 0, rx, ry, theme.grass);

  const count = plants.length + (growing ? 1 : 0);
  const dots = ['#F7B6C8', '#FFE08A', '#FFFFFF', theme.grassDark];
  for (let k = 0; k < Math.min(260, 10 + count * 3); k++) {
    const rr = Math.sqrt(rnd(3, k)) * 0.9;
    const ang = rnd(4, k) * TAU;
    ell(rr * rx * Math.cos(ang), rr * ry * Math.sin(ang), 0.035, 0.03, dots[k % dots.length]);
  }

  const all = draft ? decorations.concat([draft]) : decorations;
  ctx.save();
  const top = pt(0, 0);
  ctx.beginPath();
  ctx.ellipse(top.x, top.y, rx * s, ry * s, 0, 0, TAU);
  ctx.clip();
  for (const d of all) if (d.kind === 'river') drawRiver(ctx, d, vp, time, theme);
  for (const d of all) if (d.kind === 'path') drawPath(ctx, d, vp);
  ctx.restore();
  for (const d of all) if (d.kind === 'bridge') drawBridge(ctx, d, vp);

  const items = plants.map((p, i) => ({ pos: plantPosition(i), species: findSpecies(p.speciesID), seed: p.seed, minutes: p.minutes, progress: 1 }));
  if (growing) {
    items.push({ pos: plantPosition(plants.length), species: growing.species, seed: growing.seed, minutes: 25, progress: growing.progress });
  }
  items.sort((p, q) => p.pos.y - q.pos.y);
  for (const item of items) {
    const sizeFactor = clamp(0.75 + item.minutes / 100, 0.8, 1.35) * item.species.islandScale;
    const depthFactor = 0.92 + 0.1 * (item.pos.y / ry);
    const unit = 1.55 * sizeFactor * depthFactor * s;
    ell(item.pos.x, item.pos.y, 0.3 * sizeFactor, 0.08, rgba(theme.grassDark, 0.7));
    drawPlant(ctx, item.species, vp.view(item.pos), unit, item.progress, item.seed, time, { ground: false, detail: unit > 40 });
  }

  if (complete) drawFlag(ctx, pt(rx * 0.78, -ry * 0.18), s, time);
  if (sky && theme.particles === 'snow') drawFalling(ctx, width, height, time, false);
  if (sky && theme.particles === 'petals') drawFalling(ctx, width, height, time, true);
}

// ---- Decorations

function tracePath(ctx, points, vp) {
  const v = points.map((p) => vp.view(p));
  ctx.beginPath();
  if (!v.length) return;
  ctx.moveTo(v[0].x, v[0].y);
  if (v.length < 3) {
    for (const p of v.slice(1)) ctx.lineTo(p.x, p.y);
    return;
  }
  for (let i = 1; i < v.length - 1; i++) {
    ctx.quadraticCurveTo(v[i].x, v[i].y, (v[i].x + v[i + 1].x) / 2, (v[i].y + v[i + 1].y) / 2);
  }
  ctx.lineTo(v[v.length - 1].x, v[v.length - 1].y);
}

function strokeLine(ctx, color, width, dash = [], offset = 0) {
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.setLineDash(dash);
  ctx.lineDashOffset = offset;
  ctx.stroke();
  ctx.setLineDash([]);
}

function drawRiver(ctx, d, vp, time, theme) {
  const s = vp.scale;
  tracePath(ctx, d.points, vp);
  strokeLine(ctx, theme.grassDark, 0.4 * s);
  strokeLine(ctx, P.river, 0.32 * s);
  strokeLine(ctx, P.riverLight, 0.13 * s);
  strokeLine(ctx, 'rgba(255,255,255,0.75)', 0.04 * s, [0.07 * s, 0.45 * s], -time * 0.35 * s);
}

function drawPath(ctx, d, vp) {
  const s = vp.scale;
  tracePath(ctx, d.points, vp);
  strokeLine(ctx, P.pathEdge, 0.3 * s);
  strokeLine(ctx, P.path, 0.24 * s);
  strokeLine(ctx, P.pathStone, 0.1 * s, [0.001, 0.2 * s]);
}

function drawBridge(ctx, d, vp) {
  if (d.points.length !== 2) return;
  const a = vp.view(d.points[0]), b = vp.view(d.points[1]);
  const len = Math.hypot(b.x - a.x, b.y - a.y);
  if (len <= 1) return;
  const s = vp.scale;
  ctx.save();
  ctx.translate(a.x, a.y);
  ctx.rotate(Math.atan2(b.y - a.y, b.x - a.x));
  const half = 0.19 * s;
  roundRect(ctx, -0.04 * s, -half + 0.05 * s, len + 0.08 * s, half * 2, 0.05 * s, 'rgba(0,0,0,0.12)');
  const plankW = 0.09 * s, gap = 0.03 * s;
  for (let x = 0; x < len; x += plankW + gap) {
    roundRect(ctx, x, -half, Math.min(plankW, len - x), half * 2, 0.02 * s, P.wood);
  }
  for (const side of [-half, half]) {
    roundRect(ctx, -0.03 * s, side - 0.035 * s, len + 0.06 * s, 0.07 * s, 0.03 * s, P.woodDark);
  }
  ctx.restore();
}

function drawFlag(ctx, p, s, time) {
  const poleH = 0.9 * s;
  roundRect(ctx, p.x - 0.025 * s, p.y - poleH, 0.05 * s, poleH, 0.02 * s, P.woodDark);
  const wave = Math.sin(time * 3) * 0.04 * s;
  ctx.beginPath();
  ctx.moveTo(p.x + 0.02 * s, p.y - poleH);
  ctx.quadraticCurveTo(p.x + 0.25 * s, p.y - poleH - 0.05 * s + wave, p.x + 0.45 * s, p.y - poleH + 0.14 * s + wave);
  ctx.quadraticCurveTo(p.x + 0.22 * s, p.y - poleH + 0.3 * s - wave, p.x + 0.02 * s, p.y - poleH + 0.3 * s);
  ctx.closePath();
  ctx.fillStyle = P.flag;
  ctx.fill();
  starPath(ctx, p.x + 0.18 * s, p.y - poleH + 0.14 * s, 0.06 * s);
  ctx.fillStyle = '#fff';
  ctx.fill();
}

// ---- Sky

function drawClouds(ctx, width, height, time, theme) {
  const clouds = [[0.12, 6, 1.0, 0.1], [0.24, 4, 0.7, 0.55], [0.08, 3, 0.55, 0.8], [0.32, 5, 0.85, 0.3]];
  const span = width + 260;
  const fill = rgba(theme.cloud, 0.85);
  for (const [cy, speed, scale, offset] of clouds) {
    const x = ((offset * span + time * speed) % span) - 130;
    const y = cy * height;
    const r = 38 * scale;
    for (const [dx, dy, k] of [[-0.9, 0.2, 0.6], [0, 0, 0.85], [0.9, 0.25, 0.55]]) {
      circle(ctx, x + dx * r, y + dy * r, k * r, fill);
    }
  }
}

function drawStars(ctx, width, height, time) {
  for (let i = 0; i < 60; i++) {
    const x = rnd(11, i) * width;
    const y = rnd(12, i) * height * 0.75;
    const twinkle = time === 0 ? 0.8 : 0.45 + 0.55 * (0.5 + 0.5 * Math.sin(time * (1 + rnd(13, i) * 2) + i));
    const r = 0.8 + rnd(14, i) * 1.4;
    ctx.save();
    ctx.globalAlpha = twinkle;
    if (i % 9 === 0) {
      starPath(ctx, x, y, r * 2.6);
      ctx.fillStyle = '#FFF3C4';
      ctx.fill();
    } else {
      circle(ctx, x, y, r, '#fff');
    }
    ctx.restore();
  }
}

function drawFalling(ctx, width, height, time, petals) {
  const count = petals ? 26 : 55;
  for (let i = 0; i < count; i++) {
    const speed = (petals ? 14 : 20) + rnd(21, i) * 22;
    const span = height + 40;
    const y = ((rnd(22, i) * span + time * speed) % span) - 20;
    const x = rnd(23, i) * width + Math.sin(time * 0.8 + i) * (petals ? 18 : 8);
    if (petals) {
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(time * (0.6 + rnd(24, i)) + i);
      ctx.globalAlpha = 0.85;
      ctx.beginPath();
      ctx.ellipse(0, 0, 5, 3, 0, 0, TAU);
      ctx.fillStyle = i % 3 === 0 ? '#FFFFFF' : '#F7B6C8';
      ctx.fill();
      ctx.restore();
    } else {
      circle(ctx, x, y, 1.2 + rnd(25, i) * 2, 'rgba(255,255,255,0.9)');
    }
  }
}
