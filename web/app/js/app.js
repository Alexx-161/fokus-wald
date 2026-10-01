import {
  SPECIES, CATEGORIES, THEMES, ISLAND_CAPACITY, findSpecies, resolveTheme, onSystemThemeChange,
  islandName, formatClock, formatDuration, smooth, rgba, TAU,
} from './data.js';
import { drawPlant } from './painter.js';
import { islandShape, viewport, drawIsland, clampToIsland } from './island.js';
import * as store from './store.js';
import { icon } from './icons.js';

const { state } = store;
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const wide = matchMedia('(min-width: 860px)');
// Animation clock in seconds; kept small so sin() stays precise.
const now = () => Date.now() / 1000 - 1.75e9;
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const isStandalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;

const TABS = [
  { id: 'timer', title: 'Timer', icon: 'timer' },
  { id: 'island', title: 'Insel', icon: 'island' },
  { id: 'catalog', title: 'Pflanzen', icon: 'sprout' },
  { id: 'stats', title: 'Statistik', icon: 'chart' },
  { id: 'archipelago', title: 'Archipel', icon: 'map' },
];

const TOOLS = [
  { id: 'look', title: 'Ansehen', icon: 'move', hint: 'Ziehen zum Verschieben · Zoomen mit zwei Fingern oder Mausrad' },
  { id: 'path', title: 'Weg', icon: 'path', hint: 'Ziehe über die Insel, um einen Weg zu zeichnen' },
  { id: 'river', title: 'Fluss', icon: 'waves', hint: 'Ziehe über die Insel, um einen Fluss zu zeichnen' },
  { id: 'bridge', title: 'Brücke', icon: 'bridge', hint: 'Ziehe eine Linie – z. B. quer über einen Fluss' },
  { id: 'erase', title: 'Radieren', icon: 'eraser', hint: 'Tippe auf einen Weg, Fluss oder eine Brücke' },
];

const ui = {
  tab: 'timer',
  island: null, // null follows the island currently being planted
  settings: false,
  tool: 'look',
  zoom: 1,
  pan: { x: 0, y: 0 },
  draft: [],
  confirmGiveUp: false,
  onboarding: !state.prefs.onboardingDone,
  page: 0,
  installPrompt: null,
};

let theme = resolveTheme(state.prefs.themeID);

// ---- Helpers

function applyTheme() {
  theme = resolveTheme(state.prefs.themeID);
  const root = document.documentElement.style;
  for (const key of ['bg', 'card', 'track', 'ink', 'muted']) root.setProperty('--' + key, theme[key]);
  root.setProperty('color-scheme', theme.dark ? 'dark' : 'light');
  $('meta[name="theme-color"]').content = theme.bg;
}

/** Sizes the backing store for the device pixel ratio and returns a context in CSS pixels. */
function fit(canvas) {
  if (!canvas) return null;
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

const shownIsland = () => Math.min(ui.island ?? store.currentIsland(), store.currentIsland());
const activeTab = () => (wide.matches && ui.tab === 'timer' ? 'island' : ui.tab);

function toast(message) {
  const el = $('#toast');
  el.textContent = message;
  el.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { el.hidden = true; }, 2600);
}

// ---- Shell

function buildShell() {
  $('#app').innerHTML = `
    <div class="shell">
      <section class="timer-panel" id="timer-panel"></section>
      <section class="content">
        <nav class="toptabs" id="toptabs"></nav>
        <div class="view" id="view-island">
          <div class="island-wrap">
            <canvas id="island" class="island-canvas"></canvas>
            <div class="island-header" id="island-header"></div>
            <div class="island-tools" id="island-tools"></div>
          </div>
        </div>
        <div class="view scroll" id="view-catalog"></div>
        <div class="view scroll" id="view-stats"></div>
        <div class="view scroll" id="view-archipelago"></div>
      </section>
      <nav class="tabbar" id="tabbar"></nav>
    </div>
    <div class="onboarding" id="onboarding" hidden></div>
    <div class="toast" id="toast" hidden></div>
    <input type="file" id="import-file" accept="application/json,.json" hidden>`;
}

function renderTabs() {
  const current = activeTab();
  const button = (t) => `<button class="tab ${t.id === current ? 'active' : ''}" data-action="tab" data-tab="${t.id}">${icon(t.icon)}<span>${t.title}</span></button>`;
  $('#tabbar').innerHTML = TABS.map(button).join('');
  $('#toptabs').innerHTML = TABS.filter((t) => t.id !== 'timer').map(button).join('');
  $('#timer-panel').classList.toggle('active', current === 'timer');
  $('.shell').classList.toggle('show-content', current !== 'timer');
  for (const id of ['island', 'catalog', 'stats', 'archipelago']) {
    $('#view-' + id).classList.toggle('active', id === current);
  }
}

function renderAll() {
  renderTabs();
  renderTimer();
  renderActiveView();
}

function renderActiveView() {
  const tab = activeTab();
  if (tab === 'island') renderIslandChrome();
  if (tab === 'catalog') renderCatalog();
  if (tab === 'stats') renderStats();
  if (tab === 'archipelago') renderArchipelago();
}

