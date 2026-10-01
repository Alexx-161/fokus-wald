// Landing page: live previews drawn with the same code as the app, scroll-driven story, device-aware hints.

import { SPECIES, CATEGORIES, THEMES, findSpecies, resolveTheme, onSystemThemeChange, formatClock, smooth, clamp, TAU } from './app/js/data.js';
import { drawPlant } from './app/js/painter.js';
import { islandShape, viewport, drawIsland } from './app/js/island.js';

const $ = (sel) => document.querySelector(sel);
const now = () => Date.now() / 1000 - 1.75e9;
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

let theme = resolveTheme('wiese');
onSystemThemeChange(() => { theme = resolveTheme('wiese'); plantGrid.dirty = true; });

function fit(canvas) {
  const w = canvas.clientWidth, h = canvas.clientHeight;
  if (!w || !h) return null;
  const dpr = Math.min(window.devicePixelRatio || 1, 3);
  const pw = Math.round(w * dpr), ph = Math.round(h * dpr);
  if (canvas.width !== pw || canvas.height !== ph) {
    canvas.width = pw;
    canvas.height = ph;
  }
  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);
  return { ctx, w, h };
}

const onScreen = (el) => {
  const r = el.getBoundingClientRect();
  return r.bottom > 0 && r.top < innerHeight;
};

// ---- Shared demo world

const ORDER = ['kirsche', 'tulpe', 'tanne', 'sonnenblume', 'minze', 'fliegenpilz', 'lavendel', 'gaensebluemchen',
  'ahorn', 'leuchtpilz', 'glockenblume', 'steinpilz', 'regenbogenbaum', 'kristallbaum'];
const demoPlant = (i) => ({ speciesID: ORDER[i], seed: 0.17 + i * 0.113, minutes: [25, 45, 15, 60][i % 4] });

// River along the front of the island; the path stops at the bank, a bridge crosses, then the path goes on.
const DECORATIONS = [
  { kind: 'river', points: [{ x: -3.9, y: 0.75 }, { x: -2.2, y: 1.2 }, { x: -0.5, y: 1.5 }, { x: 1.3, y: 1.55 }, { x: 3.2, y: 1.15 }] },
  { kind: 'path', points: [{ x: -0.3, y: 2.02 }, { x: -0.42, y: 1.95 }, { x: -0.46, y: 1.86 }] },
  { kind: 'path', points: [{ x: -0.5, y: 1.1 }, { x: -0.2, y: 0.95 }, { x: 0.25, y: 0.75 }, { x: 0.42, y: 0.35 }, { x: 0.5, y: 0.1 }] },
  { kind: 'bridge', points: [{ x: -0.46, y: 1.86 }, { x: -0.5, y: 1.1 }] },
];

function drawRing(ctx, cx, cy, r, p, species, lineWidth) {
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, TAU);
  ctx.fillStyle = theme.card;
  ctx.fill();
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.arc(cx, cy, r - lineWidth * 1.6, 0, TAU);
  ctx.strokeStyle = theme.track;
  ctx.stroke();
  if (p > 0.005) {
    ctx.beginPath();
    ctx.arc(cx, cy, r - lineWidth * 1.6, -Math.PI / 2, -Math.PI / 2 + TAU * p);
    ctx.strokeStyle = species.deep;
    ctx.stroke();
  }
}

// ---- Hero: a little world that keeps planting itself

const GROW_SECONDS = 6;
const heroBase = 6;

function heroState(t) {
  const cycle = t / GROW_SECONDS;
  const planted = heroBase + (Math.floor(cycle) % (ORDER.length - heroBase));
  return { planted, progress: smooth(0, 0.92, cycle % 1), species: findSpecies(ORDER[planted]) };
}

function drawHero(t) {
  const canvas = $('#demo-island');
  if (!onScreen(canvas)) return;
  const f = fit(canvas);
  if (!f) return;
  const { planted, progress, species } = heroState(t);
  const plants = Array.from({ length: planted }, (_, i) => demoPlant(i));
  // A fixed shape keeps the camera steady while plants are added.
  const shape = islandShape(ORDER.length);
  const vp = viewport(f.w, f.h, shape, 1.08, { x: 0, y: 4 }, reducedMotion ? 0 : Math.sin(t * 0.7) * 5);
  drawIsland(f.ctx, f.w, f.h, vp, shape, {
    plants, growing: { species, seed: demoPlant(planted).seed, progress }, decorations: DECORATIONS, time: t, theme, sky: false,
  });

  const chip = fit($('#chip-plant'));
  if (chip) {
    drawRing(chip.ctx, chip.w / 2, chip.h / 2, chip.w / 2 - 1, progress, species, 3);
    const unit = (chip.h * 0.52) / (0.2 + 0.4 * smooth(0, 1, progress));
    drawPlant(chip.ctx, species, { x: chip.w / 2, y: chip.h * 0.76 }, unit, progress, 0.42, 0, { ground: false, detail: false });
  }
  $('#chip-time').textContent = formatClock(25 * 60 * (1 - progress));
  $('#chip-text').textContent = `${species.name} wächst …`;
}

