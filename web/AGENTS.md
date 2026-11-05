# web

The web demo and iikb's page.

- `Sources/KeyboardWeb` exports a `Keyboard` class to JavaScript (JavaScriptKit BridgeJS) that forwards to `TypingEngine` the way `FullKeyboardViewController` does, against the page's text field.
- `site/` is iikb's page (`page.css`, `page.js`, which fills its numbers from `copy/facts.json`), around a demo that draws the keys from `KeyboardCore`'s metrics, faces and colors and ports `KeyboardView+Touches` to pointer events.
- Deployed to Vercel as `iikb` (iikb.vercel.app) from `web/dist`, built by `scripts/web`.
- `redirect/` is the old `iikb` project, sending iikb.vercel.app there.