// ---- Timer panel

function statusText() {
  const species = store.timerSpecies();
  switch (state.timer.phase) {
    case 'idle': return `Als Nächstes wächst: ${species.name}`;
    case 'running': return `${species.name} wächst …`;
    case 'paused': return 'Pausiert – deine Pflanze wartet auf dich';
    default: {
      const last = state.plants[state.plants.length - 1];
      if (last && store.plantsOn(last.island).length === ISLAND_CAPACITY) {
        return `${islandName(last.island)} ist vollendet! Eine neue Insel taucht auf.`;
      }
      return `${species.name} steht jetzt auf deiner Insel!`;
    }
  }
}

function renderTimer() {
  const t = state.timer;
  const species = store.timerSpecies();
  const idle = t.phase === 'idle';
  const unlocked = t.phase === 'finished' ? SPECIES.find((s) => s.unlockAt > 0 && s.unlockAt === state.plants.length) : null;
  const primary = `style="background:${species.deep}"`;

  let controls = '';
  if (idle) {
    controls = `<button class="btn primary" ${primary} data-action="start">${icon('leaf', 18)} Pflanzen</button>`;
  } else if (t.phase === 'running' || t.phase === 'paused') {
    controls = (t.phase === 'running'
      ? `<button class="btn soft" data-action="pause">${icon('pause', 18)} Pause</button>`
      : `<button class="btn primary" ${primary} data-action="resume">${icon('play', 18)} Weiter</button>`)
      + `<button class="btn soft ${ui.confirmGiveUp ? 'danger' : ''}" data-action="giveup">${ui.confirmGiveUp ? 'Wirklich?' : 'Aufgeben'}</button>`;
  } else {
    controls = `<button class="btn primary" ${primary} data-action="reset">${icon('plus', 18)} Neue Pflanze</button>`;
  }

  $('#timer-panel').innerHTML = `
    <div class="timer-inner">
      <header class="row">
        <span class="brand" style="color:${species.deep}">${icon('leaf')}</span>
        <strong class="brand-name">Fokus-Wald</strong>
        <span class="spacer"></span>
        <button class="iconbtn" data-action="toggle-settings" aria-label="Einstellungen">${icon(ui.settings ? 'close' : 'settings', 16)}</button>
      </header>
      <canvas id="stage" class="stage"></canvas>
      <div class="clockrow">
        ${idle ? `<button class="iconbtn" data-action="minutes-down" aria-label="Kürzer">${icon('minus', 16)}</button>` : ''}
        <span id="clock" class="clock ${t.phase === 'paused' ? 'dim' : ''}"></span>
        ${idle ? `<button class="iconbtn" data-action="minutes-up" aria-label="Länger">${icon('plus', 16)}</button>` : ''}
      </div>
      <p class="status">${statusText()}</p>
      ${unlocked ? `<p class="unlocked" style="color:${unlocked.deep}">${icon('unlock', 15)} Neu freigeschaltet: ${unlocked.name}</p>` : ''}
      ${idle ? `
        <button class="chip-select" data-action="tab" data-tab="catalog" title="Auswählen, was wachsen soll">
          <canvas class="mini-plant" data-species="${species.id}" data-seed="${t.seed}"></canvas>
          <span>${state.prefs.selection === store.RANDOM ? 'Überraschung' : species.name}</span>${icon('down', 12)}
        </button>
        <div class="presets">
          ${[15, 25, 45, 60].map((m) => `<button class="chip ${state.prefs.minutes === m ? 'on' : ''}" ${state.prefs.minutes === m ? primary : ''} data-action="preset" data-min="${m}">${m} min</button>`).join('')}
        </div>` : ''}
      <div class="controls">${controls}</div>
      ${ui.settings ? settingsHTML() : ''}
    </div>`;
  drawStatic($('#timer-panel'));
  updateClock(true);
}

