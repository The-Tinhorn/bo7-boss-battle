-- Fast Restart. When the host pauses while crouched or prone (kronos_fast_restart "0", set by
-- scripts/fast_restart.gsc) the pause menu's Save & Quit reads Fast Restart, and pressing it
-- restarts the match instead of saving. Standing ("-") leaves Save & Quit as it is. Save & Quit
-- reaches the game two ways: Kronos's own button calls
-- KRONOS_RETAIL_K1.dispatchSave, and the game's confirm popup sends the engine event
-- "save_and_end_game" (Engine 0x76055c55456f05df). Both are taken over only while armed;
-- otherwise they pass straight through. Retried from a 100 ms loop until both are in place.
do
  local function log(s) pcall(function() KRONOS.log("fast restart: " .. tostring(s)) end) end
  local clua = rawget(_G, "CLUA")
  local HD = rawget(_G, "xhashdvar") or rawget(_G, "PushXHashDvar") or (type(clua) == "table" and clua.PushXHashDvar)

  local function in_frontend()
    local ok, v = pcall(function() return Engine[KRONOS.H("InFrontend")]() end)
    return ok and v == true
  end
  local function restart_dvar()
    local ok, v = pcall(function() return rawget(_G, "Dvar").GetDvarString(HD("kronos_fast_restart")) end)
    return ok and v or ""
  end
  local function armed() return restart_dvar() == "0" and not in_frontend() end
  local fr_armed = false

  -- Label: every LUI class's own setText is wrapped (how Kronos's menus set button text).
  local RESTART_WORDS = { "save & quit", "save and quit", "save & exit", "save and exit" }
  local function relabel(text)
    if not fr_armed or type(text) ~= "string" then return text end
    local low = string.lower(text)
    for _, w in ipairs(RESTART_WORDS) do
      local s, e = string.find(low, w, 1, true)
      if s then
        local found = string.sub(text, s, e)
        local rep = (found == string.upper(found)) and "FAST RESTART" or "Fast Restart"
        return string.sub(text, 1, s - 1) .. rep .. string.sub(text, e + 1)
      end
    end
    return text
  end
  local done, set_hooks = {}, 0
  local lui = rawget(_G, "LUI")
  if type(lui) == "table" then
    local classes = { lui }
    pcall(function() for _, v in pairs(lui) do if type(v) == "table" then classes[#classes + 1] = v end end end)
    for _, class in ipairs(classes) do
      for _, name in ipairs({ "setText", "SetText" }) do
        local original = rawget(class, name)
        if type(original) == "function" and not done[original] then
          local replacement = function(self, text, ...) return original(self, relabel(text), ...) end
          done[replacement] = true
          rawset(class, name, replacement)
          set_hooks = set_hooks + 1
        end
      end
    end
  end
  log("setText hooks=" .. set_hooks)

  local function request_restart()
    local D = rawget(_G, "Dvar")
    local set = nil
    pcall(function() set = D.SetDvarString end)
    if type(set) ~= "function" and type(clua) == "table" and type(clua.PushXHash) == "function" then
      pcall(function() set = rawget(D, clua.PushXHash("0x1e3cb005036e0c0f")) end)
    end
    local ok, err = pcall(set, HD("kronos_fast_restart"), "1")
    log("requested ok=" .. tostring(ok) .. " " .. tostring(err) .. " dvar=" .. restart_dvar())
    pcall(function() LUI.FlowManager.RequestCloseAllMenus() end)
    return true
  end
  local hooks = rawget(_G, "FAST_RESTART_HOOKS") or {}
  rawset(_G, "FAST_RESTART_HOOKS", hooks)
  local function install_restart_hooks()
    local k = rawget(_G, "KRONOS_RETAIL_K1")
    local save = type(k) == "table" and rawget(k, "dispatchSave")
    if type(save) == "function" and save ~= hooks.dispatch then
      hooks.dispatch = function(...)
        if armed() then return request_restart() end
        return save(...)
      end
      rawset(k, "dispatchSave", hooks.dispatch)
      log("dispatchSave hooked")
    end
    local E = rawget(_G, "Engine")
    local key = type(clua) == "table" and type(clua.PushXHash) == "function" and clua.PushXHash("0x76055c55456f05df")
    local event = type(E) == "table" and key and rawget(E, key)
    if type(event) == "function" and event ~= hooks.event then
      hooks.event = function(name, ...)
        if name == "save_and_end_game" and armed() then return request_restart() end
        return event(name, ...)
      end
      rawset(E, key, hooks.event)
      log("end-game event hooked")
    end
  end
  pcall(install_restart_hooks)

  local ok_root, root = pcall(function()
    local r = LUI.UIElement.new()
    LUI.GetRoot():addElement(r)
    return r
  end)
  if not ok_root or not root then
    log("no root " .. tostring(root))
    return
  end
  local function tick()
    root:Wait(100).onComplete = tick
    fr_armed = armed()
    if fr_armed then pcall(install_restart_hooks) end
  end
  tick()
end
