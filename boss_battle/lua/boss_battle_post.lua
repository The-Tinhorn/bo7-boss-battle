-- Boss Battle UI.
-- 1. Shows the Directed mode as "Boss Battle". The mod's GSC only runs in Directed matches, so
--    picking that tile starts Boss Battle; Standard and Starting Room stay vanilla. Wraps every
--    setText the UI's element classes expose (how Kronos's own menus label tiles). The tile's text carries invisible characters around the word, so the
--    word is replaced inside the string rather than matched whole. Challenge names
--    ("<map> Directed Completion") are left alone.
-- 2. Draws the boss fight timer in the top-right corner from the kronos_boss_timer dvar, which
--    scripts/boss_battle.gsc sets during the fight. Digits come from the BO3 HUD kit's glyphs.
--    The relic and weapon station menus (screen centre, under the crosshair) and the gear-up help
--    (left side) are drawn the same way.
do
  local function log(s) pcall(function() KRONOS.log("boss battle: " .. tostring(s)) end) end

  -- Replaces the Directed description in the Kronos mode menu (LUIFPSCounter.lua's DESC table).
  local BOSS_DESC = "Boss Battle mode just like Infinite Warfare. Gear up area should have everything you need. "
    .. "YELLOW portal is standard. RED is the round 100 variant. GREEN is cursed(relics broken atm). "
    .. "SUBSCRIBE TO TINHORN :)"

  local function relabel(text)
    if type(text) ~= "string" then return text end
    if string.find(text, "Completion", 1, true) then return text end
    if string.find(text, "A guided main-quest experience", 1, true) then return BOSS_DESC end
    -- The boss fights' own quick starts call zm_utility::open_sesame(), which prints this; the
    -- power switch prints the second one when Boss Battle turns the power on.
    if string.find(text, "OPEN SESAME", 1, true) or string.find(text, "POWER CAN ONLY TURN ON ONCE", 1, true) then
      return ""
    end
    if string.find(text, "Directed", 1, true) then
      return (string.gsub(text, "Directed", "Boss Battle"))
    end
    if string.find(text, "DIRECTED", 1, true) then
      return (string.gsub(text, "DIRECTED", "BOSS BATTLE"))
    end
    return text
  end
  local clua = rawget(_G, "CLUA")
  local done = {}
  local function wrap(owner, k)
    local original = type(owner) == "table" and rawget(owner, k)
    if type(original) ~= "function" or done[original] then return 0 end
    local replacement = function(self, text, ...) return original(self, relabel(text), ...) end
    done[replacement] = true
    rawset(owner, k, replacement)
    return 1
  end
  local set_hooks = 0
  local lui = rawget(_G, "LUI")
  if type(lui) == "table" then
    local classes = { lui }
    pcall(function() for _, v in pairs(lui) do if type(v) == "table" then classes[#classes + 1] = v end end end)
    for _, class in ipairs(classes) do
      for _, name in ipairs({ "setText", "SetText" }) do
        set_hooks = set_hooks + wrap(class, name)
      end
    end
  end
  log("relabel hooks setText=" .. set_hooks)

  -- Fight timer.
  local HD = rawget(_G, "xhashdvar") or rawget(_G, "PushXHashDvar") or (type(clua) == "table" and clua.PushXHashDvar)
  local function dvar_text(name)
    local ok, v = pcall(function() return rawget(_G, "Dvar").GetDvarString(HD(name)) end)
    if ok and type(v) == "string" then return v end
    return ""
  end
  -- The BO3 HUD kit, or nil plus the reason.
  local function hud_kit()
    local ok, kit = pcall(KRONOS.require, "bo3_hud")
    if ok and type(kit) == "table" and type(kit.textRow) == "function" then return kit end
    return nil, kit
  end
  local function in_frontend()
    local ok, v = pcall(function() return Engine[KRONOS.H("InFrontend")]() end)
    return ok and v == true
  end
  local ok_root, root = pcall(function()
    local r = LUI.UIElement.new()
    -- Anchored to the top-right corner: a 504x100 box, 24 px in from the right, 96 px down
    -- (timer on top, personal best under it).
    r:SetAnchorsAndPosition(1, 0, 0, 1, -528, -24, 96, 196)
    LUI.GetRoot():addElement(r)
    return r
  end)
  if not ok_root or not root then
    log("timer: no root " .. tostring(root))
    return
  end
  -- Relic menu from the kronos_bb_relic_menu dvar: "|"-separated lines, each led by a code letter
  -- (h header, f footer, n relic, o relic on, c cursor, b cursor on a relic that's on).
  -- The weapon station's kronos_bb_weapon_menu uses w gun, v gun with the player's zombie build,
  -- x cursor, y cursor on a gun with a build, i wonder weapon, j cursor on one.
  -- The help panel (kronos_bb_help) uses h, n (plain line) and f.
  local function rgb(r, g, b) return r * 65536 + g * 256 + b end
  local MENU_STYLE = {
    h = rgb(245, 200, 80), f = rgb(170, 170, 170), n = rgb(235, 235, 235),
    o = rgb(110, 235, 120), c = rgb(255, 230, 90), b = rgb(150, 255, 130),
  }
  MENU_STYLE.w, MENU_STYLE.v, MENU_STYLE.x, MENU_STYLE.y = MENU_STYLE.n, MENU_STYLE.o, MENU_STYLE.c, MENU_STYLE.b
  MENU_STYLE.i, MENU_STYLE.j = MENU_STYLE.n, MENU_STYLE.c
  local function pretty(name)
    name = string.gsub(name, "^zm_", "")
    name = string.gsub(name, "^relic_", "")
    name = string.gsub(name, "_", " ")
    return string.upper(name)
  end
  -- GSC sends loot names (sat_zm_firefly_xi_relic). The display name is the "name" field of the
  -- relic's script bundle "relic:<loot name>" (what the altar's hint card shows), localized.
  -- Keys are fnv1a64 hashes, as Kronos's LUIFPSCounter.lua uses them: getscriptbundle, name, localize.
  -- Localized text in caps, or nil for empty or an unresolved "FILE/KEY".
  local function shown_text(t)
    if type(t) == "string" and t ~= "" and not string.find(t, "^[%w_]+/[%w_]+$") then
      return string.upper((string.gsub(t, "%^%d", "")))
    end
  end
  local relic_names = {}
  local function relic_name(loot)
    if relic_names[loot] then return relic_names[loot] end
    local name
    pcall(function()
      local bundle = Engine[KRONOS.H("f06093d047200548")](clua.PushXHashAsset("relic:" .. loot))
      local raw = bundle[KRONOS.H("c4bcadba8e631b86")]
      local ok, text = pcall(Engine[KRONOS.H("aed84c33ec5f01ea")], raw)
      name = shown_text(ok and text) or shown_text(raw)
    end)
    relic_names[loot] = name or pretty(loot)
    return relic_names[loot]
  end
  -- GSC sends weapon asset names (sat_ar_falcon_mp). Display name, first that works:
  -- 1. the weapon's script bundle (Kronos's BO6 name lookup: getscriptbundle of the kind-3 prefix
  --    hash 31705bf9ed477170 .. root, its "name" field, localized; the same calls relic_name uses),
  -- 2. WEAPON.GetName(root) (gives "X9 Maverick" in the front end),
  -- 3. the prettified code name.
  local weapon_names = {}
  local function weapon_name(asset)
    if weapon_names[asset] then return weapon_names[asset] end
    local root = string.gsub(asset, "_mp$", "")
    local name
    pcall(function()
      local bundle = Engine[KRONOS.H("f06093d047200548")](KRONOS.H("31705bf9ed477170", 3) .. root)
      local raw = bundle[KRONOS.H("c4bcadba8e631b86")]
      local ok, text = pcall(Engine[KRONOS.H("aed84c33ec5f01ea")], raw)
      name = shown_text(ok and text) or shown_text(raw)
    end)
    if not name then
      pcall(function() name = shown_text(rawget(_G, "WEAPON")[KRONOS.H("9ae1e225e2dd2df4")](root)) end)
    end
    weapon_names[asset] = name or pretty((string.gsub(root, "^%w-_", "")))
    return weapon_names[asset]
  end
  -- Wonder weapons come as their loot item name minus zm_sat_item_weapon_.
  local WW_NAMES = {
    pi_raygun = "RAY GUN", pi_raygunmark2 = "RAY GUN MARK II", ww_firefly = "NECROFLUID GAUNTLET",
    ww_locust = "JOTUNN STAR", ww_mantis = "BLUNDERGAT", ww_mantis_upgraded = "SUNDERGAT",
    ww_hornet = "NEKOMANCER", ww_ruby = "LGM-1",
  }
  local function ww_name(item) return WW_NAMES[item] or pretty(item) end
  -- Anchors 0.5 = screen centre; the menu starts 120 px under the crosshair (move it with the 120/540).
  local function panel(la, ra, ta, ba, l, r, t, b)
    local p = { rows = {}, shown = "" }
    pcall(function()
      p.el = LUI.UIElement.new()
      p.el:SetAnchorsAndPosition(la, ra, ta, ba, l, r, t, b)
      LUI.GetRoot():addElement(p.el)
    end)
    return p
  end
  local menu = panel(0.5, 0.5, 0.5, 0.5, -270, 270, 120, 540)
  local help = panel(0, 1, 0, 1, 60, 620, 220, 640)
  local function draw_panel(p, text, kit)
    p.shown = text
    local i = 0
    for line in string.gmatch(text, "[^|]+") do
      i = i + 1
      local code, body = string.sub(line, 1, 1), string.sub(line, 2)
      if p == help then
        -- plain text: n here is a line, not a relic
      elseif code == "c" then body = "> " .. relic_name(body)
      elseif code == "b" then body = "> " .. relic_name(body) .. "   ON"
      elseif code == "o" then body = "   " .. relic_name(body) .. "   ON"
      elseif code == "n" then body = "   " .. relic_name(body)
      elseif code == "x" then body = "> " .. weapon_name(body)
      elseif code == "y" then body = "> " .. weapon_name(body) .. "   BUILD"
      elseif code == "v" then body = "   " .. weapon_name(body) .. "   BUILD"
      elseif code == "w" then body = "   " .. weapon_name(body)
      elseif code == "j" then body = "> " .. ww_name(body)
      elseif code == "i" then body = "   " .. ww_name(body)
      end
      if not p.rows[i] then
        -- textRow units are scaled x1.5 by the kit: 18 units per line.
        p.rows[i] = kit.textRow(p.el, "rf", 0, 360, (i - 1) * 18, (i - 1) * 18 + 15, 0)
      end
      p.rows[i].set(body, MENU_STYLE[code] or MENU_STYLE.n)
    end
    for k = i + 1, #p.rows do p.rows[k].set("") end
  end

  local row, pb_row, shown, warned
  local function show(p, text)
    if text == p.shown or not p.el then return end
    local kit = hud_kit()
    if not kit then return end
    local drew, err = pcall(draw_panel, p, text, kit)
    if not drew and not warned then log("menu: " .. tostring(err)); warned = true end
  end
  local function tick()
    root:Wait(100).onComplete = tick
    local frontend = in_frontend()
    local menu_text = frontend and "" or dvar_text("kronos_bb_relic_menu")
    if menu_text == "" and not frontend then menu_text = dvar_text("kronos_bb_weapon_menu") end
    show(menu, menu_text)
    show(help, frontend and "" or dvar_text("kronos_bb_help"))
    local text = dvar_text("kronos_boss_timer")
    -- Personal best (kronos_boss_pb) only shows with the timer.
    local pb = ""
    if frontend then text = "" end
    if text ~= "" then pb = dvar_text("kronos_boss_pb") end
    if text .. "|" .. pb == shown then return end
    if not row and text ~= "" then
      local kit, why = hud_kit()
      if not kit then
        if not warned then log("timer: bo3_hud kit unavailable " .. tostring(why)) end
        warned = true
        return
      end
      -- textRow units are scaled by the kit (x1.5), right-aligned: timer 336x41 -> 504x61 px,
      -- personal best 336x18 -> 504x27 px just under it.
      row = kit.textRow(root, "rf", 0, 336, 0, 41, 2)
      pb_row = kit.textRow(root, "rf", 0, 336, 45, 63, 2)
      log("timer: shown")
    end
    shown = text .. "|" .. pb
    if row then row.set(text) end
    if pb_row then pb_row.set(pb, MENU_STYLE.h) end
  end
  tick()
end
