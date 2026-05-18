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
--  Power Plant B – node name mapping
--  Edit these values to match what your tank.lua / boiler.lua
--  nodes actually broadcast as their node names.
-- =========================================================
local PLANT_B = {
  name           = 'Power Plant B "The Tower"',
  netherTank1    = "nether_1_1",
  netherTank2    = "nether_1_2",
  overworldTank1 = "tank_1_1",
  overworldTank2 = "tank_1_2",
  boiler1        = "boiler_1_1",
  boiler2        = "boiler_1_2",
}

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
--  Alarm panel widget
-- =========================================================

local CRIT_PCT = 20   -- ≤ this is CRITICAL
local WARN_PCT = 50   -- < this (but > CRIT) is WARNING

local function widgetAlarms(mon, ox, y, w, budget)
  local crits = {}
  local warns  = {}

  for name, node in pairs(nodes) do
    if nodeAlive(node) and node.app == "tank" then
      local pct = node.percent or 0
      if     pct <= CRIT_PCT then
        table.insert(crits, { name = name, pct = pct })
      elseif pct <  WARN_PCT then
        table.insert(warns,  { name = name, pct = pct })
      end
    end
  end
  table.sort(crits, function(a, b) return a.pct < b.pct end)
  table.sort(warns,  function(a, b) return a.pct < b.pct end)

  local row    = 0
  local active = #crits > 0 or #warns > 0

  -- Summary line
  led(mon, ox, y, active and colors.red or colors.lime, true)
  mon.setCursorPos(ox + 2, y)
  if active then
    mon.setTextColor(colors.red)
    local s = "ALARMS"
    if #crits > 0 then s = s .. "  " .. #crits .. " CRIT" end
    if #warns  > 0 then s = s .. "  " .. #warns  .. " WARN" end
    mon.write(s)
  else
    mon.setTextColor(colors.lime)
    mon.write("All clear")
  end
  row = 1

  for _, e in ipairs(crits) do
    if row >= budget then break end
    mon.setCursorPos(ox + 2, y + row)
    mon.setTextColor(colors.red)
    mon.write(string.format("CRIT  %-12s %3d%%", shortName(e.name, 12), e.pct))
    row = row + 1
  end

  for _, e in ipairs(warns) do
    if row >= budget then break end
    mon.setCursorPos(ox + 2, y + row)
    mon.setTextColor(colors.yellow)
    mon.write(string.format("WARN  %-12s %3d%%", shortName(e.name, 12), e.pct))
    row = row + 1
  end

  return row
end

-- =========================================================
--  Main monitor
-- =========================================================

