# Computers

Stats shows your iPhone and each computer you add, each apart, picked in the menu beside the title. A computer is an
address that answers `GET typing-stats.json` with its typing and dictation counts, to whoever sends its token, and the
app reads it straight from there: over Tailscale when the iPhone and the computer are both on your tailnet, or else your
home network.

```
iPhone ──GET <url>/typing-stats.json──► Mac ── Keystroke's typing-stats.json
       Authorization: Bearer <token>    (mac/share)
```

## Adding a Mac

On the Mac, with [Keystroke](https://glaze.app) counting there:

```
curl -fsSL https://raw.githubusercontent.com/AVGVSTVS96/iikb/main/mac/share | sh
```

It makes the Mac a token, has a LaunchAgent answer on port 2593 (launchd starts `~/.config/iikb/serve` for each request,
so nothing runs in between), and shows a QR code. Scan it with the iPhone's camera and iikb opens on the Mac's Stats.
The same link works pasted into Stats › Add Computer.

- **Tailscale** (when `tailscale status` answers): the listener takes only `127.0.0.1`, and `tailscale serve` puts it on
  `https://<the Mac>.<your tailnet>.ts.net/iikb`, so only your tailnet reaches it, over HTTPS. Tailscale must be on on
  the iPhone too.
- **Without it**: the listener takes the local network, at `http://<the Mac>.local:2593`, so the iPhone reaches it on
  the same Wi-Fi.

Run it again after changing networks or Tailscale, or with a path to share another stats file. `sh share --stop` stops
sharing.

## Any computer

Anything that answers the same way can be a computer: `GET <url>/typing-stats.json` with
`Authorization: Bearer <token>`, answering Keystroke's version 3 file (docs/stats.md) and its time in `Last-Modified`.
Its link:

```
iikb://computer?name=Studio&url=https%3A%2F%2Fstudio.example.ts.net%2Fiikb&token=secret
```

The address is `https`, or `http` on the local network (`.local`), as for sources (docs/sources.md).

## On the iPhone

The computers you add are in the app's `Application Support/computers.json`, so the backup keeps them. Stats reads each
one as it comes forward and keeps its last answer in `Caches/computers/`, so a computer shows as it last was while it's
asleep or out of reach. The menu's Forget removes one.
