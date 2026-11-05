#using script_4478f81b31480314;  // bgb_machine (GobbleGum machine)
#using scripts\common\callbacks;
#using scripts\common\trace;
#using scripts\common\utility;
#using scripts\mp\arsenal;
#using scripts\mp\crafting_table;
#using scripts\mp\currency;
#using scripts\mp\common\utility\loot;
#using scripts\mp\electric_power_switch;
#using scripts\mp\equipment;
#using scripts\mp\interaction;
#using scripts\mp\magicbox;
#using scripts\mp\loot\common_item;
#using scripts\mp\loot\common_item_weapon;
#using scripts\mp\pack_a_punch;
#using scripts\mp\perk_machines;
#using scripts\mp\wallbuy;
#using scripts\mp\wallbuy_armor;
#using scripts\mp\zm\zm_utility;
#using scripts\mp\zm\systems\relics\zm_relics;
#using scripts\mp\zm\systems\zm_exfil;
#using scripts\mp\zm\systems\zm_round_logic;
#using scripts\mp\zm\systems\zm_round_spawning;
#using scripts\mp\zm\spawners\zone_spawner;

#namespace boss_battle;

// Boss Battle for every BO7 launch map, played from the Directed tile (shown as Boss Battle).
// Spawn is a zombie-free lobby with maxed essence/salvage, PaP, Wunderfizz, a crafting table and
// wonder weapon loot; walking into the relic portal starts the map's real boss fight through its
// boss file's own dev quick start (zm_sat_<map>_boss_fight.gsc, BO7 dump PC_S6L_20261016), which
// sets the round and teleports players itself.
// No #using of map scripts (map-only scripts aren't resident elsewhere). Instead we provide the
// retail-missing #"dev" register_dev_console_callback shared func; every map's boss pre_main
// registers its dev start under #"hash_7d1b4b7b23fd890d", so it hands us that function pointer.
// Kronos rules: no endon, state lives on level, method results are passed as arguments.
// Diagnostics: kronos\boss_battle\state.json.

