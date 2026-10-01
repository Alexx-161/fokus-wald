// App state: timer, garden (plants, islands, decorations) and preferences, persisted in localStorage.

import { SPECIES, findSpecies, ISLAND_CAPACITY } from './data.js';

const KEY = 'fokuswald.v1';
const RANDOM = 'random';

const listeners = new Set();
export const subscribe = (fn) => { listeners.add(fn); return () => listeners.delete(fn); };
const emit = (what) => listeners.forEach((fn) => fn(what));

function load() {
  try {
    return JSON.parse(localStorage.getItem(KEY)) || {};
  } catch {
    return {};
  }
}

const saved = load();

export const state = {
  plants: saved.plants || [],
  decorations: saved.decorations || [],
  prefs: {
    themeID: 'wiese', selection: RANDOM, minutes: 25, onboardingDone: false,
    sound: true, keepAwake: false, notify: false,
    ...(saved.prefs || {}),
  },
  // phase: idle | running | paused | finished. While running, time is derived from endAt so the
  // session survives reloads and the tab being suspended in the background.
  timer: { phase: 'idle', endAt: 0, remaining: 0, total: 1, seed: Math.random(), speciesID: 'minze', ...(saved.timer || {}) },
};

function save() {
  try {
    localStorage.setItem(KEY, JSON.stringify({
      plants: state.plants, decorations: state.decorations, prefs: state.prefs, timer: state.timer,
    }));
  } catch {
    // Storage can be unavailable (private mode); the app keeps working for this visit.
  }
}

export function setPref(key, value) {
  state.prefs[key] = value;
  if (key === 'selection') refreshSpecies();
  if (key === 'minutes' && state.timer.phase === 'idle') state.timer.remaining = value * 60;
  save();
  emit('prefs');
}

// ---- Garden

export const plantsOn = (island) => state.plants.filter((p) => p.island === island);
export const decorationsOn = (island) => state.decorations.filter((d) => d.island === island);
export const isComplete = (island) => plantsOn(island).length >= ISLAND_CAPACITY;

/** The island the next plant lands on: once an island is full, a new one begins. */
export function currentIsland() {
  const last = state.plants[state.plants.length - 1];
  if (!last) return 0;
  return plantsOn(last.island).length >= ISLAND_CAPACITY ? last.island + 1 : last.island;
}

export const isUnlocked = (species) => state.plants.length >= species.unlockAt;

export function nextUnlock() {
  return SPECIES.filter((s) => !isUnlocked(s)).sort((a, b) => a.unlockAt - b.unlockAt)[0] || null;
}

export const countOf = (species) => state.plants.filter((p) => p.speciesID === species.id).length;

function pickSpecies(seed) {
  const sel = state.prefs.selection;
  if (sel !== RANDOM) {
    const chosen = findSpecies(sel);
    if (chosen.id === sel && isUnlocked(chosen)) return chosen.id;
  }
  const unlocked = SPECIES.filter(isUnlocked);
  return unlocked[Math.min(unlocked.length - 1, Math.floor(seed * unlocked.length))].id;
}

function refreshSpecies() {
  if (state.timer.phase !== 'idle') return;
  state.timer.speciesID = pickSpecies(state.timer.seed);
}

function uid() {
  return (crypto.randomUUID && crypto.randomUUID()) || String(Date.now()) + Math.random().toString(16).slice(2);
}

export function addDecoration(kind, points, island) {
  state.decorations.push({ id: uid(), kind, island, points });
  save();
  emit('garden');
}

export function undoDecoration(island) {
  for (let i = state.decorations.length - 1; i >= 0; i--) {
    if (state.decorations[i].island === island) {
      state.decorations.splice(i, 1);
      save();
      emit('garden');
      return;
    }
  }
}

function distanceToSegment(p, a, b) {
  const dx = b.x - a.x, dy = b.y - a.y;
  const len2 = dx * dx + dy * dy;
  const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2));
  return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}

/** Removes the most recently drawn decoration passing within `tolerance` of `point`. */
export function removeDecorationNear(point, island, tolerance) {
  for (let i = state.decorations.length - 1; i >= 0; i--) {
    const d = state.decorations[i];
    if (d.island !== island) continue;
    const hit = d.points.some((p, k) => k > 0 && distanceToSegment(point, d.points[k - 1], p) < tolerance);
    if (hit) {
      state.decorations.splice(i, 1);
      save();
      emit('garden');
      return;
    }
  }
}

