// Builds canvas artboards (artboards/*.dc.html) from src/*.html + shared.css.
//
// A src file is plain markup. An optional leading <style> block goes into the
// artboard's <helmet>, an optional <script data-dc-script> goes after </x-dc>.
// Macros in [[double brackets]] expand before writing:
//   [[i name size]]            inline stroke icon
//   [[bars count seed min max]] speech-like waveform bars
//   [[flat count]]             silent waveform bars
//   [[field hue]]              onboarding window background for a hue
//   [[chrome step]]            traffic lights + 8-step progress

import { readFileSync, writeFileSync, readdirSync, mkdirSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const srcDir = join(root, 'src');
const outDir = join(root, 'artboards');
mkdirSync(outDir, { recursive: true });
const shared = readFileSync(join(root, 'shared.css'), 'utf8');

const ICONS = {
  mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>',
  globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9s-1.3 6.3-3.8 9c-2.5-2.7-3.8-5.7-3.8-9S9.5 5.7 12 3z"/>',
  check: '<path d="M5 12.5l4.2 4.2L19 7"/>',
  checkCircle: '<circle cx="12" cy="12" r="9"/><path d="M8 12.3l2.8 2.8L16.2 9.5"/>',
  lock: '<rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
  keyboard: '<rect x="2.5" y="6" width="19" height="12" rx="2.5"/><path d="M6.5 10h.01M10 10h.01M13.5 10h.01M17 10h.01M8 14h8"/>',
  person: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="7.6" r="1.1"/><path d="M7.5 10.2h9M12 10.2v3.8M12 14l-2.4 3.8M12 14l2.4 3.8"/>',
  download: '<path d="M12 4v11M7.5 10.5L12 15l4.5-4.5M5 19.5h14"/>',
  sliders: '<path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7.5V12l3 2"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4 4"/>',
  copy: '<rect x="8.5" y="8.5" width="11" height="11" rx="2.5"/><path d="M15.5 8.5V6.5a2 2 0 0 0-2-2h-7a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h2"/>',
  terminal: '<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M7 9.5l3 2.5-3 2.5M12.5 15h4.5"/>',
  chevronDown: '<path d="M7 10l5 5 5-5"/>',
  chevronLeft: '<path d="M14.5 6l-6 6 6 6"/>',
  chevronRight: '<path d="M9.5 6l6 6-6 6"/>',
  ret: '<path d="M19 5v6a3 3 0 0 1-3 3H6M9.5 10.5L6 14l3.5 3.5"/>',
  x: '<path d="M7 7l10 10M17 7L7 17"/>',
  power: '<path d="M12 3.5v8M7.2 6.6a7 7 0 1 0 9.6 0"/>',
  text: '<path d="M4 6h16M4 10.5h16M4 15h10M4 19.5h7"/>',
  wave: '<path d="M4 10v4M8 7v10M12 4v16M16 8v8M20 11v2"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  display: '<rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M9 20h6M12 16.5V20"/>',
  speaker: '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"/>',
  general: '<circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/>',
  capsule: '<rect x="3" y="8.5" width="18" height="7" rx="3.5"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
  shield: '<path d="M12 3l7 3v5.5c0 4.3-2.9 7.8-7 9.5-4.1-1.7-7-5.2-7-9.5V6z"/><path d="M9 12l2.2 2.2L15.5 10"/>',
  out: '<path d="M13 5h6v6M19 5l-8 8M17 14v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h4"/>',
  warn: '<path d="M12 4l9 15.5H3z"/><path d="M12 10v4.5M12 17h.01"/>',
  history: '<path d="M4 12a8 8 0 1 0 2.4-5.7M4 4.5v4h4"/><path d="M12 8v4l2.8 1.8"/>',
  grip: 'GRIP',
  cursorArrow: 'CURSOR',
  clipboard: '<rect x="6" y="4.5" width="12" height="16" rx="2.5"/><path d="M9.5 4.5h5v2.5h-5z"/>',
  cardStack: '<rect x="4" y="8" width="16" height="12" rx="2.5"/><path d="M7 5h10"/>',
  bolt: '<path d="M13 3L5 13.5h6L10 21l8-10.5h-6z"/>',
};

function icon(name, size = '18', stroke = '1.8') {
  const s = Number(size);
  if (!ICONS[name]) throw new Error(`unknown icon: ${name}`);
  if (name === 'grip') {
    const dots = [[9, 6], [15, 6], [9, 12], [15, 12], [9, 18], [15, 18]]
      .map(([cx, cy]) => `<circle cx="${cx}" cy="${cy}" r="1.6"/>`).join('');
    return `<svg class="icon" width="${s}" height="${s}" viewBox="0 0 24 24" fill="currentColor">${dots}</svg>`;
  }
  if (name === 'cursorArrow') {
    return `<svg width="${s}" height="${s}" viewBox="0 0 24 24"><path d="M5 3l14 8.2-6.2 1.4-2.9 6.1z" fill="#fff" stroke="#111" stroke-width="1.4" stroke-linejoin="round"/></svg>`;
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

function flat(count) {
  return '<i style="height:3px"></i>'.repeat(Number(count));
}

function field(hue) {
  const h = Number(hue);
  return `background: radial-gradient(120% 85% at 50% 28%, oklch(0.47 0.12 ${h}) 0%, oklch(0.28 0.08 ${h}) 44%, oklch(0.145 0.02 ${h}) 100%);`;
}

function chrome(step) {
  const n = Number(step);
  const segs = Array.from({ length: 8 }, (_, i) =>
    `<i class="${i + 1 === n ? 'on' : i + 1 < n ? 'done' : ''}"></i>`).join('');
  return `<div class="grain"></div>
  <div class="lights"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></div>
  <div class="progress">${segs}</div>`;
}

const MACROS = { i: icon, bars, flat, field, chrome };

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
  // Russian typography: a dash never starts a line.
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
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Onest:wght@400;500;600;700&amp;family=Unbounded:wght@500;600;700&amp;family=Geologica:wght@400;500;600;700&amp;family=JetBrains+Mono:wght@400;500;600&amp;display=swap">
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
  const out = join(outDir, `${basename(file, '.html')}.dc.html`);
  writeFileSync(out, html);
  console.log(`built ${basename(out)}`);
}
