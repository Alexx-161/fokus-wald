// What makes the island feel alive: sun and moon, animals, the lighthouse and the seedbed for saplings.
// Canvas port of the Mac app's Living.swift, so every platform draws the same scene.

import { TAU, clamp, smooth, rnd, rgba, findSpecies, PALETTE as P } from './data.js';
import { drawPlant, circle, roundRect } from './painter.js';

const NIGHT = '#10163A';
const CREAM = '#F7EEDD', FOX = '#E8894A', BIRD = '#7FB2E5', BIRD_DARK = '#5E97D1', BEAK = '#F2A93B';
const RED = '#E8645A', LAMP = '#FFE08A', GLOW = '#FFF3A0', STEEL = '#5A6270';
const WINGS = ['#F7B6C8', '#FFD45C'];

/**
 * How far the real time of day tints the sky: `night` runs from 0 (day) to 1 (night), `warm` peaks at dawn
 * and dusk. `hour` is the local time (0..<24), or null for the theme's plain sky.
 */
export function daylight(hour) {
  if (hour === null || hour === undefined) return { hour: null, night: 0, warm: 0 };
  const h = hour;
  const night = h < 5 || h >= 21 ? 1 : h < 7 ? 1 - (h - 5) / 2 : h >= 19 ? (h - 19) / 2 : 0;
  const warm = Math.max(0, 1 - Math.abs(h - 6) / 1.5, 1 - Math.abs(h - 19.5) / 1.5);
  return { hour, night, warm };
}

export const hourOf = (date = new Date()) => date.getHours() + date.getMinutes() / 60;

function oval(ctx, cx, cy, w, h, fill) {
  ctx.beginPath();
  ctx.ellipse(cx, cy, w / 2, h / 2, 0, 0, TAU);
  ctx.fillStyle = fill;
  ctx.fill();
}

function polygon(ctx, points, fill) {
  ctx.beginPath();
  points.forEach(([x, y], i) => (i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)));
  ctx.closePath();
  ctx.fillStyle = fill;
  ctx.fill();
}

function radial(ctx, x, y, r, color, alpha, inner = 0) {
  const gradient = ctx.createRadialGradient(x, y, inner, x, y, r);
  gradient.addColorStop(0, rgba(color, alpha));
  gradient.addColorStop(1, rgba(color, 0));
  circle(ctx, x, y, r, gradient);
}

// ---- Sky

export function drawSkyMood(ctx, width, height, light) {
  if (light.warm > 0) {
    const gradient = ctx.createLinearGradient(0, height * 0.15, 0, height);
    gradient.addColorStop(0, rgba('#FFAA6E', 0));
    gradient.addColorStop(1, rgba('#FFAA6E', 0.5 * light.warm));
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, width, height);
  }
  if (light.night > 0) {
    ctx.fillStyle = rgba(NIGHT, 0.66 * light.night);
    ctx.fillRect(0, 0, width, height);
  }
}

export function drawSunAndMoon(ctx, width, height, light) {
  if (light.hour === null) return;
  const h = light.hour;
  const position = (t) => ({ x: width * (0.14 + 0.72 * t), y: height * (0.4 - 0.28 * Math.sin(Math.PI * t)) });
  if (light.night < 1) {
    const p = position(clamp((h - 6) / 14));
    ctx.save();
    ctx.globalAlpha *= 1 - light.night;
    radial(ctx, p.x, p.y, 34, LAMP, 0.5, 8);
    circle(ctx, p.x, p.y, 15, LAMP);
    ctx.restore();
  }
  if (light.night > 0) {
    const p = position(clamp(((h < 12 ? h + 24 : h) - 19) / 12));
    ctx.save();
    ctx.globalAlpha *= light.night;
    radial(ctx, p.x, p.y, 30, '#FFFFFF', 0.28, 8);
    circle(ctx, p.x, p.y, 13, '#F4F1DE');
    circle(ctx, p.x - 4, p.y - 3, 3, '#DDD8BE');
    circle(ctx, p.x + 4, p.y + 4, 2, '#DDD8BE');
    ctx.restore();
  }
}

export function drawNightVeil(ctx, width, height, light) {
  if (light.night <= 0) return;
  ctx.fillStyle = rgba(NIGHT, 0.24 * light.night);
  ctx.fillRect(0, 0, width, height);
}

// ---- On the grass

function bunnySpot(shape, time) {
  const cycle = (time * 0.07) % 2;
  const u = smooth(0, 1, cycle < 1 ? cycle : 2 - cycle);
  const a = { x: -0.70 * shape.rx, y: 0.50 * shape.ry }, b = { x: -0.36 * shape.rx, y: 0.78 * shape.ry };
  return { pos: { x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u }, dir: cycle < 1 ? 1 : -1 };
}

