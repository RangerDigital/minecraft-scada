-- =========================================================
--  Factory OS Supervisor v2.0
-- =========================================================

local wireless = dofile("/lib/wireless.lua")
local ui       = dofile("/lib/ui.lua")
local util     = dofile("/lib/util.lua")
local config   = dofile("/lib/config.lua")

local PROTOCOL = config.protocol()

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

  local hasAlarms = #alarms > 0

  -- Header: red background fill when alarms present, orange title otherwise
  mon.setCursorPos(1, 1)
  if hasAlarms then
    mon.setBackgroundColor(colors.red)
    mon.setTextColor(colors.white)
    local hdr = "  ! ALARMS & LOGS"
    mon.write(hdr:sub(1, w) .. (" "):rep(math.max(0, w - #hdr)))
    mon.setBackgroundColor(colors.black)
  else
    led(mon, 1, 1, heartbeat and colors.lime or colors.gray, heartbeat)
    mon.setTextColor(colors.orange)
    mon.setCursorPos(3, 1)
    mon.write("ALARMS & LOGS")
  end

  local y = 2

  for _, alarm in ipairs(alarms) do
    if y > h then break end
    mon.setCursorPos(1, y)
    mon.setBackgroundColor(colors.red)
    mon.setTextColor(colors.white)
    local line = ("  ! " .. alarm):sub(1, w)
    mon.write(line .. (" "):rep(math.max(0, w - #line)))
    mon.setBackgroundColor(colors.black)
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
--  Helpers
-- =========================================================

local function fmtTicks(ticks)
  if not ticks or ticks < 0 then return "?" end
  local secs = math.floor(ticks / 20)
  if secs < 60 then return secs .. "s" end
  local mins = math.floor(secs / 60)
  local rem  = secs % 60
  if rem == 0 then return mins .. "m" end
  return mins .. "m" .. string.format("%02d", rem) .. "s"
end

-- =========================================================
--  Widgets
-- =========================================================

local function widgetStorage(mon, name, node, ox, y, w, budget)
  local avail = w - ox - 1
  led(mon, ox, y, nodeAlive(node) and colors.lime or colors.red, true)
  mon.setCursorPos(ox + 2, y)
  mon.setTextColor(colors.cyan)
  mon.write(shortName(node.label or name, avail))

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
  local pct  = node.percent or 0
  local lblW = math.max(16, w - ox - 20)   -- leave room for " NNN%  LEVEL_STR"
  local lbl  = shortName(node.label or name, lblW)

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
    "%-" .. lblW .. "s %3d%%  %-8s",
    lbl,
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

  if budget < 3 then return 2 end

  -- Trend row: show rate of change if significant
  local trend = node.trend or 0
  local absT  = math.abs(trend)
  if absT > 5 then
    local arrow  = trend > 0 and "\30" or "\31"   -- ▲ / ▼ (CC:Tweaked CP437)
    local tColor = trend > 0 and colors.lime or colors.red
    local tStr
    if absT >= 1000 then
      tStr = string.format("%.1fk mB/s", absT / 1000)
    else
      tStr = math.floor(absT) .. " mB/s"
    end
    mon.setCursorPos(ox + 2, y + 2)
    mon.setTextColor(tColor)
    mon.write(arrow .. " " .. tStr)
    return 3
  end

  return 2
end

-- Format stress/capacity SU values compactly: 45000 → "45k"
local function fmtSU(n)
  n = math.floor(n or 0)
  if n >= 10000 then return math.floor(n / 1000) .. "k"
  elseif n >= 1000 then return string.format("%.1fk", n / 1000)
  else return tostring(n)
  end
end

local function widgetPower(mon, name, node, ox, y, w, budget)
  local alive  = nodeAlive(node)
  local pct    = node.percent or 0

  local barColor = node.alarm       and colors.red
               or pct >= 75         and colors.yellow
               or                       colors.lime

  -- Row 1: LED  label  percent  stress/capacity (compact)
  local suStr = fmtSU(node.stress) .. "/" .. fmtSU(node.capacity) .. " SU"
  local lblW  = math.max(8, w - ox - 2 - 7 - #suStr)
  local lbl   = shortName(node.label or name, lblW)

  led(mon, ox, y, alive and barColor or colors.red, true)
  mon.setCursorPos(ox + 2, y)
  mon.setTextColor(alive and barColor or colors.red)
  mon.write(string.format(
    "%-" .. lblW .. "s %3d%%  %s",
    lbl, pct, suStr
  ))

  local row = 1
  if budget < 2 then return row end

  -- Row 2: fill bar
  local barW   = math.min(w - ox - 2, 24)
  local filled = math.floor(barW * math.min(pct, 100) / 100)

  mon.setCursorPos(ox + 2, y + row)
  for i = 1, barW do
    mon.setBackgroundColor(i <= filled and barColor or colors.gray)
    mon.write(" ")
  end
  mon.setBackgroundColor(colors.black)
  row = row + 1

  -- Row 3+: speedometer readings (named "Spd 1", "Spd 2", ...)
  local speeds = node.speeds or {}
  for i, s in ipairs(speeds) do
    if row >= budget then break end
    mon.setCursorPos(ox + 2, y + row)
    local sLabel  = "Spd " .. i
    local rpmStr  = math.abs(s.rpm or 0) .. " RPM"
    local sColor  = s.rpm ~= 0 and colors.lightGray or colors.gray
    mon.setTextColor(sColor)
    mon.write(sLabel)
    mon.setCursorPos(w - #rpmStr, y + row)
    mon.setTextColor(colors.gray)
    mon.write(rpmStr)
    row = row + 1
  end

  return row
end

local function widgetTrain(mon, name, node, ox, y, w, budget)
  local alive = nodeAlive(node)
  local lblW  = math.max(14, w - ox - 16)
  local lbl   = shortName(node.label or name, lblW)

  local sc = not alive        and colors.red
          or node.assembling   and colors.yellow
          or node.present      and colors.lime
          or                       colors.gray

  -- Row 1: LED  label  station  status
  led(mon, ox, y, sc, true)
  mon.setCursorPos(ox + 2, y)
  mon.setTextColor(sc)
  local statusStr = not alive       and "OFFLINE"
                 or node.assembling  and "ASSEMBLING"
                 or node.present     and "PRESENT"
                 or                      "empty"
  -- Show: label [station]  STATUS  (station name in brackets when we have it)
  local stationSuffix = node.station and (" [" .. shortName(node.station, 12) .. "]") or ""
  local leftStr = shortName(node.label or name, lblW - #stationSuffix) .. stationSuffix
  mon.write(string.format("%-" .. lblW .. "s  %s", leftStr, statusStr))

  local row = 1
  if budget < 2 then return row end

  -- Row 2: train name + cars + dwell time + departure estimate
  mon.setCursorPos(ox + 2, y + row)
  if node.present or node.assembling then
    local parts = { shortName(node.train or "?", 14) }
    if node.cars then
      table.insert(parts, "[" .. node.cars .. "c]")
    end
    if node.presentSince then
      local dwellTicks = math.floor((os.epoch("utc") - node.presentSince) / 50)
      table.insert(parts, "at:" .. fmtTicks(dwellTicks))
      if node.currentWaitTicks then
        local rem = node.currentWaitTicks - dwellTicks
        if rem > 20 then
          table.insert(parts, "dep:~" .. fmtTicks(rem))
        else
          table.insert(parts, "dep:overdue")
        end
      end
    end
    mon.setTextColor(colors.lightGray)
    mon.write(table.concat(parts, "  "):sub(1, w - ox - 2))
  else
    if node.station then
      mon.setTextColor(colors.gray)
      mon.write(shortName(node.station, w - ox - 2))
    end
  end
  row = row + 1

  -- Route rows: one line per stop
  local route = node.route
  if type(route) ~= "table" or #route == 0 then return row end

  for _, stop in ipairs(route) do
    if row >= budget then break end
    mon.setCursorPos(ox + 2, y + row)

    if stop.current then
      mon.setTextColor(colors.lime)
      mon.write("\16 ")   -- ► current stop indicator
    else
      mon.setTextColor(colors.gray)
      mon.write("  ")
    end

    local destStr = shortName(stop.dest or "?", w - ox - 12)
    mon.setTextColor(stop.current and colors.white or colors.gray)
    mon.write(destStr)

    -- Wait time right-aligned on same row
    if stop.waitTicks then
      local wStr = fmtTicks(stop.waitTicks)
      local col  = w - #wStr
      if col > ox + 4 + #destStr then
        mon.setCursorPos(col, y + row)
        mon.setTextColor(colors.gray)
        mon.write(wStr)
      end
    end

    row = row + 1
  end

  return row
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
    if nodeAlive(node) then
      if node.app == "tank" then
        local pct   = node.percent or 0
        local lbl   = node.label or name
        local fluid = node.fluid and shortName(node.fluid, 10) or nil
        if pct <= CRIT_PCT then
          table.insert(crits, { label = lbl, pct = pct, extra = fluid })
        elseif pct < WARN_PCT then
          table.insert(warns,  { label = lbl, pct = pct })
        end
      elseif node.alarm then
        -- Non-tank node with an active alarm flag
        table.insert(crits, { label = node.label or name, pct = nil, extra = node.app })
      end
    end
  end

  -- Merge log-level alarm messages into the crit list
  for _, a in ipairs(alarms) do
    table.insert(crits, { label = a, pct = nil, isMsg = true })
  end

  table.sort(crits, function(a, b) return (a.pct or -1) < (b.pct or -1) end)
  table.sort(warns,  function(a, b) return a.pct < b.pct end)

  local active = #crits > 0 or #warns > 0
  local lblW   = math.max(8, w - 14)

  -- Summary header row (full-width background)
  if active then
    mon.setCursorPos(1, y)
    mon.setBackgroundColor(colors.red)
    mon.setTextColor(colors.white)
    local s = "  ALARMS"
    if #crits > 0 then s = s .. "  " .. #crits .. " CRIT" end
    if #warns  > 0 then s = s .. "  " .. #warns  .. " WARN" end
    mon.write(s:sub(1, w) .. (" "):rep(math.max(0, w - #s)))
    mon.setBackgroundColor(colors.black)
  else
    led(mon, ox, y, colors.lime, true)
    mon.setCursorPos(ox + 2, y)
    mon.setTextColor(colors.lime)
    mon.write("All clear")
  end

  local row = 1

  for _, e in ipairs(crits) do
    if row >= budget then break end
    mon.setCursorPos(1, y + row)
    if e.isMsg then
      mon.setBackgroundColor(colors.black)
      mon.setTextColor(colors.red)
      mon.write(("  ! " .. e.label):sub(1, w))
    else
      mon.setBackgroundColor(colors.red)
      mon.setTextColor(colors.white)
      local pctStr = e.pct   and string.format(" %3d%%", e.pct) or " ALRM"
      local lbl    = shortName(e.label, lblW)
      local s      = string.format("  CRIT  %-" .. lblW .. "s%s", lbl, pctStr)
      mon.write(s:sub(1, w) .. (" "):rep(math.max(0, w - math.min(w, #s))))
      mon.setBackgroundColor(colors.black)
    end
    row = row + 1
  end

  for _, e in ipairs(warns) do
    if row >= budget then break end
    mon.setCursorPos(1, y + row)
    mon.setBackgroundColor(colors.yellow)
    mon.setTextColor(colors.black)
    local lbl = shortName(e.label, lblW)
    local s   = string.format("  WARN  %-" .. lblW .. "s %3d%%", lbl, e.pct)
    mon.write(s:sub(1, w) .. (" "):rep(math.max(0, w - math.min(w, #s))))
    mon.setBackgroundColor(colors.black)
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

  -- Collect live nodes, grouped by node.group
  local groups   = {}
  local ordering = {}
  local totalLive = 0

  for name, node in pairs(nodes) do
    if nodeAlive(node) then
      local g = node.group or ""
      if not groups[g] then
        groups[g] = {}
        table.insert(ordering, g)
      end
      table.insert(groups[g], { name = name, node = node })
      totalLive = totalLive + 1
    end
  end

  -- Named groups first (alphabetical), ungrouped last
  table.sort(ordering, function(a, b)
    if a == "" then return false end
    if b == "" then return true  end
    return a < b
  end)

  -- Sort entries within each group by label
  for _, g in ipairs(ordering) do
    table.sort(groups[g], function(a, b)
      return (a.node.label or a.name) < (b.node.label or b.name)
    end)
  end

  local startY = sepY + 1

  if totalLive == 0 then
    mon.setCursorPos(3, startY)
    mon.setTextColor(colors.gray)
    mon.write("Waiting for SCADA nodes...")
    statusLine(mon, 3, startY + 2, colors.lime, "HB",  heartbeat)
    statusLine(mon, 3, startY + 4, colors.cyan, "NET", wirelessModem ~= nil)
    return
  end

  local contentH = h - startY + 1
  local perNode  = math.max(2, math.floor(contentH / totalLive))

  local y = startY
  for _, g in ipairs(ordering) do
    local entries = groups[g]

    -- Group header for named groups
    if g ~= "" and y <= h then
      mon.setCursorPos(1, y)
      mon.setTextColor(colors.orange)
      local hdr = "- " .. g .. " "
      mon.write(hdr .. ("-"):rep(math.max(0, w - #hdr)))
      y = y + 1
    end

    for _, entry in ipairs(entries) do
      if y > h then break end
      local budget = math.min(perNode, h - y + 1)
      local used

      if entry.node.app == "storage" then
        used = widgetStorage(mon, entry.name, entry.node, 2, y, w, budget)
      elseif entry.node.app == "tank" then
        used = widgetTank(mon, entry.name, entry.node, 2, y, w, budget)
      elseif entry.node.app == "train" then
        used = widgetTrain(mon, entry.name, entry.node, 2, y, w, budget)
      elseif entry.node.app == "power" then
        used = widgetPower(mon, entry.name, entry.node, 2, y, w, budget)
      else
        led(mon, 2, y, nodeAlive(entry.node) and colors.lime or colors.gray, true)
        mon.setCursorPos(4, y)
        mon.setTextColor(colors.lightGray)
        mon.write(shortName(entry.node.label or entry.name, 18) .. " [" .. tostring(entry.node.app or "?") .. "]")
        used = 1
      end

      y = y + used + 1
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
        local prev = nodes[msg.node]
        local prevExport = prev and prev.latestExport
        nodes[msg.node] = {
          app          = "storage",
          label        = msg.label or msg.node,
          group        = msg.group or "",
          lastSeen     = os.epoch("utc"),
          items        = msg.items or {},
          latestExport = msg.latestExport or "none",
          alarm        = false,
        }
        -- Only log first time or on export change
        if not prev or prevExport ~= (msg.latestExport or "none") then
          addLog((msg.label or msg.node) .. " updated")
        end

      elseif msg.type == "tank_status" then
        local prev = nodes[msg.node]
        local now  = os.epoch("utc")

        -- Rolling trend: mB/s (positive = filling, negative = draining)
        local trend = (prev and prev.trend) or 0
        if prev and prev.amount ~= nil and prev.lastSeen then
          local dt = (now - prev.lastSeen) / 1000
          if dt > 0.5 and dt < 15 then
            local rate = ((msg.amount or 0) - prev.amount) / dt
            trend = trend * 0.3 + rate * 0.7  -- exponential smoothing
          end
        end

        nodes[msg.node] = {
          app      = "tank",
          label    = msg.label or msg.node,
          group    = msg.group or "",
          lastSeen = now,
          fluid    = msg.fluid,
          amount   = msg.amount,
          capacity = msg.capacity,
          percent  = msg.percent or 0,
          level    = msg.level,
          alarm    = msg.alarm,
          trend    = trend,
        }
        -- Only log on alarm state change or first seen
        if not prev then
          addLog((msg.label or msg.node) .. " online")
        elseif (msg.alarm) ~= (prev and prev.alarm) then
          addLog((msg.label or msg.node) .. (msg.alarm and " ALARM ON" or " alarm off"))
        end

      elseif msg.type == "train_status" then
        local prev = nodes[msg.node]
        local wasPresent = prev and prev.present
        nodes[msg.node] = {
          app              = "train",
          label            = msg.label or msg.node,
          group            = msg.group or "",
          lastSeen         = os.epoch("utc"),
          station          = msg.station,
          present          = msg.present,
          train            = msg.train,
          cars             = msg.cars,
          assembling       = msg.assembling,
          idle             = msg.idle,
          route            = msg.route,
          presentSince     = msg.presentSince,
          currentWaitTicks = msg.currentWaitTicks,
          scheduleCurrent  = msg.scheduleCurrent,
          scheduleNext     = msg.scheduleNext,
          scheduleTotal    = msg.scheduleTotal,
          alarm            = msg.alarm,
        }
        -- Only log on presence state change
        if msg.present ~= wasPresent then
          addLog((msg.label or msg.node) .. " " .. (msg.present and "ARRIVED" or "DEPARTED"))
        end

      elseif msg.type == "power_status" then
        local prev = nodes[msg.node]
        nodes[msg.node] = {
          app      = "power",
          label    = msg.label or msg.node,
          group    = msg.group or "",
          lastSeen = os.epoch("utc"),
          stress   = msg.stress,
          capacity = msg.capacity,
          percent  = msg.percent or 0,
          speeds   = msg.speeds or {},
          alarm    = msg.alarm,
        }
        if not prev then
          addLog((msg.label or msg.node) .. " online")
        elseif (msg.alarm) ~= (prev and prev.alarm) then
          addLog((msg.label or msg.node) .. (msg.alarm and " ALARM ON" or " alarm off"))
        end

      elseif msg.type == "alarm" then
        addAlarm((msg.label or tostring(msg.node)) .. ": " .. tostring(msg.message))
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