function settingsHTML() {
  const toggle = (key, title, text) => `
    <label class="toggle">
      <span><b>${title}</b><small>${text}</small></span>
      <input type="checkbox" data-pref="${key}" ${state.prefs[key] ? 'checked' : ''}>
      <i></i>
    </label>`;
  let install = '';
  if (ui.installPrompt) {
    install = `<button class="linkbtn" data-action="install">${icon('download', 15)} Als App installieren</button>`;
  } else if (isIOS && !isStandalone) {
    install = `<p class="hint">${icon('share', 15)} Als App installieren: unten auf das Teilen-Symbol tippen, dann „Zum Home-Bildschirm“.</p>`;
  }
  return `
    <div class="settings">
      <b>Theme: ${resolveTheme(state.prefs.themeID).name}</b>
      <div class="swatches">
        ${THEMES.map((t) => {
          const c = resolveTheme(t.id, true);
          return `<button class="swatch ${t.id === state.prefs.themeID ? 'on' : ''}" data-action="theme" data-id="${t.id}" title="${t.name}"
            style="background:linear-gradient(${c.skyTop},${c.skyBottom})"><i style="background:${c.grass};border-color:${c.earth}"></i></button>`;
        }).join('')}
      </div>
      <hr>
      ${toggle('sound', 'Ton bei Ablauf', 'Ein sanfter Klang, wenn deine Pflanze fertig ist.')}
      ${'wakeLock' in navigator ? toggle('keepAwake', 'Bildschirm anlassen', 'Während einer Session geht der Bildschirm nicht aus.') : ''}
      ${'Notification' in window ? toggle('notify', 'Mitteilung bei Ablauf', 'Meldet sich, wenn die App im Hintergrund ist.') : ''}
      <hr>
      <button class="linkbtn" data-action="export">${icon('download', 15)} Fortschritt sichern</button>
      <button class="linkbtn" data-action="import">${icon('upload', 15)} Sicherung laden</button>
      <button class="linkbtn" data-action="intro">${icon('sparkles', 15)} Einführung erneut ansehen</button>
      ${install}
      <p class="hint">Dein Fortschritt wird nur auf diesem Gerät gespeichert.</p>
    </div>`;
}

let lastClock = '';
function updateClock(force = false) {
  const text = formatClock(store.remainingAt());
  if (!force && text === lastClock) return;
  lastClock = text;
  const el = $('#clock');
  if (el) el.textContent = text;
  document.title = state.timer.phase === 'running' ? `${text} · Fokus-Wald` : 'Fokus-Wald';
}

function drawStage() {
  const canvas = $('#stage');
  if (!canvas || !canvas.offsetParent) return;
  const f = fit(canvas);
  if (!f) return;
  const { ctx, w, h } = f;
  const species = store.timerSpecies();
  const p = store.progressAt();
  const cx = w / 2, cy = h / 2, r = Math.min(w, h) / 2 - 4;
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.08)';
  ctx.shadowBlur = 14;
  ctx.shadowOffsetY = 4;
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, TAU);
  ctx.fillStyle = theme.card;
  ctx.fill();
  ctx.restore();
  ctx.lineWidth = 6;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.arc(cx, cy, r - 10, 0, TAU);
  ctx.strokeStyle = theme.track;
  ctx.stroke();
  if (p > 0) {
    ctx.beginPath();
    ctx.arc(cx, cy, r - 10, -Math.PI / 2, -Math.PI / 2 + TAU * p);
    ctx.strokeStyle = species.deep;
    ctx.stroke();
  }
  const unit = (r * 2) * 0.72;
  drawPlant(ctx, species, { x: cx, y: cy + unit * 0.34 }, unit, p, state.timer.seed, now());
}

// ---- Static canvases (plant icons, island thumbnails)

function drawStatic(root) {
  for (const canvas of $$('canvas[data-species]', root)) {
    const f = fit(canvas);
    if (!f) continue;
    const u = Math.min(f.w, f.h / 0.7);
    drawPlant(f.ctx, findSpecies(canvas.dataset.species), { x: f.w / 2, y: f.h * 0.93 }, u, 1,
      Number(canvas.dataset.seed || 0.37), 0, { ground: false, detail: u > 40 });
  }
  for (const canvas of $$('canvas[data-island]', root)) {
    const f = fit(canvas);
    if (!f) continue;
    const index = Number(canvas.dataset.island);
    const plants = canvas.dataset.demo ? demoPlants() : store.plantsOn(index);
    const shape = islandShape(plants.length);
    drawIsland(f.ctx, f.w, f.h, viewport(f.w, f.h, shape), shape, {
      plants, decorations: canvas.dataset.demo ? [] : store.decorationsOn(index),
      complete: !canvas.dataset.demo && store.isComplete(index), time: 0, theme,
    });
  }
}

const demoPlants = () => ['minze', 'tulpe', 'kirsche', 'tanne', 'sonnenblume', 'fliegenpilz', 'lavendel', 'gaensebluemchen']
  .map((speciesID, i) => ({ speciesID, seed: 0.2 + i * 0.09, minutes: 25 }));

// ---- Island view

function growingPlant(island) {
  const phase = state.timer.phase;
  if (island !== store.currentIsland() || (phase !== 'running' && phase !== 'paused')) return null;
  return { species: store.timerSpecies(), seed: state.timer.seed, progress: store.progressAt() };
}

function currentShape() {
  const island = shownIsland();
  return islandShape(store.plantsOn(island).length + (growingPlant(island) ? 1 : 0));
}

