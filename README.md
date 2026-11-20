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
zap ZORK the Snatcher when he raids, and shelter in your shield dome when the
solar storm hits — the dome pays double during the storm. Rebirth into a new
station ring for +50% credits forever.

## How to play

| Key | Action |
|-----|--------|
| **E** | Catch a wild brainrot / dock in a pod / steal from a rival module |
| **L** | Lock your module (airlock shield) |
| **F** | Zap ZORK the Snatcher with the Zapper (3x drives him off) |
| **Q** | Drop your cargo |

- **30 original brainrots** across 6 rarities (Common → Secret), from
  Bloop Blorp ($8/s) to the Big Bang Burrito ($50K/s).
- **Mutations:** Gold x2, Diamond x3, Irradiated x4 (solar storm only),
  Cosmic x10 — with a legend inside the Star Chart.
- **Star Chart:** the collection panel — rarity-sorted grid, found-count
  n/30, ??? silhouettes for the ones you haven't found yet, ON BASE tags
  for docked species, and one flavor line per alien (tap a tile).
- **Events:** Solar Storm every ~60s with a live countdown banner and a
  Safe Dome that pays x2 while you shelter, Golden Hour (2x credits),
  Meteor Shower (bonus brainrots on the outer deck).
- **Quests:** 14 station quests with progress and credit rewards, plus a
  4-mission chain that always shows the next goal on the HUD.
- **Upgrades:** Tractor Beam Mk II/III, Cargo Bubble, Shield Extender,
  Module Expansion — four named, levelled tracks with LV n/m and prices.
- **Station feed:** the last events stay visible on the left of the HUD
  ("QUEST DONE ...", "Module locked for 30s!", "ZAPPED ...").
- **Sectors:** Sector 2 on the outer deck is where the rare aliens roam,
  up to Legendary.
- **Tutorial:** a guided first minute — catch, dock, lock — with a 3D
  beacon pointing at exactly what to do next. Dismissible, never blocks
  the title screen.

## Tour (screenshot capture in Studio)

From the Studio command bar (server), with a player in-game:

| Command | Shot |
|-----|------|
| `require(game.ServerScriptService.Tour).showTitle("first")` | Title screen: logo, tagline, feature line, 3-step how-to, PLAY |
| `require(game.ServerScriptService.Tour).showCatch("first")` | Tractor-beam catch (press E for the mid-beam shot) |
| `require(game.ServerScriptService.Tour).showStorm("first")` | Solar storm active: orange sky, domes up, shelter banner |
| `require(game.ServerScriptService.Tour).showModule("first")` | Showcase module with Star Chart + Upgrades open |
| `require(game.ServerScriptService.Tour).showIndex("first")` | Star Chart open: 8/30 found, ON BASE tags, legend |
| `require(game.ServerScriptService.Tour).showQuests("first")` | Quests panel open: 14 quests, mixed progress |

## The living station

Five crew NPCs with idle animations, a cleaning robot and a delivery
drone on patrol loops, control consoles with blinking lights, supply
crates by the airlock, a hydroponic garden, and a docked shuttle visible
through the observation windows. The station is bright; dark space stays
outside, as a backdrop. Every area has its own saturated accent color,
neon trim and glowing props — the festive look follows the design
language of the reference game below.

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

- `src/shared/` — game data (30 species, rarities, mutations, upgrades,
  missions), formatting, the whitelisted remotes.
- `src/server/` — world builder, brainrot factory, session-locked
  DataStore with schema migration, player state, wild spawner, storm
  service, ZORK the Snatcher, the core game service, and the
  finalist-review tour module.
- `src/client/` — 3D title screen, HUD, upgrades/Star Chart/quests/
  rebirth panels, guided tutorial with 3D beacon, ContextActionService
  input, procedural animation, beam effects.

## Credits

Built by an AI agent (Plenger) for Krstan's make.fun entry, as
@jefaprayoga-stack. All brainrot names, the station, and the game are
original — no assets, no copied code. License: MIT (see `LICENSE`).

Design reference for the round 5 festive look (candy buttons, neon trim,
showcase stage): [on1force/brainrot-game](https://github.com/on1force/brainrot-game)
(MIT) — the design language was followed with original code; no code or
asset ids were copied from it.
