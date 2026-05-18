-- =========================================================
--  Factory OS SCADA v1.7
-- =========================================================

local PROTOCOL = "factoryos"

local monitors = { peripheral.find("monitor") }

local wirelessSide = nil

for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "modem" then
    local modem = peripheral.wrap(side)

    local ok, wireless = pcall(function()
      return modem.isWireless()
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

local nodes = {}
local alarms = {}
local logs = {}

-- =========================================================
--  Helpers
-- =========================================================

local function addLog(text)
  table.insert(logs, 1, text)

  while #logs > 20 do
    table.remove(logs)
  end
end

local function addAlarm(text)
  table.insert(alarms, 1, text)

  while #alarms > 10 do
    table.remove(alarms)
  end
end

local function clear(mon)
  mon.setBackgroundColor(colors.black)
  mon.clear()
  mon.setCursorPos(1,1)
end

local function led(mon, x, y, color, on)
  mon.setCursorPos(x, y)
  mon.setBackgroundColor(on and color or colors.gray)
  mon.write(" ")
  mon.setBackgroundColor(colors.black)
end

local function header(mon, id, heartbeat)
  local w, h = mon.getSize()

  paintutils.drawFilledBox(1, 1, w, 1, colors.orange)

  mon.setTextColor(colors.black)
  mon.setCursorPos(2,1)
  mon.write("Factory OS SCADA")

  local info = "#" .. id .. " " .. w .. "x" .. h

  if w > #info + 18 then
    mon.setCursorPos(w - #info - 2, 1)
    mon.write(info)
  end

  led(mon, w, 1, colors.lime, heartbeat)
end

local function statusLine(mon, y, color, text, on)
  led(mon, 3, y, color, on)
  mon.setCursorPos(5, y)
  mon.setTextColor(colors.lightGray)
  mon.write(text)
end

local function nodeAlive(node)
  return (os.epoch("utc") - node.lastSeen) < 6000
end

local function nodeCount()
  local count = 0

  for _, node in pairs(nodes) do
    if nodeAlive(node) then
      count = count + 1
    end
  end

  return count
end

local function alarmActive()
  for _, node in pairs(nodes) do
    if node.alarm and nodeAlive(node) then
      return true
    end
  end

  return #alarms > 0
end

local function shortName(name)
  return tostring(name)
    :gsub("minecraft:", "")
    :gsub("create:", "")
    :sub(1, 14)
end

-- =========================================================
--  Wide 1-line alarm/log monitor
-- =========================================================

local scroll = 0

local function drawTicker(mon, id, heartbeat)
  clear(mon)

  local w, h = mon.getSize()

  local source = ""

  if #alarms > 0 then
    source = " ALARMS: " .. table.concat(alarms, "  |  ")
  else
    source = " LOGS: " .. table.concat(logs, "  |  ")
  end

  if source == "" then
    source = " Factory OS SCADA online "
  end

  source = source .. "     "

  scroll = scroll + 1
  if scroll > #source then scroll = 1 end

  local text = source:sub(scroll) .. source:sub(1, scroll)

  mon.setTextColor(#alarms > 0 and colors.red or colors.orange)
  mon.setCursorPos(1,1)
  mon.write(text:sub(1,w))

  led(mon, w, 1, colors.lime, heartbeat)
end

-- =========================================================
--  Main screens
-- =========================================================

local function drawMain(mon, heartbeat, id)
  clear(mon)

  local w, h = mon.getSize()

  header(mon, id, heartbeat)

  statusLine(mon, 3, colors.lime, "HB", heartbeat)
  statusLine(mon, 5, wirelessSide and colors.cyan or colors.red, "NET", wirelessSide ~= nil)
  statusLine(mon, 7, alarmActive() and colors.red or colors.gray, "ALARM", alarmActive())

  mon.setTextColor(colors.gray)
  mon.setCursorPos(3,9)
  mon.write("Modem: " .. tostring(wirelessSide))

  mon.setTextColor(colors.cyan)
  mon.setCursorPos(3,12)
  mon.write("Network Nodes")

  local y = 14

  for name, node in pairs(nodes) do
    local alive = nodeAlive(node)

    led(mon, 3, y, alive and colors.lime or colors.red, true)

    mon.setCursorPos(5, y)
    mon.setTextColor(colors.white)
    mon.write(name .. " [" .. tostring(node.app or "?") .. "]")

    y = y + 1

    if node.app == "storage" and node.items then
      for _, item in ipairs(node.items) do
        if y > h then return end

        mon.setCursorPos(7, y)

        if item.overflow > 0 then
          mon.setTextColor(colors.red)
        else
          mon.setTextColor(colors.lime)
        end

        mon.write(string.format(
          "%-12s %5d/%-5d %+d",
          shortName(item.item),
          item.current or 0,
          item.limit or 0,
          item.overflow or 0
        ))

        y = y + 1
      end
    end

    if node.app == "tank" then
      if y > h then return end

      mon.setCursorPos(7, y)

      if node.alarm then
        mon.setTextColor(colors.red)
      elseif node.percent < 50 then
        mon.setTextColor(colors.yellow)
      else
        mon.setTextColor(colors.lime)
      end

      mon.write(string.format(
        "%-12s %3d%% %s",
        shortName(node.fluid),
        node.percent or 0,
        node.level or "?"
      ))

      y = y + 1
    end

    y = y + 1

    if y > h then return end
  end
end

-- =========================================================
--  Status-only small monitor
-- =========================================================

local function drawStatusOnly(mon, heartbeat, id)
  clear(mon)

  statusLine(mon, 1, colors.lime, "HB", heartbeat)
  statusLine(mon, 3, wirelessSide and colors.cyan or colors.red, "NET", wirelessSide ~= nil)
  statusLine(mon, 5, alarmActive() and colors.red or colors.gray, "ALARM", alarmActive())

  mon.setCursorPos(5,7)
  mon.setTextColor(colors.orange)
  mon.write("NODES " .. nodeCount())
end

-- =========================================================
--  Network
-- =========================================================

local function networkLoop()
  while true do
    local _, msg = rednet.receive(PROTOCOL)

    if type(msg) == "table" then
      if msg.type == "storage_status" then
        nodes[msg.node] = {
          app = "storage",
          lastSeen = os.epoch("utc"),
          items = msg.items or {},
          latestExport = msg.latestExport or "none",
          alarm = false
        }

        addLog("storage " .. tostring(msg.node) .. " update")
      end

      if msg.type == "tank_status" then
        nodes[msg.node] = {
          app = "tank",
          lastSeen = os.epoch("utc"),
          tank = msg.tank,
          fluid = msg.fluid,
          amount = msg.amount,
          capacity = msg.capacity,
          percent = msg.percent or 0,
          level = msg.level,
          alarm = msg.alarm
        }

        addLog("tank " .. tostring(msg.node) .. " " .. tostring(msg.percent) .. "%")
      end

      if msg.type == "alarm" then
        addAlarm(tostring(msg.node) .. ": " .. tostring(msg.message))
      end
    end
  end
end

-- =========================================================
--  UI
-- =========================================================

for _, mon in ipairs(monitors) do
  pcall(function()
    mon.setTextScale(0.5)
  end)
end

local function uiLoop()
  local heartbeat = false

  while true do
    heartbeat = not heartbeat

    for i, mon in ipairs(monitors) do
      pcall(function()
        local w, h = mon.getSize()

        if w > 12 and h == 1 then
          drawTicker(mon, i, heartbeat)
        elseif i == 4 or (w <= 12 and h <= 8) then
          drawStatusOnly(mon, heartbeat, i)
        else
          drawMain(mon, heartbeat, i)
        end
      end)
    end

    sleep(0.5)
  end
end

addLog("SCADA booted")

parallel.waitForAny(
  networkLoop,
  uiLoop
)