// App state: timer, garden (plants, saplings, islands, decorations) and preferences, persisted in localStorage.

import { SPECIES, RESIDENTS, findSpecies, isGolden, ISLAND_CAPACITY } from './data.js';

const KEY = 'fokuswald.v1';
const RANDOM = 'random';
const MAX_TAGS = 12;

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
  // Unfinished plants: stopping a session early keeps it in the seedbed, and a later session lets it grow on.
  // { id, date, speciesID, seed, progress (0..<1), elapsed (seconds of focus so far) }
  saplings: saved.saplings || [],
  prefs: {
    themeID: 'wiese', selection: RANDOM, minutes: 25, onboardingDone: false,
    sound: true, keepAwake: false, notify: false,
    // tags: subjects or projects a session can be filed under; tag: the one chosen for the next session.
    tags: ['Lernen', 'Arbeit', 'Lesen'], tag: null,
    // weeklyGoal: focus minutes aimed for per week (0 = off); reaching them lights the lighthouse.
    weeklyGoal: 120, livingSky: true, breakMinutes: 5, continueSapling: true,
    ...(saved.prefs || {}),
  },
  // phase: idle | running | paused | finished. While running, time is derived from endAt so the
  // session survives reloads and the tab being suspended in the background.
  // base/carried: growth and focus seconds the session started from (non-zero when it continues a sapling).
  // breakEndAt: set while the break after a finished session is running.
  timer: {
    phase: 'idle', endAt: 0, remaining: 0, total: 1, seed: Math.random(), speciesID: 'minze',
    base: 0, carried: 0, saplingID: null, pendingID: null, breakEndAt: 0,
    ...(saved.timer || {}),
  },
  // The animal that moved in with the most recent session, for the "new resident" message (not persisted).
  newResident: null,
};

function save() {
  try {
    localStorage.setItem(KEY, JSON.stringify({
      plants: state.plants, decorations: state.decorations, saplings: state.saplings, prefs: state.prefs, timer: state.timer,
    }));
  } catch {
    // Storage can be unavailable (private mode); the app keeps working for this visit.
  }
}

export function setPref(key, value) {
  state.prefs[key] = value;
  if (key === 'selection' || key === 'continueSapling') settleIdle();
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

/** Seasonal plants are available during their month only; everything else unlocks with completed sessions. */
export const isUnlocked = (species) =>
  (species.month ? species.month === new Date().getMonth() + 1 : state.plants.length >= species.unlockAt);

export function nextUnlock() {
  return SPECIES.filter((s) => !s.month && !isUnlocked(s)).sort((a, b) => a.unlockAt - b.unlockAt)[0] || null;
}

export const countOf = (species) => state.plants.filter((p) => p.speciesID === species.id).length;
export const goldenCountOf = (species) => state.plants.filter((p) => p.speciesID === species.id && isGolden(p.minutes)).length;

export function setNote(id, text) {
  const plant = state.plants.find((p) => p.id === id);
  if (!plant) return;
  const note = text.trim().slice(0, 140);
  if ((plant.note || '') === note) return;
  if (note) plant.note = note; else delete plant.note;
  save();
}

// ---- Saplings

/** The sapling the next session grows on, if the user wants to continue one. */
export function pendingSapling() {
  return state.prefs.continueSapling && state.saplings.length ? state.saplings[state.saplings.length - 1] : null;
}

/** Saplings standing in the seedbed; the one being grown right now is on the stage instead. */
export function waitingSaplings() {
  const t = state.timer;
  const active = t.phase === 'running' || t.phase === 'paused' ? t.saplingID : null;
  return state.saplings.filter((s) => s.id !== active);
}

// ---- Tags

export function addTag(name) {
  const tag = name.trim().slice(0, 20);
  if (!tag) return;
  if (!state.prefs.tags.includes(tag)) {
    if (state.prefs.tags.length >= MAX_TAGS) return;
    state.prefs.tags.push(tag);
  }
  setPref('tag', tag);
}

export function removeTag(tag) {
  state.prefs.tags = state.prefs.tags.filter((t) => t !== tag);
  setPref('tag', state.prefs.tag === tag ? null : state.prefs.tag);
}

/** Focus minutes per tag, largest first; sessions without a tag are grouped under null. */
export function minutesByTag() {
  const totals = new Map();
  for (const p of state.plants) totals.set(p.tag || null, (totals.get(p.tag || null) || 0) + p.minutes);
  return [...totals].map(([tag, minutes]) => ({ tag, minutes })).sort((a, b) => b.minutes - a.minutes);
}

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
  if (state.timer.phase !== 'idle' || state.timer.pendingID) return;
  state.timer.speciesID = pickSpecies(state.timer.seed);
}