const lighthouseSpot = (shape) => ({ x: -0.80 * shape.rx, y: -0.16 * shape.ry });

/** Where each waiting sapling stands: a row along the front edge of the island. */
export function seedbed(saplings, shape) {
  const spacing = Math.min(0.5, (shape.rx * 1.2) / Math.max(saplings.length, 1));
  return saplings.map((sapling, index) => {
    const x = (index - (saplings.length - 1) / 2) * spacing;
    return { sapling, pos: { x, y: shape.ry * 0.84 * Math.sqrt(Math.max(0, 1 - (x / shape.rx) ** 2)) } };
  });
}

/** Things standing on the grass, as `{ y, draw }` so the island can paint them back to front with its plants. */
export function groundItems(scene, vp, shape, time, night, theme) {
  const items = [];
  const s = vp.scale;
  const shadow = rgba(theme.grassDark, 0.7);

  for (const { sapling, pos } of seedbed(scene.saplings || [], shape)) {
    const species = findSpecies(sapling.speciesID);
    const unit = 1.3 * species.islandScale * s;
    items.push({ y: pos.y, draw: (ctx) => drawPlant(ctx, species, vp.view(pos), unit, sapling.progress, sapling.seed, time, { ground: true, detail: unit > 40 }) });
  }
  if (scene.lighthouse && scene.lighthouse !== 'none') {
    const pos = lighthouseSpot(shape);
    items.push({ y: pos.y, draw: (ctx) => drawLighthouse(ctx, vp.view(pos), s, scene.lighthouse === 'lit', shadow) });
  }
  const residents = scene.residents || [];
  if (residents.includes('bunny')) {
    const spot = bunnySpot(shape, time);
    items.push({ y: spot.pos.y, draw: (ctx) => drawBunny(ctx, vp.view(spot.pos), s, spot.dir, time, shadow) });
  }
  if (residents.includes('fox')) {
    const pos = { x: 0.56 * shape.rx, y: 0.70 * shape.ry };
    items.push({ y: pos.y, draw: (ctx) => drawFox(ctx, vp.view(pos), s, time, night > 0.6, shadow) });
  }
  return items;
}

function drawBunny(ctx, p, s, dir, time, shadow) {
  oval(ctx, p.x, p.y, 0.2 * s, 0.05 * s, shadow);
  ctx.save();
  ctx.translate(p.x, p.y - (time === 0 ? 0 : Math.abs(Math.sin(time * 5)) * 0.07 * s));
  ctx.scale(dir * s, s);
  circle(ctx, -0.1, -0.07, 0.035, '#fff');
  oval(ctx, 0, -0.075, 0.2, 0.14, CREAM);
  for (const x of [0.07, 0.108]) {
    oval(ctx, x, -0.26, 0.036, 0.12, CREAM);
    oval(ctx, x, -0.26, 0.016, 0.08, rgba(P.blush, 0.8));
  }
  circle(ctx, 0.09, -0.16, 0.062, CREAM);
  circle(ctx, 0.112, -0.166, 0.01, P.face);
  circle(ctx, 0.128, -0.14, 0.014, rgba(P.blush, 0.7));
  ctx.restore();
}

function drawFox(ctx, p, s, time, asleep, shadow) {
  oval(ctx, p.x, p.y, 0.26 * s, 0.06 * s, shadow);
  ctx.save();
  ctx.translate(p.x, p.y);
  // Sits on the right side of the island and looks towards its middle.
  ctx.scale(-s, s);
  ctx.save();
  ctx.translate(-0.07, -0.05);
  ctx.rotate(time === 0 ? 0 : Math.sin(time * 2) * 0.22);
  oval(ctx, -0.08, -0.02, 0.2, 0.09, FOX);
  circle(ctx, -0.16, -0.02, 0.038, CREAM);
  ctx.restore();
  oval(ctx, 0, -0.11, 0.16, 0.22, FOX);
  oval(ctx, 0.02, -0.09, 0.08, 0.14, CREAM);
  polygon(ctx, [[-0.04, -0.3], [-0.022, -0.39], [0.012, -0.32]], FOX);
  polygon(ctx, [[0.04, -0.32], [0.076, -0.39], [0.094, -0.3]], FOX);
  circle(ctx, 0.03, -0.26, 0.075, FOX);
  oval(ctx, 0.072, -0.235, 0.08, 0.055, CREAM);
  circle(ctx, 0.106, -0.24, 0.012, P.face);
  for (const x of [0.016, 0.062]) {
    if (asleep) roundRect(ctx, x - 0.012, -0.274, 0.024, 0.006, 0.003, P.face);
    else circle(ctx, x, -0.272, 0.01, P.face);
  }
  ctx.restore();
}