// ---- Scroll story: scrolling grows the plant, then it lands on the island

const story = { el: $('#so-gehts'), step: -1 };

function storyProgress() {
  if (reducedMotion) return 0.62;
  const rect = story.el.getBoundingClientRect();
  return clamp(-rect.top / Math.max(1, rect.height - innerHeight));
}

function drawStory(t) {
  const canvas = $('#story-canvas');
  if (!onScreen(canvas)) return;
  const f = fit(canvas);
  if (!f) return;
  const { ctx, w, h } = f;
  const q = storyProgress();
  const species = findSpecies('kirsche');
  const p = smooth(0.08, 0.66, q);
  const toIsland = smooth(0.72, 0.9, q);

  if (toIsland > 0) {
    const plants = Array.from({ length: 9 }, (_, i) => demoPlant(i + 1));
    const shape = islandShape(10);
    const vp = viewport(w, h, shape, 1.04, { x: 0, y: 0 }, Math.sin(t * 0.7) * 4 + (1 - toIsland) * 30);
    ctx.save();
    ctx.globalAlpha = toIsland;
    drawIsland(ctx, w, h, vp, shape, {
      plants, growing: { species, seed: 0.42, progress: 1 }, decorations: [], time: t, theme, sky: false,
    });
    ctx.restore();
  }
  if (toIsland < 1) {
    const scale = 1 - 0.6 * toIsland;
    ctx.save();
    ctx.globalAlpha = 1 - toIsland;
    ctx.translate(w / 2, h / 2);
    ctx.scale(scale, scale);
    const r = Math.min(w, h) / 2 - 10;
    ctx.save();
    ctx.shadowColor = 'rgba(0,0,0,0.12)';
    ctx.shadowBlur = 40;
    ctx.shadowOffsetY = 16;
    ctx.beginPath();
    ctx.arc(0, 0, r, 0, TAU);
    ctx.fillStyle = theme.card;
    ctx.fill();
    ctx.restore();
    drawRing(ctx, 0, 0, r, p, species, 9);
    const unit = r * 2 * 0.7;
    drawPlant(ctx, species, { x: 0, y: unit * 0.34 }, unit, p, 0.42, t);
    ctx.restore();
  }

  const clock = $('#story-clock');
  clock.textContent = formatClock(25 * 60 * (1 - p));
  clock.style.opacity = String(1 - toIsland);
  $('#scroll-hint').style.opacity = q > 0.06 ? '0' : '1';

  const step = q < 0.2 ? 0 : q < 0.72 ? 1 : 2;
  if (step !== story.step && !reducedMotion) {
    story.step = step;
    document.querySelectorAll('.story-step').forEach((el, i) => {
      el.classList.toggle('on', i === step);
      el.classList.toggle('past', i < step);
    });
    document.querySelectorAll('#story-dots i').forEach((el, i) => el.classList.toggle('on', i === step));
  }
}

// ---- Plant showcase: every plant grows when the grid scrolls into view

const plantGrid = { el: $('#plants'), start: null, done: false, dirty: false };

function buildPlantGrid() {
  const category = Object.fromEntries(CATEGORIES.map((c) => [c.id, c.title]));
  plantGrid.el.innerHTML = SPECIES.map((s) =>
    `<div class="plant reveal"><canvas data-species="${s.id}"></canvas>${s.name}<small>${category[s.category]}</small></div>`).join('');
}

function drawPlantGrid(t) {
  if (plantGrid.done && !plantGrid.dirty) return;
  if (plantGrid.start === null) {
    if (!onScreen(plantGrid.el)) return;
    plantGrid.start = t;
  }
  let allGrown = true;
  plantGrid.el.querySelectorAll('canvas').forEach((canvas, i) => {
    const f = fit(canvas);
    if (!f) return;
    const p = reducedMotion ? 1 : smooth(0, 1, (t - plantGrid.start - 0.25 - i * 0.09) / 1.4);
    if (p < 1) allGrown = false;
    const u = Math.min(f.w, f.h / 0.7);
    drawPlant(f.ctx, findSpecies(canvas.dataset.species), { x: f.w / 2, y: f.h * 0.93 }, u, p, 0.37, p < 1 ? 0 : t, { ground: false });
  });
  plantGrid.done = allGrown;
  plantGrid.dirty = false;
}

// ---- Theme showcase

const themes = { id: 'wiese', auto: true, since: 0 };