function renderIslandChrome() {
  const island = shownIsland();
  const count = store.plantsOn(island).length;
  const tool = TOOLS.find((t) => t.id === ui.tool);
  $('#island-header').innerHTML = `
    <button class="iconbtn" data-action="island-prev" ${island === 0 ? 'disabled' : ''} aria-label="Vorherige Insel">${icon('left', 14)}</button>
    <div class="island-title">
      <div><b>${islandName(island)}</b>${store.isComplete(island) ? `<span class="badge">${icon('flag', 11)} vollendet</span>` : ''}</div>
      <div class="capacity"><i><b style="width:${Math.min(100, (count / ISLAND_CAPACITY) * 100)}%"></b></i><span>${Math.min(count, ISLAND_CAPACITY)} / ${ISLAND_CAPACITY}</span></div>
    </div>
    <button class="iconbtn" data-action="island-next" ${island >= store.currentIsland() ? 'disabled' : ''} aria-label="Nächste Insel">${icon('right', 14)}</button>`;
  $('#island-tools').innerHTML = `
    <div class="hint-pill">${tool.title}: ${tool.hint}</div>
    <div class="toolbar">
      ${TOOLS.map((t) => `<button class="tool ${t.id === ui.tool ? 'on' : ''}" data-action="tool" data-tool="${t.id}" title="${t.title}">${icon(t.icon, 17)}<span>${t.title}</span></button>`).join('')}
      <span class="sep"></span>
      <button class="iconbtn" data-action="undo" title="Letzte Zeichnung zurücknehmen">${icon('undo', 14)}</button>
      <button class="iconbtn" data-action="zoom-out" title="Verkleinern">${icon('zoomout', 14)}</button>
      <button class="iconbtn" data-action="zoom-in" title="Vergrößern">${icon('zoomin', 14)}</button>
      <button class="iconbtn" data-action="zoom-reset" title="Ansicht zurücksetzen">${icon('reset', 14)}</button>
    </div>`;
}

function drawIslandCanvas() {
  const canvas = $('#island');
  if (!canvas || !canvas.offsetParent) return;
  const f = fit(canvas);
  if (!f) return;
  const island = shownIsland();
  const plants = store.plantsOn(island);
  const growing = growingPlant(island);
  const shape = islandShape(plants.length + (growing ? 1 : 0));
  const t = now();
  const bob = ui.tool === 'look' && ui.zoom === 1 ? Math.sin(t * 0.7) * 4 : 0;
  const vp = viewport(f.w, f.h, shape, ui.zoom, ui.pan, bob);
  let draft = null;
  if (ui.draft.length >= 2) {
    draft = { kind: ui.tool === 'river' ? 'river' : ui.tool === 'bridge' ? 'bridge' : 'path', points: ui.draft };
  }
  drawIsland(f.ctx, f.w, f.h, vp, shape, {
    plants, growing, decorations: store.decorationsOn(island), draft, complete: store.isComplete(island), time: t, theme,
  });
}

function setZoom(z) {
  ui.zoom = Math.min(6, Math.max(1, z));
  if (ui.zoom === 1) ui.pan = { x: 0, y: 0 };
  else clampPan();
}

function clampPan() {
  const canvas = $('#island');
  const mx = (canvas.clientWidth * (ui.zoom - 1)) / 2 + 60, my = (canvas.clientHeight * (ui.zoom - 1)) / 2 + 60;
  ui.pan.x = Math.min(mx, Math.max(-mx, ui.pan.x));
  ui.pan.y = Math.min(my, Math.max(-my, ui.pan.y));
}

function bindIslandGestures() {
  const canvas = $('#island');
  const pointers = new Map();
  let panStart = null;
  let pinch = null;

  const local = (e) => {
    const rect = canvas.getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  };
  const world = (pos) => {
    const shape = currentShape();
    const vp = viewport(canvas.clientWidth, canvas.clientHeight, shape, ui.zoom, ui.pan);
    return clampToIsland(shape, vp.world(pos));
  };

  canvas.addEventListener('pointerdown', (e) => {
    canvas.setPointerCapture(e.pointerId);
    pointers.set(e.pointerId, local(e));
    if (pointers.size === 2) {
      const [a, b] = [...pointers.values()];
      pinch = { dist: Math.hypot(a.x - b.x, a.y - b.y), zoom: ui.zoom };
      ui.draft = [];
      panStart = null;
      return;
    }
    const pos = local(e);
    if (ui.tool === 'look') panStart = { pos, pan: { ...ui.pan } };
    else if (ui.tool === 'path' || ui.tool === 'river') ui.draft = [world(pos)];
    else if (ui.tool === 'bridge') ui.draft = [world(pos), world(pos)];
  });

  canvas.addEventListener('pointermove', (e) => {
    if (!pointers.has(e.pointerId)) return;
    const pos = local(e);
    pointers.set(e.pointerId, pos);
    if (pinch && pointers.size === 2) {
      const [a, b] = [...pointers.values()];
      setZoom(pinch.zoom * (Math.hypot(a.x - b.x, a.y - b.y) / Math.max(1, pinch.dist)));
      return;
    }
    if (ui.tool === 'look' && panStart) {
      ui.pan = { x: panStart.pan.x + pos.x - panStart.pos.x, y: panStart.pan.y + pos.y - panStart.pos.y };
      clampPan();
    } else if ((ui.tool === 'path' || ui.tool === 'river') && ui.draft.length) {
      const w = world(pos), last = ui.draft[ui.draft.length - 1];
      if (Math.hypot(w.x - last.x, w.y - last.y) >= 0.08) ui.draft.push(w);
    } else if (ui.tool === 'bridge' && ui.draft.length === 2) {
      ui.draft[1] = world(pos);
    }
  });

  const end = (e) => {
    if (!pointers.has(e.pointerId)) return;
    const pos = local(e);
    pointers.delete(e.pointerId);
    if (pinch) {
      if (pointers.size < 2) pinch = null;
      return;
    }
    const island = shownIsland();
    if (e.type === 'pointerup') {
      if ((ui.tool === 'path' || ui.tool === 'river') && ui.draft.length >= 2) {
        store.addDecoration(ui.tool, ui.draft, island);
      } else if (ui.tool === 'bridge' && ui.draft.length === 2
        && Math.hypot(ui.draft[1].x - ui.draft[0].x, ui.draft[1].y - ui.draft[0].y) > 0.3) {
        store.addDecoration('bridge', ui.draft, island);
      } else if (ui.tool === 'erase') {
        store.removeDecorationNear(world(pos), island, 0.3);
      }
    }
    ui.draft = [];
    panStart = null;
  };
  canvas.addEventListener('pointerup', end);
  canvas.addEventListener('pointercancel', end);

  canvas.addEventListener('wheel', (e) => {
    e.preventDefault();
    setZoom(ui.zoom * Math.exp(-e.deltaY * (e.ctrlKey ? 0.012 : 0.0025)));
  }, { passive: false });
}

