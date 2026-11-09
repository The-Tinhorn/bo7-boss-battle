#using script_4478f81b31480314;  // bgb_machine (GobbleGum machine)
#using script_aa3bac81ad4fc8e;   // bgb (GobbleGum slots; every bgb:: caller in the dump includes it)
#using scripts\common\callbacks;
#using scripts\common\trace;
#using scripts\common\utility;
#using scripts\common\weapon;
#using scripts\mp\ammomods\ammo_mod;
#using scripts\mp\armor;
#using scripts\mp\arsenal;
#using scripts\mp\common\perks\perkpackage;
#using scripts\mp\common\perks\zombie\zombie_perks;
#using scripts\mp\crafting_table;
#using scripts\mp\currency;
#using scripts\mp\common\utility\loot;
#using scripts\mp\common\utility\musicbank_utility;
#using scripts\mp\electric_power_switch;
#using scripts\mp\equipment;
#using scripts\mp\interaction;
#using scripts\mp\magicbox;
#using scripts\mp\loot\common_item;
#using scripts\mp\loot\common_item_weapon;
#using scripts\mp\pack_a_punch;
#using scripts\mp\perk_machines;
#using scripts\mp\supers;
#using scripts\mp\wallbuy;
#using scripts\mp\wallbuy_armor;
#using scripts\mp\weaponmetadata;
#using scripts\mp\zm\zm_utility;
#using scripts\mp\zm\systems\relics\zm_relics;
#using scripts\mp\zm\systems\zm_armor;
#using scripts\mp\zm\systems\zm_exfil;
#using scripts\mp\zm\systems\zm_round_logic;
#using scripts\mp\zm\systems\zm_round_spawning;
#using scripts\mp\zm\spawners\zone_spawner;

#namespace boss_battle;

