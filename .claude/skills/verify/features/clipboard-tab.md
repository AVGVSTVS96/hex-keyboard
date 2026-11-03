# The app's Clipboard tab

## Sub-features

The same history the keyboard's clipboard panel keeps (`ClipboardStore`, in the App Group's `Library/clipboard/history.json`, with a copy in the keyboard's own container that a group without a history takes): Pinned first, then by day, newest first, each row its text or a thumbnail over the time it was kept, under a search field. A tap copies an item again and shows "Copied"; holding offers Copy, Share, Pin or Unpin and Delete; the … menu has Clear History, which keeps what's pinned. When the app comes forward it keeps what's on the clipboard, once the keyboard has started the history and Full Access and Paste from Other Apps are on; until then a card says which to turn on.

## How to get to it (user POV)

Copy something in any app with Hex's clipboard turned on, then open Hex › Clipboard.

## Driving it

`CLIPBOARD=<history.json> PAGES=clipboard scripts/mac 'scripts/sim duoapp <tag>'` copies a history into the App Group and screenshots the tab on the Duo's screens. `ClipboardHistoryTests` (package) pins the order, pins, search and joining a history kept elsewhere; `ClipboardStoreTests` (package, simulator) what's kept from a real pasteboard and from the keyboard's older copy.
