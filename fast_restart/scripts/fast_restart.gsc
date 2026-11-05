#using scripts\common\callbacks;

#namespace fast_restart;

// Fast Restart, like the old CoDs' pause menu option. The pause menu has one slot for it (Save &
// Quit), so the host's stance picks which one it is: crouched or prone = Fast Restart, standing =
// normal Save & Quit. kronos_fast_restart: "" no match, "-" standing, "0" crouched (Fast Restart).
// GSC is paused with the menu open, so the value stays as it was when the menu opened, which is
// the same value lua/fast_restart_post.lua uses for both the label and the press. Pressing Fast
// Restart sets "1" and closes the menu (unpausing), and this restarts the match fresh:
// map_restart(0) drops the persistent game[] state (zm gamelogic's own restart() uses 1).
// Kronos style (level.* fields, while loops): this VM loses locals across loops.
// Diagnostics: kronos\fast_restart\state.json.

autoexec fr_init()
{
    // Disarmed until a player spawns, so a value left by an earlier match never carries over.
    setdvar("kronos_fast_restart", "");
    level callback::add(#"player_spawned", &fr_spawned);
}

fr_spawned(params)
{
    if (isdefined(level.fr_armed))
    {
        return;
    }
    level.fr_armed = 1;
    level thread fr_watch();
}

fr_watch()
{
    setdvar("kronos_fast_restart", "-");
    fr_store("running", getdvar("g_mapname", ""));
    while (getdvar("kronos_fast_restart", "") != "1")
    {
        level.fr_want = "-";
        level.fr_i = 0;
        while (level.fr_i < level.players.size)
        {
            if (level.players[level.fr_i] ishost() && level.players[level.fr_i] getstance() != "stand")
            {
                level.fr_want = "0";
            }
            level.fr_i = level.fr_i + 1;
        }
        if (level.fr_want != getdvar("kronos_fast_restart", ""))
        {
            setdvar("kronos_fast_restart", level.fr_want);
            fr_store("armed", level.fr_want == "0");
        }
        wait 0.25;
    }
    setdvar("kronos_fast_restart", "");
    fr_store("restart", gettime());
    if (isdefined(level.onmaprestart))
    {
        [[ level.onmaprestart ]]();
    }
    level notify(#"restarting");
    map_restart(0);
}

fr_store(key, value)
{
    nengine_store_set("fast_restart", key, value);
    nengine_store_save("fast_restart", "state");
}