function drawLighthouse(ctx, p, s, lit, shadow) {
  oval(ctx, p.x, p.y + 0.02 * s, 0.5 * s, 0.1 * s, shadow);
  ctx.save();
  ctx.translate(p.x, p.y);
  ctx.scale(s, s);
  oval(ctx, 0, 0, 0.46, 0.12, '#B8BEC8');
  polygon(ctx, [[-0.17, 0], [0.17, 0], [0.11, -0.95], [-0.11, -0.95]], '#F7F3EC');
  for (const [from, to] of [[0.2, 0.38], [0.58, 0.76]]) {
    const w0 = 0.17 - 0.06 * from, w1 = 0.17 - 0.06 * to;
    polygon(ctx, [[-w0, -0.95 * from], [w0, -0.95 * from], [w1, -0.95 * to], [-w1, -0.95 * to]], RED);
  }
  roundRect(ctx, -0.04, -0.14, 0.08, 0.14, 0.035, P.woodDark);
  roundRect(ctx, -0.15, -1.0, 0.3, 0.05, 0.015, STEEL);
  ctx.fillStyle = lit ? LAMP : '#C9CED6';
  ctx.fillRect(-0.085, -1.17, 0.17, 0.17);
  ctx.fillStyle = rgba(STEEL, 0.6);
  ctx.fillRect(-0.008, -1.17, 0.016, 0.17);
  polygon(ctx, [[-0.12, -1.17], [0.12, -1.17], [0, -1.34]], RED);
  circle(ctx, 0, -1.35, 0.02, P.woodDark);
  ctx.restore();
}

// ---- In the air

/** Butterflies and the bird; both rest at night. */
export function drawAir(ctx, scene, vp, shape, time, night) {
  if (night >= 0.6) return;
  const s = vp.scale;
  const residents = scene.residents || [];
  if (residents.includes('butterfly')) {
    for (let i = 0; i < 2; i++) {
      const v = vp.view({
        x: shape.rx * (0.35 * Math.sin(time * 0.5 + i * 2.1) + (i === 0 ? -0.3 : 0.25)),
        y: shape.ry * 0.3 * Math.cos(time * 0.37 + i),
      });
      const flap = time === 0 ? 0.8 : 0.25 + 0.75 * Math.abs(Math.sin(time * 10 + i));
      ctx.save();
      ctx.translate(v.x, v.y - (0.55 + 0.15 * Math.sin(time * 1.3 + i)) * s);
      ctx.rotate(Math.sin(time * 0.9 + i) * 0.3);
      ctx.scale(s, s);
      for (const side of [-1, 1]) {
        oval(ctx, side * 0.045 * flap, -0.012, 0.09 * flap, 0.11, WINGS[i]);
        oval(ctx, side * 0.035 * flap, 0.05, 0.06 * flap, 0.07, rgba(WINGS[i], 0.75));
      }
      oval(ctx, 0, 0.012, 0.018, 0.09, P.face);
      ctx.restore();
    }
  }
  if (residents.includes('bird')) {
    const angle = time * 0.45;
    const v = vp.view({ x: shape.rx * 0.75 * Math.cos(angle), y: shape.ry * (-0.2 + 0.5 * Math.sin(angle)) });
    oval(ctx, v.x, v.y, 0.16 * s, 0.04 * s, 'rgba(0,0,0,0.1)');
    const flap = time === 0 ? 0.6 : Math.sin(time * 9);
    ctx.save();
    ctx.translate(v.x, v.y - (1.5 + 0.1 * Math.sin(time * 2)) * s);
    ctx.scale((Math.sin(angle) > 0 ? -1 : 1) * s, s);
    polygon(ctx, [[-0.09, -0.01], [-0.17, -0.05], [-0.16, 0.03]], BIRD_DARK);
    oval(ctx, 0, 0, 0.2, 0.12, BIRD);
    oval(ctx, 0.01, 0.025, 0.13, 0.06, '#EAF4FD');
    circle(ctx, 0.09, -0.04, 0.055, BIRD);
    polygon(ctx, [[0.14, -0.045], [0.185, -0.03], [0.14, -0.015]], BEAK);
    circle(ctx, 0.105, -0.05, 0.01, P.face);
    polygon(ctx, [[-0.05, -0.02], [0.04, -0.02], [-0.02, -0.02 - 0.14 * flap]], BIRD_DARK);
    ctx.restore();
  }
}

