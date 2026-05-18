-- =========================================================
--  Factory OS Tank Node v1.0
-- =========================================================

local CONFIG = {
  telemetryRate = 2,
  capacityFallback = 1000000,
  lowPercent = 10,
  halfPercent = 50,
  highPercent = 90
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
  or ("tank_" .. os.getComputerID())

-- =========================================================
--  Peripheral discovery
-- =========================================================

local _, wirelessSide = wireless.find()

local tank = nil
local tankName = nil

for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)
  -- CC standard, CC:C Bridge, or create_target (Display Link text reader)
  if type(p.tanks) == "function"
    or type(p.getFluidInTank) == "function"
    or (type(p.dump) == "function" and type(p.getLine) == "function")
  then
    tank = p
    tankName = name
    break
  end
end

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

local function drawMonitorStatus(mon, heartbeat, alarm)
  mon.setTextScale(0.5)
  mon.setBackgroundColor(colors.black)
  mon.clear()

  local _, h = mon.getSize()
  local step = math.max(1, math.min(2, math.floor((h - 1) / 3)))
  local top  = 2

  statusLine(mon, 2, top,          colors.lime, "HB",  heartbeat)
  statusLine(mon, 2, top + step,   colors.cyan, "NET", wirelessSide ~= nil)
  statusLine(mon, 2, top + step*2,
    alarm and colors.red or colors.gray, "ALARM", alarm)
end

-- =========================================================
--  Tank state
-- =========================================================

local state = {
  fluid = "empty",
  amount = 0,
  capacity = CONFIG.capacityFallback,
  percent = 0,
  level = "EMPTY",
  alarm = false
}

-- Normalise fluid data from different peripheral APIs into
-- a standard array: { {name, amount, capacity}, ... }
-- Supports: CC standard tanks(), CC:C Bridge getFluidInTank()
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

  -- create_target: reads text lines from a Display Link (e.g. on a Threshold Switch)
  -- Peripheral type: "create_target", methods: dump(), getLine(y), resize(w,h)
  if type(p.dump) == "function" and type(p.getLine) == "function" then
    pcall(function() p.resize(20, 5) end)
    local ok, lines = pcall(function() return p.dump() end)
    if ok and type(lines) == "table" then
      local percent          = nil
      local amount, capacity = nil, nil
      local fluidName        = "unknown"

      for _, line in ipairs(lines) do
        if type(line) == "string" then
          -- "1000 / 16000 mB" pattern for absolute amounts
          local a, c = line:match("(%d+)%s*/%s*(%d+)%s*m[Bb]")
          if a and c then
            amount = tonumber(a); capacity = tonumber(c)
          end
          -- "25%" pattern for percentage-only sources
          local pct = line:match("(%d+)%s*%%")
          if pct then percent = tonumber(pct) end
          -- fluid name: alphabetic, no digits or special chars, not UI labels
          local trimmed = line:match("^%s*(.-)%s*$")
          if trimmed ~= ""
            and trimmed:match("^[A-Za-z]")
            and not trimmed:match("[:/%%]")
            and not trimmed:match("%d")
            and not trimmed:lower():match("threshold")
            and not trimmed:lower():match("switch")
            and not trimmed:lower():match("signal")
            and not trimmed:lower():match("active")
          then
            fluidName = trimmed
          end
        end
      end

      if amount and capacity then
        return {{ name = fluidName, amount = amount, capacity = capacity }}
      elseif percent then
        return {{ name = fluidName, amount = percent, capacity = 100 }}
      end
    end
  end

  return nil
end

local function readTank()
  if not tank then
    state.fluid    = "NO_TANK"
    state.amount   = 0
    state.capacity = CONFIG.capacityFallback
    state.percent  = 0
    state.level    = "ALARM"
    state.alarm    = true
    return
  end

  local tankData = readFluidPeripheral(tank)

  if not tankData then
    state.fluid    = "READ_ERROR"
    state.amount   = 0
    state.capacity = CONFIG.capacityFallback
    state.percent  = 0
    state.level    = "ALARM"
    state.alarm    = true
    return
  end

  local totalAmount   = 0
  local totalCapacity = 0
  local fluidName     = "empty"

  for _, t in pairs(tankData) do
    if type(t) == "table" then
      local amount   = t.amount   or 0
      local capacity = t.capacity or CONFIG.capacityFallback

      totalAmount   = totalAmount   + amount
      totalCapacity = totalCapacity + capacity

      if t.name then fluidName = t.name end
    end
  end

  if totalCapacity <= 0 then
    totalCapacity = CONFIG.capacityFallback
  end

  local percent = math.floor((totalAmount / totalCapacity) * 100)

  state.fluid    = fluidName
  state.amount   = totalAmount
  state.capacity = totalCapacity
  state.percent  = percent

  if percent <= CONFIG.lowPercent then
    state.level = "LOW"
    state.alarm = true
  elseif percent < CONFIG.halfPercent then
    state.level = "BELOW_HALF"
    state.alarm = false
  elseif percent < CONFIG.highPercent then
    state.level = "NORMAL"
    state.alarm = false
  else
    state.level = "HIGH"
    state.alarm = false
  end
end

-- =========================================================
--  Broadcast
-- =========================================================

local function broadcastStatus()
  if not wirelessSide then return end

  rednet.broadcast({
    type = "tank_status",
    app = "tank",
    node = nodeName,
    tank = tankName or "none",
    fluid = state.fluid,
    amount = state.amount,
    capacity = state.capacity,
    percent = state.percent,
    level = state.level,
    alarm = state.alarm,
    heartbeat = os.epoch("utc")
  }, PROTOCOL)

  if state.alarm then
    rednet.broadcast({
      type = "alarm",
      node = nodeName,
      level = "warning",
      message = "Tank low: " .. state.percent .. "%",
      ts = os.epoch("utc")
    }, PROTOCOL)
  end
end

-- =========================================================
--  Display links
-- =========================================================

local function drawDisplayLinks()
  for _, d in ipairs(displayLinks) do
    pcall(function()
      local w, h = d.getSize()

      d.clear()
      d.setCursorPos(1,1)
      d.write("Factory OS Tank")

      d.setCursorPos(1,2)
      d.write(shortFluid(state.fluid))

      d.setCursorPos(1,3)
      d.write(state.percent .. "% " .. state.level)

      d.update()
    end)
  end
end

-- =========================================================
--  Local terminal
-- =========================================================

local heartbeat = false

local function drawTerminal()
  resetTerm()

  term.setTextColor(colors.orange)
  print("Factory OS Tank Node v1.0")
  print("")

  ledTerm(colors.lime, "Heartbeat")
  ledTerm(wirelessSide and colors.cyan or colors.red, "Network")
  ledTerm(state.alarm and colors.red or colors.gray, "Alarm")

  print("")

  term.setTextColor(colors.gray)
  print("Node: " .. nodeName)
  print("Tank: " .. tostring(tankName))

  print("")

  term.setTextColor(colors.white)
  print("Fluid: " .. shortFluid(state.fluid))
  print("Level: " .. state.percent .. "%")
  print("Amount: " .. state.amount .. "/" .. state.capacity)
  print("Status: " .. state.level)
end

-- =========================================================
--  Loops
-- =========================================================

local function telemetryLoop()
  while true do
    readTank()
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
        drawMonitorStatus(mon, heartbeat, state.alarm)
      end)
    end

    sleep(0.5)
  end
end

parallel.waitForAny(
  telemetryLoop,
  uiLoop
)