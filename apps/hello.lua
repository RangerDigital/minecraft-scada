-- =========================================================
--  Factory OS SCADA Monitor v2.0
-- =========================================================

local PROTOCOL = "factoryos"

local wireless = dofile("/lib/wireless.lua")
local ui       = dofile("/lib/ui.lua")
local util     = dofile("/lib/util.lua")

local monitors = { peripheral.find("monitor") }

local wirelessModem = wireless.find()

local nodes  = {}
local alarms = {}
local logs   = {}

-- =========================================================
--  Helpers
-- =========================================================

local function addLog(text)
  table.insert(logs, 1, text)
  while #logs > 30 do table.remove(logs) end
end

local function addAlarm(text)
  table.insert(alarms, 1, text)
  while #alarms > 20 do table.remove(alarms) end
end

local clear      = ui.clearMon
local led        = ui.led
local statusLine = ui.statusLine

local function nodeAlive(node)
  return (os.epoch("utc") - node.lastSeen) < 6000
end

local function alarmActive()
  for _, node in pairs(nodes) do
    if node.alarm and nodeAlive(node) then return true end
  end
  return #alarms > 0
end

local shortName = util.shortName

-- =========================================================
--  Monitor classification
--    "tiny"   - 1×1 block status monitor
--    "ticker" - single character-row wide banner (h == 1)
--    "main"   - normal large display
-- =========================================================

local function classifyMonitor(w, h)
  if h == 1 and w > 5 then return "ticker" end
  if w <= 15 and h <= 10 then return "tiny" end
  return "main"
end

-- =========================================================
--  Tiny monitor (1×1 block) – status LEDs, no header
-- =========================================================

local function drawTiny(mon, heartbeat)
  clear(mon)
  local _, h = mon.getSize()
  -- Distribute 3 LED rows with spacing, with top padding
  local step = math.max(1, math.min(2, math.floor((h - 1) / 3)))
  local top  = 2
  statusLine(mon, 2, top,          colors.lime, "HB",    heartbeat)
  statusLine(mon, 2, top + step,   colors.cyan, "NET",   wirelessModem ~= nil)
  statusLine(mon, 2, top + step*2,
    alarmActive() and colors.red or colors.gray, "ALARM", alarmActive())
end

-- =========================================================
--  Ticker (h == 1, wide) – scrolling logs / alarms
-- =========================================================

local tickerScroll = 0

