-- =========================================================
--  Factory OS Tank Node v1.0
-- =========================================================

local CONFIG = {
  telemetryRate = 2,
  capacityFallback = 432000,
  lowPercent = 10,
  halfPercent = 50,
  highPercent = 90
}

local wireless = dofile("/lib/wireless.lua")
local ui       = dofile("/lib/ui.lua")
local util     = dofile("/lib/util.lua")
local config   = dofile("/lib/config.lua")

local PROTOCOL = config.protocol()

-- =========================================================
--  Node identity
-- =========================================================

local _cfg        = config.load("tank")
local nodeName    = _cfg.name
local nodeLabel   = _cfg.label
local nodeGroup   = _cfg.group
local factoryName = _cfg.factory_name

-- =========================================================
--  Tank capacity config
-- =========================================================

local CAPACITY_FILE = "/config/tank_capacity.txt"

local function setupCapacity()
  ui.resetTerm()
  term.setTextColor(colors.orange)
  print("====================================")
  print("      TANK CAPACITY SETUP")
  print("====================================")
  print("")
  term.setTextColor(colors.lightGray)
  print("Enter tank capacity in mB.")
  print("Press Enter to use default.")
  print("")
  term.setTextColor(colors.yellow)
  print("Examples:")
  print("  16000   small barrel")
  print("  432000  large tank (default)")
  print("  1000000 fluid vault")
  print("")
  term.setTextColor(colors.gray)
  print("[" .. CONFIG.capacityFallback .. "]")
  term.setTextColor(colors.white)
  write("> ")
  local input = read()
  local cap = tonumber(input) or CONFIG.capacityFallback
  local f = fs.open(CAPACITY_FILE, "w")
  f.write(tostring(math.floor(cap)))
  f.close()
  term.setTextColor(colors.lime)
  print("Capacity: " .. math.floor(cap) .. " mB")
  sleep(1)
  return math.floor(cap)
end

local capRaw = util.readFile(CAPACITY_FILE)
local tankCapacity = (capRaw and tonumber(capRaw)) or setupCapacity()
CONFIG.capacityFallback = tankCapacity

-- =========================================================
--  Peripheral discovery
-- =========================================================

local _, wirelessSide = wireless.find()

-- Discover all fluid tanks reachable via wired modem network
local tanks = {}

for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)
  if type(p) == "table"
    and (type(p.tanks) == "function" or type(p.getFluidInTank) == "function")
  then
    table.insert(tanks, { name = name, p = p })
  end
end

-- Tank states updated each telemetry cycle (one entry per discovered tank)
local tankStates = {}

local monitors = { peripheral.find("monitor") }

local displayLinks = {}

for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)

  if type(p.write) == "function"
    and type(p.clear) == "function"
    and type(p.getSize) == "function"
    and type(p.update) == "function"
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
local shortFluid = util.shortName

local function drawMonitorStatus(mon, heartbeat)
  mon.setTextScale(0.5)
  mon.setBackgroundColor(colors.black)
  mon.clear()

  local _, h = mon.getSize()
  local step = math.max(1, math.min(2, math.floor((h - 1) / 3)))
  local top  = 2

  local alarm = false
  for _, s in ipairs(tankStates) do
    if s.alarm then alarm = true; break end
  end

  statusLine(mon, 2, top,          colors.lime, "HB",  heartbeat)
  statusLine(mon, 2, top + step,   colors.cyan, "NET", wirelessSide ~= nil)
  statusLine(mon, 2, top + step*2, alarm and colors.red or colors.gray, "ALARM", alarm)
end

-- =========================================================
--  Fluid reading
-- =========================================================

-- Normalise fluid data from different peripheral APIs into
-- a standard array: { {name, amount, capacity}, ... }
local function readFluidPeripheral(p)
  -- Standard CC:Tweaked fluid API
  if type(p.tanks) == "function" then
    local ok, data = pcall(function() return p.tanks() end)
    if ok and type(data) == "table" then return data end
  end

  -- CC:C Bridge API: getFluidInTank(i), getTankCapacity(i), getTankCount()
  if type(p.getFluidInTank) == "function" then
    local ok, count = pcall(function()
      return type(p.getTankCount) == "function" and p.getTankCount() or 1
    end)
    if not ok then count = 1 end

    local result = {}
    for i = 0, count - 1 do
      local fOk, fluid = pcall(function() return p.getFluidInTank(i) end)
      if fOk and type(fluid) == "table" then
        local cOk, cap = pcall(function()
          return type(p.getTankCapacity) == "function"
            and p.getTankCapacity(i)
            or CONFIG.capacityFallback
        end)
        table.insert(result, {
          name     = fluid.fluidType or fluid.name,
          amount   = fluid.amount   or 0,
          capacity = (cOk and cap)  or CONFIG.capacityFallback,
        })
      end
    end
    if #result > 0 then return result end
  end

  return nil
