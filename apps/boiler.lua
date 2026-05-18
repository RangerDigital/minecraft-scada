-- =========================================================
--  Factory OS Boiler Node v1.0
--  Monitors Create mod steam engine boilers.
-- =========================================================

local CONFIG = {
  telemetryRate   = 2,
  capacityFallback = 16000,   -- mB fallback for water / steam tanks
  waterLowPercent  = 20,      -- alarm: water critically low
  waterHighPercent = 95,      -- warning: water nearly full (no inflow margin)
  steamHighPercent = 90,      -- warning: steam backing up
  tempWarmPercent  = 50,      -- below this → "WARMING" state (no useful steam)
}

local PROTOCOL = "factoryos"

local wireless = dofile("/lib/wireless.lua")
local ui       = dofile("/lib/ui.lua")
local util     = dofile("/lib/util.lua")

-- =========================================================
--  Node identity
-- =========================================================

local nodeName =
  util.readFile("/config/node_name.txt")
  or os.getComputerLabel()
  or ("boiler_" .. os.getComputerID())

-- =========================================================
--  Peripheral discovery
-- =========================================================

local _, wirelessSide = wireless.find()

-- Discover boiler peripherals on the wired network.
-- Expects CC:C Bridge Display Link Target blocks (expose getLine).
local boilers = {}

for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)
  if type(p) == "table" and type(p.getLine) == "function" then
    table.insert(boilers, { name = name, p = p })
  end
end

-- Boiler states updated each telemetry cycle
local boilerStates = {}

local monitors = { peripheral.find("monitor") }

local displayLinks = {}

for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)
  if type(p) == "table"
    and type(p.write)    == "function"
    and type(p.clear)    == "function"
    and type(p.getSize)  == "function"
    and type(p.update)   == "function"
  then
    table.insert(displayLinks, p)
  end
end

-- =========================================================
--  UI helpers
-- =========================================================

local resetTerm  = ui.resetTerm
local ledTerm    = ui.ledTerm
local led        = ui.led
local statusLine = ui.statusLine

local function drawMonitorStatus(mon, heartbeat)
  mon.setTextScale(0.5)
  mon.setBackgroundColor(colors.black)
  mon.clear()

  local _, h = mon.getSize()
  local step = math.max(1, math.min(2, math.floor((h - 1) / 3)))
  local top  = 2

  local alarm = false
  for _, s in ipairs(boilerStates) do
    if s.alarm then alarm = true; break end
  end

  statusLine(mon, 2, top,          colors.lime, "HB",    heartbeat)
  statusLine(mon, 2, top + step,   colors.cyan, "NET",   wirelessSide ~= nil)
  statusLine(mon, 2, top + step*2, alarm and colors.red or colors.gray, "ALARM", alarm)
end

-- =========================================================
--  Boiler reading helpers
-- =========================================================

-- Percentage helper (0-100, integer)
local function pct(amount, capacity)
  if capacity <= 0 then return 0 end
  return math.floor((amount / capacity) * 100)
end

-- Read boiler status from a CC:C Bridge Display Link Target block.
-- The boiler status display shows visual progress bars, e.g.:
--   line 1: "BOILER STATUS: LVL9"
--   line 2: "SIZE [$$$$$$......] "
--   line 3: "water[$$$$$$$$$$..] "
--   line 4: "heat [$$$$$$......] "
-- Filled segments are '$'; bar width is 16. Percentages are derived by
-- counting '$' chars and dividing by 16.
local BAR_WIDTH = 16

local function readFromTarget(p)
  if type(p.getLine) ~= "function" then return nil end

  local function line(n)
    local ok, v = pcall(function() return p.getLine(n) end)
    return (ok and type(v) == "string") and v or ""
  end

  -- Count '$' chars in line and convert to 0-100 percentage
  local function barPct(s)
    local filled = select(2, s:gsub("%$", ""))
    return math.min(100, math.floor(filled / BAR_WIDTH * 100))
  end

  -- Split lines into per-boiler sections.
  -- A header line (contains "boiler" or "lvl") starts a new section.
  local sections = {}
  local cur = nil

  for n = 1, 16 do
    local l = line(n)
    if l == "" then break end
    local ll = l:lower()
    if ll:find("boiler") or ll:find("lvl") then
      if cur then table.insert(sections, cur) end
      cur = {}
    elseif cur then
      if ll:find("water") then
        cur.waterPct = barPct(l)
      elseif ll:find("size") then
        cur.steamPct = barPct(l)
      elseif ll:find("heat") then
        cur.tempPct = barPct(l)
      end
    end
  end
  if cur then table.insert(sections, cur) end

  if #sections == 0 then return nil end

  local cap = CONFIG.capacityFallback
  local out = {}
  for _, d in ipairs(sections) do
    local wPct = d.waterPct or 0
    local sPct = d.steamPct or 0
    local tPct = d.tempPct  or 0
    table.insert(out, {
      waterAmount = math.floor(wPct / 100 * cap),
      waterCap    = cap,
      steamAmount = math.floor(sPct / 100 * cap),
      steamCap    = cap,
      temp        = math.floor(tPct / 100 * 1000),
      maxTemp     = 1000,
    })
  end

  return out
end