local function drawTicker(mon, heartbeat)
  local w = mon.getSize()

  local source
  if #alarms > 0 then
    source = "  ALARMS: " .. table.concat(alarms, "  |  ")
  elseif #logs > 0 then
    source = "  LOGS: " .. table.concat(logs, "  |  ")
  else
    source = "  Factory OS SCADA online  "
  end

  source = source .. "   "

  tickerScroll = tickerScroll + 1
  if tickerScroll > #source then tickerScroll = 1 end

  local text = source:sub(tickerScroll) .. source:sub(1, tickerScroll - 1)

  mon.setBackgroundColor(colors.black)
  mon.setTextColor(#alarms > 0 and colors.red or colors.orange)
  mon.setCursorPos(1, 1)
  mon.write(text:sub(1, w - 1))

  led(mon, w, 1, colors.lime, heartbeat)
end

-- =========================================================
--  Logs / alarms board (monitor 2)
-- =========================================================

local function drawLogs(mon, heartbeat)
  clear(mon)
  local w, h = mon.getSize()

  -- Header - heartbeat LED + title, no background fill
  led(mon, 1, 1, colors.lime, heartbeat)
  mon.setTextColor(colors.red)
  mon.setCursorPos(3, 1)
  mon.write("ALARMS & LOGS")

  local y = 2

  for _, alarm in ipairs(alarms) do
    if y > h then break end
    mon.setCursorPos(1, y)
    mon.setTextColor(colors.red)
    mon.write(("! " .. alarm):sub(1, w))
    y = y + 1
  end

  if #alarms > 0 and #logs > 0 and y <= h then
    mon.setCursorPos(1, y)
    mon.setTextColor(colors.gray)
    mon.write(("-"):rep(w))
    y = y + 1
  end

  for _, entry in ipairs(logs) do
    if y > h then break end
    mon.setCursorPos(1, y)
    mon.setTextColor(colors.gray)
    mon.write(("  " .. entry):sub(1, w))
    y = y + 1
  end

  if y == 2 then
    mon.setCursorPos(2, 2)
    mon.setTextColor(colors.lime)
    mon.write("All clear")
  end
end

-- =========================================================
--  Header bar
-- =========================================================

local function drawHeader(mon, id, heartbeat)
  local w, h = mon.getSize()

  mon.setBackgroundColor(colors.black)

  -- Heartbeat LED blinks green
  led(mon, 1, 1, colors.lime, heartbeat)

  -- "Factory OS" in orange
  mon.setTextColor(colors.orange)
  mon.setCursorPos(3, 1)
  mon.write("Factory OS")

  -- Monitor number and size in gray, right-aligned
  local info = "#" .. id .. " " .. w .. "x" .. h
  if w >= #info + 4 then
    mon.setTextColor(colors.gray)
    mon.setCursorPos(w - #info + 1, 1)
    mon.write(info)
  end
end

-- =========================================================
--  Widgets
-- =========================================================

local function widgetStorage(mon, name, node, ox, y, w, budget)
  led(mon, ox, y, nodeAlive(node) and colors.lime or colors.red, true)
  mon.setCursorPos(ox + 2, y)
  mon.setTextColor(colors.cyan)
  mon.write(shortName(name) .. " [storage]")

  local rows = 1

  if node.items then
    for _, item in ipairs(node.items) do
      if rows >= budget then break end
      mon.setCursorPos(ox + 2, y + rows)
      mon.setTextColor(item.overflow > 0 and colors.red or colors.lime)
      mon.write(string.format(
        "%-12s %5d/%-5d %+d",
        shortName(item.item),
        item.current  or 0,
        item.limit    or 0,
        item.overflow or 0
      ))
      rows = rows + 1
    end
  end

  return rows
end

local function widgetTank(mon, name, node, ox, y, w, budget)
  local pct = node.percent or 0

  led(mon, ox, y, nodeAlive(node) and colors.lime or colors.red, true)
  mon.setCursorPos(ox + 2, y)

  if node.alarm then
    mon.setTextColor(colors.red)
  elseif pct < 50 then
    mon.setTextColor(colors.yellow)
  else
    mon.setTextColor(colors.lime)
  end

  mon.write(string.format(
    "%-14s %3d%%  %-11s",
    shortName(node.fluid or "empty"),
    pct,
    node.level or "?"
  ))

  if budget < 2 then return 1 end

  -- Fill bar
  local barW   = math.min(w - ox - 2, 24)
  local filled = math.floor(barW * math.min(pct, 100) / 100)
  local barColor = node.alarm and colors.red
    or (pct < 50 and colors.yellow or colors.lime)

  mon.setCursorPos(ox + 2, y + 1)
  for i = 1, barW do
    mon.setBackgroundColor(i <= filled and barColor or colors.gray)
    mon.write(" ")
  end
  mon.setBackgroundColor(colors.black)

  return 2
end

-- =========================================================
--  Main monitor
-- =========================================================

local function drawMain(mon, id, heartbeat)
  clear(mon)

  local w, h = mon.getSize()

  drawHeader(mon, id, heartbeat)

  -- Collect live nodes sorted by name for stable layout
  local live = {}
  for name, node in pairs(nodes) do
    if nodeAlive(node) then
      table.insert(live, { name = name, node = node })
    end
  end
  table.sort(live, function(a, b) return a.name < b.name end)

  if #live == 0 then
    mon.setCursorPos(3, 3)
    mon.setTextColor(colors.gray)
    mon.write("Waiting for SCADA nodes...")
    statusLine(mon, 3, 5, colors.lime, "HB",    heartbeat)
    statusLine(mon, 3, 7, colors.cyan, "NET",   wirelessModem ~= nil)
    statusLine(mon, 3, 9,
      alarmActive() and colors.red or colors.gray, "ALARM", alarmActive())
    return
  end

  -- Distribute available height evenly across discovered nodes
  local contentH = h - 2
  local perNode  = math.max(2, math.floor(contentH / #live))

  local y = 3
  for _, entry in ipairs(live) do
    if y > h then break end

    local budget = math.min(perNode, h - y + 1)
    local used

    if entry.node.app == "storage" then
      used = widgetStorage(mon, entry.name, entry.node, 2, y, w, budget)
    elseif entry.node.app == "tank" then
      used = widgetTank(mon, entry.name, entry.node, 2, y, w, budget)
    else
      led(mon, 2, y, nodeAlive(entry.node) and colors.lime or colors.gray, true)
      mon.setCursorPos(4, y)
      mon.setTextColor(colors.lightGray)
      mon.write(shortName(entry.name) .. " [" .. tostring(entry.node.app or "?") .. "]")
      used = 1
    end

    y = y + used + 1
  end
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
          app          = "storage",
          lastSeen     = os.epoch("utc"),
          items        = msg.items or {},
          latestExport = msg.latestExport or "none",
          alarm        = false,
        }
        addLog("storage " .. tostring(msg.node) .. " updated")

      elseif msg.type == "tank_status" then
        nodes[msg.node] = {
          app      = "tank",
          lastSeen = os.epoch("utc"),
          fluid    = msg.fluid,
          amount   = msg.amount,
          capacity = msg.capacity,
          percent  = msg.percent or 0,
          level    = msg.level,
          alarm    = msg.alarm,
        }
        addLog("tank " .. tostring(msg.node) .. " " .. tostring(msg.percent) .. "%")

      elseif msg.type == "alarm" then
        addAlarm(tostring(msg.node) .. ": " .. tostring(msg.message))
      end
    end
  end
end

-- =========================================================
--  UI
-- =========================================================

for _, mon in ipairs(monitors) do
  pcall(function() mon.setTextScale(0.5) end)
end

local function uiLoop()
  local heartbeat = false

  while true do
    heartbeat = not heartbeat

    for i, mon in ipairs(monitors) do
      pcall(function()
        local w, h = mon.getSize()
        local kind  = classifyMonitor(w, h)

        if kind == "ticker" then
          drawTicker(mon, heartbeat)
        elseif kind == "tiny" then
          drawTiny(mon, heartbeat)
        elseif i == 2 then
          drawLogs(mon, heartbeat)
        else
          drawMain(mon, i, heartbeat)
        end
      end)
    end

    sleep(0.5)
  end
end

addLog("SCADA booted")

parallel.waitForAny(networkLoop, uiLoop)