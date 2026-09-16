// Builds canvas artboards (artboards/*.dc.html) from src/*.html + shared.css.
//
// A src file is plain markup. An optional leading <style> block goes into the
// artboard's <helmet>, an optional <script data-dc-script> goes after </x-dc>.
// Macros in [[double brackets]] expand before writing:
//   [[i name size stroke]]       inline stroke icon
//   [[bars count seed min max]]  speech-like waveform bars
//   [[flat count]]               silent waveform bars
//   [[obar step]]                onboarding title bar (traffic lights, "Шаг n из 8")
//   [[mbar Title_with_underscores]]  main window title bar
//   [[rail key]]                 main window section rail, key = home|keys|text|dict|history|model|perm

import { readFileSync, writeFileSync, readdirSync, mkdirSync, rmSync, cpSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const srcDir = join(root, 'src');
const outDir = join(root, 'artboards');
rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });
// images next to artboards so local screenshots resolve them
cpSync(join(root, 'img'), outDir, { recursive: true });
const shared = readFileSync(join(root, 'shared.css'), 'utf8');
const FONTS = 'https://fonts.googleapis.com/css2?family=Onest:wght@400;500;600;700&amp;family=JetBrains+Mono:wght@400;500&amp;display=swap';

const ICONS = {
  check: '<path d="M5 12.5l4.2 4.2L19 7"/>',
  checkCircle: '<circle cx="12" cy="12" r="9"/><path d="M8 12.3l2.8 2.8L16.2 9.5"/>',
  chevronDown: '<path d="M7 10l5 5 5-5"/>',
  chevronLeft: '<path d="M14.5 6l-6 6 6 6"/>',
  chevronRight: '<path d="M9.5 6l6 6-6 6"/>',
  arrowRight: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4 4"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  copy: '<rect x="8.5" y="8.5" width="11" height="11" rx="2.5"/><path d="M15.5 8.5V6.5a2 2 0 0 0-2-2h-7a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h2"/>',
  x: '<path d="M7 7l10 10M17 7L7 17"/>',
  warn: '<path d="M12 4l9 15.5H3z"/><path d="M12 10v4.5M12 17h.01"/>',
  lock: '<rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
  mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>',
  out: '<path d="M13 5h6v6M19 5l-8 8M17 14v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h4"/>',
  wave: '<path d="M4 10v4M8 7v10M12 4v16M16 8v8M20 11v2"/>',
  speaker: '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"/>',
  history: '<path d="M4 12a8 8 0 1 0 2.4-5.7M4 4.5v4h4"/><path d="M12 8v4l2.8 1.8"/>',
  sliders: '<path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/>',
  power: '<path d="M12 3.5v8M7.2 6.6a7 7 0 1 0 9.6 0"/>',
  download: '<path d="M12 4v11M7.5 10.5L12 15l4.5-4.5M5 19.5h14"/>',
  ret: '<path d="M19 5v6a3 3 0 0 1-3 3H6M9.5 10.5L6 14l3.5 3.5"/>',
  clipboard: '<rect x="6" y="4.5" width="12" height="16" rx="2.5"/><path d="M9.5 4.5h5v2.5h-5z"/>',
  card: '<rect x="4" y="8" width="16" height="12" rx="2.5"/><path d="M7 5h10"/>',
  grip: 'GRIP',
  cursorArrow: 'CURSOR',
};

function icon(name, size = '18', stroke = '1.8') {
  const s = Number(size);
  if (!ICONS[name]) throw new Error(`unknown icon: ${name}`);
  if (name === 'grip') {
    const dots = [[9, 6], [15, 6], [9, 12], [15, 12], [9, 18], [15, 18]].map(([cx, cy]) => `<circle cx="${cx}" cy="${cy}" r="1.6"/>`).join('');
    return `<svg class="icon" width="${s}" height="${s}" viewBox="0 0 24 24" fill="currentColor">${dots}</svg>`;
  }
  if (name === 'cursorArrow') {
    return `<svg class="icon" width="${s}" height="${s}" viewBox="0 0 24 24"><path d="M5 3l14 8.2-6.2 1.4-2.9 6.1z" fill="#fff" stroke="#111" stroke-width="1.4" stroke-linejoin="round"/></svg>`;
  }
  return `<svg class="icon" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${stroke}" stroke-linecap="round" stroke-linejoin="round">${ICONS[name]}</svg>`;
}

function bars(count, seed, min, max) {
  const n = Number(count), lo = Number(min), hi = Number(max);
  let s = Number(seed) * 7919 + 17;
  const rand = () => { s = (s * 9301 + 49297) % 233280; return s / 233280; };
  let out = '';
  for (let i = 0; i < n; i++) {
    const t = n === 1 ? 0.5 : i / (n - 1);
    const envelope = Math.pow(Math.sin(Math.PI * (0.08 + 0.84 * t)), 0.7);
    const syllable = 0.5 + 0.5 * Math.abs(Math.sin(i * 1.37 + Number(seed)));
    const h = lo + (hi - lo) * envelope * syllable * (0.45 + 0.55 * rand());
    out += `<i style="height:${Math.max(lo, Math.round(h))}px"></i>`;
  }
  return out;
}

const flat = (count) => '<i style="height:3px"></i>'.repeat(Number(count));
const lights = '<div class="lights"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></div>';

function obar(step) {
  const n = Number(step);
  const back = n > 1 ? `<div class="back">${icon('chevronLeft', 16, 2)}Назад</div>` : '';
  return `<div class="bar">${lights}Шаг ${n} из 8</div>${back}`;
}

function mbar(title) {
  return `<div class="bar">${lights}${title.replace(/_/g, ' ')}</div>`;
}

const RAIL = [['home', 'appicon'], ['keys', 'keycap'], ['text', 'textcard'], ['dict', 'aa'], ['history', 'stack'], ['model', 'chip']];
function rail(active) {
  const item = ([key, img]) => `<div class="ri${key === active ? ' on' : ''}"><img src="${img}-sm.webp" alt=""></div>`;
  return `<div class="rail">${RAIL.map(item).join('')}<div style="flex: 1;"></div>${item(['perm', 'lock'])}</div>`;
}

const MACROS = { i: icon, bars, flat, obar, mbar, rail };

function expand(text) {
  return text.replace(/\[\[(\w+)((?:\s+[^\]\s]+)*)\s*\]\]/g, (_, name, args) => {
    const fn = MACROS[name];
    if (!fn) throw new Error(`unknown macro: ${name}`);
    return fn(...args.trim().split(/\s+/).filter(Boolean));
  });
}

for (const file of readdirSync(srcDir).filter((f) => f.endsWith('.html')).sort()) {
  let src = readFileSync(join(srcDir, file), 'utf8');
  let local = '';
  src = src.replace(/^\s*<style>([\s\S]*?)<\/style>/, (_, css) => { local = css; return ''; });
  let script = '';
  src = src.replace(/<script data-dc-script[\s\S]*?<\/script>\s*$/, (m) => { script = m; return ''; });
  const body = expand(src.trim()).replace(/ — /g, '&nbsp;— ');
  const html = `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <link rel="stylesheet" href="${FONTS}">
  <style>
${shared.trim()}
${local.trim()}
  </style>
</helmet>
${body}
</x-dc>
${script.trim()}
</body>
</html>
`;
  writeFileSync(join(outDir, `${basename(file, '.html')}.dc.html`), html);
  console.log(`built ${basename(file, '.html')}`);
}