local function readAllBoilers()
  local newStates = {}

  for i, b in ipairs(boilers) do
    local p = b.p

    -- ── CC:C Bridge Display Link Target ───────────────────────────────
    local bridgeList = readFromTarget(p)
    if not bridgeList then goto continue end

    for j, bridge in ipairs(bridgeList) do
      local waterPct    = pct(bridge.waterAmount, bridge.waterCap)
      local steamPct    = pct(bridge.steamAmount, bridge.steamCap)
      local tempPercent = pct(bridge.temp, bridge.maxTemp)

      -- ── Status classification ───────────────────────────────────────
      local status, alarm
      if waterPct <= CONFIG.waterLowPercent then
        status = "WATER_LOW";  alarm = true
      elseif steamPct >= CONFIG.steamHighPercent then
        status = "STEAM_HIGH"; alarm = true
      elseif tempPercent > 0 and tempPercent < CONFIG.tempWarmPercent then
        status = "WARMING";    alarm = false
      elseif waterPct >= CONFIG.waterHighPercent then
        status = "WATER_FULL"; alarm = false
      else
        status = "RUNNING";    alarm = false
      end

      local nodeIdx = (i - 1) * 2 + j
      table.insert(newStates, {
        node        = nodeName .. "_" .. nodeIdx,
        pName       = b.name .. "_" .. j,
        temp        = bridge.temp,
        maxTemp     = bridge.maxTemp,
        tempPercent = tempPercent,
        waterPct    = waterPct,
        waterAmount = bridge.waterAmount,
        waterCap    = bridge.waterCap,
        steamPct    = steamPct,
        steamAmount = bridge.steamAmount,
        steamCap    = bridge.steamCap,
        status      = status,
        alarm       = alarm,
      })
    end

    ::continue::
  end

  boilerStates = newStates
end

-- =========================================================
--  Broadcast
-- =========================================================

local function broadcastStatus()
  if not wirelessSide then return end

  for _, s in ipairs(boilerStates) do
    rednet.broadcast({
      type        = "boiler_status",
      app         = "boiler",
      node        = s.node,
      boiler      = s.pName,
      temp        = s.temp,
      maxTemp     = s.maxTemp,
      tempPercent = s.tempPercent,
      waterPct    = s.waterPct,
      waterAmount = s.waterAmount,
      waterCap    = s.waterCap,
      steamPct    = s.steamPct,
      steamAmount = s.steamAmount,
      steamCap    = s.steamCap,
      status      = s.status,
      alarm       = s.alarm,
      heartbeat   = os.epoch("utc"),
    }, PROTOCOL)

    if s.alarm then
      rednet.broadcast({
        type    = "alarm",
        node    = s.node,
        level   = "warning",
        message = "Boiler " .. s.status .. " (water=" .. s.waterPct
                  .. "%, steam=" .. s.steamPct .. "%, temp=" .. s.tempPercent .. "%)",
        ts      = os.epoch("utc"),
      }, PROTOCOL)
    end
  end
end

-- =========================================================
--  Display links
-- =========================================================

local function drawDisplayLinks()
  for _, d in ipairs(displayLinks) do
    pcall(function()
      d.clear()
      d.setCursorPos(1, 1)
      d.write("Factory OS Boiler")

      local y = 2
      for _, s in ipairs(boilerStates) do
        d.setCursorPos(1, y)
        local parts = {}
        parts[#parts+1] = "W:" .. s.waterPct .. "%"
        parts[#parts+1] = "S:" .. s.steamPct .. "%"
        if s.tempPercent > 0 then parts[#parts+1] = "T:" .. s.tempPercent .. "%" end
        d.write(table.concat(parts, " "))
        y = y + 1
      end

      d.update()
    end)
  end
end

-- =========================================================
--  Local terminal
-- =========================================================

local heartbeat = false

local function anyAlarm()
  for _, s in ipairs(boilerStates) do
    if s.alarm then return true end
  end
  return false
end

local function drawTerminal()
  resetTerm()

  term.setTextColor(colors.orange)
  print("Factory OS Boiler Node v1.0")
  print("")

  ledTerm(colors.lime, "Heartbeat")
  ledTerm(wirelessSide and colors.cyan or colors.red, "Network")
  ledTerm(anyAlarm() and colors.red or colors.gray, "Alarm")

  print("")

  term.setTextColor(colors.gray)
  print("Node: " .. nodeName)
  print("Boilers: " .. #boilers)

  if #boilerStates == 0 then
    print("")
    term.setTextColor(colors.red)
    print("No boilers detected")
    return
  end

  for _, s in ipairs(boilerStates) do
    print("")

    local statusColor = s.alarm        and colors.red
      or (s.status == "WARMING"        and colors.yellow)
      or (s.status == "WATER_FULL"     and colors.yellow)
      or colors.lime

    term.setTextColor(statusColor)
    print("Status: " .. s.status)

    term.setTextColor(colors.gray)
    print("Temp:  " .. s.temp .. " / " .. s.maxTemp .. " (" .. s.tempPercent .. "%)")
    print("Water: " .. s.waterAmount .. " / " .. s.waterCap .. " mB (" .. s.waterPct .. "%)")
    print("Steam: " .. s.steamAmount .. " / " .. s.steamCap .. " mB (" .. s.steamPct .. "%)")
  end
end

-- =========================================================
--  Loops
-- =========================================================

local function telemetryLoop()
  while true do
    readAllBoilers()
    broadcastStatus()
    drawDisplayLinks()
    sleep(CONFIG.telemetryRate)
  end
end

local function uiLoop()
  while true do
    heartbeat = not heartbeat

    drawTerminal()

    for _, mon in ipairs(monitors) do
      pcall(function()
        drawMonitorStatus(mon, heartbeat)
      end)
    end

    sleep(0.5)
  end
end

parallel.waitForAny(
  telemetryLoop,
  uiLoop
)
