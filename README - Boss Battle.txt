BOSS BATTLE  (test build 0.5)  -  by Tinhorn
Infinite Warfare style boss battles for Black Ops 7 Zombies on the Kronos client.
SUBSCRIBE TO TINHORN :)  youtube.com/@TheTinhorn


NEW IN 0.5
- Fast Restart is no longer part of Boss Battle, so Save & Quit is back to normal. Fast Restart is
  now a separate mod of its own: github.com/The-Tinhorn/bo7-fast-restart
- Rex Infernus: zombies now spawn in the boss fight. They were spawning under the arena floor.
- The gear-up armor chalks sit a bit higher off the floor.

NEW IN 0.4
- FAST RESTART: in a Boss Battle match the pause menu's "Save & Quit" becomes "Fast Restart". It
  restarts the match straight back to the gear-up area without the menus or a reload (host only).
- The gear-up armor wallbuy now sits on the visible floor (on Kowakujo it was sunk into the ground).

NEW IN 0.3
- Fights no longer play like Directed: zombies sprint and hit like standard Zombies.
- YELLOW portal: zombies are round 40, but the boss has the health it has for a solo player in
  normal Zombies (round 25 on most maps), so it isn't tankier than a 4-player fight anymore.
  RED portal is unchanged: a real round-100 boss.
- Kowakujo: the gear-up Pack-a-Punch no longer gets hidden by the map's own PaP setup. It can
  take up to ~20 seconds to appear there.
- Rex Infernus: the gear-up Wunderfizz has power now.
- Rex Infernus: everyone gets the upgraded grapple (unlimited uses) in the gear-up area and again
  when the fight starts.
- All zombies are cleared when you enter a portal. Stray zombies elsewhere on the map could fill
  the fight's zombie limit, so none spawned in the arena.
- The script now comes pre-compiled (scripts\compiled\boss_battle.gscc). Compiling it in game
  was giving some people "transmission error".

NEW IN 0.2
- Portal colours swapped: YELLOW is now round 40 and RED is round 100.
- The round counter now shows 40 / 100 in the fight (it used to stay on 1).
- Rex Infernus: you're moved out of the cramped spawn house to the map's Pack-a-Punch, and the
  gear-up Pack-a-Punch there works.
- Bigger fight timer.
- The relic menu at the green portal works.
- Power and relic setup now wait until the map has finished loading.


WHAT YOU NEED
- Kronos v1.41 (the version this was built and tested on).
- The "BO3 HUD kit" mod that comes with Kronos, enabled. The timer and relic menu use it.


INSTALL
1. Close the game.
2. Copy the "boss_battle" folder from this zip into your Kronos mods folder, so you end up with:
      <game folder>\kronos\mods\boss_battle\mod.json
3. Keep the "scripts\compiled" folder and the boss_battle.gscc inside it. Kronos crashes at
   startup if that folder is missing.
4. Start the game and make sure "Boss Battle" is enabled in the Kronos Mods menu.

UPDATING TO A NEW TEST BUILD
1. Close the game completely.
2. Copy the new files over the old ones.
3. Make sure boss_battle\scripts\compiled\boss_battle.gscc was replaced by the new one too.4. Start the game. Quitting to the menu is not enough; the game keeps the old script until a full
   restart.

UNINSTALL
Disable it in the Kronos Mods menu, or delete the boss_battle folder.


HOW TO PLAY
- Pick any map and choose the "Boss Battle" tile. It takes over the Directed tile; Standard,
  Cursed and the other modes are untouched.
- You spawn in a gear-up area: no zombies, the round is frozen and your money stays maxed.
  Around you: Pack-a-Punch, Wunderfizz, crafting table, Arsenal, GobbleGum machine, Mystery Box,
  an armor wallbuy on the floor, and every wonder weapon on the floor (one of each per player).
  Gold armor, Pack-a-Punch tier 4 and ultra rarity are always unlocked.
  On Rex Infernus the spawn house is too tight, so a few seconds in you're teleported to the
  map's Pack-a-Punch and the gear-up area is set up there.
- YELLOW portal: the map's boss fight at round 40, with the boss at solo health.
- RED portal: the same fight at round 100.
- GREEN portal: relics. Stand next to it and a relic list appears on the left.
     Use (interact)        = next relic
     Crouch + Use          = switch the selected relic on / off
  If any relic is on when you walk into the yellow or red portal, the fight is CURSED and uses
  the game's Cursed boss tuning. With no relics on it uses the standard tuning.
- The fight timer and your personal best (PB) show in the top-right corner. PBs are kept per
  map, per round (40 / 100) and standard vs Cursed.


KNOWN ISSUES / NOT TESTED YET
- Cursed fights (relics on) are barely tested: report whether each relic actually does something.
- Wonder weapons from other maps may be missing effects off their home map.
- Directed's on-screen objective hints don't show during fights.
- Not this mod, but worth knowing: some operator skins (T.E.D.D.'s Civil Protector for one) can
  leave Kronos stuck on the loading screen on some maps, like Ashes. Switch to a different skin.

REPORTING A PROBLEM
Tell Tinhorn:
- the map, which portal (yellow / red), whether any relics were on, and what happened;
- and send these two files, copied right after the problem, BEFORE starting the game again
  (the first one is overwritten every launch):
      <game folder>\poi_reg.log
      <game folder>\kronos\boss_battle\state.json
