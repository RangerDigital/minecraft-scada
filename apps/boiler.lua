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
-- Create mod exposes boiler valves as "create:fluid_tank" (or "create_fluid_tank").
-- Fall back to checking for getTemperature() for other integrations.
local boilers = {}

for _, name in ipairs(peripheral.getNames()) do
  local pType = peripheral.getType(name)
  local p     = peripheral.wrap(name)
  if type(p) == "table" then
    local isFluidTank = pType and pType:find("fluid_tank") ~= nil
    local hasTemp     = type(p.getTemperature) == "function"
    if isFluidTank or hasTemp then
      table.insert(boilers, { name = name, p = p })
    end
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

-- Try to read a fluid tank at `index` (0-based) from peripheral p.
-- Returns { name, amount, capacity } or nil.
local function readTankSlot(p, index)
  if type(p.getFluidInTank) ~= "function" then return nil end

  local fOk, fluid = pcall(function() return p.getFluidInTank(index) end)
  if not fOk or type(fluid) ~= "table" then return nil end

  local cap = CONFIG.capacityFallback
  if type(p.getTankCapacity) == "function" then
    local cOk, c = pcall(function() return p.getTankCapacity(index) end)
    if cOk and type(c) == "number" and c > 0 then cap = c end
  end

  return {
    name     = fluid.fluidType or fluid.name or "unknown",
    amount   = fluid.amount or 0,
    capacity = cap,
  }
end

-- Percentage helper (0–100, integer)
local function pct(amount, capacity)
  if capacity <= 0 then return 0 end
  return math.floor((amount / capacity) * 100)
end

local function readAllBoilers()
  local newStates = {}

  for i, b in ipairs(boilers) do
    local p = b.p

    -- Temperature (0 .. maxTemp)
    local temp    = 0
    local maxTemp = 1000  -- Create high-pressure default
    local ok

    if type(p.getTemperature) == "function" then
      ok, temp = pcall(function() return p.getTemperature() end)
      if not ok or type(temp) ~= "number" then temp = 0 end
    end

    if type(p.getMaxTemperature) == "function" then
      local mOk, m = pcall(function() return p.getMaxTemperature() end)
      if mOk and type(m) == "number" and m > 0 then maxTemp = m end
    end

    local tempPercent = pct(temp, maxTemp)

    -- Water tank (slot 0) and steam tank (slot 1) via CC:C Bridge or similar
    local waterPct, steamPct = 0, 0
    local waterAmount, waterCap = 0, CONFIG.capacityFallback
    local steamAmount, steamCap = 0, CONFIG.capacityFallback

    local waterSlot = readTankSlot(p, 0)
    if waterSlot then
      waterAmount = waterSlot.amount
      waterCap    = waterSlot.capacity
      waterPct    = pct(waterAmount, waterCap)
    end

    local steamSlot = readTankSlot(p, 1)
    if steamSlot then
      steamAmount = steamSlot.amount
      steamCap    = steamSlot.capacity
      steamPct    = pct(steamAmount, steamCap)
    end

    -- Heat level (optional — some integrations expose this)
    local heatLevel = nil
    if type(p.getHeatLevel) == "function" then
      local hOk, h = pcall(function() return p.getHeatLevel() end)
      if hOk and type(h) == "number" then heatLevel = h end
    end

    -- Status classification
    local status, alarm

    if waterPct <= CONFIG.waterLowPercent then
      status = "WATER_LOW"; alarm = true
    elseif steamPct >= CONFIG.steamHighPercent then
      status = "STEAM_HIGH"; alarm = true
    elseif tempPercent < CONFIG.tempWarmPercent then
      status = "WARMING"; alarm = false
    elseif waterPct >= CONFIG.waterHighPercent then
      status = "WATER_FULL"; alarm = false
    else
      status = "RUNNING"; alarm = false
    end

    table.insert(newStates, {
      node        = nodeName .. "_" .. i,
      pName       = b.name,
      temp        = temp,
      maxTemp     = maxTemp,
      tempPercent = tempPercent,
      waterPct    = waterPct,
      waterAmount = waterAmount,
      waterCap    = waterCap,
      steamPct    = steamPct,
      steamAmount = steamAmount,
      steamCap    = steamCap,
      heatLevel   = heatLevel,
      status      = status,
      alarm       = alarm,
    })
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
      heatLevel   = s.heatLevel,
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
        d.write("W:" .. s.waterPct .. "% S:" .. s.steamPct
                .. "% T:" .. s.tempPercent .. "%")
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

    if s.heatLevel then
      print("Heat:  " .. s.heatLevel)
    end
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