end

local function readAllTanks()
  local newStates = {}
  for i, t in ipairs(tanks) do
    local data = readFluidPeripheral(t.p)
    if data then
      local totalAmount   = 0
      local totalCapacity = 0
      local fluidName     = "empty"

      for _, slot in pairs(data) do
        if type(slot) == "table" then
          totalAmount = totalAmount + (slot.amount or 0)
          -- tanks() only returns name+amount per CC:Tweaked docs; capacity is nil.
          -- Use max so that if a mod does return it, shared-total tanks aren't multiplied.
          local cap = slot.capacity or 0
          if cap > totalCapacity then totalCapacity = cap end
          if slot.name then fluidName = slot.name end
        end
      end

      if totalCapacity <= 0 then totalCapacity = CONFIG.capacityFallback end

      local percent = math.floor((totalAmount / totalCapacity) * 100)
      local level, alarm

      if percent <= CONFIG.lowPercent then
        level = "LOW";        alarm = true
      elseif percent < CONFIG.halfPercent then
        level = "BELOW_HALF"; alarm = false
      elseif percent < CONFIG.highPercent then
        level = "NORMAL";     alarm = false
      else
        level = "HIGH";       alarm = false
      end

      table.insert(newStates, {
        node     = nodeName .. "_" .. i,
        pName    = t.name,
        fluid    = fluidName,
        amount   = totalAmount,
        capacity = totalCapacity,
        percent  = percent,
        level    = level,
        alarm    = alarm,
      })
    end
  end
  tankStates = newStates
end

-- =========================================================
--  Broadcast
-- =========================================================

local function broadcastStatus()
  if not wirelessSide then return end

  for i, s in ipairs(tankStates) do
    local tankLabel = (#tankStates > 1)
      and (nodeLabel .. " " .. string.char(64 + i))
      or nodeLabel

    rednet.broadcast({
      type      = "tank_status",
      app       = "tank",
      node      = s.node,
      tank      = s.pName,
      fluid     = s.fluid,
      amount    = s.amount,
      capacity  = s.capacity,
      percent   = s.percent,
      level     = s.level,
      alarm     = s.alarm,
      label     = tankLabel,
      group     = nodeGroup,
      heartbeat = os.epoch("utc"),
    }, PROTOCOL)

    if s.alarm then
      rednet.broadcast({
        type    = "alarm",
        node    = s.node,
        label   = tankLabel,
        level   = "warning",
        message = "Tank low: " .. s.percent .. "%",
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
      d.write("Factory OS Tank")

      local y = 2
      for _, s in ipairs(tankStates) do
        d.setCursorPos(1, y)
        d.write(shortFluid(s.fluid) .. " " .. s.percent .. "%")
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
  for _, s in ipairs(tankStates) do
    if s.alarm then return true end
  end
  return false
end

local function drawTerminal()
  local W = term.getSize()
  ui.nodeHeader("tank", nodeLabel, nodeGroup, factoryName, wirelessSide ~= nil)
  ledTerm(anyAlarm() and colors.red or colors.gray,
    "Alarm:  " .. (anyAlarm() and "ACTIVE" or "none"))
  ledTerm(colors.lightGray, "Tanks:  " .. #tanks)
  ledTerm(colors.lime, "HB:     " .. (heartbeat and "●" or "○"))
  term.setTextColor(colors.gray)
  print(("-"):rep(W))

  if #tankStates == 0 then
    print("")
    term.setTextColor(colors.red)
    print("No tanks detected")
    return
  end

  for _, s in ipairs(tankStates) do
    print("")
    local c = s.alarm and colors.red
      or (s.percent < 50 and colors.yellow or colors.lime)
    term.setTextColor(c)
    print(shortFluid(s.fluid) .. " " .. s.percent .. "%")
    term.setTextColor(colors.gray)
    print(s.amount .. " / " .. s.capacity .. " mB")
    print("Status: " .. s.level)
  end
end

-- =========================================================
--  Loops
-- =========================================================

local function telemetryLoop()
  while true do
    readAllTanks()
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