/** Light sources, drawn over the night tint so they glow: the lighthouse beam and fireflies. */
export function drawLights(ctx, scene, vp, shape, time, night) {
  const s = vp.scale;
  if (scene.lighthouse === 'lit') {
    const base = vp.view(lighthouseSpot(shape));
    const source = { x: base.x, y: base.y - 1.085 * s };
    const turn = Math.cos(time * 0.7);
    const spread = (0.06 + 0.2 * Math.abs(turn)) * 3.2 * s;
    const tip = { x: source.x + 3.2 * s * turn, y: source.y - 0.25 * s };
    const strength = (0.22 + 0.3 * night) * (0.35 + 0.65 * Math.abs(turn));
    const gradient = ctx.createLinearGradient(source.x, source.y, tip.x, tip.y);
    gradient.addColorStop(0, rgba(LAMP, strength));
    gradient.addColorStop(1, rgba(LAMP, 0));
    polygon(ctx, [[source.x, source.y], [tip.x, tip.y - spread], [tip.x, tip.y + spread]], gradient);
    radial(ctx, source.x, source.y, 0.45 * s, LAMP, 0.55);
  }
  if ((scene.residents || []).includes('fireflies') && night > 0.3) {
    for (let i = 0; i < 9; i++) {
      const v = vp.view({
        x: shape.rx * 0.85 * Math.sin(time * 0.13 * (1 + rnd(31, i)) + i * 1.7),
        y: shape.ry * 0.8 * Math.cos(time * 0.11 * (1 + rnd(32, i)) + i * 2.3),
      });
      const y = v.y - (0.25 + 0.7 * rnd(33, i) + 0.1 * Math.sin(time * 0.9 + i)) * s;
      ctx.save();
      ctx.globalAlpha *= night * (0.25 + 0.75 * Math.sin(time * 1.4 + i * 2.1) ** 2);
      radial(ctx, v.x, y, 0.16 * s, GLOW, 0.55);
      circle(ctx, v.x, y, 0.022 * s, GLOW);
      ctx.restore();
    }
  }
}

/** A tilted watering can with falling drops, shown over the plant during the break after a session. */
export function drawWateringCan(ctx, p, u, time) {
  const tilt = -0.45 + Math.sin(time * 1.5) * 0.06;
  const dark = '#6FB3DD';
  ctx.save();
  ctx.translate(p.x, p.y);
  ctx.rotate(tilt);
  ctx.scale(u, u);
  ctx.beginPath();
  ctx.ellipse(0.07, -0.02, 0.05, 0.05, 0, 0, TAU);
  ctx.strokeStyle = dark;
  ctx.lineWidth = 0.018;
  ctx.stroke();
  polygon(ctx, [[-0.06, -0.01], [-0.17, -0.075], [-0.155, -0.095], [-0.06, -0.045]], dark);
  roundRect(ctx, -0.07, -0.065, 0.14, 0.11, 0.025, P.river);
  roundRect(ctx, -0.055, -0.055, 0.03, 0.07, 0.012, 'rgba(255,255,255,0.35)');
  ctx.restore();
  // The spout's tip in unrotated coordinates, where the drops start.
  const tip = {
    x: p.x + u * (-0.165 * Math.cos(tilt) + 0.085 * Math.sin(tilt)),
    y: p.y + u * (-0.165 * Math.sin(tilt) - 0.085 * Math.cos(tilt)),
  };
  for (let i = 0; i < 4; i++) {
    const phase = (time * 1.2 + i * 0.25) % 1;
    ctx.save();
    ctx.globalAlpha *= 1 - phase;
    circle(ctx, tip.x - u * 0.008 * i, tip.y + u * 0.3 * phase, u * 0.012, P.river);
    ctx.restore();
  }
}

/** Draws one resident as a small icon, using the same code as on the island. */
export function drawResidentIcon(ctx, width, height, id, theme) {
  const shape = { rx: 1.95, ry: 1.069, depth: 1.375 };
  const focus = {
    butterfly: [-0.3 * shape.rx, 0.3 * shape.ry, 0.55, 4.2],
    bird: [0.75 * shape.rx, -0.2 * shape.ry, 1.5, 3.4],
    bunny: [-0.70 * shape.rx, 0.50 * shape.ry, 0.15, 2.6],
    fox: [0.56 * shape.rx, 0.70 * shape.ry, 0.2, 2.2],
    fireflies: [0, 0, 0.5, 1.2],
  }[id];
  const scale = (height * focus[3]) / 2;
  const ox = width / 2 - focus[0] * scale, oy = height / 2 - (focus[1] - focus[2]) * scale;
  const vp = { scale, view: (p) => ({ x: ox + p.x * scale, y: oy + p.y * scale }) };
  const scene = { residents: [id] };
  for (const item of groundItems(scene, vp, shape, 0, 0, theme)) item.draw(ctx);
  drawAir(ctx, scene, vp, shape, 0, 0);
  drawLights(ctx, scene, vp, shape, 0.6, 1);
}