// ---- Catalog

function renderCatalog() {
  const card = (s) => {
    const unlocked = store.isUnlocked(s);
    const selected = state.prefs.selection === s.id;
    const missing = s.unlockAt - state.plants.length;
    const planted = store.countOf(s);
    const foot = !unlocked ? `${icon('lock', 12)} noch ${missing} ${missing === 1 ? 'Session' : 'Sessions'}`
      : planted > 0 ? `${planted}× gepflanzt` : 'noch nie gepflanzt';
    return `
      <button class="card species ${selected ? 'on' : ''} ${unlocked ? '' : 'locked'}" ${unlocked ? '' : 'disabled'}
        style="--deep:${s.deep}" data-action="select" data-id="${s.id}">
        ${selected ? `<span class="tick">${icon('check', 14)}</span>` : ''}
        <span class="plant-bubble" style="background:${rgba(s.light, 0.35)}">
          <canvas data-species="${s.id}"></canvas>
          ${unlocked ? '' : `<span class="lock">${icon('lock', 22)}</span>`}
        </span>
        <b>${s.name}</b>
        <small>${s.blurb}</small>
        <span class="foot">${foot}</span>
      </button>`;
  };
  const random = state.prefs.selection === store.RANDOM;
  $('#view-catalog').innerHTML = `
    <p class="lead">Wähle, was in deiner nächsten Session wachsen soll. Mit jeder Session schaltest du neue Pflanzen frei.</p>
    <button class="card random ${random ? 'on' : ''}" data-action="select" data-id="${store.RANDOM}">
      <span class="dice">${icon('dice', 28)}</span>
      <span><b>Überraschung</b><small>Jedes Mal eine zufällige freigeschaltete Pflanze</small></span>
      ${random ? `<span class="tick">${icon('check', 14)}</span>` : ''}
    </button>
    ${CATEGORIES.map((c) => `
      <h3>${icon(c.icon, 18)} ${c.title}</h3>
      <div class="grid">${SPECIES.filter((s) => s.category === c.id).map(card).join('')}</div>`).join('')}`;
  drawStatic($('#view-catalog'));
}

// ---- Statistics

function renderStats() {
  const days = store.minutesPerDay(7);
  const max = Math.max(25, ...days.map((d) => d.minutes));
  const today = new Date().toDateString();
  const weekday = new Intl.DateTimeFormat('de-DE', { weekday: 'short' });
  const tile = (value, label, ic) => `<div class="card tile"><span class="ic">${icon(ic, 15)}</span><b>${value}</b><small>${label}</small></div>`;
  const fav = store.favoriteSpecies();
  const next = store.nextUnlock();
  const s = store.streak();
  $('#view-stats').innerHTML = `
    <div class="tiles">
      ${tile(state.plants.length, 'Pflanzen', 'leaf')}
      ${tile(formatDuration(store.totalMinutes()), 'Fokuszeit', 'clock')}
      ${tile(store.todayCount(), 'heute', 'sun')}
      ${tile(`${s} ${s === 1 ? 'Tag' : 'Tage'}`, 'Serie', 'flame')}
      ${tile(store.currentIsland(), 'Inseln vollendet', 'flag')}
    </div>
    <div class="card block">
      <b>Fokus der letzten 7 Tage</b>
      <div class="chart">
        ${days.map((d) => `
          <div class="bar">
            <small>${d.minutes || ''}</small>
            <i class="${d.day.toDateString() === today ? 'today' : ''}" style="height:${Math.max(4, (120 * d.minutes) / max)}px"></i>
            <small>${weekday.format(d.day)}</small>
          </div>`).join('')}
      </div>
    </div>
    <div class="pair">
      <div class="card block">
        <b>Lieblingspflanze</b>
        ${fav ? `<div class="mini-row"><canvas data-species="${fav.id}"></canvas><span><b>${fav.name}</b><small>${store.countOf(fav)}× gepflanzt</small></span></div>`
          : '<small>Pflanze deine erste Pflanze!</small>'}
      </div>
      <div class="card block">
        <b>Nächste Freischaltung</b>
        ${next ? `<div class="mini-row"><canvas class="gray" data-species="${next.id}"></canvas><span><b>${next.name}</b>
          <span class="capacity"><i><b style="width:${Math.min(100, (state.plants.length / next.unlockAt) * 100)}%"></b></i><span>${state.plants.length} / ${next.unlockAt}</span></span></span></div>`
          : '<small>Alles freigeschaltet – Wahnsinn!</small>'}
      </div>
    </div>`;
  drawStatic($('#view-stats'));
}