// Boss Battle for every BO7 launch map, played from the Directed tile (shown as Boss Battle).
// Spawn is a zombie-free lobby with maxed essence/salvage, PaP, Wunderfizz, a crafting table and a
// T.E.D.D. station listing every gun and wonder weapon; using a relic portal starts the map's real boss fight through its
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
    level.bb_portal_lift = 50;      // portal centre above the floor; raise or lower here
    level.bb_armor_lift = 50;       // armor chalk centre above the floor (chest height); raise or lower here
    level.bb_fight_round = 40;
    level.bb_missed = 0;            // objects that found no open spot (diagnostics)
    level.bb_weapon_rarity = 1;     // weapon station guns: 0 common, 1 uncommon (green), 2 rare, 3 epic, 4 legendary
    // Weapon portal classes, matched on the weapon name (sat_ar_wren_mp, t10_sm_p04_chuck9_mp);
    // "" catches the rest.
    level.bb_weapon_tags = ["_ar_", "_sm_", "_sh_", "_lm_", "_dm_", "_sn_", "_pi_", "_la_", "_me_", ""];
    // The last one is the wonder weapons (weapon_list).
    level.bb_weapon_class_names = ["ASSAULT RIFLES", "SMGS", "SHOTGUNS", "LMGS", "MARKSMAN", "SNIPERS", "PISTOLS", "LAUNCHERS", "MELEE", "OTHER", "WONDER WEAPONS"];
    setdvar("kronos_boss_timer", "");  // hides a timer left over from a quit match
    setdvar("kronos_boss_pb", "");
    setdvar("kronos_bb_relic_menu", "");
    setdvar("kronos_bb_weapon_menu", "");
    setdvar("kronos_bb_help", "");
    nengine_store_load("boss_battle_times", "times");
    nengine_store_load("boss_battle_gear", "gear");
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
    // No out-of-bounds damage in the gear-up area. On Rex Infernus it sits behind shut doors in zones
    // that aren't enabled, and zm_player hurts anyone outside an enabled zone every 3 s. This is the
    // switch exfil uses to turn that check off; start_fight puts it back.
    level.bb_oob_off_was = level.var_1a7d5de49b6970b1;
    level.var_1a7d5de49b6970b1 = 1;
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
        level thread rex_red_pedestals();
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
    // anyone lands in a wall. Field counter: this VM loses locals across loops.
    level.bb_rl_i = 0;
    while (level.bb_rl_i < level.players.size)
    {
        level.players[level.bb_rl_i] setorigin(level.bb_spawn_origin + anglestoright(level.bb_spawn_angles) * (level.bb_rl_i * 40));
        level.players[level.bb_rl_i] setplayerangles(level.bb_spawn_angles);
        level.bb_rl_i++;
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
// wallbuy to the right, Aether Tools to the left. A waitframe between objects spreads the
// search out; everything that crosses a wait lives on level.
spawn_lobby()
{
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

    spawn_aether_tools();

    // Relic-trial portals, spawned the way the relic system does (spawn, wait a frame, set the vfx
    // part). Each portal gets a Use prompt that starts its fight.
    level.bb_portals = [];
    level.bb_portal_hinted = [];
    level.bb_portal_uses = [];
    level.bb_pi = 0;
    while (level.bb_pi < level.bb_portal_spots.size)
    {
        level.bb_portal_hinted[level.bb_pi] = 0;
        level.bb_portal_mid = portal_mid(level.bb_portal_spots[level.bb_pi]);
        portal_relic(spawnscriptable("zm_relic_portals", level.bb_portal_mid, portal_angles(level.bb_portal_spots[level.bb_pi])), level.bb_portal_colors[level.bb_pi]);
        // No hint string: the one localized-string literal tried here (&"shared_hintstrings/...")
        // came with a client loading-screen hang on Mantis (2026-11-05). portal_watch's label says USE.
        portal_use_keep(interaction::register_interact(level.bb_portal_mid, 80, &portal_used));
        level.bb_pi++;
    }
    bb_store("portal_uses", level.bb_portal_uses.size);
    bb_store("portal", "" + level.bb_portal_spots[0]);
    bb_store("open_spots_missed", level.bb_missed);
    level thread portal_watch();
    // Last and on its own thread: it pokes game wallbuy internals, so a failure there can't stop
    // the portal or anything else from spawning.
    level thread spawn_armor_wallbuys();
    level thread spawn_arsenal_and_gum();
    level thread spawn_relic_altar();
    level thread spawn_weapon_portal();
    level thread regear_watch();
    help_show();
}

// Kowakujo's PaP quest hides every machine in the PaP list when round logic begins
// (zm_sat_hornet_pap_quest::pap_machine_setup, which sets flag "pap_setup" when done), ours too if
// it's already listed, so there ours waits for that first (20 s cap). Own thread: nothing else waits.
// Astra does the same (zm_sat_ruby_quest_pap::setup_pap_machine) right after flag "begin_round_logic"
// with no done flag, so there ours waits for that flag plus a second for the hide to run.
spawn_lobby_pap()
{
    level.bb_pap_wait = gettime() + 20000;
    while (level.bb_map == "hornet" && !bb_flag("pap_setup") && gettime() < level.bb_pap_wait)
    {
        wait 0.5;
    }
    while (level.bb_map == "ruby" && !bb_flag("begin_round_logic") && gettime() < level.bb_pap_wait)
    {
        wait 0.5;
    }
    if (level.bb_map == "ruby")
    {
        wait 1;
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
    first = menu_first(level.bb_relic_i, level.bb_relic_keys.size);
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
    level.bb_relic_pos = portal_mid(level.bb_spot);
    level.bb_relic_i = 0;
    relic_altar_keep(spawnscriptable("zm_relic_portals", level.bb_relic_pos, portal_angles(level.bb_spot)));
    level.bb_relic_use = interaction::register_interact(level.bb_relic_pos, 70, &relic_used, &relic_hint);
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

// First row of a nine-row menu window around the cursor.
menu_first(i, size)
{
    first = i - 4;
    if (first > size - 9)
    {
        first = size - 9;
    }
    if (first < 0)
    {
        first = 0;
    }
    return first;
}

// ---- Weapon station -----------------------------------------------------------------------
// A T.E.D.D. task station off to the side of the gear-up area lists every gun in
// level.weaponmetadata (the mode's weapon table; Kronos adds the BO6 guns to it), grouped by
// class, in a menu like the relic one, with the wonder weapons first. Guns come at
// level.bb_weapon_rarity (green). Use: next gun. Crouch + Use: take it. Prone + Use: next class.
// The gun comes as the player's own zombie build when they have one equipped for it:
// weaponmetadata::function_c68204eff69ed046 is the lookup wallbuys and the box use, and it reads
// self.favoriteweapons, where Kronos's zm_bo6_builds also puts the BO6 zombie builds.
spawn_weapon_portal()
{
    wait 3;  // spawn_lobby's other objects have their spots by now
    place(120, 360, 64, 200);
    level.bb_weapon_pos = floor_spot(level.bb_spot);
    // Faces the gear-up area; if the screen shows its back, add 180 to the yaw here.
    level.bb_weapon_angles = face_spawn(level.bb_spot);
    // The T.E.D.D. task station model: the gametype's, the first source tedd_tasks::function_11956b77accdefca
    // picks. Only the object; the station's own prompt and trial logic aren't set up.
    level.bb_weapon_portal = spawn("script_model", level.bb_weapon_pos);
    level.bb_weapon_portal.angles = level.bb_weapon_angles;
    if (isdefined(level.gametypebundle.var_491e3a85ef39e784))
    {
        level.bb_weapon_portal setmodel(level.gametypebundle.var_491e3a85ef39e784);
    }
    bb_store("weapon_station", isdefined(level.gametypebundle.var_491e3a85ef39e784));
    // Where the station's own prompt sits (tedd_tasks: 20 in front, 55 up).
    level.bb_weapon_use = interaction::register_interact(level.bb_weapon_pos + anglestoforward(level.bb_weapon_angles) * 20 + (0, 0, 55), 70, &weapon_used);
    level.bb_weapon_i = 0;
    bb_store("weapon_portal", isdefined(level.bb_weapon_use));
    bb_store("open_spots_missed", level.bb_missed);
    while (isdefined(level.bb_lobby))
    {
        level.bb_wm_player = undefined;
        foreach (player in level.players)
        {
            if (isalive(player) && distance2dsquared(player.origin, level.bb_weapon_pos) < 180 * 180)
            {
                level.bb_wm_player = player;
            }
        }
        if (isdefined(level.bb_wm_player))
        {
            weapon_menu_show();
        }
        else if (getdvar("kronos_bb_weapon_menu", "") != "")
        {
            setdvar("kronos_bb_weapon_menu", "");
        }
        wait 0.25;
    }
    setdvar("kronos_bb_weapon_menu", "");
}

// Built on first use, so the BO6 guns Kronos adds after load are in. Not kept while empty.
// Wonder weapons come first, listed by loot item (what the gear-up area used to drop on the floor):
// Ray Gun, Mk II, the map's own, then the Necrofluid Gauntlet, Jotunn Star, Blundergat and Nekomancer
// from other maps (those may lack effects/alt fire off their home map), plus the Sundergat. The LGM-1
// (ruby) was broken off Astra, so it's only listed on its own map.
weapon_list()
{
    if (isdefined(level.bb_weapon_refs) || !isdefined(level.weaponmetadata))
    {
        return;
    }
    names = [];
    classes = [];
    ww = ["zm_sat_item_weapon_pi_raygun", "zm_sat_item_weapon_pi_raygunmark2", "zm_sat_item_weapon_ww_" + level.bb_map];
    foreach (code in ["firefly", "locust", "mantis", "hornet"])
    {
        if (code != level.bb_map)
        {
            ww[ww.size] = "zm_sat_item_weapon_ww_" + code;
        }
    }
    ww[ww.size] = "zm_sat_item_weapon_ww_mantis_upgraded";
    foreach (item in ww)
    {
        if (isdefined(getscriptbundle("itemspawnentry:" + item)))
        {
            names[names.size] = item;
            classes[classes.size] = level.bb_weapon_tags.size;  // past the tags: "WONDER WEAPONS"
        }
    }
    for (c = 0; c < level.bb_weapon_tags.size; c++)
    {
        foreach (entry in level.weaponmetadata)
        {
            if (isdefined(entry.weapon) && !istrue(entry.iswonderweapon) && weapon_class(entry.weapon) == c)
            {
                names[names.size] = entry.weapon;
                classes[classes.size] = c;
            }
        }
    }
    bb_store("weapons", names.size);
    if (names.size > 0)
    {
        level.bb_weapon_refs = names;
        level.bb_weapon_cls = classes;
    }
}

weapon_class(name)
{
    for (i = 0; i < level.bb_weapon_tags.size; i++)
    {
        if (issubstr(name, level.bb_weapon_tags[i]))
        {
            return i;
        }
    }
    return level.bb_weapon_tags.size - 1;
}

// Use on the weapon portal (self = its interact).
weapon_used(player)
{
    weapon_list();
    if (!isdefined(level.bb_weapon_refs))
    {
        return;
    }
    if (player getstance() == "crouch")
    {
        weapon_give(player);
    }
    else if (player getstance() == "prone")
    {
        c = level.bb_weapon_cls[level.bb_weapon_i];
        for (n = 0; n < level.bb_weapon_refs.size && level.bb_weapon_cls[level.bb_weapon_i] == c; n++)
        {
            level.bb_weapon_i = (level.bb_weapon_i + 1) % level.bb_weapon_refs.size;
        }
    }
    else
    {
        level.bb_weapon_i = (level.bb_weapon_i + 1) % level.bb_weapon_refs.size;
    }
    level.bb_wm_player = player;
    weapon_menu_show();
}

// Handed over the way a wallbuy hands out a favorite: the gametype's generic weapon item carrying
// our weapon object, through the item system's own use, so a full loadout swaps out the held gun.
// Kronos loses a method call's result stored in a local (creator-live, live-proven 2026-10-29; the
// first station build lost the gun that way: weapon_given "... failed"), so every call result here
// lives on level.bb_wg_* (no waits, so one give can't interleave with another).
// state.json weapon_given = last gun and whether it was the player's build, or why it failed.
weapon_give(player)
{
    level.bb_wg_name = level.bb_weapon_refs[level.bb_weapon_i];
    if (is_ww(level.bb_weapon_i))
    {
        ww_give(player);
        return;
    }
    level.bb_wg_w = player weaponmetadata::function_c68204eff69ed046(level.bb_wg_name);
    level.bb_wg_build = isdefined(level.bb_wg_w);
    if (!level.bb_wg_build)
    {
        level.bb_wg_w = weapon::buildweapon(level.bb_wg_name);
    }
    if (!isdefined(level.bb_wg_w) || isnullweapon(level.bb_wg_w))
    {
        bb_store("weapon_given", level.bb_wg_name + " failed: no weapon built");
        return;
    }
    if (!isdefined(level.gametypebundle.var_9d7bd1394c38803a))
    {
        bb_store("weapon_given", level.bb_wg_name + " failed: no generic weapon item in this mode");
        return;
    }
    level.bb_wg_bundle = getscriptbundle(level.gametypebundle.var_9d7bd1394c38803a);
    level.bb_wg_bundle.rarity = level.bb_weapon_rarity;
    give_item(player);
    bb_store("weapon_given", level.bb_wg_name + " build " + level.bb_wg_build);
}

// A wonder weapon comes the way a wallbuy hands out a gun that isn't a favorite: the item's own
// bundle and the weapon it builds (item_weapon::function_477bf1207c6672a5).
ww_give(player)
{
    level.bb_wg_bundle = getscriptbundle("itemspawnentry:" + level.bb_wg_name);
    level.bb_wg_w = item_weapon::function_477bf1207c6672a5(level.bb_wg_bundle);
    if (!isdefined(level.bb_wg_w) || isnullweapon(level.bb_wg_w))
    {
        bb_store("weapon_given", level.bb_wg_name + " failed: no weapon built");
        return;
    }
    // On Paradox the Sundergat item builds a plain Blundergat (2026-11-07 log: "sat_ww_mantis_zm pap 0
    // att sat_zm_ww_mantis sat_rec_ww_mantis"), so it gets the parts the game's own upgrade swaps
    // (weap_ww_mantis::function_b63980f0807dbada, PaP 0 branch) before the give.
    if (level.bb_map == "mantis" && level.bb_wg_name == "zm_sat_item_weapon_ww_mantis_upgraded")
    {
        level.bb_wg_w = level.bb_wg_w withattachment("sat_bar_ww_mantis");
        level.bb_wg_w = level.bb_wg_w withoutattachment("sat_rec_ww_mantis");
        level.bb_wg_w = level.bb_wg_w withattachment("sat_rec_ww_mantis2");
    }
    give_item(player);
    bb_store("weapon_given", level.bb_wg_name);
}

is_ww(i)
{
    return level.bb_weapon_cls[i] == level.bb_weapon_tags.size;
}

// Gives level.bb_wg_w through level.bb_wg_bundle, as the wallbuy builds its fake item.
give_item(player)
{
    level.bb_wg_item = spawnstruct();
    level.bb_wg_item.weaponobj = level.bb_wg_w;
    level.bb_wg_item.count = item_count(level.bb_wg_w, weaponclipsize(level.bb_wg_w));
    level.bb_wg_item.weaponstockammo = utility::get_max_stock_ammo(level.bb_wg_w);
    level.bb_wg_item.pickup_source = #"wallbuy";
    player loadweaponsforplayer([level.bb_wg_w]);
    player common_item::function_3f39e7be347cf7e1(level.bb_wg_bundle, level.bb_wg_item);
}

item_count(w, clip)
{
    if (w.isdualwield)
    {
        return common_item::function_598dd39282efb544(clip, clip);
    }
    if (w.hasalternate)
    {
        return common_item::function_598dd39282efb544(clip, undefined, weaponclipsize(w getaltweapon()));
    }
    return common_item::function_598dd39282efb544(clip);
}

// kronos_bb_weapon_menu, same line format as the relic menu: w gun, x cursor, v gun the nearest
// player has a zombie build for, y cursor on one, i wonder weapon, j cursor on one. Names go out raw
// (wonder weapons as their item name minus zm_sat_item_weapon_); the Lua shows display names.
weapon_menu_show()
{
    weapon_list();
    if (!isdefined(level.bb_weapon_refs))
    {
        setdvar("kronos_bb_weapon_menu", "hWEAPONS   NONE FOUND YET");
        return;
    }
    i = level.bb_weapon_i;
    text = "hWEAPONS   " + level.bb_weapon_class_names[level.bb_weapon_cls[i]] + "   (" + (i + 1) + "/" + level.bb_weapon_refs.size + ")";
    first = menu_first(i, level.bb_weapon_refs.size);
    for (k = first; k < first + 9 && k < level.bb_weapon_refs.size; k++)
    {
        if (is_ww(k))
        {
            code = "i";
            if (k == i)
            {
                code = "j";
            }
            text = text + "|" + code + getsubstr(level.bb_weapon_refs[k], 19);  // past "zm_sat_item_weapon_"
            continue;
        }
        code = "w";
        if (has_build(level.bb_wm_player, level.bb_weapon_refs[k]))
        {
            code = "v";
        }
        if (k == i)
        {
            if (code == "v")
            {
                code = "y";
            }
            else
            {
                code = "x";
            }
        }
        text = text + "|" + code + level.bb_weapon_refs[k];
    }
    setdvar("kronos_bb_weapon_menu", text + "|fUSE: NEXT     CROUCH + USE: TAKE|fPRONE + USE: NEXT CLASS");
}

has_build(player, name)
{
    return isdefined(player) && isdefined(player.favoriteweapons) && isdefined(player.favoriteweapons[name]);
}

// ---- Re-gear ----------------------------------------------------------------------------------
// At fight start each player's guns (full weapon name with attachments and camo, PaP level, rarity,
// ammo mod), perks, lethal, tactical, field upgrade, armor (carrier level, plates, gold) and the three
// GobbleGum slots go to kronos\boss_battle_gear\gear.json, keyed "p<entity number>_". In a later lobby,
// holding AIM + MELEE for a second puts it all back, the way zm_save::restore_player_state rebuilds a
// saved player. Kronos loses a method call's result stored in a local (creator-live 2026-10-29; the
// first version saved 0 guns and no perks that way), so every call result here lives on self.bb_g_*
// / level.bb_g_* or is passed straight on as an argument; loops are while loops over those fields.
gear_save()
{
    foreach (player in level.players)
    {
        player gear_save_one("p" + player getentitynumber() + "_");
    }
    nengine_store_save("boss_battle_gear", "gear");
}

// self.bb_g_ws = guns in the two primary slots plus Mule Kick's third (the slots zm_save saves).
gear_weapons()
{
    self.bb_g_ws = [];
    self.bb_g_w = self item_weapon::function_e7484276ad85f220(#"primary_0");
    self gear_keep();
    self.bb_g_w = self item_weapon::function_e7484276ad85f220(#"primary_1");
    self gear_keep();
    if (isdefined(self.var_3bf72dcd2775aa78) && self zombie_perks::has_perk("specialty_z_mod") && self hasweapon(self.var_3bf72dcd2775aa78))
    {
        self.bb_g_w = self.var_3bf72dcd2775aa78;
        self gear_keep();
    }
}

gear_keep()
{
    if (isdefined(self.bb_g_w) && !isnullweapon(self.bb_g_w))
    {
        self.bb_g_ws[self.bb_g_ws.size] = self.bb_g_w;
    }
}

gear_save_one(k)
{
    self gear_weapons();
    self.bb_g_i = 0;
    while (self.bb_g_i < self.bb_g_ws.size)
    {
        self gear_save_weapon(k + "w" + self.bb_g_i, self.bb_g_ws[self.bb_g_i]);
        self.bb_g_i = self.bb_g_i + 1;
    }
    gear_set(k + "weapons", self.bb_g_ws.size);
    gear_set(k + "perks", self gear_perks());
    gear_set(k + "lethal", self equipment_mp::getcurrentequipment("primary"));
    gear_set(k + "lethal_ammo", self equipment_mp::getequipmentslotammo("primary"));
    gear_set(k + "tactical", self equipment_mp::getcurrentequipment("secondary"));
    gear_set(k + "tactical_ammo", self equipment_mp::getequipmentslotammo("secondary"));
    gear_set(k + "super", self supers_mp::getcurrentsuperref());
    gear_set(k + "armor_level", self.platecarrierlevel);
    gear_set(k + "armor_plates", self armor::function_22290101992e4874());
    gear_set(k + "armor_gold", istrue(self.var_a1faa64d8c07872e));
    // GobbleGum action slots 1-3 (zm_save reads the same array).
    if (isdefined(self.var_b02f6e7abbbc8a84))
    {
        gear_set(k + "gum1", self.var_b02f6e7abbbc8a84[1]);
        gear_set(k + "gum2", self.var_b02f6e7abbbc8a84[2]);
        gear_set(k + "gum3", self.var_b02f6e7abbbc8a84[3]);
    }
    gear_set(k + "saved", 1);
    bb_store("gear_saved", self.bb_g_ws.size + " guns, perks " + self gear_perks());
}

gear_save_weapon(p, w)
{
    gear_set(p, getcompleteweaponname(w));
    gear_set(p + "_pap", self pack_a_punch::get_pap_level(w));
    gear_set(p + "_rarity", self item_weapon::function_fb81bd2fe070faa6(w));
    gear_set(p + "_mod", self ammo_mod::get_ammo_mod_name(w));
}

// Active perks as one space-separated string.
gear_perks()
{
    self.bb_g_perks = "";
    if (!isdefined(self.perks_active))
    {
        return self.bb_g_perks;
    }
    self.bb_g_list = self zombie_perks::get_active_perks_str_array();
    self.bb_g_j = 0;
    while (self.bb_g_j < self.bb_g_list.size)
    {
        self.bb_g_perks = self.bb_g_perks + self.bb_g_list[self.bb_g_j] + " ";
        self.bb_g_j = self.bb_g_j + 1;
    }
    return self.bb_g_perks;
}

gear_set(key, value)
{
    if (!isdefined(value))
    {
        value = "";
    }
    nengine_store_set("boss_battle_gear", key, value);
}

gear_get(key)
{
    level.bb_g_v = nengine_store_get("boss_battle_gear", key);
    if (!isdefined(level.bb_g_v))
    {
        return "";
    }
    return "" + level.bb_g_v;
}

gear_int(key)
{
    if (gear_get(key) == "")
    {
        return 0;
    }
    return int(gear_get(key));
}

// Lobby only: AIM + MELEE held for a second (10 checks, 0.1 s apart) re-gears that player.
regear_watch()
{
    while (isdefined(level.bb_lobby))
    {
        foreach (player in level.players)
        {
            if (!isdefined(player.bb_rg_hold) || !isalive(player) || isdefined(player.bb_rg_busy) || !player adsbuttonpressed() || !player meleebuttonpressed())
            {
                player.bb_rg_hold = 0;
            }
            else
            {
                player.bb_rg_hold = player.bb_rg_hold + 1;
            }
            if (player.bb_rg_hold >= 10)
            {
                player.bb_rg_hold = 0;
                player thread regear();
            }
        }
        wait 0.1;
    }
}

// self = the player. The saved guns stream in first (a give without it froze the game for seconds
// in the 2026-11-07 Sundergat test), then gear_apply swaps everything over in one go.
regear()
{
    self.bb_rg_busy = 1;
    self.bb_rg_k = "p" + self getentitynumber() + "_";
    if (gear_int(self.bb_rg_k + "saved") == 0)
    {
        self iprintlnbold("^3No loadout saved yet: it's saved when a boss fight starts");
        self.bb_rg_busy = undefined;
        return;
    }
    self iprintlnbold("^2Re-gearing: last run's loadout and perks");
    self gear_built(self.bb_rg_k);
    self.bb_rg_t = gettime();
    self loadweaponsforplayer(self.bb_g_ws, 1);
    waitframe();
    while (!self hasloadedviewweapons(self.bb_g_ws) && gettime() - self.bb_rg_t < 10000)
    {
        waitframe();
    }
    if (isdefined(level.bb_lobby) && isalive(self))
    {
        self gear_apply(self.bb_rg_k);
    }
    wait 1;  // so one long hold can't run it twice
    self.bb_rg_busy = undefined;
}

// self.bb_g_ws = the saved guns that still build.
gear_built(k)
{
    self.bb_g_ws = [];
    self.bb_g_i = 0;
    while (self.bb_g_i < gear_int(k + "weapons"))
    {
        self.bb_g_w = gear_weapon(k + "w" + self.bb_g_i);
        self gear_keep();
        self.bb_g_i = self.bb_g_i + 1;
    }
}

gear_weapon(key)
{
    if (gear_get(key) == "")
    {
        return undefined;
    }
    level.bb_g_mw = makeweaponfromstring(gear_get(key));
    if (!isdefined(level.bb_g_mw) || isnullweapon(level.bb_g_mw))
    {
        return undefined;
    }
    return level.bb_g_mw;
}

// No waits in here. state.json regear = guns given / guns saved.
gear_apply(k)
{
    self.bb_g_list = strtok(gear_get(k + "perks"), " ");
    self.bb_g_j = 0;
    while (self.bb_g_j < self.bb_g_list.size)
    {
        if (!self zombie_perks::has_perk(self.bb_g_list[self.bb_g_j]))
        {
            self zombie_perks::give_perk(self.bb_g_list[self.bb_g_j], 0);
        }
        self.bb_g_j = self.bb_g_j + 1;
    }
    self equipment_mp::clearallequipment();
    self supers_mp::clearsuper();
    self gear_weapons();
    self.bb_g_i = 0;
    while (self.bb_g_i < self.bb_g_ws.size)
    {
        self takeweapon(self.bb_g_ws[self.bb_g_i]);
        self.bb_g_i = self.bb_g_i + 1;
    }
    self.bb_g_first = undefined;
    self.bb_g_given = 0;
    self.bb_g_i = 0;
    while (self.bb_g_i < gear_int(k + "weapons"))
    {
        self.bb_g_w = gear_weapon(k + "w" + self.bb_g_i);
        if (isdefined(self.bb_g_w))
        {
            self gear_give_weapon(k + "w" + self.bb_g_i, self.bb_g_i);
        }
        self.bb_g_i = self.bb_g_i + 1;
    }
    if (isdefined(self.bb_g_first))
    {
        self switchtoweaponimmediate(self.bb_g_first);
    }
    self gear_equip(k + "lethal", "primary");
    self gear_equip(k + "tactical", "secondary");
    // Field upgrade: what swapping it in the menu does (see blood_burner's zm_bb_after_save_restore),
    // which hands it over fully charged.
    if (gear_get(k + "super") != "" && gear_get(k + "super") != "none")
    {
        self perkpackage::perkpackage_giveimmediate(gear_get(k + "super"));
        self perkpackage::perkpackage_reset();
        self setclientomnvar("ui_perk_package_super1", supers_mp::getsuperid(gear_get(k + "super")));
    }
    // Armor: carrier level (zm_armor sets max armor and fills it), then the plate count, then gold.
    if (gear_int(k + "armor_level") > 0)
    {
        self zm_armor::function_fdbe2cad6d8bb7e7(gear_int(k + "armor_level"));
        self armor::function_b359444c252374fc(gear_int(k + "armor_plates"));
    }
    if (gear_int(k + "armor_gold") && !istrue(self.var_a1faa64d8c07872e))
    {
        self utility::callsharedfunc(#"zombie", #"set_golden_armor");
    }
    // GobbleGums: the slots as they were (ztron_gobblegums clears and fills them the same way).
    if (isdefined(level.bgb))
    {
        self gear_gum(1, gear_get(k + "gum1"));
        self gear_gum(2, gear_get(k + "gum2"));
        self gear_gum(3, gear_get(k + "gum3"));
    }
    bb_store("regear", self.bb_g_given + "/" + gear_int(k + "weapons"));
}

// self.bb_g_w = the gun; i = its index (2 = Mule Kick's third).
gear_give_weapon(p, i)
{
    if (!isdefined(self.bb_g_first))
    {
        self.bb_g_first = self.bb_g_w;
    }
    self giveweapon(self.bb_g_w);
    self.bb_g_index = self item_weapon::function_1464d1c9177c4934(self.bb_g_w);
    if (i == 2 && self zombie_perks::has_perk("specialty_z_mod"))
    {
        self.var_3bf72dcd2775aa78 = self.bb_g_w;
        self.var_1dbdf5cd10dc5432 = self.bb_g_index;
    }
    self setweaponammoclip(self.bb_g_w, weaponclipsize(self.bb_g_w));
    self setweaponammostock(self.bb_g_w, utility::get_max_stock_ammo(self.bb_g_w));
    self gear_fill(self.bb_g_w getaltweapon());
    // The full name already carries the PaP attachments, so PaP is only re-registered here.
    if (gear_int(p + "_pap") > 0)
    {
        self pack_a_punch::function_3f3b9cdbb4843e45(self.bb_g_w, gear_int(p + "_pap"), self.bb_g_first == self.bb_g_w);
    }
    self item_weapon::function_40e1cbd0e1f47d1a(self.bb_g_w, gear_int(p + "_rarity"), self.bb_g_first == self.bb_g_w);
    self item_weapon::function_b2eab55086e607dc(self.bb_g_w, gear_int(p + "_pap"), gear_int(p + "_rarity"));
    if (gear_get(p + "_mod") != "" && gear_get(p + "_mod") != "none")
    {
        self ammo_mod::add_ammo_mod_to_weapon(self.bb_g_w, gear_get(p + "_mod"), self.bb_g_first == self.bb_g_w);
    }
    if (isdefined(self.bb_g_index))
    {
        self item_weapon::function_55c302d95295530f(self.bb_g_w, gear_int(p + "_rarity"), self.bb_g_index);
    }
    self.bb_g_given = self.bb_g_given + 1;
}

gear_fill(w)
{
    if (!isdefined(w) || isnullweapon(w))
    {
        return;
    }
    self setweaponammoclip(w, weaponclipsize(w));
    self setweaponammostock(w, utility::get_max_stock_ammo(w));
}

gear_equip(key, slot)
{
    if (gear_get(key) != "" && gear_get(key) != "none")
    {
        self equipment_mp::giveequipment(gear_get(key), slot);
        self equipment_mp::setequipmentslotammo(slot, gear_int(key + "_ammo"));
    }
}

gear_gum(slot, ref)
{
    self bgb::take(slot);
    if (ref != "" && ref != "none")
    {
        self bgb::set_action_slot(slot, ref, 0, 0);
    }
}

// The gear-up area's controls, drawn on the left by lua/boss_battle_post.lua (same line format as
// the menus: h header, n line, f grey sub-line). Cleared when the fight starts.
help_show()
{
    text = "hBOSS BATTLE: GEAR UP";
    text = text + "|nYELLOW PORTAL: ROUND " + level.bb_portal_rounds[0] + " BOSS FIGHT";
    text = text + "|nRED PORTAL: ROUND " + level.bb_portal_rounds[1] + " BOSS FIGHT";
    text = text + "|f   USE ON A PORTAL TO START THE FIGHT";
    text = text + "|nGREEN PORTAL: CURSED RELICS";
    text = text + "|f   USE: NEXT     CROUCH + USE: ON/OFF";
    text = text + "|nT.E.D.D. STATION: GUNS + WONDER WEAPONS";
    text = text + "|f   USE: NEXT     CROUCH + USE: TAKE";
    text = text + "|f   PRONE + USE: NEXT CLASS";
    text = text + "|nRE-GEAR: LAST RUN'S LOADOUT + PERKS";
    text = text + "|f   HOLD AIM + MELEE";
    // The Fast Restart mod sets this once a player spawns.
    if (getdvar("kronos_fast_restart", "") != "")
    {
        text = text + "|nFAST RESTART: PAUSE WHILE CROUCHED";
        text = text + "|f   SAVE & QUIT BECOMES FAST RESTART";
    }
    setdvar("kronos_bb_help", text);
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
        level.bb_spot = getclosestpointonnavmesh(want, 128) ?? want;
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
    return face_point(level.bb_spawn_origin, spot);
}

// The relic portal model is authored lying flat: every map places it at pitch ~90, which stands it
// up with its face toward the yaw. Here the yaw points at the spawn, so it faces the gear-up area.
portal_angles(spot)
{
    yaw = face_spawn(spot);
    return (90, yaw[1], 0);
}

// Upright portal centre: the real floor under the nav point, plus level.bb_portal_lift.
portal_mid(spot)
{
    return floor_spot(spot) + (0, 0, level.bb_portal_lift);
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
        // Upright like a real wall chalk. A wallbuy's face points along its RIGHT vector (wallbuy.gsc
        // drops bought items at angles + (0, -90, 0)), so yaw + 90 turns the face to the spawn.
        w.origin = floor_spot(level.bb_spot) + (0, 0, level.bb_armor_lift);
        yaw = face_spawn(level.bb_spot);
        w.angles = (0, yaw[1] + 90, 0);
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

// Navmesh points can sit under the visible floor (Kowakujo's sank the armor chalk), so heights are
// measured from whatever a ray straight down hits; the navmesh height if the ray misses.
floor_spot(spot)
{
    return floor_hit(spot, trace::ray_trace(spot + (0, 0, 40), spot - (0, 0, 40)));
}

floor_hit(spot, hit)
{
    if (hit["fraction"] < 1)
    {
        return hit["position"];
    }
    return spot;
}

// Two ultra Aether Tools per player on the floor, next to the loot (Directed's Arsenal menu has no
// tier-5 row to unlock). zm_sat_item_aether_tool_5 is the last entry of zm.gsc's dev upgrade list
// (give_player_weapon_upgrades, hash 7a0163ba7eb3481), spawned the same way. state.json aether_ultra
// = tools placed (0 means the game refused the item in this mode).
spawn_aether_tools()
{
    level.bb_at_bundle = getscriptbundle("itemspawnentry:zm_sat_item_aether_tool_5");
    level.bb_at_placed = 0;
    level.bb_at_n = 0;
    while (isdefined(level.bb_at_bundle) && level.bb_at_n < level.players.size * 2)
    {
        place(-90, 90, 16, 44);
        level.bb_at_placed = level.bb_at_placed + keep_item(common_item::function_61c2c0251e742ffd(level.bb_at_bundle, 1, loot_opts(level.bb_spot)));
        level.bb_at_n = level.bb_at_n + 1;
        waitframe();
    }
    bb_store("aether_ultra", level.bb_at_placed);
}

// Same drop options as creator_live's wonder weapon gift; critical + var_fd47e835523b473f stop despawning.
loot_opts(spot)
{
    options = common_item::function_f5dfaa3bbdf99a33(spot, spot + (0, 0, 38));
    options.critical = 1;
    options.var_fd47e835523b473f = 1;
    return options;
}

// Kept so start_fight can clear what nobody picked up (Paradox Junction's arena is the spawn).
// One item or an array of them; returns how many were kept.
keep_item(item)
{
    if (!isdefined(item))
    {
        return 0;
    }
    level.bb_keep = item;
    if (!isarray(level.bb_keep))
    {
        level.bb_keep = [item];
    }
    level.bb_kept = 0;
    while (level.bb_kept < level.bb_keep.size)
    {
        level.bb_cleanup_items[level.bb_cleanup_items.size] = level.bb_keep[level.bb_kept];
        level.bb_kept = level.bb_kept + 1;
    }
    return level.bb_kept;
}

// Removes the lobby's floor loot and armor wallbuys when the fight starts. Machines stay.
clear_lobby_drops()
{
    foreach (item in level.bb_cleanup_items)
    {
        if (isdefined(item))
        {
            common_item::function_869d7676e359a627(item, 1);  // the game's own item cleanup
        }
    }
    foreach (wb in level.bb_cleanup_wb)
    {
        if (isdefined(wb))
        {
            wb notify(#"death");  // same removal as the start room script's wallbuys
            wb freescriptable();
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
    }
    if (isdefined(level.bb_relic_altar))
    {
        level.bb_relic_altar freescriptable();
    }
    if (isdefined(level.bb_relic_use))
    {
        level.bb_relic_use delete();
    }
    if (isdefined(level.bb_weapon_portal))
    {
        level.bb_weapon_portal delete();
    }
    if (isdefined(level.bb_weapon_use))
    {
        level.bb_weapon_use delete();
    }
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

portal_use_keep(use)
{
    if (!isdefined(use))
    {
        return;
    }
    use.bb_round = level.bb_portal_rounds[level.bb_pi];
    level.bb_portal_uses[level.bb_portal_uses.size] = use;
}

// Use on a yellow/red portal (self = its interact): start that portal's fight.
portal_used(player)
{
    level.bb_fight_round = self.bb_round;
    level thread start_fight();
}

portal_watch()
{
    while (isdefined(level.bb_lobby))
    {
        foreach (i, spot in level.bb_portal_spots)
        {
            near_any = 0;
            foreach (player in level.players)
            {
                if (!isalive(player) || abs(player.origin[2] - spot[2]) >= 100)
                {
                    continue;
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
                    player iprintlnbold(level.bb_portal_codes[i] + "Round " + level.bb_portal_rounds[i] + " ^7boss fight - press USE");
                }
            }
            level.bb_portal_hinted[i] = near_any;
        }
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
    setdvar("kronos_bb_help", "");
    level thread gear_save();  // what everyone takes into this fight, for re-gear next run; own thread so it can't block the fight
    level.var_1a7d5de49b6970b1 = level.bb_oob_off_was;
    zm_round_spawning::pause_round_spawning(0, "boss_battle_lobby");
    // The boss files mute round_start / round_end music for the fight, but past round 10 a round
    // change plays round_start_short / round_end_short instead (zm_music), so the quick start's
    // change to round 40 / 100 played round music over the start of the fight. Rex Infernus at round
    // 100 still had round music over the fight with no boss music (2026-11-09), so the rest of
    // zm_music's round cues go too: round_start_first (round 1), specialround_loop (a looping track
    // the round never ends to stop when the round is a special one) and hash_638ae84b7500610c (round
    // end under a mode modifier). A muted cue (musicbank disabled_events) never plays.
    foreach (cue in [#"round_start", #"round_end", #"round_start_short", #"round_end_short", #"round_start_first", #"specialround_loop", #"hash_638ae84b7500610c"])
    {
        musicbank_utility::function_683e33ddcb824d18(cue);
        musicbank_utility::function_4f253fd35ec68cbc(level.players, cue);
    }
    foreach (portal in level.bb_portals)
    {
        if (isdefined(portal))
        {
            portal freescriptable();
        }
    }
    foreach (use in level.bb_portal_uses)
    {
        if (isdefined(use))
        {
            use delete();
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
    // A special round also sets the special-round sound state (zm_music special_round_start_music);
    // clear it as zm_music's own round end does, so it can't sit over the boss music.
    bb_store("special_round", istrue(level.var_6c65aec37d0dcb9d));
    if (istrue(level.var_6c65aec37d0dcb9d))
    {
        function_398bc9ee922d91fd("sndSpecialRound", 0);
        level.var_6c65aec37d0dcb9d = 0;
    }
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

// Rex Infernus: every grapple pedestal hands out the red (upgraded) hook, as if the main quest's eye
// sat in each one. Placing the eye only sets these four fields on its pedestal (zm_sat_scarab_mq
// function_660c7a8837bf677d); zm_ncfdpedestal::give_grappling_hook then gives
// equip_grappling_hook_upgraded. state.json "red_pedestals" = how many were changed.
rex_red_pedestals()
{
    level.bb_pedestal_until = gettime() + 60000;
    while (!bb_flag("ncfds_spawned") && gettime() < level.bb_pedestal_until)
    {
        wait 0.5;
    }
    if (!isdefined(level.ncfd_pedestals))
    {
        bb_store("red_pedestals", "none");
        return;
    }
    foreach (pedestal in level.ncfd_pedestals)
    {
        pedestal.var_c62a3e81dd2e88bd = 1;
        pedestal.interact.var_c62a3e81dd2e88bd = 1;
        pedestal.vfx.var_c62a3e81dd2e88bd = 1;
        pedestal.vfx_off.var_c62a3e81dd2e88bd = 1;
    }
    bb_store("red_pedestals", level.ncfd_pedestals.size);
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
    // Call results stay on level, not in locals (the Kronos quirk; the old counters here came out undefined).
    foreach (subclass in ["zombie_base", "zombie_base_armored_heavy", "zombie_base_armored_light"])
    {
        level.bb_rx_locs = zone_spawner::function_20c574a6ba7cc5c6(["zone_boss_arena"], subclass);
        if (isdefined(level.bb_rx_locs))
        {
            foreach (loc in level.bb_rx_locs)
            {
                if (isdefined(loc.origin_old) && !isdefined(loc.bb_fixed))
                {
                    loc.bb_fixed = 1;
                    loc.origin = rex_ground(loc.origin_old);
                }
            }
        }
    }
    bb_store("rex_spawn_fix", "ran");
}

// The floor under a spawn's original spot, or the spot itself when the floor found is over 200 under
// it (still no floor there: the designer's spot beats a point under the arena).
rex_ground(spot)
{
    if (spot[2] - getgroundposition(spot, 16)[2] > 200)
    {
        return spot;
    }
    return getgroundposition(spot, 16) + (0, 0, 8);
}

// Directed's gametype bundle stays loaded all match. The zombie scripts read from it: speed caps
// (super sprint -> sprint, sprint -> run), swapped health and damage tables, and a health multiplier.
// Cleared for the fight so it plays like standard Zombies.
drop_directed_bundle()
{
    if (!isdefined(level.gametypebundle))
    {
        return;
    }
    level.gametypebundle.var_25934546ad2751f3 = 0;
    level.gametypebundle.var_ed84de94958fe6c0 = 0;
    level.gametypebundle.var_6cfc57a4b0d987d = undefined;
    level.gametypebundle.var_b608dbcf2a9c24e6 = undefined;
    level.gametypebundle.var_e3501b33c18021fd = undefined;
}

// Every AI's starting health goes through this shared func (zombie_utils / zombie_init). During a
// yellow-portal fight a boss (aicategory "boss") is priced at the map's vanilla solo boss round.
boss_solo_health(bundle, round, flag)
{
    // zombie_init prices a new AI's health (zombie_init.gsc line 226) before it copies aicategory onto
    // it (line 298), so at spawn only the settings bundle it set at line 67 knows it's a boss.
    cat = self.aicategory;
    if (!isdefined(cat) && isdefined(self.var_d6894f01a36b4ff3))
    {
        cat = self.var_d6894f01a36b4ff3.aicategory;
    }
    if (isdefined(round) && isdefined(cat) && cat == "boss" && round > solo_boss_round())
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
