# BRAINROT ORBIT

[![roblox-brainrot-01](https://make.fun/badge/roblox-brainrot-01.svg)](https://make.fun/c/roblox-brainrot-01)
[![rank](https://make.fun/badge/roblox-brainrot-01/JefaCVC/brainrot-orbit/rank.svg)](https://make.fun/c/roblox-brainrot-01)
[![reward](https://make.fun/badge/roblox-brainrot-01/JefaCVC/brainrot-orbit/reward.svg)](https://make.fun/c/roblox-brainrot-01)

**Catch them. Dock them. Get rich before the storm hits.**

A 3D brainrot game on a bright space station, built for the
[make.fun roblox-brainrot-01 bounty](https://make.fun/c/roblox-brainrot-01).
Wild alien brainrots roam the observation deck — catch them with your tractor
beam, carry them home in your cargo bubble, and dock them in your module's
habitat pods to earn credits every second. Lock your module against thieves,
bonk ZORK the Snatcher when he raids, and dash to your shield dome when the
solar storm hits. Rebirth into a new station ring for +50% credits forever.

## How to play

| Key | Action |
|-----|--------|
| **E** | Catch a wild brainrot / dock in a pod / steal from a rival module |
| **L** | Lock your module (energy shield) |
| **F** | Bonk ZORK the Snatcher with the Plasma Bat (3x drives him off) |
| **Q** | Drop your cargo |

- **19 original brainrots** across 6 rarities (Common → Secret), from
  Bloop Blorp ($8/s) to the Big Bang Burrito ($50K/s).
- **Mutations:** Gold x2, Diamond x3, Irradiated x4 (solar storm only),
  Cosmic x10 — plus an Index with ??? silhouettes for the ones you
  haven't found yet.
- **Events:** Solar Storm every ~60s, Golden Hour (2x credits),
  Meteor Shower (bonus brainrots on the outer deck).
- **Upgrades:** Tractor Beam Mk II/III, Cargo Bubble, Shield Extender,
  Module Expansion — four named, levelled tracks.
- **Missions:** a 3-mission chain with credit rewards, always showing
  the next goal on the HUD.

## Build

Rojo-first, no Studio dependency for the build:

```sh
rojo build default.project.json --output game.rbxl
mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts
```

The world (station, modules, garden, airlock, crew, planet, satellites)
is built at runtime by `src/server/WorldBuilder.luau` — the place file
holds the scripts, and the server builds the world when it starts.

## Layout

- `src/shared/` — game data (19 species, rarities, mutations, upgrades,
  missions), formatting, the whitelisted remotes.
- `src/server/` — world builder, brainrot factory, session-locked
  DataStore with schema migration, player state, wild spawner, storm
  service, ZORK the Snatcher, the core game service, and the
  finalist-review tour module.
- `src/client/` — 3D title screen, HUD, upgrades/index/rebirth panels,
  ContextActionService input, procedural animation, beam effects.

## Credits

Built by an AI agent (Plenger) for Krstan's make.fun entry, as
@jefaprayoga-stack. All brainrot names, the station, and the game are
original — no assets, no copied code. License: MIT (see `LICENSE`).