// ---- Statistics

const dayKey = (date) => {
  const d = new Date(date);
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
};

export const totalMinutes = () => state.plants.reduce((sum, p) => sum + p.minutes, 0);
export const todayCount = () => state.plants.filter((p) => dayKey(p.date) === dayKey(Date.now())).length;

/** Consecutive days with at least one session, ending today (or yesterday if today is still empty). */
export function streak() {
  const days = new Set(state.plants.map((p) => dayKey(p.date)));
  const day = new Date();
  if (!days.has(dayKey(day))) day.setDate(day.getDate() - 1);
  let count = 0;
  while (days.has(dayKey(day))) {
    count++;
    day.setDate(day.getDate() - 1);
  }
  return count;
}

export function minutesPerDay(days) {
  const out = [];
  for (let offset = days - 1; offset >= 0; offset--) {
    const day = new Date();
    day.setDate(day.getDate() - offset);
    const key = dayKey(day);
    out.push({ day, minutes: state.plants.filter((p) => dayKey(p.date) === key).reduce((s, p) => s + p.minutes, 0) });
  }
  return out;
}

export function favoriteSpecies() {
  const counts = new Map();
  for (const p of state.plants) counts.set(p.speciesID, (counts.get(p.speciesID) || 0) + 1);
  let best = null;
  for (const [id, n] of counts) if (!best || n > best[1]) best = [id, n];
  return best ? findSpecies(best[0]) : null;
}

// ---- Timer

export function remainingAt(now = Date.now()) {
  const t = state.timer;
  if (t.phase === 'running') return Math.max(0, (t.endAt - now) / 1000);
  return t.phase === 'finished' ? 0 : t.remaining;
}

export function progressAt(now = Date.now()) {
  const t = state.timer;
  if (t.phase === 'idle') return 0;
  if (t.phase === 'finished') return 1;
  return Math.min(1, Math.max(0, 1 - remainingAt(now) / t.total));
}

export const timerSpecies = () => findSpecies(state.timer.speciesID);

export function startTimer() {
  const t = state.timer;
  if (t.phase !== 'idle') return;
  t.total = state.prefs.minutes * 60;
  t.remaining = t.total;
  t.endAt = Date.now() + t.total * 1000;
  t.phase = 'running';
  save();
  emit('timer');
}

export function pauseTimer() {
  const t = state.timer;
  if (t.phase !== 'running') return;
  t.remaining = remainingAt();
  t.phase = 'paused';
  save();
  emit('timer');
}

export function resumeTimer() {
  const t = state.timer;
  if (t.phase !== 'paused') return;
  t.endAt = Date.now() + t.remaining * 1000;
  t.phase = 'running';
  save();
  emit('timer');
}

export function resetTimer() {
  const t = state.timer;
  t.phase = 'idle';
  t.seed = Math.random();
  t.remaining = state.prefs.minutes * 60;
  refreshSpecies();
  save();
  emit('timer');
}

/** Completes the session if its end time has passed. Returns true when a plant was just added. */
export function checkTimer() {
  const t = state.timer;
  if (t.phase !== 'running' || Date.now() < t.endAt) return false;
  state.plants.push({
    id: uid(), date: new Date(t.endAt).toISOString(), minutes: Math.round(t.total / 60),
    seed: t.seed, speciesID: t.speciesID, island: currentIsland(),
  });
  t.phase = 'finished';
  t.remaining = 0;
  save();
  emit('timer');
  emit('garden');
  return true;
}

// ---- Backup

export function exportData() {
  return JSON.stringify({ app: 'fokus-wald', version: 1, plants: state.plants, decorations: state.decorations }, null, 2);
}

export function importData(text) {
  const data = JSON.parse(text);
  if (data.app !== 'fokus-wald' || !Array.isArray(data.plants)) throw new Error('Keine Fokus-Wald-Datei');
  state.plants = data.plants.filter((p) => typeof p.speciesID === 'string' && typeof p.island === 'number');
  state.decorations = Array.isArray(data.decorations) ? data.decorations : [];
  refreshSpecies();
  save();
  emit('garden');
}

// A stored idle timer may reference a locked or stale species; settle it once at startup.
if (state.timer.phase === 'idle') {
  state.timer.remaining = state.prefs.minutes * 60;
  refreshSpecies();
}

export { RANDOM };
