// Shared data and math, mirrored from the Mac app so plants look identical on every platform.

export const TAU = Math.PI * 2;

export const clamp = (x, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, x));

export function smooth(a, b, x) {
  const t = clamp((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

/** Deterministic pseudo-random value in 0..<1 for a given seed and slot. */
export function rnd(seed, k) {
  const v = Math.sin(seed * 9301.0 + k * 49.297 + 0.5) * 43758.5453;
  return v - Math.floor(v);
}

export const hex = (n) => '#' + n.toString(16).padStart(6, '0');

export function rgba(color, alpha) {
  const n = parseInt(color.slice(1), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${alpha})`;
}

export const CATEGORIES = [
  { id: 'tree', title: 'Bäume', icon: 'tree' },
  { id: 'flower', title: 'Blumen', icon: 'flower' },
  { id: 'mushroom', title: 'Pilze', icon: 'mushroom' },
  { id: 'special', title: 'Besondere', icon: 'sparkles' },
  { id: 'seasonal', title: 'Saison', icon: 'calendar' },
];

export const MONTHS = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September',
  'Oktober', 'November', 'Dezember'];

const KIND_SCALE = {
  roundTree: 1.0, pine: 1.0, festive: 1.0, rainbow: 1.0, crystal: 1.0,
  tulip: 0.72, sunflower: 0.72, daisy: 0.72, bell: 0.72,
  toadstool: 0.64, porcini: 0.64, glowshroom: 0.64,
};

// `month` (1–12) marks a seasonal plant, which can only be planted during that month.
function species(id, name, category, kind, colors, unlockAt, blurb, month = null) {
  const [main, shade, light, deep, accent] = colors.map(hex);
  const islandScale = category === 'special' ? 1.08 : KIND_SCALE[kind];
  return { id, name, category, kind, main, shade, light, deep, accent, unlockAt, blurb, islandScale, month };
}

/** Sessions of this length or more grow the rare golden variant. */
export const GOLDEN_MINUTES = 50;
export const isGolden = (minutes) => minutes >= GOLDEN_MINUTES;

export const SPECIES = [
  species('minze', 'Minzbäumchen', 'tree', 'roundTree', [0x8FD694, 0x6BBF7A, 0xBDEBC1, 0x5BAE6C, 0xF07C7C], 0, 'Frisch und rund – trägt kleine rote Äpfel.'),
  species('kirsche', 'Kirschblüte', 'tree', 'roundTree', [0xF7B6C8, 0xEC94AE, 0xFDDAE4, 0xE07A99, 0xFFFFFF], 0, 'Zartrosa Wolken voller Blüten.'),
  species('tanne', 'Tännchen', 'tree', 'pine', [0x6CC093, 0x4FA478, 0x9BDDB8, 0x3F9468, 0xFFD66B], 0, 'Steht stramm und trägt am Ende einen Stern.'),
  species('ahorn', 'Herbstahorn', 'tree', 'roundTree', [0xF7B877, 0xEB9A55, 0xFCD7AE, 0xDC8443, 0xE5646B], 2, 'Warme Herbstfarben, ganz ohne Herbst.'),
  species('lavendel', 'Lavendelbaum', 'tree', 'roundTree', [0xC6B4F0, 0xA894E0, 0xE3D8FB, 0x9179D6, 0xFFFFFF], 4, 'Duftet nach Ruhe und Konzentration.'),

  species('tulpe', 'Tulpe', 'flower', 'tulip', [0xF58A8A, 0xE06C70, 0xFFC2C0, 0xD9595F, 0xFFE08A], 0, 'Ein fröhlicher Kelch in Korallenrot.'),
  species('sonnenblume', 'Sonnenblume', 'flower', 'sunflower', [0xFFD45C, 0xF2B93B, 0xFFE9A3, 0xD99A1E, 0x9A6A45], 1, 'Dreht ihr Lächeln immer zur Sonne.'),
  species('gaensebluemchen', 'Gänseblümchen', 'flower', 'daisy', [0xFFFFFF, 0xE6DDEB, 0xFFFFFF, 0xC99A2E, 0xFFD45C], 3, 'Klein, weiß und immer gut gelaunt.'),
  species('glockenblume', 'Glockenblume', 'flower', 'bell', [0xA9B7F5, 0x8C9BE8, 0xD4DCFC, 0x7183D9, 0xFFFFFF], 6, 'Läutet ganz leise, wenn du fertig bist.'),

  species('fliegenpilz', 'Fliegenpilz', 'mushroom', 'toadstool', [0xE8645A, 0xC94A42, 0xF59A92, 0xC9473F, 0xFFFFFF], 5, 'Rot mit weißen Punkten – nur zum Anschauen!'),
  species('steinpilz', 'Steinpilz', 'mushroom', 'porcini', [0xC08A5B, 0x9C6B3E, 0xDDB48B, 0x9A6A40, 0xF3E6D0], 8, 'Gemütlich, braun und standfest.'),
  species('leuchtpilz', 'Leuchtpilz', 'mushroom', 'glowshroom', [0x7FD9E0, 0x4FB7C2, 0xBFF1F4, 0x3FA9B3, 0xBFFAFF], 12, 'Leuchtet sanft – besonders im Dunkeln.'),

  species('kristallbaum', 'Kristallbaum', 'special', 'crystal', [0xA8D8F5, 0x84BDE6, 0xE1F3FD, 0x5C9FD1, 0xD7C6F7], 15, 'Funkelnde Kristalle statt Blätter.'),
  species('regenbogenbaum', 'Regenbogenbaum', 'special', 'rainbow', [0xF7B6C8, 0xC9B6F2, 0xFFFFFF, 0x8E7BD6, 0xFFFFFF], 20, 'Jedes Blätterbüschel in einer anderen Farbe.'),

  species('eisblume', 'Eisblume', 'seasonal', 'crystal', [0xDDF1FB, 0xB9DCEF, 0xFFFFFF, 0x6FA9C9, 0xC9E6F7], 0, 'Wächst nur, wenn es draußen klirrt.', 1),
  species('winterling', 'Winterling', 'seasonal', 'daisy', [0xFFE066, 0xF0C63C, 0xFFF2A8, 0xD9A51E, 0xF2A93B], 0, 'Gelber Farbtupfer im letzten Schnee.', 2),
  species('krokus', 'Krokus', 'seasonal', 'tulip', [0xB59AE8, 0x957AD6, 0xDCCBF7, 0x7D62C4, 0xFFD45C], 0, 'Schiebt sich als Erster durch den Schnee.', 3),
  species('osterglocke', 'Osterglocke', 'seasonal', 'bell', [0xFFE066, 0xF2C53D, 0xFFF3B0, 0xD9A51E, 0xFFFFFF], 0, 'Läutet den Frühling ein.', 4),
  species('apfelbluete', 'Apfelblüte', 'seasonal', 'roundTree', [0xA9DDA0, 0x86C47C, 0xD3F0CC, 0x5BAE6C, 0xFFE3EC], 0, 'Frisches Grün mit zartrosa Blüten.', 5),
  species('mohn', 'Mohnblume', 'seasonal', 'daisy', [0xF0564A, 0xD23F36, 0xFF9A8F, 0xC9372F, 0xFFD45C], 0, 'Leuchtend rot am Wegesrand.', 6),
  species('kornblume', 'Kornblume', 'seasonal', 'daisy', [0x6F9BEA, 0x4F7CD6, 0xBBD2FA, 0x436FCB, 0xFFE9A3], 0, 'So blau wie der Sommerhimmel.', 7),
  species('zitrone', 'Zitronenbaum', 'seasonal', 'roundTree', [0x9BD67F, 0x79BE60, 0xC9EDB6, 0x5AA846, 0xFFE14D], 0, 'Trägt kleine Sonnen als Früchte.', 8),
  species('pflaume', 'Pflaumenbaum', 'seasonal', 'roundTree', [0x8CCB8E, 0x6BB174, 0xBFE6BF, 0x57A066, 0x8A5FBF], 0, 'Süße lila Früchte zum Schulanfang.', 9),
  species('pfifferling', 'Pfifferling', 'seasonal', 'porcini', [0xF6B544, 0xE0942B, 0xFFD98A, 0xD9861E, 0xFBE3B0], 0, 'Goldgelb und nur im Herbst zu finden.', 10),
  species('nebelpilz', 'Nebelpilz', 'seasonal', 'glowshroom', [0xB9A9E6, 0x9684D1, 0xDDD3F7, 0x8570C4, 0xE2D9FF], 0, 'Schimmert im Novembernebel.', 11),
  species('christbaum', 'Christbäumchen', 'seasonal', 'festive', [0x4FA06E, 0x3B8757, 0x86C9A0, 0x2F7A4C, 0xFFD66B], 0, 'Geschmückt mit bunten Kugeln.', 12),
];

const byID = new Map(SPECIES.map((s) => [s.id, s]));
export const findSpecies = (id) => byID.get(id) || SPECIES[0];

export const PALETTE = {
  trunk: '#B07F5F', crystalTrunk: '#A9B1C4', soil: '#C9A27E', soilLight: '#DABA97', sprout: '#8ED68F',
  stem: '#5FAF6A', leaf: '#7CC48A', mushroomStem: '#F7EEDD', gills: '#E6D3B3', face: '#4A3F38',
  blush: '#F48FA8', star: '#FFD66B', river: '#8CCBEF', riverLight: '#C4E6FA', pathEdge: '#D2B07E',
  path: '#E6CB9C', pathStone: '#F4E2C0', wood: '#C08A5B', woodDark: '#8E6240', flag: '#E07A99',
};

const wieseLight = {
  bg: '#FBF7F0', card: '#FFFFFF', track: '#EFE8DC', ink: '#3E3A34', muted: '#948C80',
  skyTop: '#CFE8FA', skyBottom: '#FFF1E3', cloud: '#FFFFFF',
};
const wieseDark = {
  bg: '#1D1E1B', card: '#282A26', track: '#363832', ink: '#EEE9E0', muted: '#9C978E',
  skyTop: '#1E2A44', skyBottom: '#3A3350', cloud: '#5A5878',
};

export const THEMES = [
  { id: 'wiese', name: 'Wiese', dark: null, particles: 'none', ...wieseLight,
    grass: '#A7DB9B', grassDark: '#86C47C', earth: '#C99A6E', earthDark: '#9C7050', pebble: '#D8B48E' },
  { id: 'mitternacht', name: 'Mitternacht', dark: true, particles: 'stars',
    bg: '#1B2033', card: '#252B42', track: '#333B59', ink: '#ECEAF8', muted: '#9C9AB8',
    skyTop: '#0E1430', skyBottom: '#2E2754', cloud: '#3C3F6A',
    grass: '#74B394', grassDark: '#58977B', earth: '#86607A', earthDark: '#5C4058', pebble: '#9C7A92' },
  { id: 'sakura', name: 'Kirschblüte', dark: false, particles: 'petals',
    bg: '#FFF4F6', card: '#FFFFFF', track: '#F9DFE6', ink: '#5A3A44', muted: '#B08A96',
    skyTop: '#FFD6E2', skyBottom: '#FFF3E8', cloud: '#FFFFFF',
    grass: '#B8E2A6', grassDark: '#98CE8A', earth: '#D3A07E', earthDark: '#AE7A5C', pebble: '#F0C6C6' },
  { id: 'herbst', name: 'Herbst', dark: false, particles: 'none',
    bg: '#FBF1E6', card: '#FFFAF3', track: '#F1DEC6', ink: '#4E3B2C', muted: '#A68B72',
    skyTop: '#FFD3A0', skyBottom: '#FFF1DE', cloud: '#FFF8EE',
    grass: '#D8C67A', grassDark: '#BFAA5C', earth: '#B98A5E', earthDark: '#8C6442', pebble: '#D9B48A' },
  { id: 'winter', name: 'Winter', dark: false, particles: 'snow',
    bg: '#F2F6FA', card: '#FFFFFF', track: '#DDE7F0', ink: '#34404D', muted: '#8B98A6',
    skyTop: '#C9DCF0', skyBottom: '#F3F7FC', cloud: '#FFFFFF',
    grass: '#F5F9FC', grassDark: '#D3E0EB', earth: '#9EAABA', earthDark: '#737F90', pebble: '#C2CCD8' },
];

const systemDark = typeof matchMedia === 'function' ? matchMedia('(prefers-color-scheme: dark)') : null;

/** Resolves a theme id to concrete colors; "Wiese" follows the system light/dark setting. */
export function resolveTheme(id, forceLight = false) {
  const theme = THEMES.find((t) => t.id === id) || THEMES[0];
  if (theme.dark !== null) return theme;
  const dark = !forceLight && systemDark && systemDark.matches;
  return { ...theme, ...(dark ? wieseDark : wieseLight), dark };
}

export const onSystemThemeChange = (fn) => systemDark && systemDark.addEventListener('change', fn);

export const TAG_COLORS = ['#5FAF6A', '#E07A99', '#7183D9', '#F2B93B', '#4FB7C2', '#DC8443', '#9179D6', '#C9473F'];

/** Stable palette slot for a tag, so its color survives other tags being added or removed. */
export function tagColor(tag) {
  if (!tag) return null;
  let slot = 0;
  for (const ch of tag) slot = (slot * 31 + ch.codePointAt(0)) % 1000003;
  return TAG_COLORS[slot % TAG_COLORS.length];
}

// Animals that move onto the island once a milestone is reached. They never leave again.
export const RESIDENTS = [
  { id: 'butterfly', name: 'Schmetterlinge', condition: 'ab 3 Pflanzen' },
  { id: 'bird', name: 'Vogel', condition: 'ab 10 Pflanzen' },
  { id: 'bunny', name: 'Hase', condition: 'erste vollendete Insel' },
  { id: 'fox', name: 'Fuchs', condition: '7 Tage in Folge' },
  { id: 'fireflies', name: 'Glühwürmchen', condition: '10 Stunden Fokuszeit · kommen nachts' },
];

export const ISLAND_CAPACITY = 30;

const ISLAND_NAMES = ['Moosinsel', 'Kirschwolke', 'Sonnenfels', 'Pilzhügel', 'Lavendelbucht', 'Sternenriff',
  'Nebelhain', 'Honigwiese', 'Tannenkuppe', 'Glitzerinsel', 'Wolkenacker', 'Blütenbogen'];

export function islandName(index) {
  const round = Math.floor(index / ISLAND_NAMES.length);
  return ISLAND_NAMES[index % ISLAND_NAMES.length] + (round > 0 ? ` ${round + 1}` : '');
}

export function formatClock(seconds) {
  const total = Math.max(0, Math.ceil(seconds));
  const h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s = total % 60;
  const pad = (n) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
}

export function formatDuration(minutes) {
  const h = Math.floor(minutes / 60), m = minutes % 60;
  if (h === 0) return `${m} min`;
  return m === 0 ? `${h} h` : `${h} h ${m} min`;
}
