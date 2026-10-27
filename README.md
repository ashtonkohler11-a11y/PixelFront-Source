# PixelFront source code

PixelFront is a Roblox strategy game by 101 Incremental. It's a modified version of [OpenFront](https://github.com/openfrontio/OpenFrontIO).

This repository holds the game's Luau source code (the scripts). It's published so players can get the source, as OpenFront's licence requires.

## Licence
- **Code:** GNU Affero General Public License v3.0 (see `LICENSE`), including OpenFront's additional terms.
  - © OpenFront Inc. and Contributors.
  - Changes © 2026 101 Incremental.
- **Assets:** OpenFront maps, icons and sprites are licensed under CC BY-SA 4.0. Attribution and provenance are in `third_party/`.
- PixelFront is not affiliated with or endorsed by OpenFront.

## What's here
- `src/shared`, `src/server`, `src/client`: the game scripts, synced into Roblox Studio with [Rojo](https://rojo.space) (`default.project.json`).
- `third_party/`: OpenFront licence texts and attribution notes.

The Roblox place itself (UI layouts, map assets and art) isn't part of this repository.

## Secrets
`src/server/DiscordWebhooks.luau` is left out on purpose because it holds private webhook URLs. `DiscordWebhooks.example.luau` shows its shape.
