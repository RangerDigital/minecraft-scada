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

-- =========================================================
--  Node identity
-- =========================================================

local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  local v = f.readAll()
  f.close()
  return v:gsub("%s+$", "")
end

local nodeName =
  readFile("/config/node_name.txt")
  or os.getComputerLabel()
  or ("tank_" .. os.getComputerID())

-- =========================================================
--  Peripheral discovery
-- =========================================================

local wirelessSide = nil

for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "modem" then
    local m = peripheral.wrap(side)
    local ok, wireless = pcall(function()
      return m.isWireless()
    end)

    if ok and wireless then
      wirelessSide = side
      break
    end
  end
end

if wirelessSide then
  rednet.open(wirelessSide)
end

local tank = nil
local tankName = nil

for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)

  if type(p.tanks) == "function" then
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

local function ledTerm(color, text)
  term.setBackgroundColor(color)
  write(" ")
  term.setBackgroundColor(colors.black)
  write(" ")
  term.setTextColor(colors.lightGray)
  print(text)
end

local function resetTerm()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
end

local function led(mon, x, y, color, on)
  mon.setCursorPos(x, y)
  mon.setBackgroundColor(on and color or colors.gray)
  mon.write(" ")
  mon.setBackgroundColor(colors.black)
end

local function statusLine(mon, y, color, text, on)
  led(mon, 2, y, color, on)
  mon.setCursorPos(4, y)
  mon.setTextColor(colors.lightGray)
  mon.write(text)
end

local function drawMonitorStatus(mon, heartbeat, alarm)
  mon.setTextScale(0.5)
  mon.setBackgroundColor(colors.black)
  mon.clear()

  statusLine(mon, 1, colors.lime, "HB", heartbeat)
  statusLine(mon, 3, colors.cyan, "NET", wirelessSide ~= nil)
  statusLine(mon, 5, colors.red, "ALARM", alarm)
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

local function readTank()
  if not tank then
    state.fluid = "NO_TANK"
    state.amount = 0
    state.capacity = CONFIG.capacityFallback
    state.percent = 0
    state.level = "ALARM"
    state.alarm = true
    return
  end

  local ok, tanks = pcall(function()
    return tank.tanks()
  end)

  if not ok or type(tanks) ~= "table" then
    state.fluid = "READ_ERROR"
    state.amount = 0
    state.capacity = CONFIG.capacityFallback
    state.percent = 0
    state.level = "ALARM"
    state.alarm = true
    return
  end

  local totalAmount = 0
  local totalCapacity = 0
  local fluidName = "empty"

  for _, t in pairs(tanks) do
    if type(t) == "table" then
      local amount = t.amount or 0
      local capacity = t.capacity or CONFIG.capacityFallback

      totalAmount = totalAmount + amount
      totalCapacity = totalCapacity + capacity

      if t.name then
        fluidName = t.name
      end
    end
  end

  if totalCapacity <= 0 then
    totalCapacity = CONFIG.capacityFallback
  end

  local percent = math.floor((totalAmount / totalCapacity) * 100)

  state.fluid = fluidName
  state.amount = totalAmount
  state.capacity = totalCapacity
  state.percent = percent

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

local function shortFluid(name)
  return tostring(name):gsub("minecraft:", ""):gsub("create:", ""):sub(1, 18)
end

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
  print("Modem: " .. tostring(wirelessSide))
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
        local w, h = mon.getSize()

        if w <= 12 and h <= 8 then
          drawMonitorStatus(mon, heartbeat, state.alarm)
        end
      end)
    end

    sleep(0.5)
  end
end

parallel.waitForAny(
  telemetryLoop,
  uiLoop
)