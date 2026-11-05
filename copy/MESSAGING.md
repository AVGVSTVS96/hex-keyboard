# iikb: words

## Name

- **iikb**, lowercase everywhere. The name stands alone and is never expanded.
- Code and bundle IDs keep iikb so updates preserve installed data. Explain this only in the README's Install section.

## Position

**The best iOS keyboard. In the world.**

That's what we're building. A keyboard that learns your thumbs, writes what you say, and earns its place on your iPhone and iPad.

Apple and Raycast are the bar to beat. Lead with iikb's ambition and the concrete work behind it, rather than describing it as a copy of either keyboard. Credit Raycast for visual inspiration, and NVIDIA and FluidAudio for Parakeet dictation.

“Best” states the project's ambition. Never present it as an independently measured ranking or claim a win over Apple's complete keyboard from the spell-checker baseline.

## Website

- Hero: “The best iOS keyboard. In the world.” Supporting line above, with **Build iikb** linking to the README's Install section.
- Challenge: “Apple, Raycast: we're coming for the space bar.”
- Screens: iPhone, iPad and Duo keyboard layout captures, switchable with plain buttons; all layouts remain available without JavaScript. Existing simulator captures illustrate layouts, not a claim of the latest build.
- Typing: adaptive touch targets, on-device next-word model, personal vocabulary, space corrections and Your Taps.
- Benchmark: subordinate to the product story, explicitly a recorded biased-tap test against nearest key plus Apple's spell checker. Numbers come from `copy/facts.json`, regenerated with `bun copy/facts.mjs`.
- Voice: on-device recognition, writing styles, cancel, microphone switch, transcript review and available recordings.
- Tools: clipboard with large-text retention, emoji, GIFs, theme and layout controls, user-configured sources.
- Availability: MIT, iOS 26+, build from source; no App Store download implied. English today; swipe typing in development and further languages not yet available.

## Metadata

Title: iikb · The best iOS keyboard. In the world.

Description: Building the best iOS keyboard in the world. Adaptive typing, on-device dictation, and tools worth switching for. Open source for iPhone and iPad.

## Accuracy and privacy

Only cite capabilities verified in the current code. Keep raw benchmark scope beside results. Never publish private dictations, tap counts, addresses or clipboard content. On-device recognition is not a blanket no-network claim: model downloads, GIF searches, configured sources and build-configured backups have different data paths. Describe them accurately in the README.

## Tone

Confident, direct, competitive. Concrete capabilities carry the argument. No invented awards, rankings, users, testimonials or performance claims. No generic marketing filler.