local function drawMain(mon, id, heartbeat)
  clear(mon)

  local w, h = mon.getSize()

  drawHeader(mon, id, heartbeat)

  -- Alarm panel (always visible below header)
  local alarmBudget = math.min(4, math.floor((h - 1) / 3))
  local alarmUsed   = widgetAlarms(mon, 2, 2, w, alarmBudget)

  -- Separator
  local sepY = 2 + alarmUsed
  if sepY <= h then
    mon.setCursorPos(1, sepY)
    mon.setTextColor(colors.gray)
    mon.write(("-"):rep(w))
  end

  -- Collect live nodes sorted by name for stable layout
  local live = {}
  for name, node in pairs(nodes) do
    if nodeAlive(node) then
      table.insert(live, { name = name, node = node })
    end
  end
  table.sort(live, function(a, b) return a.name < b.name end)

  local startY = sepY + 1

  if #live == 0 then
    mon.setCursorPos(3, startY)
    mon.setTextColor(colors.gray)
    mon.write("Waiting for SCADA nodes...")
    statusLine(mon, 3, startY + 2, colors.lime, "HB",  heartbeat)
    statusLine(mon, 3, startY + 4, colors.cyan, "NET", wirelessModem ~= nil)
    return
  end

  -- Distribute remaining height evenly across discovered nodes
  local contentH = h - startY + 1
  local perNode  = math.max(2, math.floor(contentH / #live))

  local y = startY
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
--  Power Plant B – SCADA topology diagram
-- =========================================================

local function drawPlantB(mon, heartbeat)
  ui.clearMon(mon)
  local w, h = mon.getSize()

  local mid  = math.floor(w / 2) + 1
  local barW = math.max(6, math.min(16, mid - 7))

  local y = 1

  -- ── Header ────────────────────────────────────────────
  led(mon, 1, y, colors.lime, heartbeat)
  mon.setTextColor(colors.orange)
  mon.setCursorPos(3, y)
  mon.write(PLANT_B.name)
  led(mon, w - 5, y, colors.cyan, wirelessModem ~= nil)
  mon.setCursorPos(w - 3, y)
  mon.setTextColor(wirelessModem and colors.white or colors.gray)
  mon.write("NET")
  y = y + 1

  -- ── Separator ─────────────────────────────────────────
  mon.setCursorPos(1, y)
  mon.setTextColor(colors.gray)
  mon.write(("-"):rep(w))
  y = y + 1

  -- Helper: draw one tank column at colX starting at row y.
  -- Renders a label row and a fill-bar row (2 rows total).
  local function drawTankCol(colX, nodeKey, label)
    local node      = nodes[nodeKey]
    local alive     = node and nodeAlive(node)
    local pct       = alive and (node.percent or 0) or 0
    local alm       = node and node.alarm
    local fillColor = (alm or pct <= 20) and colors.red
                   or (pct <= 50)        and colors.yellow
                   or colors.orange

    -- label row
    led(mon, colX, y, alive and (alm and colors.red or colors.lime) or colors.gray, alive == true)
    mon.setCursorPos(colX + 2, y)
    mon.setTextColor(colors.lightGray)
    mon.write(label)

    -- bar row
    local filled = math.floor(barW * math.min(pct, 100) / 100)
    mon.setCursorPos(colX, y + 1)
    for i = 1, barW do
      mon.setBackgroundColor(i <= filled and fillColor or colors.gray)
      mon.write(" ")
    end
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(pct <= 20 and colors.red or pct <= 50 and colors.yellow or colors.white)
    mon.write(string.format(" %3d%%", pct))
  end

  -- ── Nether source ─────────────────────────────────────
  if y <= h then
    mon.setCursorPos(3, y)
    mon.setTextColor(colors.red)
    mon.write("NETHER SOURCE")
    y = y + 1
  end
  if y + 1 <= h then
    drawTankCol(2,   PLANT_B.netherTank1, "Nether T1")
    drawTankCol(mid, PLANT_B.netherTank2, "Nether T2")
    y = y + 2
  end

  -- ── Train connector ───────────────────────────────────
  if y <= h then
    local lbl = "< LAVA TRAIN >"
    local pad = math.max(0, math.floor((w - #lbl) / 2))
    mon.setCursorPos(1, y)
    mon.setTextColor(colors.gray)
    mon.write(("-"):rep(pad))
    mon.setTextColor(colors.yellow)
    mon.write(lbl)
    mon.setTextColor(colors.gray)
    mon.write(("-"):rep(math.max(0, w - pad - #lbl)))
    y = y + 1
  end

  -- ── Overworld supply ──────────────────────────────────
  if y <= h then
    mon.setCursorPos(3, y)
    mon.setTextColor(colors.cyan)
    mon.write("OVERWORLD SUPPLY")
    y = y + 1
  end
  if y + 1 <= h then
    drawTankCol(2,   PLANT_B.overworldTank1, "OW Tank 1")
    drawTankCol(mid, PLANT_B.overworldTank2, "OW Tank 2")
    y = y + 2
  end

  -- ── Down arrows to boilers ────────────────────────────
  if y <= h then
    mon.setTextColor(colors.gray)
    mon.setCursorPos(2 + math.floor(barW / 2), y)
    mon.write("v")
    mon.setCursorPos(mid + math.floor(barW / 2), y)
    mon.write("v")
    y = y + 1
  end

  -- ── Boiler panels ─────────────────────────────────────
  local function drawBoilerPanel(colX, nodeKey, label)
    local node  = nodes[nodeKey]
    local alive = node and nodeAlive(node)
    local alm   = node and node.alarm

    led(mon, colX, y, alive and (alm and colors.red or colors.lime) or colors.gray, alive == true)
    mon.setCursorPos(colX + 2, y)
    mon.setTextColor(alm and colors.red or alive and colors.cyan or colors.gray)
    mon.write(label)

    if not alive then
      if y + 1 <= h then
        mon.setCursorPos(colX, y + 1)
        mon.setTextColor(colors.gray)
        mon.write("  offline")
      end
      return
    end

    local sc = (alm
             or node.status == "WATER_LOW")  and colors.red
            or (node.status == "WARMING"
             or node.status == "STEAM_HIGH") and colors.yellow
            or colors.lime

    if y + 1 <= h then
      mon.setCursorPos(colX, y + 1)
      mon.setTextColor(sc)
      mon.write(string.format("W:%3d%% T:%3d%%", node.waterPct or 0, node.tempPercent or 0))
    end
    if y + 2 <= h then
      mon.setCursorPos(colX, y + 2)
      mon.setTextColor(sc)
      mon.write(string.format("S:%3d%% %-8s", node.steamPct or 0, node.status or "?"))
    end
  end

  if y + 2 <= h then
    drawBoilerPanel(2,   PLANT_B.boiler1, "BOILER 1")
    drawBoilerPanel(mid, PLANT_B.boiler2, "BOILER 2")
    y = y + 3
  end

  -- ── Bottom separator ──────────────────────────────────
  if y <= h then
    mon.setCursorPos(1, y)
    mon.setTextColor(colors.gray)
    mon.write(("-"):rep(w))
    y = y + 1
  end

  -- ── Plant alarm summary ───────────────────────────────
  if y <= h then
    local plantAlarm = false
    for _, k in ipairs({ PLANT_B.netherTank1, PLANT_B.netherTank2,
                         PLANT_B.overworldTank1, PLANT_B.overworldTank2,
                         PLANT_B.boiler1, PLANT_B.boiler2 }) do
      if nodes[k] and nodes[k].alarm then plantAlarm = true; break end
    end
    led(mon, 2, y, plantAlarm and colors.red or colors.lime, true)
    mon.setCursorPos(4, y)
    if plantAlarm then
      mon.setTextColor(colors.red)
      mon.write("PLANT ALARM")
    else
      mon.setTextColor(colors.lime)
      mon.write("Plant nominal")
    end
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

      elseif msg.type == "boiler_status" then
        nodes[msg.node] = {
          app         = "boiler",
          lastSeen    = os.epoch("utc"),
          tempPercent = msg.tempPercent or 0,
          waterPct    = msg.waterPct    or 0,
          steamPct    = msg.steamPct    or 0,
          status      = msg.status      or "?",
          alarm       = msg.alarm,
        }
        addLog("boiler " .. tostring(msg.node) .. " " .. tostring(msg.status or "?"))

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
        elseif i == 3 then
          drawPlantB(mon, heartbeat)
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