// ---- Archipelago

function renderArchipelago() {
  const dateFormat = new Intl.DateTimeFormat('de-DE', { dateStyle: 'medium' });
  const cards = [];
  for (let i = store.currentIsland(); i >= 0; i--) {
    const plants = store.plantsOn(i);
    const complete = store.isComplete(i);
    const done = complete ? `Vollendet am ${dateFormat.format(new Date(plants[plants.length - 1].date))}` : `Wächst gerade · ${plants.length} / ${ISLAND_CAPACITY}`;
    cards.push(`
      <button class="card island-card" data-action="open-island" data-index="${i}">
        <canvas data-island="${i}"></canvas>
        <span class="row"><b>${islandName(i)}</b><span class="spacer"></span>${complete ? `<span style="color:#E07A99">${icon('flag', 15)}</span>` : ''}</span>
        <small>${done}</small>
      </button>`);
  }
  $('#view-archipelago').innerHTML = `
    <p class="lead">Hat eine Insel ${ISLAND_CAPACITY} Pflanzen, ist sie vollendet: Sie bekommt ein Fähnchen, wandert in dein Archipel, und eine neue Insel taucht auf.</p>
    <div class="grid islands">${cards.join('')}</div>`;
  drawStatic($('#view-archipelago'));
}

// ---- Onboarding

const PAGES = 5;

function renderOnboarding() {
  const el = $('#onboarding');
  el.hidden = !ui.onboarding;
  if (!ui.onboarding) return;
  const step = (ic, title, text) => `<div class="step"><span class="ic">${icon(ic, 16)}</span><span><b>${title}</b><small>${text}</small></span></div>`;
  let body = '';
  if (ui.page === 0) {
    body = `
      <div class="ob-center">
        <canvas id="ob-canvas" class="ob-canvas"></canvas>
        <h1>Willkommen im Fokus&#8209;Wald</h1>
        <p class="lead center">Konzentrier dich – und schau zu, wie dabei etwas Schönes wächst.</p>
      </div>`;
  } else if (ui.page === 1) {
    body = `
      <h2>So funktioniert's</h2>
      <canvas class="ob-island" data-island="0" data-demo="1"></canvas>
      ${step('timer', 'Zeit wählen & pflanzen', 'Stell ein, wie lange du dich konzentrieren willst.')}
      ${step('leaf', 'Deine Pflanze wächst mit', 'Solange du fokussiert bleibst, wächst sie vom Keimling zur vollen Pracht.')}
      ${step('island', 'Deine Insel füllt sich', 'Jede Session pflanzt sie auf deine Insel. Bei 30 Pflanzen ist sie vollendet – und eine neue taucht auf.')}`;
  } else if (ui.page === 2) {
    body = `
      <h2>Wähle deinen Stil</h2>
      <p class="lead">Du kannst das Theme später jederzeit in den Einstellungen ändern.</p>
      <div class="grid themes">
        ${THEMES.map((t) => {
          const c = resolveTheme(t.id, true);
          return `<button class="card theme ${t.id === state.prefs.themeID ? 'on' : ''}" data-action="theme" data-id="${t.id}">
            <span class="preview" style="background:linear-gradient(${c.skyTop},${c.skyBottom})"><i style="background:${c.grass};border-color:${c.earth}"></i></span>
            <b>${t.name}</b></button>`;
        }).join('')}
      </div>`;
  } else if (ui.page === 3) {
    const random = state.prefs.selection === store.RANDOM;
    body = `
      <h2>Was soll zuerst wachsen?</h2>
      <p class="lead">Mit jeder Session schaltest du weitere Pflanzen frei – bis hin zu Pilzen und Kristallbäumen.</p>
      <div class="grid choices">
        <button class="card choice ${random ? 'on' : ''}" data-action="select" data-id="${store.RANDOM}"><span class="dice">${icon('dice', 26)}</span><b>Überraschung</b></button>
        ${SPECIES.filter(store.isUnlocked).map((s) => `
          <button class="card choice ${state.prefs.selection === s.id ? 'on' : ''}" data-action="select" data-id="${s.id}">
            <canvas data-species="${s.id}"></canvas><b>${s.name}</b></button>`).join('')}
      </div>
      <b class="q">Wie lange möchtest du dich konzentrieren?</b>
      <div class="presets left">
        ${[15, 25, 45, 60].map((m) => `<button class="chip ${state.prefs.minutes === m ? 'on' : ''}" data-action="preset" data-min="${m}">${m} min</button>`).join('')}
      </div>`;
  } else {
    const install = isStandalone ? ''
      : isIOS ? step('share', 'Als App aufs iPhone oder iPad', 'In Safari unten auf das Teilen-Symbol tippen, dann „Zum Home-Bildschirm“. Danach startet Fokus-Wald wie eine echte App.')
        : step('download', 'Als App installieren', 'In Chrome oder Edge oben in der Adressleiste auf „App installieren“ klicken – oder später in den Einstellungen.');
    body = `
      <h2>Fast geschafft!</h2>
      ${install}
      ${step('lock', 'Alles bleibt bei dir', 'Dein Fortschritt wird nur auf diesem Gerät gespeichert. In den Einstellungen kannst du ihn sichern.')}
      ${step('map', 'Mehr entdecken', 'Unter „Insel“ kannst du zoomen und Wege, Flüsse und Brücken malen. „Pflanzen“ zeigt alles, was du freischalten kannst.')}`;
  }
  el.innerHTML = `
    <div class="ob-sheet">
      <div class="ob-top">${ui.page < PAGES - 1 ? '<button class="linkbtn plain" data-action="ob-skip">Überspringen</button>' : ''}</div>
      <div class="ob-body">${body}</div>
      <div class="dots">${Array.from({ length: PAGES }, (_, i) => `<i class="${i === ui.page ? 'on' : ''}"></i>`).join('')}</div>
      <div class="controls">
        ${ui.page > 0 ? '<button class="btn soft" data-action="ob-back">Zurück</button>' : ''}
        <button class="btn primary" data-action="ob-next">${ui.page === PAGES - 1 ? "Los geht's!" : 'Weiter'}</button>
      </div>
    </div>`;
  drawStatic(el);
}