/** Decides what an idle timer shows: the waiting sapling, or the next new plant. */
function settleIdle() {
  const t = state.timer;
  if (t.phase !== 'idle') return;
  const pending = pendingSapling();
  if (pending) {
    t.seed = pending.seed;
    t.speciesID = pending.speciesID;
    t.pendingID = pending.id;
  } else {
    if (t.pendingID) t.seed = Math.random();
    t.pendingID = null;
    refreshSpecies();
  }
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

/** The longest run of consecutive days ever reached. */
export function longestStreak() {
  const days = [...new Set(state.plants.map((p) => {
    const d = new Date(p.date);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  }))].sort((a, b) => a - b);
  let best = 0, run = 0, previous = null;
  for (const day of days) {
    // Rounding absorbs the hour that daylight saving adds or removes.
    run = previous !== null && Math.round((day - previous) / 864e5) === 1 ? run + 1 : 1;
    best = Math.max(best, run);
    previous = day;
  }
  return best;
}

/** Focus minutes since Monday. */
export function weekMinutes() {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  start.setDate(start.getDate() - ((start.getDay() + 6) % 7));
  return state.plants.filter((p) => new Date(p.date) >= start).reduce((sum, p) => sum + p.minutes, 0);
}

export const weeklyGoalReached = () => state.prefs.weeklyGoal > 0 && weekMinutes() >= state.prefs.weeklyGoal;

/** True when the most recent session is the one that pushed the week over its goal. */
export function goalJustReached() {
  const last = state.plants[state.plants.length - 1];
  return Boolean(last) && weeklyGoalReached() && weekMinutes() - last.minutes < state.prefs.weeklyGoal;
}

export function residents() {
  const met = {
    butterfly: state.plants.length >= 3,
    bird: state.plants.length >= 10,
    bunny: currentIsland() >= 1,
    fox: longestStreak() >= 7,
    fireflies: totalMinutes() >= 600,
  };
  return RESIDENTS.filter((r) => met[r.id]).map((r) => r.id);
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
  if (t.phase === 'idle') {
    const pending = pendingSapling();
    return pending ? pending.progress : 0;
  }
  if (t.phase === 'finished') return 1;
  return Math.min(1, Math.max(0, t.base + (1 - t.base) * (1 - remainingAt(now) / t.total)));
}

export const isOnBreak = () => state.timer.phase === 'finished' && state.timer.breakEndAt > 0;
export const breakRemainingAt = (now = Date.now()) => Math.max(0, (state.timer.breakEndAt - now) / 1000);

/** Focus minutes the plant will hold when this session completes. */
export function plannedMinutes() {
  const t = state.timer;
  if (t.phase !== 'idle') return Math.round((t.carried + t.total) / 60);
  const pending = pendingSapling();
  return Math.round(((pending ? pending.elapsed : 0) + state.prefs.minutes * 60) / 60);
}

export const timerSpecies = () => findSpecies(state.timer.speciesID);

export function startTimer() {
  const t = state.timer;
  if (t.phase !== 'idle') return;
  const pending = pendingSapling();
  t.total = state.prefs.minutes * 60;
  t.remaining = t.total;
  t.base = pending ? pending.progress : 0;
  t.carried = pending ? pending.elapsed : 0;
  t.saplingID = pending ? pending.id : null;
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

/**
 * Stops the session early. Nothing dies: the plant stays as a sapling and grows on next time.
 * Sessions under a minute leave nothing behind. Returns true when a sapling was kept.
 */
export function giveUpTimer() {
  const t = state.timer;
  if (t.phase !== 'running' && t.phase !== 'paused') return false;
  const elapsed = t.carried + t.total - remainingAt();
  const kept = elapsed >= 60;
  if (kept) {
    const sapling = {
      id: t.saplingID || uid(), date: new Date().toISOString(), speciesID: t.speciesID, seed: t.seed,
      progress: Math.min(0.97, progressAt()), elapsed,
    };
    state.saplings = state.saplings.filter((s) => s.id !== sapling.id).concat([sapling]);
    state.prefs.continueSapling = true;
  }
  resetTimer();
  emit('garden');
  return kept;
}

export function resetTimer() {
  const t = state.timer;
  t.phase = 'idle';
  t.breakEndAt = 0;
  t.base = 0;
  t.carried = 0;
  t.saplingID = null;
  t.pendingID = null;
  t.seed = Math.random();
  t.remaining = state.prefs.minutes * 60;
  settleIdle();
  save();
  emit('timer');
}

export function startBreak() {
  const t = state.timer;
  if (t.phase !== 'finished') return;
  t.breakEndAt = Date.now() + state.prefs.breakMinutes * 60000;
  save();
  emit('timer');
}

/**
 * Completes the session, or the break after it, once its end time has passed.
 * Returns 'planted' when a plant was just added, 'break' when a break just ended, otherwise false.
 */
export function checkTimer() {
  const t = state.timer;
  if (isOnBreak() && Date.now() >= t.breakEndAt) {
    resetTimer();
    return 'break';
  }
  if (t.phase !== 'running' || Date.now() < t.endAt) return false;
  const before = residents();
  const plant = {
    id: uid(), date: new Date(t.endAt).toISOString(), minutes: Math.round((t.carried + t.total) / 60),
    seed: t.seed, speciesID: t.speciesID, island: currentIsland(),
  };
  if (state.prefs.tag) plant.tag = state.prefs.tag;
  state.plants.push(plant);
  if (t.saplingID) state.saplings = state.saplings.filter((s) => s.id !== t.saplingID);
  state.newResident = residents().find((id) => !before.includes(id)) || null;
  t.phase = 'finished';
  t.remaining = 0;
  save();
  emit('timer');
  emit('garden');
  return 'planted';
}

// ---- Backup

// The same file format is read and written by the Mac app and the iPhone/iPad app, so progress can move between them.
export function exportData() {
  return JSON.stringify({
    app: 'fokus-wald', version: 2, plants: state.plants, decorations: state.decorations, saplings: state.saplings,
    tags: state.prefs.tags, weeklyGoal: state.prefs.weeklyGoal,
  }, null, 2);
}

export function importData(text) {
  const data = JSON.parse(text);
  if (data.app !== 'fokus-wald' || !Array.isArray(data.plants)) throw new Error('Keine Fokus-Wald-Datei');
  state.plants = data.plants.filter((p) => typeof p.speciesID === 'string' && typeof p.island === 'number');
  state.decorations = Array.isArray(data.decorations) ? data.decorations.filter((d) => Array.isArray(d.points)) : [];
  state.saplings = Array.isArray(data.saplings)
    ? data.saplings.filter((s) => typeof s.speciesID === 'string' && typeof s.progress === 'number') : [];
  if (Array.isArray(data.tags)) state.prefs.tags = data.tags.filter((t) => typeof t === 'string').slice(0, MAX_TAGS);
  if (!state.prefs.tags.includes(state.prefs.tag)) state.prefs.tag = null;
  if (typeof data.weeklyGoal === 'number') state.prefs.weeklyGoal = Math.max(0, data.weeklyGoal);
  state.newResident = null;
  settleIdle();
  save();
  emit('garden');
}

// A stored idle timer may reference a locked or stale species; settle it once at startup.
if (state.timer.phase === 'idle') {
  state.timer.remaining = state.prefs.minutes * 60;
  state.timer.pendingID = null;
  settleIdle();
}

export { RANDOM, MAX_TAGS };
