// Counts every number the copy cites from the repo and writes copy/facts.json. Run: bun copy/facts.mjs
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const read = (path) => readFileSync(join(root, path), "utf8");
const lines = (path) => read(path).split("\n").filter(Boolean);
const resources = "Packages/HexKeyboard/Sources/KeyboardEnglish/Resources";

function find(path, pattern) {
  const match = read(path).match(pattern);
  if (!match) throw new Error(`${path} no longer says ${pattern}`);
  return match;
}

const evals = lines("scripts/eval.expected");
function evalLine(prefix) {
  const line = evals.find((l) => l.startsWith(prefix));
  if (!line) throw new Error(`scripts/eval.expected has no "${prefix}"`);
  return line;
}
const total = (keyboard) => {
  const line = evalLine(`EVAL thumbs keyboard=${keyboard} total:`);
  return {
    words: Number(line.match(/words=(\d+)/)[1]),
    raw: Number(line.match(/raw=([\d.]+)%/)[1]),
    autocorrect: Number(line.match(/autocorrect=([\d.]+)%/)[1]),
  };
};
const curve = (keyboard) =>
  evalLine(`EVAL thumbs keyboard=${keyboard} per 500 words`)
    .split(": ")[1]
    .split(" ")
    .map((pair) => Number(pair.split("/")[1].replace("%", "")));

const themes = [...read(`Packages/HexKeyboard/Sources/KeyboardCore/Keys/Themes.swift`).matchAll(/case \.\w+: "([^"]+)"/g)]
  .map((m) => m[1])
  .slice(0, find("Packages/HexKeyboard/Sources/KeyboardCore/Keys/Themes.swift", /enum ThemeName[^{]*\{\s*case ([^\n]+)/)[1].split(",").length);

const settings = read("Packages/HexKeyboard/Sources/KeyboardCore/Typing/KeyboardSettings.swift");
const strengths = [...settings.slice(settings.indexOf("public var strength")).matchAll(/case \.(\w+): ([\d.]+)/g)]
  .filter(([, name]) => name !== "off")
  .map(([, name, value]) => ({ name, share: Number(value) }));

const emojiWords = lines(`${resources}/emoji.txt`).filter((l) => l.split("\t")[1]).length;
const emoji = lines(`${resources}/emoji-search.txt`).filter((l) => !l.startsWith("#")).length;

const lexicon = readFileSync(join(root, resources, "en.lexicon"));
if (lexicon.subarray(0, 4).toString() !== "HXL1") throw new Error("en.lexicon isn't HXL1");
let words = 0;
for (let offset = 8; offset + 8 <= lexicon.length; offset += 8) if (lexicon[offset + 1] !== 0) words++;

const count = (dir, pattern) =>
  [...new Bun.Glob("**/*.swift").scanSync(join(root, dir))].reduce(
    (sum, file) => sum + (read(join(dir, file)).match(pattern) ?? []).length,
    0,
  );

const phrases = lines("Packages/HexKeyboard/Tests/KeyboardUITests/phrases.txt").length;
const baseline = total("baseline");
const learning = total("learning");
const phraseWords = lines("Packages/HexKeyboard/Tests/KeyboardUITests/phrases.txt").join(" ").split(/\s+/).length;
if (baseline.words !== learning.words || learning.words !== 2 * phraseWords) throw new Error("the thumbs run isn't the phrase set typed twice");

const facts = {
  name: "iikb",
  site: "https://iikb.vercel.app",
  repo: "https://github.com/AVGVSTVS96/iikb",
  license: "MIT",
  iosMinimum: Number(find("project.yml", /iOS: "(\d+)/)[1]),
  accuracy: {
    source: "scripts/eval.expected, EVAL thumbs (KeyboardUITests/Evaluation.biasedThumbs)",
    phrases,
    words: learning.words,
    blockWords: Number(evalLine("EVAL thumbs keyboard=learning per").match(/per (\d+) words/)[1]),
    baseline: baseline.autocorrect,
    iikb: learning.autocorrect,
    baselineCurve: curve("baseline"),
    iikbCurve: curve("learning"),
  },
  missesToMoveAKey: 3,
  themes,
  haptics: {
    levels: strengths.length,
    softest: Math.min(...strengths.map((s) => s.share)),
    strongest: Math.max(...strengths.map((s) => s.share)),
  },
  emoji,
  emojiWords,
  lexiconWords: words,
  tests: {
    core: count("Packages/HexKeyboard/Tests/KeyboardCoreTests", /@Test\b/g),
    ui: count("Packages/HexKeyboard/Tests/KeyboardUITests", /@Test\b/g) + count("UITests", /func test\w*\(/g),
    coreSeconds: Number(find("PROGRESS.md", /runs KeyboardCore's tests on Linux in about (\d+) s/)[1]),
  },
  voice: {
    downloadMB: Number(find("App/Voice/VoiceModel.swift", /Downloads once, about (\d+) MB/)[1]),
    speechSeconds: Number(find("PROGRESS.md", /writes ([\d.]+) s of speech in ([\d.]+) s/)[1]),
    writeSeconds: Number(find("PROGRESS.md", /writes ([\d.]+) s of speech in ([\d.]+) s/)[2]),
  },
};
find("Packages/HexKeyboard/Tests/KeyboardCoreTests/TypingModelTests.swift", /theSameMissThreeTimesRunningMovesTheKey/);

writeFileSync(join(import.meta.dir, "facts.json"), `${JSON.stringify(facts, null, 2)}\n`);
console.log(JSON.stringify(facts, null, 2));