function drawOnboardingCanvas() {
  const canvas = $('#ob-canvas');
  if (!canvas) return;
  const f = fit(canvas);
  if (!f) return;
  const { ctx, w, h } = f;
  const t = now();
  const cycle = 6.5;
  const showcase = ['kirsche', 'tulpe', 'fliegenpilz', 'tanne', 'sonnenblume', 'regenbogenbaum'];
  const species = findSpecies(showcase[Math.floor(t / cycle) % showcase.length]);
  const p = smooth(0.3, 4.8, t % cycle);
  const r = Math.min(w, h) / 2 - 4;
  ctx.beginPath();
  ctx.arc(w / 2, h / 2, r, 0, TAU);
  ctx.fillStyle = theme.card;
  ctx.fill();
  const unit = r * 2 * 0.72;
  drawPlant(ctx, species, { x: w / 2, y: h / 2 + unit * 0.34 }, unit, p, 0.42, t);
}

function finishOnboarding() {
  ui.onboarding = false;
  store.setPref('onboardingDone', true);
  renderOnboarding();
}

// ---- Completion: sound, notification, wake lock

let audio = null;
function unlockAudio() {
  try {
    audio = audio || new (window.AudioContext || window.webkitAudioContext)();
    if (audio.state === 'suspended') audio.resume();
  } catch {
    audio = null;
  }
}

function chime() {
  if (!state.prefs.sound || !audio) return;
  [659.25, 783.99, 1046.5].forEach((freq, i) => {
    const osc = audio.createOscillator(), gain = audio.createGain();
    const start = audio.currentTime + i * 0.16;
    osc.type = 'sine';
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0, start);
    gain.gain.linearRampToValueAtTime(0.22, start + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.001, start + 1.1);
    osc.connect(gain).connect(audio.destination);
    osc.start(start);
    osc.stop(start + 1.2);
  });
}

async function notifyDone() {
  if (!state.prefs.notify || !('Notification' in window) || Notification.permission !== 'granted' || !document.hidden) return;
  const options = { body: `${store.timerSpecies().name} ist fertig gewachsen!`, icon: 'icons/icon-192.png' };
  try {
    const reg = navigator.serviceWorker && (await navigator.serviceWorker.getRegistration());
    if (reg) await reg.showNotification('Fokus-Wald', options);
    else new Notification('Fokus-Wald', options);
  } catch {
    // Notifications are best-effort.
  }
}

let wakeLock = null;
async function syncWakeLock() {
  const wanted = state.prefs.keepAwake && state.timer.phase === 'running' && !document.hidden;
  try {
    if (wanted && !wakeLock && 'wakeLock' in navigator) {
      wakeLock = await navigator.wakeLock.request('screen');
      wakeLock.addEventListener('release', () => { wakeLock = null; });
    } else if (!wanted && wakeLock) {
      await wakeLock.release();
      wakeLock = null;
    }
  } catch {
    wakeLock = null;
  }
}

