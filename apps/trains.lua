-- =========================================================
--  Factory OS Train Station Node v1.0
--  Monitors Create: Steam 'n' Rails train stations and
--  broadcasts train_status telemetry over FactoryOS.
-- =========================================================

local CONFIG = {
  telemetryRate = 2,
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
  or ("trains_" .. os.getComputerID())

local nodeLabel = util.readFile("/config/node_label.txt") or nodeName
local nodeGroup = util.readFile("/config/node_group.txt") or ""

-- =========================================================
--  Peripheral discovery
-- =========================================================

local _, wirelessSide = wireless.find()

local resetTerm  = ui.resetTerm
local ledTerm    = ui.ledTerm
local statusLine = ui.statusLine

-- Discover all Create train station peripherals
local stations = {}

for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)
  if type(p) == "table"
    and type(p.isTrainPresent) == "function"
  then
    table.insert(stations, { name = name, p = p })
  end
end

local monitors = { peripheral.find("monitor") }

-- =========================================================
--  State
-- =========================================================

-- One record per discovered station peripheral
-- { name, present, train, assembling, alarm }
local stationStates = {}

-- =========================================================
--  Reading
-- =========================================================

local function readAllStations()
  local newStates = {}

  for _, s in ipairs(stations) do
    local ok, present = pcall(function()
      return s.p.isTrainPresent()
    end)
    if not ok then present = false end

    local trainName = nil
    if present then
      local tok, tn = pcall(function()
        return s.p.getTrainName()
      end)
      if tok and type(tn) == "string" then
        trainName = tn
      end
    end

    local assembling = false
    do
      local aok, av = pcall(function()
        return s.p.isAssembling()
      end)
      if aok and type(av) == "boolean" then assembling = av end
    end

    table.insert(newStates, {
      name       = s.name,
      present    = present,
      train      = trainName,
      assembling = assembling,
      alarm      = false,
    })
  end

  stationStates = newStates
end

-- =========================================================
--  Broadcast
-- =========================================================

local function broadcastStatus()
  if not wirelessSide then return end

  for i, s in ipairs(stationStates) do
    -- Use nodeLabel for single-station nodes; suffix index when multiple
    local stLabel = (#stations == 1) and nodeLabel
                    or (nodeLabel .. " " .. i)

    rednet.broadcast({
      type       = "train_status",
      app        = "train",
      node       = nodeName .. "_" .. i,
      label      = stLabel,
      group      = nodeGroup,
      station    = s.name,
      present    = s.present,
      train      = s.train or "none",
      assembling = s.assembling,
      alarm      = s.alarm,
      heartbeat  = os.epoch("utc"),
    }, PROTOCOL)
  end
end

-- =========================================================
--  Status monitor
-- =========================================================

local function anyAlarm()
  for _, s in ipairs(stationStates) do
    if s.alarm then return true end
  end
  return false
end

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
    anyAlarm() and colors.red or colors.gray, "ALARM", anyAlarm())
end

-- =========================================================
--  Local terminal
-- =========================================================

local heartbeat = false

local function drawTerminal()
  resetTerm()

  term.setTextColor(colors.orange)
  print("Factory OS Train Node v1.0")
  print("")

  ledTerm(colors.lime, "Heartbeat")
  ledTerm(wirelessSide and colors.cyan or colors.red, "Network")

  print("")

  term.setTextColor(colors.gray)
  print("Node:     " .. nodeName)
  print("Label:    " .. nodeLabel)
  if nodeGroup ~= "" then
    print("Group:    " .. nodeGroup)
  end
  print("Stations: " .. #stations)

  if #stations == 0 then
    print("")
    term.setTextColor(colors.red)
    print("No train stations detected.")
    print("Wrap a Create_Station peripheral.")
    return
  end

  for _, s in ipairs(stationStates) do
    print("")
    if s.present then
      term.setTextColor(colors.lime)
      print("Present: " .. (s.train or "unknown"))
    elseif s.assembling then
      term.setTextColor(colors.yellow)
      print("Assembling...")
    else
      term.setTextColor(colors.gray)
      print(s.name .. " - empty")
    end
  end
end

-- =========================================================
--  Loops
-- =========================================================

local function telemetryLoop()
  while true do
    readAllStations()
    broadcastStatus()
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
