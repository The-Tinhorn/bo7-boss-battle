# Boss Battle for BO7 Zombies (Kronos)

Infinite Warfare style boss battles for Black Ops 7 Zombies on the Kronos client, on every launch map.
By [Tinhorn](https://www.youtube.com/@TheTinhorn) — subscribe :)

Two separate mods live here:

| Mod | Folder | What it does |
|---|---|---|
| **Boss Battle** | [`boss_battle/`](boss_battle) | Pick the **Boss Battle** tile (it takes over Directed). You spawn in a zombie-free gear-up area with maxed money, Pack-a-Punch, Wunderfizz, crafting table, Arsenal, GobbleGum, Mystery Box, armor and every wonder weapon. Walk into the **YELLOW** portal (round 40) or **RED** portal (round 100) to start the map's boss fight, with a timer and personal best. The **GREEN** portal toggles relics for a Cursed fight. |
| **Fast Restart** | [`fast_restart/`](fast_restart) | Old-CoD fast restart, in any Zombies match. **Crouch (or go prone), then pause:** Save & Quit reads *Fast Restart* and restarts the match instantly. **Pause standing:** normal Save & Quit. Host only. |

## Install

**From a release:** download `BossBattle-test-<version>.zip` from [Releases](../../releases), close the game, and copy the
`boss_battle` folder (and `fast_restart` if you want it) into `<game folder>\kronos\mods\`. Keep each mod's
`scripts\compiled` folder. Then enable the mods in the Kronos Mods menu.

Boss Battle needs the **BO3 HUD kit** mod that ships with Kronos (for the timer and relic menu). Built and tested on Kronos v1.41.

Full how-to-play, known issues and the changelog: [`README - Boss Battle.txt`](README%20-%20Boss%20Battle.txt).

## Reporting a problem

Tell Tinhorn the map, the portal, whether relics were on and what happened, and send `<game folder>\poi_reg.log`
and `<game folder>\kronos\boss_battle\state.json`, copied right after the problem and before starting the game again.