autoexec init()
{
    bb_store("map", getdvar("g_mapname", ""));
    bb_store("gametype", getdvar("g_gametype", ""));
    level.bb_map = bb_map_code(getdvar("g_mapname", ""));
    if (!isdefined(level.bb_map))
    {
        return;
    }
    // Boss Battle replaces the Directed mode (its menu tile is relabelled by lua/boss_battle_post.lua).
    // g_gametype is still empty at autoexec, so the mode check waits for on_spawned.
    // One portal per boss round, side by side: yellow = round 40, red = round 100. The fight scales
    // the boss to the round it's started at.
    level.bb_portal_rounds = [40, 100];
    level.bb_portal_colors = ["yellow", "red"];
    level.bb_portal_codes = ["^3", "^1"];
    level.bb_fight_round = 40;
    level.bb_missed = 0;            // objects that found no open spot (diagnostics)
    setdvar("kronos_boss_timer", "");  // hides a timer left over from a quit match
    setdvar("kronos_boss_pb", "");
    setdvar("kronos_bb_relic_menu", "");
    nengine_store_load("boss_battle_times", "times");
    utility::registersharedfunc(#"dev", #"register_dev_console_callback", &capture_dev_callback);
    level callback::add(#"player_spawned", &on_spawned);
    level callback::add(#"zm_mq_quest_complete", &on_quest_complete);
    bb_store("loaded", 1);
}

bb_map_code(mapname)
{
    foreach (code in ["firefly", "ruby", "mantis", "scarab", "locust", "hornet"])
    {
        if (mapname == "zm_sat_" + code)
        {
            return code;
        }
    }
    return undefined;
}

// Per-map boss signals from each zm_sat_<map>_boss_fight.gsc.
// Level flag the fight sets when the boss dies (the zm_mq_quest_complete callback covers most maps too).
boss_done_flag()
{
    if (level.bb_map == "mantis") return "boss_fight_done";
    if (level.bb_map == "locust") return "boss_fight_end";
    return level.bb_map + "_boss_fight_complete";
}

// Level flag set when the intro cinematic ends, where the map has one (Ashes uses a notify instead).
boss_intro_flag()
{
    if (level.bb_map == "hornet") return "hornet_boss_fight_intro_complete";
    if (level.bb_map == "scarab") return "scarab_boss_intro_done";
    return undefined;
}

on_quest_complete(params)
{
    if (isdefined(level.bb_t0))
    {
        level.bb_boss_dead = 1;
    }
}

bb_flag(name)
{
    return isdefined(name) && utility::flag_exist(name) && level utility::flag(name);
}

capture_dev_callback(name, func)
{
    if (name == #"hash_7d1b4b7b23fd890d")
    {
        level.bb_boss_start = func;
        bb_store("boss_hook", 1);
    }
}

on_spawned(params)
{
    if (isdefined(level.bb_setup))
    {
        return;
    }
    level.bb_setup = 1;  // once per match; bb_lobby clears when the fight starts, so respawns can't re-run this
    bb_store("gametype", getdvar("g_gametype", ""));
    // zm_guided.gsc main() (the Directed gametype) builds level.directed_mode with this field.
    if (!isdefined(level.directed_mode) || !isdefined(level.directed_mode.var_fcdcd383b4f959ed))
    {
        bb_store("loaded", "skipped_not_directed");
        return;
    }
    level.bb_lobby = 1;
    zm_round_spawning::pause_round_spawning(1, "boss_battle_lobby");
    zm_exfil::disable_zm_exfil(1);
    level thread lobby_upkeep();
    // Layout follows where the player spawned, facing the way they face.
    // Kept on level: vectors handed to a thread that then waits came through undefined.
    level.bb_spawn_origin = self.origin;
    level.bb_spawn_angles = (0, self.angles[1], 0);
    bb_store("spawn_origin", "" + level.bb_spawn_origin);
    level thread spawn_lobby_after_load();
    bb_store("lobby", 1);
}

// player_spawned can fire while the loading screen is still up, and spawning the machines and
// portal right then left one load stuck. Give the load a few seconds, then place them from a
// fresh thread.
// The power switch and the borrowed Cursed relic setup wait for the load too: Astra and Ashes both
// hung on a dimmed/loading screen after they were moved into player_spawned.
spawn_lobby_after_load()
{
    wait 5;
    bb_store("after_load", 1);
    // Power only (open_sesame's first line): doors stay shut, no "OPEN SESAME!" banner.
    electric_power_switch::function_2d462dbfcc76b0db(1);
    // The gear-up Wunderfizz waits for the global "power_on" flag, which Rex Infernus's switches
    // don't set. Setting that flag ourselves gave a black screen there (Rex's quests key off it), so
    // instead the Wunderfizz type is put on perk_machines' "powered at start" list.
    if (!isdefined(level.var_1d3d915cc555bf38))
    {
        level.var_1d3d915cc555bf38 = [];
    }
    level.var_1d3d915cc555bf38["specialty_choice"] = 1;
    // Relics: own thread so an error in the game's relic init can't stop the lobby; the unlocks
    // are applied afterwards from another thread either way.
    level thread relic_init();
    level thread relic_unlocks_later();
    if (level.bb_map == "scarab")
    {
        relocate_to_pap();
        level thread give_grapples();
    }
    level thread spawn_lobby();
}

// Rex Infernus spawns players in a cramped house, so everyone is teleported in front of the map's
// own Pack-a-Punch and the gear-up area is laid out around that spot instead. The PaP comes from
// pack_a_punch.gsc's machine list (level.var_db52bcfd04d45a7a), or failing that the map's
// "pack_a_punch_machine" structs. state.json "relocate" = where everyone went, or why not.
relocate_to_pap()
{
    level.bb_pap_struct = undefined;
    if (isdefined(level.var_db52bcfd04d45a7a) && level.var_db52bcfd04d45a7a.size > 0)
    {
        level.bb_pap_struct = level.var_db52bcfd04d45a7a[0];
    }
    else
    {
        pap_struct_keep(utility::getstructarray("pack_a_punch_machine", "script_noteworthy"));
    }
    if (!isdefined(level.bb_pap_struct) || !isdefined(level.bb_pap_struct.origin))
    {
        bb_store("relocate", "no_pap");
        return;
    }
    if (!isdefined(level.bb_pap_struct.angles))
    {
        level.bb_pap_struct.angles = (0, 0, 0);
    }
    level.bb_pap_front = level.bb_pap_struct.origin + anglestoforward(level.bb_pap_struct.angles) * 120;
    relocate_keep(getclosestpointonnavmesh(level.bb_pap_front, 96));
    if (!isdefined(level.bb_relocated))
    {
        relocate_keep(getclosestpointonnavmesh(level.bb_pap_struct.origin, 160));
    }
}

// Rex Infernus's map Pack-a-Punch bundle is its quest forge (sat_zm_quest_scarab_pap), which stays
// shut until the map's PaP quest is done, so a copy of it in the gear-up area doesn't work.
// pack_a_punch::get_pap_bundle() checks level.var_9afe2a15c55fcc5 before the map's bundle, so this
// points it at the game type's / game mode's standard machine. state.json "pap_bundle" says which.
standard_pap_bundle()
{
    if (isdefined(level.gametypebundle) && isdefined(level.gametypebundle.packapunchbundle))
    {
        level.var_9afe2a15c55fcc5 = level.gametypebundle.packapunchbundle;
        bb_store("pap_bundle", "gametype");
        return;
    }
    if (isdefined(level.gamemodebundle) && isdefined(level.gamemodebundle.packapunchbundle))
    {
        level.var_9afe2a15c55fcc5 = level.gamemodebundle.packapunchbundle;
        bb_store("pap_bundle", "gamemode");
        return;
    }
    bb_store("pap_bundle", "none_found");
}

pap_struct_keep(structs)
{
    if (isdefined(structs) && structs.size > 0)
    {
        level.bb_pap_struct = structs[0];
    }
}

relocate_keep(spot)
{
    if (!isdefined(spot))
    {
        bb_store("relocate", "no_navmesh");
        return;
    }
    level.bb_relocated = 1;
    level.bb_spawn_origin = spot;
    level.bb_spawn_angles = face_point(level.bb_pap_struct.origin, spot);
    // Doors stay shut, so the PaP's zone may not be enabled yet; place() then skips the zone check
    // (still same floor, on the navmesh and in sight of this spot).
    if (utility::issharedfuncdefined(#"zombie", #"hash_bad01cbc996e3dba") && !utility::callsharedfunc(#"zombie", #"hash_bad01cbc996e3dba", spot))
    {
        level.bb_skip_zone_check = 1;
    }
    // ponytail: co-op players are spread 40 units apart sideways without a navmesh check; add one if
    // anyone lands in a wall.
    i = 0;
    foreach (player in level.players)
    {
        player setorigin(level.bb_spawn_origin + anglestoright(level.bb_spawn_angles) * (i * 40));
        player setplayerangles(level.bb_spawn_angles);
        i++;
    }
    bb_store("relocate", "" + spot);
}

face_point(target, from)
{
    dir = vectortoangles(target - from);
    return (0, dir[1], 0);
}

// Keeps the lobby empty and the wallet full until the fight starts.
lobby_upkeep()
{
    while (isdefined(level.bb_lobby))
    {
        zm_utility::util_kill_all_zombies();
        foreach (player in level.players)
        {
            player currency::set_currency_amount(#"essence", 999999);
            player currency::set_currency_amount(#"salvage", 999999);
            player currency::set_currency_amount(#"rare_salvage", 999999);
        }
        wait 2;
    }
}

// Each object gets the first open spot found by place(), searched in its preferred direction:
// portal straight ahead, Wunderfizz ahead-left, crafting table ahead-right, PaP behind, armor
// wallbuy to the right, wonder weapon loot to the left. A waitframe between objects spreads the
// search out; everything that crosses a wait lives on level.
spawn_lobby()
{
    // Splash in the bold centre-screen text open_sesame used; ^5 is the light blue colour code.
    foreach (player in level.players)
    {
        player iprintlnbold("^5SUBSCRIBE TO TINHORN");
    }
    level.bb_used = [];
    level.bb_cleanup_items = [];
    level.bb_cleanup_wb = [];
    // Both portal spots first, straight ahead; the gap puts the second one beside the first.
    level.bb_portal_spots = [];
    foreach (r in level.bb_portal_rounds)
    {
        place(0, 220, 64, 150);
        level.bb_portal_spots[level.bb_portal_spots.size] = level.bb_spot;
    }
    waitframe();

    place(-40, 140, 48, 110);
    fizz = spawnstruct();
    fizz.origin = level.bb_spot;
    fizz.angles = face_spawn(level.bb_spot);
    paid = spawnstruct();
    paid.script_currency = #"essence";
    // Skip the "buy N perks / reach round N" wait before the Wunderfizz appears.
    level.var_865fa84b8f7cc220 = 1;
    fizz thread perk_machines::function_e3d3bfcc06c89350(paid);
    level thread bb_store_later("wunderfizz", fizz, 10);
    waitframe();

    place(40, 140, 48, 110);
    table = spawnstruct();
    table.origin = level.bb_spot;
    table.angles = face_spawn(level.bb_spot);
    table crafting_table::spawn_crafting_table();
    bb_store("crafting", isdefined(table.var_7fac639c5e7fd54));
    waitframe();

    place(180, 120, 48, 110);
    level.bb_pap_spot = level.bb_spot;
    level thread spawn_lobby_pap();
    waitframe();

    spawn_wonder_loot();

    // Relic-trial portals, spawned the way the relic system does (spawn, wait a frame, set the vfx
    // part). If the scriptable isn't loaded, fall back to Ashes' garage teleport pad.
    level.bb_portals = [];
    level.bb_portal_hinted = [];
    level.bb_pi = 0;
    while (level.bb_pi < level.bb_portal_spots.size)
    {
        level.bb_portal_hinted[level.bb_pi] = 0;
        portal_relic(spawnscriptable("zm_relic_portals", level.bb_portal_spots[level.bb_pi], face_spawn(level.bb_portal_spots[level.bb_pi])), level.bb_portal_colors[level.bb_pi]);
        if (!isdefined(level.bb_portals[level.bb_pi]))
        {
            portal_pad(spawnscriptable(%"zm_sat_firefly_garage_player_teleport_station", level.bb_portal_spots[level.bb_pi], face_spawn(level.bb_portal_spots[level.bb_pi])));
        }
        level.bb_pi++;
    }
    bb_store("portal", "" + level.bb_portal_spots[0]);
    bb_store("open_spots_missed", level.bb_missed);
    level thread portal_watch();
    // Last and on its own thread: it pokes game wallbuy internals, so a failure there can't stop
    // the portal or anything else from spawning.
    level thread spawn_armor_wallbuys();
    level thread spawn_arsenal_and_gum();
    level thread spawn_relic_altar();
}

// Kowakujo's PaP quest hides every machine in the PaP list when round logic begins
// (zm_sat_hornet_pap_quest::pap_machine_setup, which sets flag "pap_setup" when done), ours too if
// it's already listed, so there ours waits for that first (20 s cap). Own thread: nothing else waits.
spawn_lobby_pap()
{
    level.bb_pap_wait = gettime() + 20000;
    while (level.bb_map == "hornet" && !bb_flag("pap_setup") && gettime() < level.bb_pap_wait)
    {
        wait 0.5;
    }
    bb_store("pap_waited_ms", 20000 - (level.bb_pap_wait - gettime()));
    level.bb_pap = spawnstruct();
    level.bb_pap.origin = level.bb_pap_spot;
    level.bb_pap.angles = face_spawn(level.bb_pap_spot);
    level.bb_pap.script_start = 1;  // starts active, skipping the map's PaP quest
    if (level.bb_map == "scarab")
    {
        standard_pap_bundle();
    }
    level.bb_pap pack_a_punch::init_pap_machine(undefined);
    bb_store("pap", isdefined(level.bb_pap.var_370acb837a3a86c3));
}

// ---- Relics -------------------------------------------------------------------------------
// Relics are Cursed-only: zm_relics' init returns unless the Cursed flag
// (level.var_8a98c33a6b47db4a, set by zm_rb_r_mod) is up, while each relic script registers its
// on/off functions in every mode. So the init runs here with the flag raised for the call only,
// and relics are switched on and off in game at the green relic portal.
relic_init()
{
    if (!isdefined(level.zm_relics))
    {
        level.bb_cursed_flag = level.var_8a98c33a6b47db4a;
        level.var_8a98c33a6b47db4a = 1;
        zm_relics::init_zm_relics();
        level.var_8a98c33a6b47db4a = level.bb_cursed_flag;
    }
    level.bb_relic_keys = [];
    level.bb_relic_names = [];
    foreach (key, bundle in level.zm_relics)
    {
        level.bb_relic_keys[level.bb_relic_keys.size] = key;
        // Loot name (e.g. relic_gramophone); the Lua menu turns it into display text.
        relic_name_keep(loot::function_f54ecb89dfab8e8c(bundle.lootid));
    }
    bb_store("relics", level.bb_relic_keys.size);
}

relic_name_keep(name)
{
    if (!isdefined(name))
    {
        name = "relic " + (level.bb_relic_names.size + 1);
    }
    level.bb_relic_names[level.bb_relic_names.size] = "" + name;
}

// The relic menu drawn by lua/boss_battle_post.lua from the kronos_bb_relic_menu dvar: lines
// split by "|", each starting with a code: h header, f footer, n relic, o relic on, c cursor,
// b cursor on a relic that is on. Nine relics show at a time around the cursor.
relic_menu_show()
{
    level.bb_relic_menu_on = 1;
    level.bb_relic_on_count = 0;
    foreach (key in level.bb_relic_keys)
    {
        if (relic_is_on(level.zm_relics[key]))
        {
            level.bb_relic_on_count++;
        }
    }
    text = "hRELICS   " + level.bb_relic_on_count + " ON   (" + (level.bb_relic_i + 1) + "/" + level.bb_relic_keys.size + ")";
    first = level.bb_relic_i - 4;
    if (first > level.bb_relic_keys.size - 9)
    {
        first = level.bb_relic_keys.size - 9;
    }
    if (first < 0)
    {
        first = 0;
    }
    for (k = first; k < first + 9 && k < level.bb_relic_keys.size; k++)
    {
        code = "n";
        if (k == level.bb_relic_i)
        {
            code = "c";
        }
        if (relic_is_on(level.zm_relics[level.bb_relic_keys[k]]))
        {
            if (code == "c")
            {
                code = "b";
            }
            else
            {
                code = "o";
            }
        }
        text = text + "|" + code + level.bb_relic_names[k];
    }
    text = text + "|fUSE: NEXT     CROUCH + USE: ON / OFF";
    setdvar("kronos_bb_relic_menu", text);
}

relic_menu_hide()
{
    if (isdefined(level.bb_relic_menu_on))
    {
        level.bb_relic_menu_on = undefined;
        setdvar("kronos_bb_relic_menu", "");
    }
}

relic_unlocks_later()
{
    wait 1;
    relic_unlocks();
    bb_store("relic_unlocks", 1);
}

// What Cursed relic tier 3 unlocks (zm_relics' tier setter), always on in Boss Battle: gold armor
// from the armor wallbuy (tier 1+), ultra rarity (tier 2+) and Pack-a-Punch tier 4 (tier 3).
// Relic points start at 9, so switching relics on and off never drops below tier 3.
relic_unlocks()
{
    if (!isdefined(level.var_acf4b75304823180) || level.var_acf4b75304823180 < 9)
    {
        level.var_acf4b75304823180 = 9;
    }
    level.zm_relic_tier = 3;
    level.var_48e2b36291b57f44 = 5;  // max rarity: ultra
    level.var_eda995bb839c4aa = 4;   // max Pack-a-Punch tier
    utility::registersharedfunc(#"relics", #"hash_459bf078b969217d", &zm_relics::function_f09353885602ac5e);
    setomnvar("ui_show_weapon_upgrade_tier_5", 1);
    if (hasomnvar("ui_zm_relic_tier"))
    {
        setomnvarforallclients("ui_zm_relic_tier", 3);
    }
}

// Green relic portal behind the spawn. Use: show the next relic. Crouch + Use: switch the shown
// relic on or off. Feedback goes to the player's screen.
spawn_relic_altar()
{
    wait 3;  // after relic_init
    if (!isdefined(level.bb_relic_keys) || level.bb_relic_keys.size == 0)
    {
        bb_store("relic_altar", "no_relics");
        return;
    }
    place(180, 240, 64, 150);
    level.bb_relic_pos = level.bb_spot;
    level.bb_relic_i = 0;
    level.bb_relic_hinted = 0;
    relic_altar_keep(spawnscriptable("zm_relic_portals", level.bb_relic_pos, face_spawn(level.bb_relic_pos)));
    level.bb_relic_use = interaction::register_interact(level.bb_relic_pos + (0, 0, 40), 70, &relic_used, &relic_hint);
    bb_store("relic_altar", isdefined(level.bb_relic_use));
    while (isdefined(level.bb_lobby))
    {
        near_any = 0;
        foreach (player in level.players)
        {
            if (isalive(player) && distance2dsquared(player.origin, level.bb_relic_pos) < 220 * 220)
            {
                near_any = 1;
            }
        }
        if (near_any)
        {
            relic_menu_show();
        }
        else
        {
            relic_menu_hide();
        }
        wait 0.25;
    }
    relic_menu_hide();
}

relic_altar_keep(portal)
{
    if (!isdefined(portal))
    {
        return;
    }
    level.bb_relic_altar = portal;
    waitframe();
    portal utility::function_7c10ea82c1e305b8("vfx", "green_portal");
}

relic_bundle()
{
    return level.zm_relics[level.bb_relic_keys[level.bb_relic_i]];
}

relic_is_on(bundle)
{
    return isdefined(bundle.modifiertype) && zm_relics::function_9ee232e9e55c3939(bundle.modifiertype);
}

relic_used(player)
{
    if (player getstance() == "crouch")
    {
        relic_toggle();
    }
    else
    {
        level.bb_relic_i = (level.bb_relic_i + 1) % level.bb_relic_keys.size;
    }
    relic_menu_show();
}

relic_toggle()
{
    bundle = relic_bundle();
    if (!isdefined(bundle.modifiertype))
    {
        return;
    }
    if (relic_is_on(bundle))
    {
        zm_relics::function_90442c590e60cb05(bundle);
    }
    else
    {
        zm_relics::function_f6ef95770f20fc2c(bundle);
    }
    relic_unlocks();
}

// Prompt over the relic portal: the shown relic's own name.
relic_hint(interact, player)
{
    hint = spawnstruct();
    hint.type = "HINT_BUTTON";
    hint.string = relic_bundle().name;
    hint.title = relic_bundle().name;
    return hint;
}

// Arsenal (weapon rarity / armor upgrades) behind-left and GobbleGum machine behind-right.
// Both spawn like the map's own content_manager instances: a struct with origin/angles handed to
// the machine's init. Own thread, after everything else, so a failure here can't block the rest.
spawn_arsenal_and_gum()
{
    place(140, 120, 48, 110);
    arsenal = spawnstruct();
    arsenal.origin = level.bb_spot;
    arsenal.angles = face_spawn(level.bb_spot);
    arsenal.script_start = 1;  // starts enabled instead of waiting on power
    arsenal thread arsenal::init_arsenal_machine(undefined);
    level.bb_arsenal = arsenal;  // removed at fight start (it stayed in Paradox Junction's arena)
    level thread bb_store_arsenal_later(arsenal);
    waitframe();

    place(-140, 120, 48, 110);
    gum = spawnstruct();
    gum.origin = level.bb_spot;
    gum.angles = face_spawn(level.bb_spot);
    gum bgb_machine::function_9a3e81eb8357ad32(undefined);
    bb_store("gobblegum", isdefined(gum.mdl_bgb_machine));
    waitframe();

    spawn_magicbox();
}

// An extra Mystery Box, built the way magicbox.gsc builds a map box location: copy the map box's
// scriptable/variant, register the struct (function_ab59e6993557d5b6), then show it and mark it
// the active box so it takes uses. level.var_5542fc8f8eafa0c0 is the game's "box never moves"
// switch (should_move_magicbox), so the teddy bear can't carry it out of the lobby.
spawn_magicbox()
{
    if (!isdefined(level.var_1bbb5557537e2c0c) || level.var_1bbb5557537e2c0c.size == 0)
    {
        bb_store("magicbox", "no_map_box");
        return;
    }
    level.bb_box_template = level.var_1bbb5557537e2c0c[0];
    place(-170, 160, 56, 120);
    box = spawnstruct();
    box.origin = level.bb_spot;
    box.angles = face_spawn(level.bb_spot);
    box.targetname = "boss_battle_box";
    box.var_16c78d02bcf00cbc = level.bb_box_template.var_16c78d02bcf00cbc;
    box.script_parameters = level.bb_box_template.script_parameters;
    box magicbox::function_ab59e6993557d5b6();
    box thread magicbox::show_magicbox(1);
    box.var_f14b2b4820b635e7 = 1;
    level.var_5542fc8f8eafa0c0 = 1;
    bb_store("magicbox", isdefined(box.mdl_magicbox));
}

bb_store_arsenal_later(s)
{
    wait 5;
    bb_store("arsenal", isdefined(s.mdl_arsenal));
}

// Open-floor search. Rings outward from the spawn (min_r, +40 per ring), preferred direction first
// then alternating 22.5 degrees either side, and takes the first spot that is on the navmesh, on
// the spawn's floor, has walkable floor `clear` units all round (keeps machines out of walls and
// doorways), is visible from the spawn and is `gap` from everything already placed. No waits in
// here. Result: level.bb_spot. If nothing qualifies, the preferred spot snapped to the navmesh.
place(yaw_offset, min_r, clear, gap)
{
    level.bb_spot = undefined;
    for (r = min_r; r < min_r + 400 && !isdefined(level.bb_spot); r += 40)
    {
        for (i = 0; i < 16 && !isdefined(level.bb_spot); i++)
        {
            step = int((i + 1) / 2) * 22.5;
            if (i % 2 == 1)
            {
                step = 0 - step;
            }
            want = level.bb_spawn_origin + anglestoforward((0, level.bb_spawn_angles[1] + yaw_offset + step, 0)) * r;
            spot_ok(want, getclosestpointonnavmesh(want, 32), clear, gap);
        }
    }
    if (!isdefined(level.bb_spot))
    {
        level.bb_missed = level.bb_missed + 1;
        want = level.bb_spawn_origin + anglestoforward((0, level.bb_spawn_angles[1] + yaw_offset, 0)) * min_r;
        level.bb_spot = machine_spot(want, getclosestpointonnavmesh(want, 128));
    }
    level.bb_used[level.bb_used.size] = level.bb_spot;
}

spot_ok(want, nav, clear, gap)
{
    if (!isdefined(nav) || distance2dsquared(nav, want) > 24 * 24 || abs(nav[2] - level.bb_spawn_origin[2]) > 48)
    {
        return;
    }
    if (distance2dsquared(nav, level.bb_spawn_origin) < 80 * 80)
    {
        return;  // keep the spawn point itself clear
    }
    foreach (used in level.bb_used)
    {
        if (distance2dsquared(used, nav) < gap * gap)
        {
            return;
        }
    }
    for (k = 0; k < 8 && clear > 0; k++)
    {
        probe = nav + anglestoforward((0, k * 45, 0)) * clear;
        if (!near(getclosestpointonnavmesh(probe, 16), probe))
        {
            return;
        }
    }
    if (!sighttracepassed(level.bb_spawn_origin + (0, 0, 60), nav + (0, 0, 40), 0, undefined))
    {
        return;
    }
    // Must be inside an enabled zone: doors stay shut, and some maps (Paradox Junction) have
    // navmesh and sight lines past barriers into areas players can't reach. Same check the
    // magic box uses for its start location.
    if (!isdefined(level.bb_skip_zone_check) && utility::issharedfuncdefined(#"zombie", #"hash_bad01cbc996e3dba") && !utility::callsharedfunc(#"zombie", #"hash_bad01cbc996e3dba", nav))
    {
        return;
    }
    level.bb_spot = nav;
}

near(found, probe)
{
    return isdefined(found) && distance2dsquared(found, probe) < 12 * 12;
}

face_spawn(spot)
{
    dir = vectortoangles(level.bb_spawn_origin - spot);
    return (0, dir[1], 0);
}

// Armor wallbuys, one per armor level, in a row to the right of the spawn at chest height.
// wallbuy.gsc keeps every variant wallbuy in level.var_49911708ccd031bf, keyed by its scriptable
// name; the armor ones carry .armorlevel. When the map uses the single "universal" armor wallbuy,
// function_d925a3a846d30612 swaps that in itself, so only one is placed. Some game modes switch
// armor wallbuys off (gametype bundle flag var_c1e5bbace58c9528, which also skips
// wallbuy_armor's setup), so the flag is lifted while ours spawn and the setup is run if missing.
spawn_armor_wallbuys()
{
    level.bb_armor_names = [];
    if (isdefined(level.var_49911708ccd031bf))
    {
        foreach (name, variant in level.var_49911708ccd031bf)
        {
            if (isstring(name) && isdefined(variant.armorlevel))
            {
                level.bb_armor_names[level.bb_armor_names.size] = name;
            }
        }
    }
    bb_store("armor_names", bb_join(level.bb_armor_names));
    if (level.bb_armor_names.size == 0)
    {
        bb_store("armor_wallbuy", "none_on_map");
        return;
    }
    if (wallbuy::function_3401a0a7b55ffbdb())
    {
        level.bb_armor_names = [level.bb_armor_names[0]];
    }
    if (!utility::issharedfuncdefined(hashcat(#"hash_98a94353ec1044cc", "armor"), #"hash_aabdea2170a670c7"))
    {
        bb_store("armor_setup", "ran");
        wallbuy_armor::function_c3daf070dd67a8ad();
        waitframe();
    }
    level.bb_armor_flag = level.gametypebundle.var_c1e5bbace58c9528;
    level.gametypebundle.var_c1e5bbace58c9528 = 0;
    level.bb_armor_made = 0;
    foreach (name in level.bb_armor_names)
    {
        place(90, 100, 32, 70);
        w = spawnstruct();
        // Laid flat on the floor, face up, top edge away from the spawn so it reads upright.
        // Height above the floor: 2 sat too low (Tinhorn 2026-11-05), raise again here if needed.
        w.origin = floor_spot(level.bb_spot) + (0, 0, 8);
        yaw = face_spawn(level.bb_spot);
        w.angles = (-90, yaw[1], 0);
        w.script_noteworthy = name;
        wallbuy::function_d925a3a846d30612(w, undefined, name);
        if (isdefined(w.wallbuy_scriptable))
        {
            level.bb_armor_made++;
            level.bb_cleanup_wb[level.bb_cleanup_wb.size] = w.wallbuy_scriptable;
        }
    }
    level.gametypebundle.var_c1e5bbace58c9528 = level.bb_armor_flag;
    bb_store("armor_wallbuy", level.bb_armor_made);
}

// Navmesh points can sit under the visible floor (Kowakujo's sank the flat armor chalk), so the
// chalk rests on whatever a ray straight down hits; the navmesh height if the ray misses.
floor_spot(spot)
{
    return floor_hit(spot, trace::ray_trace(spot + (0, 0, 40), spot - (0, 0, 40)));
}

floor_hit(spot, hit)
{
    if (hit["fraction"] < 1)
    {
        bb_store("armor_floor_lift", hit["position"][2] - spot[2]);
        return hit["position"];
    }
    return spot;
}

bb_join(list)
{
    text = "";
    foreach (item in list)
    {
        text = text + item + " ";
    }
    return text;
}

// One of each wonder weapon per player as floor loot, each on its own open spot to the left of the
// spawn: Ray Gun, Mk II, the map's own wonder weapon, then the Necrofluid Gauntlet, Jotunn Star,
// Blundergat and Nekomancer from other maps (those may lack effects/alt fire off their home map),
// plus the Sundergat (upgraded Blundergat). The LGM-1 (ruby) was broken off Astra, so it only
// shows up on its own map.
spawn_wonder_loot()
{
    level.bb_loot = ["zm_sat_item_weapon_pi_raygun", "zm_sat_item_weapon_pi_raygunmark2", "zm_sat_item_weapon_ww_" + level.bb_map];
    foreach (code in ["firefly", "locust", "mantis", "hornet"])
    {
        if (code != level.bb_map)
        {
            level.bb_loot[level.bb_loot.size] = "zm_sat_item_weapon_ww_" + code;
        }
    }
    level.bb_loot[level.bb_loot.size] = "zm_sat_item_weapon_ww_mantis_upgraded";
    level.bb_placed = 0;
    level.bb_n = 0;  // one drop per (player, item); counters on level because of the waitframe
    while (level.bb_n < level.players.size * level.bb_loot.size)
    {
        place(-90, 90, 16, 44);
        level.bb_placed += drop_loot(getscriptbundle("itemspawnentry:" + level.bb_loot[level.bb_n % level.bb_loot.size]), level.bb_spot);
        level.bb_n++;
        waitframe();
    }
    bb_store("wonder_loot", level.bb_placed);
}

// Same drop as creator_live's wonder weapon gift; critical + var_fd47e835523b473f stop despawning.
drop_loot(bundle, spot)
{
    if (!isdefined(bundle))
    {
        return 0;
    }
    options = common_item::function_f5dfaa3bbdf99a33(spot, spot + (0, 0, 38));
    options.critical = 1;
    options.var_fd47e835523b473f = 1;
    keep_item(item_weapon::function_b960bc85ea91de14(bundle, options));
    return 1;
}

// Kept so start_fight can clear what nobody picked up (Paradox Junction's arena is the spawn).
keep_item(item)
{
    if (isdefined(item))
    {
        level.bb_cleanup_items[level.bb_cleanup_items.size] = item;
    }
}

// Removes the lobby's floor loot and armor wallbuys when the fight starts. Machines stay.
clear_lobby_drops()
{
    removed = 0;
    foreach (item in level.bb_cleanup_items)
    {
        if (isdefined(item))
        {
            common_item::function_869d7676e359a627(item, 1);  // the game's own item cleanup
            removed++;
        }
    }
    foreach (wb in level.bb_cleanup_wb)
    {
        if (isdefined(wb))
        {
            wb notify(#"death");  // same removal as the start room script's wallbuys
            wb freescriptable();
            removed++;
        }
    }
    level.bb_cleanup_items = [];
    level.bb_cleanup_wb = [];
    if (isdefined(level.bb_arsenal) && isdefined(level.bb_arsenal.mdl_arsenal))
    {
        if (isdefined(level.bb_arsenal.mdl_arsenal.interact))
        {
            level.bb_arsenal.mdl_arsenal.interact freescriptable();
        }
        if (isdefined(level.bb_arsenal.mdl_arsenal.vo_src))
        {
            level.bb_arsenal.mdl_arsenal.vo_src delete();
        }
        level.bb_arsenal.mdl_arsenal delete();
        removed++;
    }
    if (isdefined(level.bb_relic_altar))
    {
        level.bb_relic_altar freescriptable();
    }
    if (isdefined(level.bb_relic_use))
    {
        level.bb_relic_use delete();
    }
    bb_store("cleared", removed);
}

portal_relic(portal, color)
{
    if (!isdefined(portal))
    {
        bb_store("portal_kind", "relic_missing");
        return;
    }
    level.bb_portals[level.bb_pi] = portal;
    waitframe();
    portal utility::function_7c10ea82c1e305b8("vfx", color + "_portal");
    bb_store("portal_kind", "relic");
}

portal_pad(pad)
{
    if (!isdefined(pad))
    {
        bb_store("portal_kind", "none");
        return;
    }
    level.bb_portals[level.bb_pi] = pad;
    level.bb_portal_beacon = 1;
    pad setscriptablepartstate("body", "usable");
    pad setscriptablepartstate("fx", "available");
    bb_store("portal_kind", "garage_pad");
}

// Wunderfizz spawns after a short wait inside the game function; report whether it made it.
bb_store_later(key, s, seconds)
{
    wait seconds;
    bb_store(key, isdefined(s.mdl_perk_machine));
}

machine_spot(wanted, nav)
{
    if (isdefined(nav))
    {
        return nav;
    }
    return wanted;
}

portal_watch()
{
    beacon = 0;
    while (isdefined(level.bb_lobby))
    {
        foreach (i, spot in level.bb_portal_spots)
        {
            // Garage pad fallback only: pulse the Ashes teleport-out effect so the spot always shows.
            if (isdefined(level.bb_portal_beacon) && beacon % 12 == 0 && isdefined(level._effect["garage_player_teleport_out"]))
            {
                playfx(level._effect["garage_player_teleport_out"], spot);
            }
            near_any = 0;
            foreach (player in level.players)
            {
                if (!isalive(player) || abs(player.origin[2] - spot[2]) >= 100)
                {
                    continue;
                }
                if (distance2dsquared(player.origin, spot) < 60 * 60)
                {
                    level.bb_fight_round = level.bb_portal_rounds[i];
                    level thread start_fight();
                }
                if (distance2dsquared(player.origin, spot) < 220 * 220)
                {
                    near_any = 1;
                }
            }
            // Label each portal once per approach.
            if (near_any && !level.bb_portal_hinted[i])
            {
                foreach (player in level.players)
                {
                    player iprintlnbold(level.bb_portal_codes[i] + "Round " + level.bb_portal_rounds[i] + " ^7boss fight");
                }
            }
            level.bb_portal_hinted[i] = near_any;
        }
        beacon++;
        wait 0.25;
    }
}

start_fight()
{
    if (!isdefined(level.bb_lobby))
    {
        return;
    }
    if (level.bb_map == "firefly" && !isdefined(level.wonder_veh))
    {
        // The fight script uses Tessie unguarded; wait for it instead of crashing the fight.
        bb_store("fight", "waiting_tessie");
        return;
    }
    if (!isdefined(level.bb_boss_start))
    {
        bb_store("fight", "no_boss_hook");
        return;
    }
    level.bb_lobby = undefined;  // stops lobby_upkeep and portal_watch
    zm_round_spawning::pause_round_spawning(0, "boss_battle_lobby");
    foreach (portal in level.bb_portals)
    {
        if (isdefined(portal))
        {
            portal freescriptable();
        }
    }
    clear_lobby_drops();
    // Stray zombies elsewhere on the map count toward the fight's live-zombie cap (Rex Infernus only
    // spawns arena adds while under it), so the map starts the fight empty.
    zm_utility::util_kill_all_zombies();
    if (level.bb_map == "scarab")
    {
        level thread give_grapples();
        level thread rex_fix_arena_spawns();
    }
    // The quick start only queues its round (zm_round_logic::function_68bdb49c82c0f892 stores it
    // for the next round change, which never comes during the fight), so the fight stayed on
    // round 1 with round 1 health. Set the round counter itself first; the quick start then sees
    // it already matches.
    zm_round_logic::set_rb_round_number(level.bb_fight_round);
    zm_utility::function_1bd2eda42461fad1(level.bb_fight_round);  // HUD round counter (ui_round_num)
    set_fight_tuning();
    // The boss file's dev quick start: sets the round, then threads start_boss_fight().
    level thread [[ level.bb_boss_start ]](["round" + level.bb_fight_round]);
    bb_store("fight", "started");
    bb_store("fight_round", level.bb_fight_round);
    level thread fight_watch();
}

// The clock starts when the intro cinematic ends (or 90 s after the portal if that signal never
// comes) and stops when the fight's own complete flag is set. It's shown in the screen corner by
// lua/boss_battle_post.lua, which reads the kronos_boss_timer dvar.
fight_watch()
{
    load_best();
    if (level.bb_map == "firefly")
    {
        level utility::waittill_any_timeout(90, #"firefly_boss_intro_done");
    }
    else
    {
        // Maps with an intro flag: wait for it (90 s cap). Others start the clock right away.
        level.bb_wait_until = gettime() + 90000;
        while (isdefined(boss_intro_flag()) && !bb_flag(boss_intro_flag()) && gettime() < level.bb_wait_until)
        {
            wait 0.1;
        }
    }
    level.bb_t0 = gettime();
    bb_store("fight", "timing");
    level thread fight_diag();
    while (!isdefined(level.bb_boss_dead) && !bb_flag(boss_done_flag()))
    {
        setdvar("kronos_boss_timer", fmt_time(gettime() - level.bb_t0));
        wait 0.1;
    }
    level.bb_t1 = gettime();
    setdvar("kronos_boss_timer", fmt_time(level.bb_t1 - level.bb_t0));
    bb_store("fight_ms", level.bb_t1 - level.bb_t0);
    bb_store("fight", "complete");
    record_time(level.bb_t1 - level.bb_t0);
    wait 20;
    setdvar("kronos_boss_timer", "");
    setdvar("kronos_boss_pb", "");
}

// Personal best for this map, round and tuning (Cursed kept apart from standard), shown under
// the timer from the kronos_boss_pb dvar.
load_best()
{
    level.bb_time_key = level.bb_map + "_r" + level.bb_fight_round;
    if (level.bb_cursed_fight)
    {
        level.bb_time_key = level.bb_time_key + "_cursed";
    }
    level.bb_best_ms = 0;
    level.bb_best = nengine_store_get("boss_battle_times", "best_ms_" + level.bb_time_key);
    if (isdefined(level.bb_best))
    {
        level.bb_best_ms = int(level.bb_best);
    }
    show_best();
}

show_best()
{
    if (level.bb_best_ms > 0)
    {
        setdvar("kronos_boss_pb", "PB " + fmt_time(level.bb_best_ms));
    }
    else
    {
        setdvar("kronos_boss_pb", "PB --:--.-");
    }
}

// Each boss picks its tuning set (boss health, attacks, armor drops...) when its fight starts,
// checking in order: Directed (level.directed_mode) -> "zm_guided", the easiest; Cursed
// (level.var_8a98c33a6b47db4a) -> the Cursed sets; otherwise the standard "round100"/"default".
// Boss Battle runs in Directed, so the Directed marker is dropped for the rest of the match (the
// quest guidance that reads it checks isdefined first; only its on-screen guidance goes). With any
// relic switched on the fight is Cursed: the Cursed flag goes up and stays up, since some bosses
// check it during the fight too (no Full Armor drops between phases on the Blundergat map).
set_fight_tuning()
{
    level.bb_cursed_fight = 0;
    if (isdefined(level.bb_relic_keys))
    {
        foreach (key in level.bb_relic_keys)
        {
            if (relic_is_on(level.zm_relics[key]))
            {
                level.bb_cursed_fight = 1;
            }
        }
    }
    level.directed_mode = undefined;
    drop_directed_bundle();
    if (level.bb_fight_round < 100)
    {
        // Yellow portal: zombies and the round counter stay at the fight round, but the boss gets
        // the health a solo player has in vanilla. Red keeps the real round-100 boss.
        level.bb_health_func = utility::getsharedfunc(#"zombie", #"health_scaling_get_starting_health");
        utility::registersharedfunc(#"zombie", #"health_scaling_get_starting_health", &boss_solo_health);
    }
    if (level.bb_cursed_fight)
    {
        level.var_8a98c33a6b47db4a = 1;
        bb_store("fight_tuning", "cursed");
        msg = "^1Cursed ^7boss fight";
    }
    else
    {
        bb_store("fight_tuning", "standard");
        msg = "^7Standard boss fight";
    }
    foreach (player in level.players)
    {
        player iprintlnbold(msg);
    }
}


// Rex Infernus: the upgraded grapple the map's pedestals give (zm_ncfdpedestal::give_grappling_hook),
// handed to everyone in the gear-up area and again at the fight, with the unlimited-use flag the
// boss fight sets itself.
give_grapples()
{
    if (utility::flag_exist("ncfd_infinite_grapple_enabled"))
    {
        level utility::flag_set("ncfd_infinite_grapple_enabled");
    }
    foreach (player in level.players)
    {
        player.var_32e68c63905a0787 = 1;
        player enableoffhandweapons();
        player equipment_mp::giveequipment("equip_grappling_hook_upgraded", "secondary");
    }
    bb_store("grapple", level.players.size);
}

// Zombie counts for the first minute of the fight (state.json fight_ai_N: all AI alive,
// arena_spawns: spawn points the fight can use in zone_boss_arena).
fight_diag()
{
    if (level.bb_map == "scarab")
    {
        bb_store_size("arena_spawns", zone_spawner::function_20c574a6ba7cc5c6(["zone_boss_arena"], "zombie_base"));
    }
    for (i = 1; i <= 6; i++)
    {
        wait 10;
        bb_store_size("fight_ai_" + (i * 10), getaiarray());
        if (level.bb_map == "scarab")
        {
            rex_adds_diag();
        }
    }
}

// Rex Infernus snaps its arena spawn points to the floor (getgroundposition, keeping .origin_old)
// the moment its fight starts (zm_sat_scarab_boss_fight function_de46ba50ea2f6c61). In vanilla the
// players ride the lift in first; from our portal they're still in the gear-up area and the arena's
// collision isn't built yet (poi_reg "collision: N tiles were missing from built worlds" comes as
// they arrive), so the trace falls through and every add spawned under the floor (state.json
// rex_ai_in_low_high_far 1/30/0/0), filling the fight's 30-add cap. Redone from the original spots
// once the intro is over, before the first wave (spawn_adds waits 10 s after the same flag).
rex_fix_arena_spawns()
{
    level.bb_rex_until = gettime() + 90000;
    while (!bb_flag("scarab_boss_intro_done") && gettime() < level.bb_rex_until)
    {
        wait 0.1;
    }
    total = 0;
    moved = 0;
    deepest = 0;
    foreach (subclass in ["zombie_base", "zombie_base_armored_heavy", "zombie_base_armored_light"])
    {
        locs = zone_spawner::function_20c574a6ba7cc5c6(["zone_boss_arena"], subclass);
        if (!isdefined(locs))
        {
            continue;
        }
        foreach (loc in locs)
        {
            if (!isdefined(loc.origin_old) || isdefined(loc.bb_fixed))
            {
                continue;
            }
            loc.bb_fixed = 1;
            total++;
            if (loc.origin_old[2] - loc.origin[2] > deepest)
            {
                deepest = loc.origin_old[2] - loc.origin[2];
            }
            ground = getgroundposition(loc.origin_old, 16) + (0, 0, 8);
            // Still no floor under it: the designer's spot beats a point under the arena.
            if (loc.origin_old[2] - ground[2] > 200)
            {
                ground = loc.origin_old;
            }
            if (distancesquared(ground, loc.origin) > 1)
            {
                moved++;
            }
            loc.origin = ground;
        }
    }
    bb_store("rex_spawn_fix", moved + "/" + total + " moved, deepest was " + int(deepest) + " under");
}

// Rex Infernus only spawns arena adds while fewer than 30 zombies are within 1350 units (2D, any
// height) of the arena centre. Tinhorn sees none, yet ~30 stay alive all fight, so this logs where
// they are (state.json rex_*, latest sample wins): in the arena / below / above / outside it, how
// many ignore everyone or have a target, one example, and the host's position.
rex_adds_diag()
{
    boss = level.s_scarab_boss.entity;
    if (!isdefined(boss) || !isdefined(boss.var_cb0f79c5c25b23f4))
    {
        bb_store("rex_center", "none");
        return;
    }
    c = boss.var_cb0f79c5c25b23f4;
    n_in = 0;
    n_low = 0;
    n_high = 0;
    n_far = 0;
    n_ignore = 0;
    n_enemy = 0;
    sample = "-";
    host = level.players[0];
    foreach (ai in getaiarray())
    {
        if (ai == boss)
        {
            continue;
        }
        if (distance2dsquared(ai.origin, c) > 1350 * 1350)
        {
            n_far++;
        }
        else if (ai.origin[2] < c[2] - 200)
        {
            n_low++;
        }
        else if (ai.origin[2] > c[2] + 200)
        {
            n_high++;
        }
        else
        {
            n_in++;
        }
        if (isdefined(ai.ignoreall) && ai.ignoreall)
        {
            n_ignore++;
        }
        if (isdefined(ai.enemy))
        {
            n_enemy++;
        }
        if (sample == "-" && isdefined(host))
        {
            sample = txt(ai.subclass) + " " + ai.origin + " d" + int(distance(ai.origin, host.origin));
        }
    }
    bb_store("rex_center", "" + c);
    bb_store("rex_ai_in_low_high_far", n_in + "/" + n_low + "/" + n_high + "/" + n_far);
    bb_store("rex_ai_ignoreall", n_ignore);
    bb_store("rex_ai_with_enemy", n_enemy);
    bb_store("rex_ai_sample", sample);
    bb_store("rex_adds_paused", bb_flag("scarab_pause_boss_adds"));
    if (isdefined(host))
    {
        bb_store("rex_host", "" + host.origin + " ignoreme " + txt(host.ignoreme));
    }
}

bb_store_size(key, arr)
{
    if (isdefined(arr))
    {
        bb_store(key, arr.size);
    }
}

// Directed's gametype bundle stays loaded all match. The zombie scripts read from it: speed caps
// (super sprint -> sprint, sprint -> run), swapped health and damage tables, and a health multiplier.
// Cleared for the fight so it plays like standard Zombies. Old values go to state.json.
drop_directed_bundle()
{
    if (!isdefined(level.gametypebundle))
    {
        return;
    }
    bb_store("directed_speed_caps", txt(level.gametypebundle.var_25934546ad2751f3) + "/" + txt(level.gametypebundle.var_ed84de94958fe6c0));
    bb_store("directed_health_mult", txt(level.gametypebundle.var_6cfc57a4b0d987d));
    bb_store("directed_health_swaps", isdefined(level.gametypebundle.var_b608dbcf2a9c24e6));
    bb_store("directed_damage_swaps", isdefined(level.gametypebundle.var_e3501b33c18021fd));
    level.gametypebundle.var_25934546ad2751f3 = 0;
    level.gametypebundle.var_ed84de94958fe6c0 = 0;
    level.gametypebundle.var_6cfc57a4b0d987d = undefined;
    level.gametypebundle.var_b608dbcf2a9c24e6 = undefined;
    level.gametypebundle.var_e3501b33c18021fd = undefined;
}

txt(v)
{
    if (!isdefined(v))
    {
        return "-";
    }
    return "" + v;
}

// Every AI's starting health goes through this shared func (zombie_utils / zombie_init). During a
// yellow-portal fight a boss (aicategory "boss") is priced at the map's vanilla solo boss round.
boss_solo_health(bundle, round, flag)
{
    if (isdefined(round) && isdefined(self.aicategory) && self.aicategory == "boss" && round > solo_boss_round())
    {
        round = solo_boss_round();
        bb_store("boss_health_round", round);
    }
    return self [[ level.bb_health_func ]](bundle, round, flag);
}

// The round each boss file uses for one player (its function_b80976b7930587b4).
solo_boss_round()
{
    if (level.bb_map == "locust" && isdefined(level.locust_boss) && isdefined(level.locust_boss.var_40b00bc48b18b2a8))
    {
        return level.locust_boss.var_40b00bc48b18b2a8;
    }
    boss = undefined;
    if (level.bb_map == "mantis") boss = level.s_dark_heart;
    if (level.bb_map == "scarab") boss = level.s_scarab_boss;
    if (level.bb_map == "hornet") boss = level.s_hornet_boss;
    if (isdefined(boss) && isdefined(boss.var_6b7fb2da3cdf5121))
    {
        return boss.var_6b7fb2da3cdf5121;
    }
    return 25;  // firefly and ruby hardcode 25 for one player
}

// Announces the kill time and keeps the best one in kronos\boss_battle_times\times.json.
record_time(ms)
{
    // Best/last kept per map, boss round and tuning (key from load_best).
    msg = "^3Round " + level.bb_fight_round + " boss down in ^7" + fmt_time(ms);
    if (level.bb_best_ms <= 0 || ms < level.bb_best_ms)
    {
        msg = msg + "  ^2NEW BEST";
        nengine_store_set("boss_battle_times", "best_ms_" + level.bb_time_key, ms);
        level.bb_best_ms = ms;
        show_best();
    }
    else
    {
        msg = msg + "  ^3Best ^7" + fmt_time(level.bb_best_ms);
    }
    nengine_store_set("boss_battle_times", "last_ms_" + level.bb_time_key, ms);
    nengine_store_save("boss_battle_times", "times");
    foreach (player in level.players)
    {
        player iprintlnbold(msg);
    }
}

// m:ss.t
fmt_time(ms)
{
    s = int(ms / 1000);
    text = int(s / 60) + ":";
    if (s % 60 < 10)
    {
        text = text + "0";
    }
    return text + (s % 60) + "." + (int(ms / 100) % 10);
}

bb_store(key, value)
{
    nengine_store_set("boss_battle", key, value);
    nengine_store_save("boss_battle", "state");
}
