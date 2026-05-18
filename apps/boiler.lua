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

-- Read one fluid slot (0-based) from a peripheral.
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

-- Percentage helper (0-100, integer)
local function pct(amount, capacity)
  if capacity <= 0 then return 0 end
  return math.floor((amount / capacity) * 100)
end

local function readAllBoilers()
  local newStates = {}

  for i, b in ipairs(boilers) do
    local p = b.p

    -- ── Read all fluid slots, classify by fluid name ──────────────────
    local allSlots = {}
    if type(p.getFluidInTank) == "function" then
      local count = 1
      if type(p.getTankCount) == "function" then
        local ok, n = pcall(function() return p.getTankCount() end)
        if ok and type(n) == "number" and n > 0 then count = n end
      end
      for idx = 0, count - 1 do
        local slot = readTankSlot(p, idx)
        if slot then table.insert(allSlots, slot) end
      end
    end

    local waterSlot, steamSlot, lavaSlot
    for _, slot in ipairs(allSlots) do
      local nm = (slot.name or ""):lower()
      if     not waterSlot and nm:find("water") then waterSlot = slot
      elseif not steamSlot and nm:find("steam") then steamSlot = slot
      elseif not lavaSlot  and nm:find("lava")  then lavaSlot  = slot
      end
    end

    -- ── Temperature ───────────────────────────────────────────────────
    local temp    = 0
    local maxTemp = 1000
    if type(p.getTemperature) == "function" then
      local ok, t = pcall(function() return p.getTemperature() end)
      if ok and type(t) == "number" then temp = t end
    end
    if type(p.getMaxTemperature) == "function" then
      local ok, m = pcall(function() return p.getMaxTemperature() end)
      if ok and type(m) == "number" and m > 0 then maxTemp = m end
    end
    local tempPercent = pct(temp, maxTemp)

    -- ── Per-fluid percentages ─────────────────────────────────────────
    local waterPct = waterSlot and pct(waterSlot.amount, waterSlot.capacity) or 0
    local steamPct = steamSlot and pct(steamSlot.amount, steamSlot.capacity) or 0
    local lavaPct  = lavaSlot  and pct(lavaSlot.amount,  lavaSlot.capacity)  or 0

    -- ── Heat level (optional) ─────────────────────────────────────────
    local heatLevel
    if type(p.getHeatLevel) == "function" then
      local ok, h = pcall(function() return p.getHeatLevel() end)
      if ok and type(h) == "number" then heatLevel = h end
    end

    -- ── Status classification ─────────────────────────────────────────
    -- Only raise fluid alarms for fluids that are actually present.
    local hasWater = waterSlot ~= nil
    local hasLava  = lavaSlot  ~= nil
    local status, alarm

    if hasLava and not hasWater and lavaPct <= CONFIG.waterLowPercent then
      status = "LAVA_LOW";   alarm = true
    elseif hasWater and waterPct <= CONFIG.waterLowPercent then
      status = "WATER_LOW";  alarm = true
    elseif steamPct >= CONFIG.steamHighPercent then
      status = "STEAM_HIGH"; alarm = true
    elseif tempPercent > 0 and tempPercent < CONFIG.tempWarmPercent then
      status = "WARMING";    alarm = false
    elseif hasWater and waterPct >= CONFIG.waterHighPercent then
      status = "WATER_FULL"; alarm = false
    else
      status = "RUNNING";    alarm = false
    end

    table.insert(newStates, {
      node        = nodeName .. "_" .. i,
      pName       = b.name,
      temp        = temp,
      maxTemp     = maxTemp,
      tempPercent = tempPercent,
      hasWater    = hasWater,
      waterPct    = waterPct,
      waterAmount = waterSlot and waterSlot.amount   or 0,
      waterCap    = waterSlot and waterSlot.capacity or CONFIG.capacityFallback,
      hasLava     = hasLava,
      lavaPct     = lavaPct,
      lavaAmount  = lavaSlot and lavaSlot.amount   or 0,
      lavaCap     = lavaSlot and lavaSlot.capacity or CONFIG.capacityFallback,
      steamPct    = steamPct,
      steamAmount = steamSlot and steamSlot.amount   or 0,
      steamCap    = steamSlot and steamSlot.capacity or CONFIG.capacityFallback,
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
      hasWater    = s.hasWater,
      waterPct    = s.waterPct,
      waterAmount = s.waterAmount,
      waterCap    = s.waterCap,
      hasLava     = s.hasLava,
      lavaPct     = s.lavaPct,
      lavaAmount  = s.lavaAmount,
      lavaCap     = s.lavaCap,
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
        local parts = {}
        if s.hasLava  then parts[#parts+1] = "L:" .. s.lavaPct  .. "%" end
        if s.hasWater then parts[#parts+1] = "W:" .. s.waterPct .. "%" end
        if s.steamPct > 0 then parts[#parts+1] = "S:" .. s.steamPct .. "%" end
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
    if s.tempPercent > 0 then
      print("Temp:  " .. s.temp .. " / " .. s.maxTemp .. " (" .. s.tempPercent .. "%)")
    end
    if s.hasLava then
      print("Lava:  " .. s.lavaAmount .. " / " .. s.lavaCap .. " mB (" .. s.lavaPct .. "%)")
    end
    if s.hasWater then
      print("Water: " .. s.waterAmount .. " / " .. s.waterCap .. " mB (" .. s.waterPct .. "%)")
    end
    if s.steamPct > 0 then
      print("Steam: " .. s.steamAmount .. " / " .. s.steamCap .. " mB (" .. s.steamPct .. "%)")
    end
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
