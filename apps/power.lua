-- =========================================================
--  Factory OS Power Node v1.0
--  Monitors Create mod Stressometer and Speedometer
--  peripherals and broadcasts power_status telemetry.
--
--  Peripherals detected automatically via wired modem:
--    Create_Stressometer  – getStress(), getStressCapacity()
--    Create_Speedometer   – getSpeed()
-- =========================================================

local CONFIG = {
  telemetryRate = 2,
  alarmPercent  = 90,  -- stress % at which alarm triggers
}

local wireless = dofile("/lib/wireless.lua")
local ui       = dofile("/lib/ui.lua")
local util     = dofile("/lib/util.lua")
local config   = dofile("/lib/config.lua")

local PROTOCOL = config.protocol()

-- =========================================================
--  Node identity
-- =========================================================

local _cfg      = config.load("power")
local nodeName  = _cfg.name
local nodeLabel = _cfg.label
local nodeGroup = _cfg.group

-- =========================================================
--  Peripheral discovery
-- =========================================================

local _, wirelessSide = wireless.find()

local resetTerm  = ui.resetTerm
local ledTerm    = ui.ledTerm
local statusLine = ui.statusLine

-- Discover Create stressometers and speedometers attached
-- via wired modem network.
local stressometers = {}
local speedometers  = {}

for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)
  if type(p) == "table" then
    if type(p.getStress) == "function" then
      table.insert(stressometers, { name = name, p = p })
    elseif type(p.getSpeed) == "function" then
      -- Only add as speedometer if NOT already a stressometer
      table.insert(speedometers, { name = name, p = p })
    end
  end
end

local monitors = { peripheral.find("monitor") }

-- =========================================================
--  State
-- =========================================================

local powerState = {
  stress    = 0,
  capacity  = 0,
  percent   = 0,
  speeds    = {},   -- { { name=..., rpm=... }, ... }
  alarm     = false,
}

-- =========================================================
--  Helpers
-- =========================================================

local function try(fn)
  local ok, v = pcall(fn)
  return ok and v or nil
end

-- =========================================================
--  Readings
-- =========================================================

local function readPower()
  -- Aggregate stress across all stressometers
  local totalStress    = 0
  local totalCapacity  = 0

  for _, s in ipairs(stressometers) do
    local stress    = try(function() return s.p.getStress()         end) or 0
    local capacity  = try(function() return s.p.getStressCapacity() end) or 0
    totalStress    = totalStress   + stress
    totalCapacity  = totalCapacity + capacity
  end

  local pct = (totalCapacity > 0)
    and math.min(100, math.floor(totalStress / totalCapacity * 100))
    or 0

  -- Read each speedometer
  local speeds = {}
  for _, s in ipairs(speedometers) do
    local rpm = try(function() return s.p.getSpeed() end)
    if rpm ~= nil then
      table.insert(speeds, { name = s.name, rpm = math.floor(rpm) })
    end
  end

  powerState = {
    stress    = math.floor(totalStress),
    capacity  = math.floor(totalCapacity),
    percent   = pct,
    speeds    = speeds,
    alarm     = pct >= CONFIG.alarmPercent,
  }
end

-- =========================================================
--  Broadcast
-- =========================================================

local function broadcastStatus()
  rednet.broadcast({
    type      = "power_status",
    app       = "power",
    node      = nodeName,
    label     = nodeLabel,
    group     = nodeGroup,
    stress    = powerState.stress,
    capacity  = powerState.capacity,
    percent   = powerState.percent,
    speeds    = powerState.speeds,
    alarm     = powerState.alarm,
    heartbeat = os.epoch("utc"),
  }, PROTOCOL)
end

-- =========================================================
--  Status monitor (tiny 1×1 block monitor)
-- =========================================================

local function drawMonitorStatus(mon, heartbeat)
  mon.setTextScale(0.5)
  mon.setBackgroundColor(colors.black)
  mon.clear()

  local _, h = mon.getSize()
  local step = math.max(1, math.min(2, math.floor((h - 1) / 3)))
  local top  = 2

  statusLine(mon, 2, top,          colors.lime, "HB",    heartbeat)
  statusLine(mon, 2, top + step,   colors.cyan, "NET",   wirelessSide ~= nil)
  statusLine(mon, 2, top + step*2,
    powerState.alarm and colors.red or colors.gray, "ALARM", powerState.alarm)
end

-- =========================================================
--  Local terminal
-- =========================================================

local heartbeat = false

local function drawTerminal()
  local W = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)

  term.setTextColor(colors.orange)
  print("FACTORY OS - POWER")
  term.setTextColor(colors.gray)
  print(("-"):rep(W))

  ledTerm(colors.lime,   "Node:   " .. nodeName)
  ledTerm(colors.cyan,   "Label:  " .. nodeLabel)
  ledTerm(colors.purple, "Group:  " .. (nodeGroup ~= "" and nodeGroup or "(none)"))

  term.setTextColor(colors.gray)
  print(("-"):rep(W))

  -- Stress bar
  local stressColor = powerState.alarm         and colors.red
                   or powerState.percent >= 75  and colors.yellow
                   or                               colors.lime

  ledTerm(stressColor, string.format(
    "Stress: %d / %d SU  (%d%%)",
    powerState.stress, powerState.capacity, powerState.percent
  ))

  -- Speedometers
  if #powerState.speeds > 0 then
    term.setTextColor(colors.gray)
    print(("-"):rep(W))
    for _, s in ipairs(powerState.speeds) do
      term.setTextColor(s.rpm ~= 0 and colors.lightGray or colors.gray)
      print(string.format("  %-16s %6d RPM", s.name, s.rpm))
    end
  end

  term.setTextColor(colors.gray)
  print(("-"):rep(W))

  ledTerm(colors.lime, "HB:     " .. tostring(heartbeat))
  ledTerm(colors.cyan, "NET:    " .. tostring(wirelessSide))
end

-- =========================================================
--  Main loops
-- =========================================================

local function telemetryLoop()
  while true do
    readPower()
    broadcastStatus()

    for _, mon in ipairs(monitors) do
      pcall(function()
        local w, h = mon.getSize()
        if w <= 15 and h <= 10 then
          drawMonitorStatus(mon, heartbeat)
        end
      end)
    end

    heartbeat = not heartbeat
    drawTerminal()
    sleep(CONFIG.telemetryRate)
  end
end

-- =========================================================
--  Boot
-- =========================================================

resetTerm()
drawTerminal()

if wirelessSide == nil then
  ledTerm(colors.red, "No wireless modem!")
  sleep(5)
end

if #stressometers == 0 and #speedometers == 0 then
  ledTerm(colors.yellow, "No power peripherals found.")
  sleep(3)
end

telemetryLoop()
