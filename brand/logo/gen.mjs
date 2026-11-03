// Draws iikb's marks from Helvetica Neue's own outlines. The fonts are Apple's system files, read from FONTS
// (default ../.scratch/fonts, extracted from the Mac's HelveticaNeue.ttc), and never committed: only the outlines are.
import opentype from "opentype.js";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const fonts = process.env.FONTS ?? join(here, "../../.scratch/fonts");
const load = (name) => opentype.parse(readFileSync(join(fonts, name)).buffer);
const bold = load("HelveticaNeue-Bold.ttf");
const out = join(here, "out");
mkdirSync(out, { recursive: true });

const ink = "#000", paper = "#fff";
const round = (n) => Math.round(n * 100) / 100;

// One line of text as a path, tracked in thousandths of an em, with its ink bounds.
function line(text, size, tracking, x = 0, y = 0) {
  const glyphs = bold.stringToGlyphs(text);
  const scale = size / bold.unitsPerEm;
  let pen = x;
  const parts = [];
  glyphs.forEach((glyph, i) => {
    parts.push(glyph.getPath(pen, y, size));
    pen += glyph.advanceWidth * scale + (i < glyphs.length - 1 ? (tracking / 1000) * size : 0);
  });
  const path = new opentype.Path();
  parts.forEach((p) => path.extend(p));
  const box = path.getBoundingBox();
  return { d: path.toPathData(2), box, advance: pen - x };
}

const svg = (w, h, body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${round(w)} ${round(h)}" width="${round(w)}" height="${round(h)}">${body}</svg>\n`;

// The wordmark: iikb in Helvetica Neue Bold, tracked tight, cropped to its ink.
function wordmark(color) {
  const t = line("iikb", 100, -45);
  const { x1, y1, x2, y2 } = t.box;
  return svg(x2 - x1, y2 - y1, `<path transform="translate(${round(-x1)} ${round(-y1)})" fill="${color}" d="${t.d}"/>`);
}

// The icon: the wordmark flush left on the bottom margin of a black square, as wide as the margins allow.
function icon(field, color, size = 1024, rounded = false, margin = 0.13) {
  const m = margin * size;
  const probe = line("iikb", 100, -45);
  const type = (100 * (size - 2 * m)) / (probe.box.x2 - probe.box.x1);
  const fit = line("iikb", type, -45);
  const t = line("iikb", type, -45, m - fit.box.x1, size - m - fit.box.y2);
  const r = rounded ? ` rx="${size * 0.225}"` : "";
  return svg(size, size, `<rect width="${size}" height="${size}"${r} fill="${field}"/><path fill="${color}" d="${t.d}"/>`);
}

// Directions not taken, kept so the comparison can be redrawn.
function poster(size = 1024) {
  const type = 0.4 * size, margin = 0.12 * size;
  const probe = line("iikb", type, -45);
  const t = line("iikb", type, -45, margin - probe.box.x1, size - margin);
  return svg(size, size, `<rect width="${size}" height="${size}" rx="${size * 0.225}" fill="${ink}"/><path fill="${paper}" d="${t.d}"/>`);
}

function spacebar(size = 1024) {
  const key = { x: 0.1 * size, y: 0.4 * size, w: 0.8 * size, h: 0.3 * size };
  const type = 0.13 * size;
  const probe = line("iikb", type, -30);
  const t = line("iikb", type, -30, key.x + 0.06 * size - probe.box.x1, key.y + 0.06 * size - probe.box.y1);
  return svg(size, size, `<rect width="${size}" height="${size}" rx="${size * 0.225}" fill="${ink}"/><rect x="${key.x}" y="${key.y}" width="${key.w}" height="${key.h}" rx="${0.06 * size}" fill="${paper}"/><path fill="${ink}" d="${t.d}"/>`);
}

// The favicon: the icon on a tighter margin so the name survives 16px, white on black, and black on white in a dark
// browser, where a black square would sink into the tab bar.
function favicon(size = 64) {
  const m = 0.09 * size;
  const probe = line("iikb", 100, -45);
  const type = (100 * (size - 2 * m)) / (probe.box.x2 - probe.box.x1);
  const fit = line("iikb", type, -45);
  const t = line("iikb", type, -45, m - fit.box.x1, size - m - fit.box.y2);
  const style = `<style>rect{fill:${ink}}path{fill:${paper}}@media (prefers-color-scheme:dark){rect{fill:${paper}}path{fill:${ink}}}</style>`;
  return svg(size, size, `${style}<rect width="${size}" height="${size}" rx="${size * 0.2}"/><path d="${t.d}"/>`);
}

const files = {
  "favicon.svg": favicon(),
  "direction-poster.svg": poster(),
  "direction-spacebar.svg": spacebar(),
  "wordmark-ink.svg": wordmark(ink),
  "wordmark-paper.svg": wordmark(paper),
  "icon.svg": icon(ink, paper),
  "icon-light.svg": icon(paper, ink),
  "icon-rounded.svg": icon(ink, paper, 1024, true),
};
for (const [name, body] of Object.entries(files)) writeFileSync(join(out, name), body);
console.log(Object.keys(files).join("\n"));
