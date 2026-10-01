// Canvas port of the Mac app's island. Plants sit on a sunflower spiral, so the island grows outward
// from the middle and earlier plants never move when new ones are added.

import { TAU, clamp, rnd, rgba, findSpecies, isGolden, PALETTE as P } from './data.js';
import { drawPlant, circle, starPath, roundRect } from './painter.js';
import { daylight, drawSkyMood, drawSunAndMoon, drawNightVeil, groundItems, drawAir, drawLights } from './living.js';

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

const sizeFactor = (minutes, species) => clamp(0.75 + minutes / 100, 0.8, 1.35) * species.islandScale;

/** The plant under a point in island world coordinates; the one furthest to the front wins. */
export function plantAt(point, plants) {
  let best = null, bestY = -Infinity;
  plants.forEach((plant, index) => {
    const pos = plantPosition(index);
    const size = sizeFactor(plant.minutes, findSpecies(plant.speciesID));
    const h = 0.95 * size;
    const dx = (point.x - pos.x) / (0.42 * size), dy = (point.y - (pos.y - h * 0.5)) / (h * 0.62);
    if (dx * dx + dy * dy <= 1 && pos.y > bestY) {
      best = plant;
      bestY = pos.y;
    }
  });
  return best;
}

/**
 * `scene` is everything beyond plants and decorations:
 * { hour, month, residents: [ids], lighthouse: 'none' | 'dark' | 'lit', saplings: [...] } – all optional.
 * `sky: false` leaves the background transparent so the island can float on a page.
 */
export function drawIsland(ctx, width, height, vp, shape, opts) {
  const { plants = [], growing = null, decorations = [], draft = null, complete = false, time = 0, theme, sky = true, scene = {} } = opts;
  // Dark skies already are night, so the time of day only tints light ones.
  const light = daylight(sky && !theme.dark && scene.hour !== undefined ? scene.hour : null);
  if (sky) {
    const gradient = ctx.createLinearGradient(0, 0, 0, height);
    gradient.addColorStop(0, theme.skyTop);
    gradient.addColorStop(1, theme.skyBottom);
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, width, height);
    drawSkyMood(ctx, width, height, light);
    if (theme.particles === 'stars') drawStars(ctx, width, height, time, 1);
    else if (light.night > 0.05) drawStars(ctx, width, height, time, light.night);
    drawSunAndMoon(ctx, width, height, light);
    drawClouds(ctx, width, height, time, theme, 0.85 * (1 - 0.55 * light.night));
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

  // Everything standing on the grass is drawn back to front.
  const items = [];
  const addPlant = (pos, species, seed, minutes, progress) => {
    const factor = sizeFactor(minutes, species);
    const unit = 1.55 * factor * (0.92 + 0.1 * (pos.y / ry)) * s;
    items.push({
      y: pos.y,
      draw: () => {
        ell(pos.x, pos.y, 0.3 * factor, 0.08, rgba(theme.grassDark, 0.7));
        drawPlant(ctx, species, vp.view(pos), unit, progress, seed, time, { ground: false, detail: unit > 40, golden: isGolden(minutes) });
      },
    });
  };
  plants.forEach((p, i) => addPlant(plantPosition(i), findSpecies(p.speciesID), p.seed, p.minutes, 1));
  if (growing) addPlant(plantPosition(plants.length), growing.species, growing.seed, growing.minutes || 25, growing.progress);
  items.push(...groundItems(scene, vp, shape, time, light.night, theme));
  items.sort((p, q) => p.y - q.y);
  for (const item of items) item.draw(ctx);

  if (complete) drawFlag(ctx, pt(rx * 0.78, -ry * 0.18), s, time);
  drawAir(ctx, scene, vp, shape, time, light.night);
  drawNightVeil(ctx, width, height, light);
  drawLights(ctx, scene, vp, shape, time, light.night);
  if (!sky) return;
  if (theme.particles === 'snow') drawFalling(ctx, width, height, time, 'snow', 55);
  else if (theme.particles === 'petals') drawFalling(ctx, width, height, time, 'petals', 26);
  else if (theme.particles === 'none' && scene.month) {
    // Themes without weather of their own show a light version of the real season.
    const m = scene.month;
    if (m >= 3 && m <= 5) drawFalling(ctx, width, height, time, 'petals', 9);
    else if (m >= 9 && m <= 11) drawFalling(ctx, width, height, time, 'leaves', 12);
    else if (m === 12 || m <= 2) drawFalling(ctx, width, height, time, 'snow', 22);
  }
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

function drawClouds(ctx, width, height, time, theme, opacity) {
  const clouds = [[0.12, 6, 1.0, 0.1], [0.24, 4, 0.7, 0.55], [0.08, 3, 0.55, 0.8], [0.32, 5, 0.85, 0.3]];
  const span = width + 260;
  const fill = rgba(theme.cloud, opacity);
  for (const [cy, speed, scale, offset] of clouds) {
    const x = ((offset * span + time * speed) % span) - 130;
    const y = cy * height;
    const r = 38 * scale;
    for (const [dx, dy, k] of [[-0.9, 0.2, 0.6], [0, 0, 0.85], [0.9, 0.25, 0.55]]) {
      circle(ctx, x + dx * r, y + dy * r, k * r, fill);
    }
  }
}

function drawStars(ctx, width, height, time, opacity) {
  for (let i = 0; i < 60; i++) {
    const x = rnd(11, i) * width;
    const y = rnd(12, i) * height * 0.75;
    const twinkle = time === 0 ? 0.8 : 0.45 + 0.55 * (0.5 + 0.5 * Math.sin(time * (1 + rnd(13, i) * 2) + i));
    const r = 0.8 + rnd(14, i) * 1.4;
    ctx.save();
    ctx.globalAlpha = twinkle * opacity;
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

const LEAVES = ['#F2A93B', '#E5646B', '#D99A1E'];

function drawFalling(ctx, width, height, time, kind, count) {
  const flakes = kind === 'snow';
  for (let i = 0; i < count; i++) {
    const speed = (flakes ? 20 : 14) + rnd(21, i) * 22;
    const span = height + 40;
    const y = ((rnd(22, i) * span + time * speed) % span) - 20;
    const x = rnd(23, i) * width + Math.sin(time * 0.8 + i) * (flakes ? 8 : 18);
    if (flakes) {
      circle(ctx, x, y, 1.2 + rnd(25, i) * 2, 'rgba(255,255,255,0.9)');
    } else {
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(time * (0.6 + rnd(24, i)) + i);
      ctx.globalAlpha = 0.85;
      ctx.beginPath();
      ctx.ellipse(0, 0, 5, 3, 0, 0, TAU);
      ctx.fillStyle = kind === 'leaves' ? LEAVES[i % LEAVES.length] : i % 3 === 0 ? '#FFFFFF' : '#F7B6C8';
      ctx.fill();
      ctx.restore();
    }
  }
}
