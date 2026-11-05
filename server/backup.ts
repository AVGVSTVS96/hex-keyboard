#!/usr/bin/env bun
/**
 * Backup: keeps every file iikb sends (`Backup.swift`, docs/backup.md) in <dir>/mirror, laid out as `scripts/backup`
 * lays it out, and deletes nothing: a file sent again with other contents moves the one it replaces to
 * <dir>/versions/<time>/.
 *
 *   BACKUP_TOKEN=secret bun server/backup.ts [--port 2592] [--dir ~/.local/share/hex-keyboard/backup]
 *
 * GET /         every file it holds, as { "app/transcripts.jsonl": [size, modified], … }, times in seconds
 * PUT /<name>   a file, with its modification time in X-Modified
 * GET /mac/<name>  a file the Mac sent, with its time in Last-Modified, for the app's Stats (docs/stats.md)
 * GET /personal/<name>  a file made here for the iPhone (`scripts/personal`'s network), the same way; the iPhone's
 *               own files are never read back out, so its token can't take them
 */
import { mkdir, readdir, rename, rm, stat, utimes } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, relative, sep } from "node:path";
import { parseArgs } from "node:util";

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

export const backup =
  (dir: string, token: string, now = () => new Date()) =>
  async (request: Request): Promise<Response> => {
    if (request.headers.get("authorization") !== `Bearer ${token}`) return new Response(null, { status: 401 });
    const mirror = join(dir, "mirror");
    const name = decodeURIComponent(new URL(request.url).pathname).replace(/^\/+(backup\/*)?/, "");
    if (request.method === "GET" && name === "") return Response.json(await held(mirror));

    const file = join(mirror, name);
    if (request.method === "GET") {
      const sent = Bun.file(file);
      if (!given.some((folder) => file.startsWith(join(mirror, folder) + sep)) || !(await sent.exists())) return new Response(null, { status: 404 });
      return new Response(sent, { headers: { "last-modified": new Date((await stat(file)).mtimeMs).toUTCString() } });
    }
    const modified = Number(request.headers.get("x-modified"));
    if (request.method !== "PUT" || !file.startsWith(mirror + sep) || !Number.isSafeInteger(modified)) return new Response(null, { status: 400 });

    const incoming = join(dir, "incoming", crypto.randomUUID());
    await mkdir(dirname(incoming), { recursive: true });
    await Bun.write(incoming, request);
    if (await Bun.file(file).exists()) {
      if (await same(file, incoming)) {
        await rm(incoming);
      } else {
        const version = join(dir, "versions", stamp(now()), name);
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
      dir: { type: "string", default: join(homedir(), ".local/share/hex-keyboard/backup") },
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
