#!/usr/bin/env bun
/**
 * Backup: keeps every file iikb sends (`Backup.swift`, docs/backup.md) in <dir>/mirror, laid out as `scripts/backup`
 * lays it out, and deletes nothing: a file sent again with other contents moves the one it replaces to
 * <dir>/versions/<time>/.
 *
 *   BACKUP_TOKEN=secret bun server/backup.ts [--port 2592] [--dir ~/.local/share/iikb/backup]
 *
 * Each request names its device in X-Device ("iPhone" when it names none, as builds before it). An iPhone's files are
 * kept in <dir>; another device's in <dir>-<device> (~/.local/share/iikb/backup-ipad), so they never go over the
 * iPhone's, while what the server gives back stays one for all of them. The listing says the device back in X-Device,
 * which a device other than an iPhone waits for before sending anything.
 *
 * GET /         every file it holds for the device, and what it gives back, as { "app/transcripts.jsonl": [size, modified], … }, times in seconds
 * PUT /<name>   a file, with its modification time in X-Modified
 * GET /mac/<name>  a file the Mac sent, with its time in Last-Modified, for the app's Stats (docs/stats.md)
 * GET /personal/<name>  a file made here for the iPhone (`scripts/personal`'s network), the same way; the iPhone's
 *               own files are never read back out, so its token can't take them
 * GET /iphone/typing-stats.json  the iPhone's typing and dictation counts, made here as Keystroke keeps the Mac's
 *               (`keystroke.ts`), for Keystroke on the Mac (docs/stats.md)
 */
import { mkdir, readdir, rename, rm, stat, utimes } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, relative, sep } from "node:path";
import { parseArgs } from "node:util";

import { keystroke } from "./keystroke.ts";

/** What the server gives back: what the Mac sent and what it makes for the iPhone. */
const given = ["mac", "personal"];

export type Held = Record<string, [size: number, modified: number]>;

const held = async (mirror: string): Promise<Held> => {
  const entries = await readdir(mirror, { recursive: true, withFileTypes: true }).catch(() => []);
  const files = entries.filter((entry) => entry.isFile()).map((entry) => join(entry.parentPath, entry.name));
  const stats = await Promise.all(files.map((file) => stat(file)));
  return Object.fromEntries(files.map((file, i) => [relative(mirror, file).split(sep).join("/"), [stats[i]!.size, Math.floor(stats[i]!.mtimeMs / 1000)]]));
};

const same = async (a: string, b: string) => {
  const [one, other] = [Bun.file(a), Bun.file(b)];
  return one.size === other.size && Buffer.from(await one.arrayBuffer()).equals(Buffer.from(await other.arrayBuffer()));
};

/** The time as `scripts/backup` names a version: 2026-11-04T045605, here. */
const stamp = (date: Date) => {
  const two = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}T${two(date.getHours())}${two(date.getMinutes())}${two(date.getSeconds())}`;
};

/** Where a version replaced at `time` goes: the second's folder, or, when that second already kept one of this file,
 * the next of 2026-11-04T045605.001, .002, … `scripts/restore` sorts these after the second's own, so `--at` still
 * picks the first replaced. */
const free = async (versions: string, time: string, name: string) => {
  for (let n = 0; ; n++) {
    const version = join(versions, n === 0 ? time : `${time}.${String(n).padStart(3, "0")}`, name);
    if (!(await Bun.file(version).exists())) return version;
  }
};

export const backup =
  (dir: string, token: string, now = () => new Date()) =>
  async (request: Request): Promise<Response> => {
    if (request.headers.get("authorization") !== `Bearer ${token}`) return new Response(null, { status: 401 });
    const device = request.headers.get("x-device") ?? "iPhone";
    if (!/^[A-Za-z]+$/.test(device)) return new Response(null, { status: 400 });
    const shared = join(dir, "mirror");
    const own = device === "iPhone" ? dir : `${dir.replace(/\/+$/, "")}-${device.toLowerCase()}`;
    const mirror = join(own, "mirror");
    const name = decodeURIComponent(new URL(request.url).pathname).replace(/^\/+(backup\/*)?/, "");
    if (request.method === "GET" && name === "") {
      const gives = Object.entries(await held(shared)).filter(([file]) => given.some((folder) => file.startsWith(`${folder}/`)));
      return Response.json({ ...(await held(mirror)), ...Object.fromEntries(gives) }, { headers: { "x-device": device } });
    }
    if (request.method === "GET" && name === "iphone/typing-stats.json") return Response.json(await keystroke(shared));

    if (request.method === "GET") {
      const file = join(shared, name);
      const sent = Bun.file(file);
      if (!given.some((folder) => file.startsWith(join(shared, folder) + sep)) || !(await sent.exists())) return new Response(null, { status: 404 });
      return new Response(sent, { headers: { "last-modified": new Date((await stat(file)).mtimeMs).toUTCString() } });
    }
    const file = join(mirror, name);
    const modified = Number(request.headers.get("x-modified"));
    if (request.method !== "PUT" || !file.startsWith(mirror + sep) || !Number.isSafeInteger(modified)) return new Response(null, { status: 400 });

    const incoming = join(own, "incoming", crypto.randomUUID());
    await mkdir(dirname(incoming), { recursive: true });
    await Bun.write(incoming, request);
    if (await Bun.file(file).exists()) {
      if (await same(file, incoming)) {
        await rm(incoming);
      } else {
        const version = await free(join(own, "versions"), stamp(now()), name);
        await mkdir(dirname(version), { recursive: true });
        await rename(file, version);
      }
    }
    if (await Bun.file(incoming).exists()) {
      await mkdir(dirname(file), { recursive: true });
      await rename(incoming, file);
    }
    await utimes(file, modified, modified);
    return new Response(null, { status: 204 });
  };

if (import.meta.main) {
  const { values } = parseArgs({
    options: {
      port: { type: "string", default: "2592" },
      dir: { type: "string", default: join(homedir(), ".local/share/iikb/backup") },
    },
  });
  const token = process.env["BACKUP_TOKEN"];
  if (!token) throw new Error("BACKUP_TOKEN is unset");
  Bun.serve({
    hostname: "127.0.0.1",
    port: Number(values.port),
    maxRequestBodySize: Number.MAX_SAFE_INTEGER,
    fetch: backup(values.dir, token),
  });
}
