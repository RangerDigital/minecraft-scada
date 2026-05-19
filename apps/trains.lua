-- =========================================================
--  Factory OS Train Station Node v2.0
--  Monitors Create: Steam 'n' Rails train stations and
--  broadcasts train_status telemetry over FactoryOS.
-- =========================================================

local CONFIG = {
  telemetryRate = 2,
}

local wireless = dofile("/lib/wireless.lua")
local ui       = dofile("/lib/ui.lua")
local util     = dofile("/lib/util.lua")
local config   = dofile("/lib/config.lua")

local PROTOCOL = config.protocol()

-- =========================================================
--  Node identity
-- =========================================================

local _cfg        = config.load("trains")
local nodeName    = _cfg.name
local nodeLabel   = _cfg.label
local nodeGroup   = _cfg.group
local factoryName = _cfg.factory_name

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
--   assembling, idle, route, presentSince, currentWaitTicks, alarm }
local stationStates = {}

-- Track UTC ms when each station's train first became present
local arrivalTimes = {}

-- =========================================================
--  Helpers
-- =========================================================

-- Safe peripheral call: returns value or nil on error
local function try(fn)
  local ok, v = pcall(fn)
  return ok and v or nil
end

-- Format ticks into a human-readable string
local function fmtTicks(ticks)
  if not ticks or ticks < 0 then return "?" end
  local secs = math.floor(ticks / 20)
  if secs < 60 then return secs .. "s" end
  local mins = math.floor(secs / 60)
  local rem  = secs % 60
  if rem == 0 then return mins .. "m" end
  return mins .. "m" .. string.format("%02d", rem) .. "s"
end

-- Extract the minimum timed wait (in ticks) from a schedule entry's conditions
local function waitTicksOf(entry)
  if type(entry.conditions) ~= "table" then return nil end
  for _, cond in ipairs(entry.conditions) do
    if type(cond) == "table" then
      local id = tostring(cond.id or "")
      local d  = type(cond.data) == "table" and cond.data or {}
      if id:find("time") or id:find("delay") then
        local v = tonumber(d.value)
        if v then
          local unit = tonumber(d.timeUnit) or 0
          if unit == 1 then v = v * 20 end    -- seconds -> ticks
          if unit == 2 then v = v * 1200 end  -- minutes -> ticks
          return math.floor(v)
        end
      end
    end
  end
  return nil
end

-- Parse a schedule table into usable fields + a route array
local function parseSchedule(sched)
  if type(sched) ~= "table" then return nil, nil, nil, nil, {} end

  local entries = type(sched.entries) == "table" and sched.entries or {}
  local total   = #entries
  if total == 0 then return nil, nil, 0, sched.cyclic, {} end

  local cur = (type(sched.currentEntry) == "number") and sched.currentEntry or 1
  cur = math.max(1, math.min(cur, total))

  local function destOf(e)
    if type(e) ~= "table" then return nil end
    -- Direct field (some versions)
    if e.destination then return e.destination end
    if e.name        then return e.name        end
    -- Create: S'n'R stores destination in instruction.data.text
    if type(e.instruction) == "table" then
      local d = e.instruction.data
      if type(d) == "table" then
        if d.text        then return d.text        end
        if d.destination then return d.destination end
        if d.name        then return d.name        end
      end
      if e.instruction.text then return e.instruction.text end
    end
    return e.id
  end

  local currentDest = destOf(entries[cur])
  local nextIdx     = (cur % total) + 1
  local nextDest    = destOf(entries[nextIdx])

  -- Build simplified route array
  local route = {}
  for i, e in ipairs(entries) do
    table.insert(route, {
      dest      = destOf(e) or "?",
      waitTicks = waitTicksOf(e),
      current   = (i == cur),
    })
  end

  return currentDest, nextDest, total, sched.cyclic, route
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

    -- Track arrival time
    local key = s.name
    if present and not arrivalTimes[key] then
      arrivalTimes[key] = os.epoch("utc")
    elseif not present and not assembling then
      arrivalTimes[key] = nil
    end
    local presentSince = present and arrivalTimes[key] or nil

    -- Train info (only meaningful when present)
    local trainName, cars, idle
    if present or assembling then
      trainName = try(function() return s.p.getTrainName() end)
      cars      = try(function() return s.p.getCarCount()  end)
      if not cars then
        local carList = try(function() return s.p.getTrainCars() end)
        if type(carList) == "table" then cars = #carList end
      end
      idle = try(function() return s.p.isCurrentlyIdle() end) == true
    end

    -- Schedule + route
    local schedRaw = try(function() return s.p.getSchedule() end)
    local sCur, sNext, sTotal, sCyclic, route = parseSchedule(schedRaw)

    -- Wait condition at the current schedule stop
    local currentWaitTicks = nil
    if route then
      for _, r in ipairs(route) do
        if r.current then currentWaitTicks = r.waitTicks; break end
      end
    end

    table.insert(newStates, {
      name             = s.name,
      stationName      = stationName,
      present          = present,
      assembling       = assembling,
      train            = trainName,
      cars             = cars,
      idle             = idle,
      scheduleCurrent  = sCur,
      scheduleNext     = sNext,
      scheduleTotal    = sTotal,
      scheduleCyclic   = sCyclic,
      route            = route,
      presentSince     = presentSince,
      currentWaitTicks = currentWaitTicks,
      alarm            = false,
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
      station          = s.stationName,
      present          = s.present,
      train            = s.train,
      cars             = s.cars,
      assembling       = s.assembling,
      idle             = s.idle,
      scheduleCurrent  = s.scheduleCurrent,
      scheduleNext     = s.scheduleNext,
      scheduleTotal    = s.scheduleTotal,
      scheduleCyclic   = s.scheduleCyclic,
      route            = s.route,
      presentSince     = s.presentSince,
      currentWaitTicks = s.currentWaitTicks,
      alarm            = s.alarm,
      heartbeat        = os.epoch("utc"),
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

local function drawTerminal()
  local W = term.getSize()
  ui.nodeHeader("trains", nodeLabel, nodeGroup, factoryName, wirelessSide ~= nil)
  ledTerm(anyAlarm() and colors.red or colors.gray,
    "Alarm:  " .. (anyAlarm() and "ACTIVE" or "none"))
  ledTerm(colors.lightGray, "Stations: " .. #stations)
  ledTerm(colors.lime, "HB:     " .. (heartbeat and "●" or "○"))
  term.setTextColor(colors.gray)
  print(("-"):rep(W))

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
      -- Full route list
      if type(s.route) == "table" then
        for _, r in ipairs(s.route) do
          if r.current then
            term.setTextColor(colors.lime)
            term.write("  \16 " .. r.dest)
          else
            term.setTextColor(colors.gray)
            term.write("    " .. r.dest)
          end
          if r.waitTicks then
            term.setTextColor(colors.gray)
            term.write("  [" .. fmtTicks(r.waitTicks) .. "]")
          end
          print("")
        end
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
