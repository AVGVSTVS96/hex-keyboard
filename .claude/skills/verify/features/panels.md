# GIF search and the clipboard

## Sub-features

The GIF tool at the bar's left opens KLIPY's trending GIFs in two rows that scroll sideways (one in the compact layout), each at its own aspect ratio. The keys type into "Search KLIPY", and a search goes out as you type, one at a time (`GifSearch`). A tap puts the GIF on the clipboard and the search row says "Copied. Paste it, or hold a GIF to drag it in."; holding one drags it into the app's field; the clock shows the GIFs you sent. It needs Full Access and a KLIPY key in `Packages/HexKeyboard/Sources/KeyboardUI/Resources/Keys/klipy.key`; without a key there's no GIF tool.

The clipboard tool beside it opens what you copied, pinned first, newest first, with how long ago. The keys search it. A tap types the text into the app, or puts an image back on the clipboard; holding a row offers Pin and Delete. It needs Full Access and Settings › Apps › Hex › Paste from Other Apps set to Allow; the panel says which is missing, and Turn On opens Hex's page in Settings.

## How to get to it (user POV)

Tap the GIF or clipboard tool at the bar's left, before the suggestions.

## Driving it with XCUITest

`ToolPanelTests` (UI, `scripts/paneltest`) turns on Full Access, searches "cat", taps a GIF, checks the clipboard holds a GIF and the clock shows it; then copies text in the test runner, meets the Paste from Other Apps message on a fresh simulator, taps Turn On and allows it, finds the copy, searches it, types it into the app and pins it, screenshotting each step into `shots/raw/panels/`. `ClipboardHistoryTests` and `GifSearchTests` (package) pin the history's order, pins and search, and the one-request-at-a-time searching; `ClipboardStoreTests` and `GifTests` (package, simulator) pin what's kept from a real pasteboard and how KLIPY's pages decode.
