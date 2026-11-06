/**
 * The iPhone's typing and dictation as Keystroke keeps the Mac's (its typing-stats.json, version 3), so Keystroke can
 * show both (docs/stats.md): counts and times from the keyboard's hours and the transcripts, never their text.
 */
import { join } from "node:path";

const channel = () => ({
  keystrokes: 0,
  chars: 0,
  words: 0,
  backspaces: 0,
  activeMs: 0,
  peakWpm: 0,
  timedChars: 0,
  timedMs: 0,
  inserts: 0,
  hours: Array<number>(24).fill(0),
  hourChars: Array<number>(24).fill(0),
  hourActiveMs: Array<number>(24).fill(0),
});

type Channel = ReturnType<typeof channel>;
type Day = { date: string; typed: Channel; voice: Channel };

type Hour = { day: string; hour: number; seconds: number; tally: { keys: number; characters: number; words: number; deletes: number } };
type Transcript = { date: number; seconds: number; text: string };

/** Transcripts' dates count seconds from 2001, as Foundation's do. */
const since2001 = Date.UTC(2001, 0, 1);

const lines = async <T>(file: string): Promise<Array<T>> => {
  const text = await Bun.file(file).text().catch(() => "");
  return text.split("\n").flatMap((line) => {
    try {
      return line ? [JSON.parse(line) as T] : [];
    } catch {
      return [];
    }
  });
};

const local = (date: Date) => {
  const two = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}`;
};

export const keystroke = async (mirror: string) => {
  const days: Record<string, Day> = {};
  const day = (date: string) => (days[date] ??= { date, typed: channel(), voice: channel() });

  for (const { day: date, hour, seconds, tally } of await lines<Hour>(join(mirror, "group/Library/typing.jsonl"))) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !(hour >= 0 && hour < 24)) continue;
    const typed = day(date).typed;
    const ms = Math.round(seconds * 1000);
    typed.keystrokes += tally.keys;
    typed.chars += tally.characters;
    typed.words += tally.words;
    typed.backspaces += tally.deletes;
    typed.activeMs += ms;
    typed.hours[hour]! += tally.keys;
    typed.hourChars[hour]! += tally.characters;
    typed.hourActiveMs[hour]! += ms;
  }

  let words = 0;
  let chars = 0;
  let inserts = 0;
  let lastSeen = 0;
  for (const { date, seconds, text } of await lines<Transcript>(join(mirror, "app/transcripts.jsonl"))) {
    if (!text) continue;
    const at = new Date(since2001 + date * 1000);
    const voice = day(local(at)).voice;
    const count = text.split(/\s+/).filter(Boolean).length;
    const ms = Math.round(seconds * 1000);
    voice.chars += text.length;
    voice.words += count;
    voice.timedChars += text.length;
    voice.timedMs += ms;
    voice.inserts += 1;
    voice.hours[at.getHours()]! += 1;
    voice.hourChars[at.getHours()]! += text.length;
    voice.hourActiveMs[at.getHours()]! += ms;
    words += count;
    chars += text.length;
    inserts += 1;
    lastSeen = Math.max(lastSeen, at.getTime());
  }

  return {
    version: 3,
    createdAt: Math.min(Date.now(), ...Object.keys(days).map((date) => new Date(`${date}T00:00:00`).getTime())),
    paused: false,
    days,
    wpmHistogram: {},
    sources: inserts ? { iikb: { name: "iikb", words, chars, inserts, lastSeen } } : {},
    sourceOverrides: {},
  };
};
