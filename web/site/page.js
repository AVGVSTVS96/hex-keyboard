const facts = await fetch("facts.json").then((response) => response.json());
const get = (path) => path.split(".").reduce((value, key) => value?.[key], facts);
const format = (value) => (typeof value === "number" ? value.toLocaleString("en-US") : value);

for (const element of document.querySelectorAll("[data-fact]")) {
  const value = get(element.dataset.fact);
  if (value != null) element.textContent = format(value);
}

const chart = document.getElementById("chart");
const { iikbCurve, baselineCurve, blockWords } = facts.accuracy;
const svg = "http://www.w3.org/2000/svg";

function draw() {
  const width = chart.clientWidth;
  const narrow = width < 560;
  const height = narrow ? 260 : 340;
  const left = 36;
  const right = narrow ? 8 : 200;
  const top = 12;
  const bottom = 36;
  const x = (index) => left + (index / (iikbCurve.length - 1)) * (width - left - right);
  const y = (value) => top + ((100 - value) / 20) * (height - top - bottom);
  const path = (curve) => curve.map((value, index) => `${index ? "L" : "M"}${x(index).toFixed(1)} ${y(value).toFixed(1)}`).join("");
  const ticks = [80, 85, 90, 95, 100]
    .map((value) => `<line class="grid-line" x1="${left}" x2="${width}" y1="${y(value)}" y2="${y(value)}"/><text class="tick" x="0" y="${y(value) + 4}">${value}%</text>`)
    .join("");
  const labels = iikbCurve
    .map((_, index) => index)
    .filter((index) => !narrow || index % 3 === 0 || index === iikbCurve.length - 1)
    .map((index) => `<text class="tick" x="${x(index)}" y="${height - 8}" text-anchor="${index === iikbCurve.length - 1 ? "end" : "middle"}">${((index + 1) * blockWords).toLocaleString("en-US")}${index === iikbCurve.length - 1 ? " words" : ""}</text>`)
    .join("");
  const dots = (curve, name) => curve.map((value, index) => `<circle class="fade dot-${name}" cx="${x(index)}" cy="${y(value)}" r="3.5"/>`).join("");
  const last = iikbCurve.length - 1;
  const ends = narrow
    ? `<text class="end end-ours fade" x="${left + 4}" y="${y(iikbCurve[0]) + 22}">iikb</text><text class="end end-theirs fade" x="${left + 4}" y="${y(baselineCurve[0]) + 22}">Nearest key + Apple's spell checker</text>`
    : `<text class="end end-ours fade" x="${x(last) + 14}" y="${y(iikbCurve[last]) + 5}">iikb</text><text class="end end-theirs fade" x="${x(last) + 14}" y="${y(baselineCurve[last]) - 4}">Nearest key +</text><text class="end end-theirs fade" x="${x(last) + 14}" y="${y(baselineCurve[last]) + 14}">Apple's spell checker</text>`;
  chart.innerHTML = `<svg xmlns="${svg}" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" aria-hidden="true">${ticks}${labels}<path class="series theirs draw" d="${path(baselineCurve)}"/><path class="series ours draw" d="${path(iikbCurve)}"/>${dots(baselineCurve, "theirs")}${dots(iikbCurve, "ours")}${ends}</svg>`;
  for (const line of chart.querySelectorAll(".draw")) line.style.setProperty("--length", line.getTotalLength());
}

let drawnWidth = 0;
new ResizeObserver(() => {
  if (chart.clientWidth === drawnWidth) return;
  drawnWidth = chart.clientWidth;
  draw();
}).observe(chart);

new IntersectionObserver(([entry], observer) => {
  if (!entry.isIntersecting) return;
  chart.classList.add("seen");
  observer.disconnect();
}, { threshold: 0.35 }).observe(chart);