function buildThemeChips() {
  $('#theme-chips').innerHTML = THEMES.map((t) => {
    const c = resolveTheme(t.id, true);
    return `<button class="theme-chip ${t.id === themes.id ? 'on' : ''}" data-theme="${t.id}">
      <i style="background:linear-gradient(${c.skyTop},${c.grass})"></i>${t.name}</button>`;
  }).join('');
}

function setTheme(id) {
  themes.id = id;
  document.querySelectorAll('.theme-chip').forEach((el) => el.classList.toggle('on', el.dataset.theme === id));
}

function drawThemeIsland(t) {
  const canvas = $('#theme-island');
  if (!onScreen(canvas)) return;
  if (themes.auto && !reducedMotion && t - themes.since > 3.5) {
    themes.since = t;
    setTheme(THEMES[(THEMES.findIndex((x) => x.id === themes.id) + 1) % THEMES.length].id);
  }
  const f = fit(canvas);
  if (!f) return;
  const plants = Array.from({ length: 12 }, (_, i) => demoPlant(i));
  const shape = islandShape(ORDER.length);
  drawIsland(f.ctx, f.w, f.h, viewport(f.w, f.h, shape, 1.05, { x: 0, y: 8 }, Math.sin(t * 0.7) * 4), shape, {
    plants, decorations: DECORATIONS, time: t, theme: resolveTheme(themes.id),
  });
}

// ---- Closing stage

function drawClosing(t) {
  const canvas = $('#closing-stage');
  if (!onScreen(canvas)) return;
  const f = fit(canvas);
  if (!f) return;
  const showcase = ['minze', 'fliegenpilz', 'tulpe', 'regenbogenbaum'];
  const species = findSpecies(showcase[Math.floor(t / 5) % showcase.length]);
  const p = reducedMotion ? 1 : smooth(0.05, 0.8, (t % 5) / 5);
  const r = Math.min(f.w, f.h) / 2 - 3;
  drawRing(f.ctx, f.w / 2, f.h / 2, r, p, species, 5);
  const unit = r * 2 * 0.7;
  drawPlant(f.ctx, species, { x: f.w / 2, y: f.h / 2 + unit * 0.34 }, unit, p, 0.42, t);
}

// ---- Page behaviour

function setupReveal() {
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('in');
        observer.unobserve(entry.target);
      }
    }
  }, { threshold: 0.15, rootMargin: '0px 0px -6% 0px' });
  document.querySelectorAll('.reveal').forEach((el, i) => {
    if (el.classList.contains('plant')) el.style.setProperty('--d', `${(i % 14) * 0.04}s`);
    observer.observe(el);
  });
}

function onScroll() {
  $('#nav').classList.toggle('scrolled', scrollY > 8);
  if (!reducedMotion && innerWidth > 900) {
    $('#hero-art').style.transform = `translateY(${Math.min(scrollY, 700) * 0.08}px)`;
  }
}

function detectDevice() {
  const ua = navigator.userAgent;
  if (/iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) return 'ios';
  if (/Android/.test(ua)) return 'android';
  if (/Windows/.test(ua)) return 'windows';
  if (/Macintosh/.test(ua)) return 'mac';
  return null;
}

function applyDevice() {
  const device = detectDevice();
  if (!device) return;
  const card = document.querySelector(`.device[data-device="${device}"]`);
  if (card) card.classList.add('yours-on');
  const second = $('#cta-second');
  const note = $('#cta-note');
  if (device === 'mac') {
    second.textContent = 'Mac-App laden';
    second.href = 'downloads/Fokus-Wald.zip';
    second.setAttribute('download', '');
    note.innerHTML = 'Mac-App mit Notch-Anzeige · ab macOS 14 · <a href="mac.html">Anleitung</a>';
  } else {
    second.textContent = 'So installierst du die App';
    note.textContent = {
      ios: 'Tipp: In Safari öffnen → Teilen → „Zum Home-Bildschirm“',
      android: 'Tipp: In Chrome öffnen → ⋮ → „App installieren“',
      windows: 'Tipp: In Edge oder Chrome öffnen → in der Adressleiste auf „Installieren“',
    }[device];
  }
}

function loop() {
  requestAnimationFrame(loop);
  const stamp = performance.now();
  if (stamp - (loop.last || 0) < 30) return;
  loop.last = stamp;
  const t = now();
  drawHero(t);
  drawStory(t);
  drawPlantGrid(t);
  drawThemeIsland(t);
  drawClosing(t);
}

buildPlantGrid();
buildThemeChips();
applyDevice();
setupReveal();
onScroll();
addEventListener('scroll', onScroll, { passive: true });
$('#theme-chips').addEventListener('click', (e) => {
  const chip = e.target.closest('[data-theme]');
  if (!chip) return;
  themes.auto = false;
  setTheme(chip.dataset.theme);
});
loop();
