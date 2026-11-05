import { afterEach, expect, test } from "bun:test";
import { mkdtemp, readdir, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { backup, type Held } from "./backup.ts";

const dirs: Array<string> = [];
afterEach(async () => {
  for (const dir of dirs.splice(0)) await rm(dir, { recursive: true });
});

const server = async (times: Array<Date> = []) => {
  const dir = await mkdtemp(join(tmpdir(), "backup-"));
  dirs.push(dir);
  const fetch = backup(dir, "secret", () => times.shift() ?? new Date());
  const send = (method: string, path: string, body?: string, modified = 1_762_000_000, token = "secret") =>
    fetch(new Request(`http://server${path}`, { method, body, headers: { authorization: `Bearer ${token}`, "x-modified": String(modified) } }));
  return { dir, send, held: async () => (await (await send("GET", "/")).json()) as Held };
};

test("keeps a file with the size and time it was sent with, under its name", async () => {
  const { dir, send, held } = await server();
  expect((await send("PUT", "/keyboard/support/typing-memory.json", "{}", 1_762_000_123)).status).toBe(204);
  expect(await held()).toEqual({ "keyboard/support/typing-memory.json": [2, 1_762_000_123] });
  expect(await readFile(join(dir, "mirror/keyboard/support/typing-memory.json"), "utf8")).toBe("{}");
  expect((await stat(join(dir, "mirror/keyboard/support/typing-memory.json"))).mtimeMs).toBe(1_762_000_123_000);
});

test("tailscale serve's /backup in the path names nothing", async () => {
  const { send, held } = await server();
  await send("PUT", "/backup/app/transcripts.jsonl", "a");
  expect(Object.keys(await held())).toEqual(["app/transcripts.jsonl"]);
});

test("a file sent with other contents keeps the one it replaces as a version, and one sent again unchanged keeps none", async () => {
  const { dir, send } = await server([new Date(2026, 10, 4, 4, 56, 5), new Date(2026, 10, 4, 5, 0, 0)]);
  await send("PUT", "/app/transcripts.jsonl", "one");
  await send("PUT", "/app/transcripts.jsonl", "one\ntwo", 1_762_000_500);
  await send("PUT", "/app/transcripts.jsonl", "one\ntwo", 1_762_000_600);
  expect(await readFile(join(dir, "mirror/app/transcripts.jsonl"), "utf8")).toBe("one\ntwo");
  expect(await readdir(join(dir, "versions"))).toEqual(["2026-11-04T045605"]);
  expect(await readFile(join(dir, "versions/2026-11-04T045605/app/transcripts.jsonl"), "utf8")).toBe("one");
  expect((await stat(join(dir, "mirror/app/transcripts.jsonl"))).mtimeMs).toBe(1_762_000_600_000);
});

test("takes nothing without the token, outside its folder, or without a time", async () => {
  const { send, held } = await server();
  expect((await send("GET", "/", undefined, 0, "wrong")).status).toBe(401);
  expect((await send("PUT", "/app/x", "a", 1, "wrong")).status).toBe(401);
  expect((await send("PUT", "/app/..%2F..%2Fx", "a")).status).toBe(400);
  expect((await send("PUT", "/", "a")).status).toBe(400);
  expect((await send("PUT", "/app/x", "a", Number.NaN)).status).toBe(400);
  expect((await send("DELETE", "/app/x")).status).toBe(400);
  expect(await held()).toEqual({});
});

test("gives back only what the Mac sent, with the time it was sent with", async () => {
  const { send } = await server();
  await send("PUT", "/mac/typing-stats.json", "{}", 1_762_000_123);
  await send("PUT", "/app/transcripts.jsonl", "private");
  const mac = await send("GET", "/backup/mac/typing-stats.json");
  expect(mac.status).toBe(200);
  expect(await mac.text()).toBe("{}");
  expect(new Date(mac.headers.get("last-modified")!).getTime()).toBe(1_762_000_123_000);
  expect((await send("GET", "/app/transcripts.jsonl")).status).toBe(404);
  expect((await send("GET", "/mac/..%2Fapp/transcripts.jsonl")).status).toBe(404);
  expect((await send("GET", "/mac/missing.json")).status).toBe(404);
  expect((await send("GET", "/mac/typing-stats.json", undefined, 0, "wrong")).status).toBe(401);
});

test("gives back what it made for the iPhone, under personal/", async () => {
  const { send } = await server();
  await send("PUT", "/personal/en.network", "net", 1_762_000_321);
  const personal = await send("GET", "/backup/personal/en.network");
  expect(await personal.text()).toBe("net");
  expect(new Date(personal.headers.get("last-modified")!).getTime()).toBe(1_762_000_321_000);
  expect((await send("GET", "/personal/../app/x")).status).toBe(404);
});

test("a file replaced twice in one second keeps both versions, the first where --at finds it first", async () => {
  const second = new Date(2026, 10, 4, 4, 56, 5);
  const { dir, send } = await server([second, second, second]);
  await send("PUT", "/keyboard/support/typing-memory.json", "learned");
  await send("PUT", "/keyboard/support/typing-memory.json", "", 1_762_000_500);
  await send("PUT", "/keyboard/support/typing-memory.json", "{}", 1_762_000_600);
  await send("PUT", "/keyboard/support/typing-memory.json", "[]", 1_762_000_700);
  expect((await readdir(join(dir, "versions"))).sort()).toEqual(["2026-11-04T045605", "2026-11-04T045605.001", "2026-11-04T045605.002"]);
  expect(await readFile(join(dir, "versions/2026-11-04T045605/keyboard/support/typing-memory.json"), "utf8")).toBe("learned");
  expect(await readFile(join(dir, "versions/2026-11-04T045605.001/keyboard/support/typing-memory.json"), "utf8")).toBe("");
  expect(await readFile(join(dir, "versions/2026-11-04T045605.002/keyboard/support/typing-memory.json"), "utf8")).toBe("{}");
  expect(await readFile(join(dir, "mirror/keyboard/support/typing-memory.json"), "utf8")).toBe("[]");
});