function tick() {
  if (store.checkTimer()) {
    chime();
    notifyDone();
  }
}

// ---- Actions

function adjustMinutes(up) {
  const m = state.prefs.minutes;
  store.setPref('minutes', up ? (m < 5 ? m + 1 : Math.min(180, m + 5)) : (m <= 5 ? Math.max(1, m - 1) : m - 5));
}

const actions = {
  tab: (el) => { ui.tab = el.dataset.tab; renderAll(); },
  'toggle-settings': () => { ui.settings = !ui.settings; renderTimer(); },
  'minutes-down': () => adjustMinutes(false),
  'minutes-up': () => adjustMinutes(true),
  preset: (el) => store.setPref('minutes', Number(el.dataset.min)),
  start: () => { unlockAudio(); store.startTimer(); },
  pause: () => store.pauseTimer(),
  resume: () => { unlockAudio(); store.resumeTimer(); },
  reset: () => store.resetTimer(),
  giveup: () => {
    if (ui.confirmGiveUp) {
      ui.confirmGiveUp = false;
      store.resetTimer();
    } else {
      ui.confirmGiveUp = true;
      renderTimer();
      setTimeout(() => { ui.confirmGiveUp = false; renderTimer(); }, 3000);
    }
  },
  theme: (el) => store.setPref('themeID', el.dataset.id),
  select: (el) => store.setPref('selection', el.dataset.id),
  'island-prev': () => { ui.island = shownIsland() - 1; setZoom(1); renderIslandChrome(); },
  'island-next': () => { ui.island = shownIsland() + 1; setZoom(1); renderIslandChrome(); },
  tool: (el) => { ui.tool = el.dataset.tool; ui.draft = []; renderIslandChrome(); },
  undo: () => store.undoDecoration(shownIsland()),
  'zoom-in': () => setZoom(ui.zoom * 1.4),
  'zoom-out': () => setZoom(ui.zoom / 1.4),
  'zoom-reset': () => setZoom(1),
  'open-island': (el) => { ui.island = Number(el.dataset.index); ui.tab = 'island'; setZoom(1); renderAll(); },
  export: () => {
    const url = URL.createObjectURL(new Blob([store.exportData()], { type: 'application/json' }));
    const a = Object.assign(document.createElement('a'), { href: url, download: 'fokus-wald-sicherung.json' });
    a.click();
    URL.revokeObjectURL(url);
  },
  import: () => $('#import-file').click(),
  intro: () => { ui.page = 0; ui.onboarding = true; renderOnboarding(); },
  install: async () => {
    if (!ui.installPrompt) return;
    ui.installPrompt.prompt();
    await ui.installPrompt.userChoice;
    ui.installPrompt = null;
    renderTimer();
  },
  'ob-next': () => { if (ui.page === PAGES - 1) finishOnboarding(); else { ui.page++; renderOnboarding(); } },
  'ob-back': () => { ui.page = Math.max(0, ui.page - 1); renderOnboarding(); },
  'ob-skip': () => finishOnboarding(),
};

function bindEvents() {
  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-action]');
    if (el && !el.disabled && actions[el.dataset.action]) actions[el.dataset.action](el);
  });

  document.addEventListener('change', async (e) => {
    const key = e.target.dataset && e.target.dataset.pref;
    if (key) {
      let value = e.target.checked;
      if (key === 'notify' && value && Notification.permission !== 'granted') {
        value = (await Notification.requestPermission()) === 'granted';
        if (!value) toast('Mitteilungen sind im Browser blockiert.');
      }
      if (key === 'sound' && value) unlockAudio();
      store.setPref(key, value);
      syncWakeLock();
    }
    if (e.target.id === 'import-file' && e.target.files[0]) {
      try {
        store.importData(await e.target.files[0].text());
        toast('Sicherung geladen.');
      } catch {
        toast('Diese Datei ist keine Fokus-Wald-Sicherung.');
      }
      e.target.value = '';
    }
  });

  store.subscribe((what) => {
    if (what === 'prefs') {
      applyTheme();
      renderOnboarding();
    }
    renderAll();
    syncWakeLock();
  });

  wide.addEventListener('change', renderAll);
  onSystemThemeChange(() => { applyTheme(); renderAll(); });
  document.addEventListener('visibilitychange', () => { tick(); syncWakeLock(); });
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    ui.installPrompt = e;
    if (ui.settings) renderTimer();
  });
  // Covers background tabs, where animation frames stop but timers still fire.
  setInterval(tick, 1000);
}

function loop() {
  requestAnimationFrame(loop);
  const t = performance.now();
  if (t - (loop.last || 0) < 30) return;
  loop.last = t;
  tick();
  updateClock();
  drawStage();
  drawIslandCanvas();
  if (ui.onboarding && ui.page === 0) drawOnboardingCanvas();
}

// ---- Start

buildShell();
applyTheme();
bindEvents();
bindIslandGestures();
renderAll();
renderOnboarding();
tick();
loop();

if ('serviceWorker' in navigator && location.protocol === 'https:') {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
