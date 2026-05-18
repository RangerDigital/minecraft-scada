-- =========================================================
--  Factory OS Train Station Node v2.0
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

-- One record per discovered station peripheral:
-- { name, stationName, present, train, cars,
--   assembling, idle,
--   scheduleCurrent, scheduleNext, scheduleTotal, scheduleCyclic,
--   alarm }
local stationStates = {}

-- =========================================================
--  Helpers
-- =========================================================

-- Safe peripheral call: returns value or nil on error
local function try(fn)
  local ok, v = pcall(fn)
  return ok and v or nil
end

-- Parse a schedule table from the peripheral into something useful
local function parseSchedule(sched)
  if type(sched) ~= "table" then return nil, nil, nil, nil end

  local entries = type(sched.entries) == "table" and sched.entries or {}
  local total   = #entries
  if total == 0 then return nil, nil, 0, sched.cyclic end

  local cur     = (type(sched.currentEntry) == "number") and sched.currentEntry or 1
  cur           = math.max(1, math.min(cur, total))

  local function destOf(e)
    if type(e) ~= "table" then return nil end
    return e.destination or e.name or e.id
  end

  local currentDest = destOf(entries[cur])
  local nextIdx     = (cur % total) + 1
  local nextDest    = destOf(entries[nextIdx])

  return currentDest, nextDest, total, sched.cyclic
end

-- =========================================================
--  Reading
-- =========================================================

local function readAllStations()
  local newStates = {}

  for _, s in ipairs(stations) do
    -- Core presence
    local present    = try(function() return s.p.isTrainPresent() end) == true
    local assembling = try(function() return s.p.isAssembling()   end) == true

    -- Station's configured in-game name
    local stationName = try(function() return s.p.getStationName() end) or s.name

    -- Train info (only meaningful when present)
    local trainName, cars, idle
    if present or assembling then
      trainName = try(function() return s.p.getTrainName() end)
      cars      = try(function() return s.p.getCarCount()  end)
      -- getTrainCars() may return a list instead
      if not cars then
        local carList = try(function() return s.p.getTrainCars() end)
        if type(carList) == "table" then cars = #carList end
      end
      idle = try(function() return s.p.isCurrentlyIdle() end) == true
    end

    -- Schedule
    local schedRaw     = try(function() return s.p.getSchedule() end)
    local sCur, sNext, sTotal, sCyclic = parseSchedule(schedRaw)

    table.insert(newStates, {
      name          = s.name,
      stationName   = stationName,
      present       = present,
      assembling    = assembling,
      train         = trainName,
      cars          = cars,
      idle          = idle,
      scheduleCurrent = sCur,
      scheduleNext    = sNext,
      scheduleTotal   = sTotal,
      scheduleCyclic  = sCyclic,
      alarm           = false,
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
    local stLabel = (#stations == 1) and nodeLabel
                    or (nodeLabel .. " " .. i)

    rednet.broadcast({
      type            = "train_status",
      app             = "train",
      node            = nodeName .. "_" .. i,
      label           = stLabel,
      group           = nodeGroup,
      station         = s.stationName,
      present         = s.present,
      train           = s.train,
      cars            = s.cars,
      assembling      = s.assembling,
      idle            = s.idle,
      scheduleCurrent = s.scheduleCurrent,
      scheduleNext    = s.scheduleNext,
      scheduleTotal   = s.scheduleTotal,
      scheduleCyclic  = s.scheduleCyclic,
      alarm           = s.alarm,
      heartbeat       = os.epoch("utc"),
    }, PROTOCOL)
  end
end

-- =========================================================
--  Status monitor (tiny 1x1 block monitor)
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
--  Local terminal – rich HMI display
-- =========================================================

local heartbeat = false

local function printLed(color, label, active)
  if active then
    term.setBackgroundColor(color)
    term.setTextColor(colors.black)
    term.write(" ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(color)
    term.write(" " .. label .. "  ")
  else
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.gray)
    term.write("   " .. label .. "  ")
  end
end

local function drawTerminal()
  local W = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)

  -- Header
  term.setTextColor(colors.orange)
  term.write("Factory OS  Train Node v2.0")
  term.setCursorPos(1, 2)
  printLed(colors.lime, "HB",  heartbeat)
  printLed(wirelessSide and colors.cyan or colors.red, "NET", wirelessSide ~= nil)
  printLed(anyAlarm() and colors.red or colors.gray, "ALARM", anyAlarm())
  print("")

  -- Identity
  term.setTextColor(colors.gray)
  print(string.format("Node:  %-20s  Stations: %d", nodeName, #stations))
  term.setTextColor(colors.white)
  print(string.format("Label: %s", nodeLabel))
  if nodeGroup ~= "" then
    term.setTextColor(colors.orange)
    print(string.format("Group: %s", nodeGroup))
  end

  if #stations == 0 then
    print("")
    term.setTextColor(colors.red)
    print("No train stations detected.")
    print("Wrap a Create_Station peripheral.")
    return
  end

  for _, s in ipairs(stationStates) do
    -- Section divider
    term.setTextColor(colors.gray)
    print(("-"):rep(W))

    -- Station name
    term.setTextColor(colors.cyan)
    print("  " .. s.stationName)

    -- Status line
    if s.assembling then
      term.setTextColor(colors.yellow)
      print("  Status:  ASSEMBLING")
    elseif s.present then
      term.setTextColor(colors.lime)
      print("  Status:  PRESENT")
    else
      term.setTextColor(colors.gray)
      print("  Status:  EMPTY")
    end

    -- Train details
    if s.present or s.assembling then
      term.setTextColor(colors.white)
      local trainLine = "  Train:   " .. (s.train or "unknown")
      if s.cars then
        trainLine = trainLine .. string.format("  [%d car%s]", s.cars, s.cars == 1 and "" or "s")
      end
      print(trainLine)

      -- Idle status
      if s.idle ~= nil then
        term.setTextColor(s.idle and colors.gray or colors.lime)
        print("  Motion:  " .. (s.idle and "idle" or "active"))
      end
    end

    -- Schedule
    if s.scheduleTotal and s.scheduleTotal > 0 then
      term.setTextColor(colors.lightGray)
      local cycMark = s.scheduleCyclic and " (cyclic)" or ""
      print(string.format("  Route:   %d stops%s", s.scheduleTotal, cycMark))
      if s.scheduleCurrent then
        term.setTextColor(colors.white)
        print("  Heading: " .. s.scheduleCurrent)
      end
      if s.scheduleNext and s.scheduleNext ~= s.scheduleCurrent then
        term.setTextColor(colors.gray)
        print("  Next:    " .. s.scheduleNext)
      end
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
