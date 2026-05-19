-- =========================================================
--  Factory OS Pocket SCADA v1.0
--  Compact status viewer for advanced pocket computer.
-- =========================================================

local wireless = dofile("/lib/wireless.lua")
local util     = dofile("/lib/util.lua")
local config   = dofile("/lib/config.lua")

local PROTOCOL     = config.protocol()
local factoryLabel = config.load().factory_name

local wirelessModem = wireless.find()

local nodes  = {}
local alarms = {}

-- =========================================================
--  Helpers
-- =========================================================

local function nodeAlive(node)
  return (os.epoch("utc") - node.lastSeen) < 6000
end

local function anyAlarm()
  for _, node in pairs(nodes) do
    if node.alarm and nodeAlive(node) then return true end
  end
  return false
end

local function addAlarm(text)
  table.insert(alarms, 1, text)
  while #alarms > 10 do table.remove(alarms) end
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
          app      = "storage",
          label    = msg.label or msg.node,
          group    = msg.group or "",
          lastSeen = os.epoch("utc"),
          items    = msg.items or {},
          alarm    = false,
        }
      elseif msg.type == "tank_status" then
        nodes[msg.node] = {
          app      = "tank",
          label    = msg.label or msg.node,
          group    = msg.group or "",
          lastSeen = os.epoch("utc"),
          fluid    = msg.fluid,
          percent  = msg.percent or 0,
          level    = msg.level,
          alarm    = msg.alarm,
        }
      elseif msg.type == "train_status" then
        nodes[msg.node] = {
          app             = "train",
          label           = msg.label or msg.node,
          group           = msg.group or "",
          lastSeen        = os.epoch("utc"),
          station         = msg.station,
          present         = msg.present,
          train           = msg.train,
          cars            = msg.cars,
          assembling      = msg.assembling,
          idle            = msg.idle,
          scheduleCurrent = msg.scheduleCurrent,
          scheduleNext    = msg.scheduleNext,
          scheduleTotal   = msg.scheduleTotal,
          alarm           = false,
        }
      elseif msg.type == "power_status" then
        nodes[msg.node] = {
          app      = "power",
          label    = msg.label or msg.node,
          group    = msg.group or "",
          lastSeen = os.epoch("utc"),
          stress   = msg.stress,
          capacity = msg.capacity,
          percent  = msg.percent or 0,
          alarm    = msg.alarm,
        }
      elseif msg.type == "vault_status" then
        nodes[msg.node] = {
          app          = "vault",
          label        = msg.label or msg.node,
          group        = msg.group or "",
          lastSeen     = os.epoch("utc"),
          items        = msg.items or {},
          freeSlots    = msg.freeSlots  or 0,
          totalSlots   = msg.totalSlots or 0,
          spacePercent = msg.spacePercent or 0,
          alarm        = msg.alarm,
        }
      elseif msg.type == "alarm" then
        addAlarm((msg.label or tostring(msg.node)) .. " " .. tostring(msg.message))
      end
    end
  end
end

-- =========================================================
--  UI – pocket screen (26×20)
-- =========================================================

local W, H = term.getSize()

local function ledTerm(color, label, active)
  if active then
    term.setBackgroundColor(color)
    term.setTextColor(colors.black)
    term.write(" ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(color)
    term.write(" " .. label)
  else
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.gray)
    term.write("   " .. label)
  end
end

local function fillBar(pct, color, barW)
  local filled = math.floor(barW * math.min(pct, 100) / 100)
  for i = 1, barW do
    term.setBackgroundColor(i <= filled and color or colors.gray)
    term.write(" ")
  end
  term.setBackgroundColor(colors.black)
end

local function drawUI(heartbeat)
  W, H = term.getSize()

  term.setBackgroundColor(colors.black)
  term.clear()

  -- ── Header bar ───────────────────────────────────────
  term.setCursorPos(1, 1)
  term.setBackgroundColor(colors.orange)
  term.setTextColor(colors.black)
  term.write(" FACTORY OS ")
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.gray)
  term.write(" " .. factoryLabel)

  -- HB blink + NET dot right-aligned
  term.setCursorPos(W - 3, 1)
  term.setTextColor(heartbeat and colors.lime or colors.gray)
  term.write(heartbeat and "\4" or "\7")
  term.setCursorPos(W - 1, 1)
  term.setTextColor(wirelessModem and colors.cyan or colors.red)
  term.write("N")
  term.setBackgroundColor(colors.black)

  local y = 2

  -- ── Alarm banners (up to 2 rows) ──────────────────────
  local alarmLines = {}
  for _, node in pairs(nodes) do
    if node.alarm and nodeAlive(node) then
      table.insert(alarmLines, (node.label or "?") .. " alarm")
    end
  end
  for _, a in ipairs(alarms) do
    table.insert(alarmLines, a)
  end

  for i = 1, math.min(2, #alarmLines) do
    if y >= H - 1 then break end
    term.setCursorPos(1, y)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    local line = ("! " .. alarmLines[i]):sub(1, W)
    term.write(line .. (" "):rep(math.max(0, W - #line)))
    term.setBackgroundColor(colors.black)
    y = y + 1
  end

  -- ── Divider ───────────────────────────────────────────
  term.setCursorPos(1, y)
  term.setTextColor(colors.gray)
  term.write(("-"):rep(W))
  y = y + 1

  -- ── Node list ─────────────────────────────────────────
  local valCol = math.max(14, math.floor(W * 0.55))
  local lblW   = valCol - 3
  local barW   = W - valCol - 4

  local groups   = {}
  local ordering = {}

  for name, node in pairs(nodes) do
    local g = node.group or ""
    if not groups[g] then
      groups[g] = {}
      table.insert(ordering, g)
    end
    table.insert(groups[g], { name = name, node = node })
  end

  table.sort(ordering, function(a, b)
    if a == "" then return false end
    if b == "" then return true  end
    return a < b
  end)

  for _, g in ipairs(ordering) do
    table.sort(groups[g], function(a, b)
      return (a.node.label or a.name) < (b.node.label or b.name)
    end)
  end

  if #ordering == 0 then
    term.setCursorPos(2, y)
    term.setTextColor(colors.gray)
    term.write("Waiting for nodes...")
    term.setCursorPos(1, H)
    term.setTextColor(colors.gray)
    term.write(("-"):rep(W))
    return
  end

  for _, g in ipairs(ordering) do
    if y >= H then break end

    -- Group header: gray fill + orange text
    if g ~= "" then
      term.setCursorPos(1, y)
      term.setBackgroundColor(colors.gray)
      term.setTextColor(colors.orange)
      local hdr = "  " .. g .. "  "
      term.write(hdr .. (" "):rep(math.max(0, W - #hdr)))
      term.setBackgroundColor(colors.black)
      y = y + 1
    end

    for _, e in ipairs(groups[g]) do
      if y >= H then break end

      local node  = e.node
      local alive = nodeAlive(node)
      local alm   = node.alarm
      local lbl   = node.label or e.name

      -- LED dot with alarm background highlight
      term.setCursorPos(1, y)
      if alm and alive then
        term.setBackgroundColor(colors.red)
        term.setTextColor(colors.white)
        term.write("!")
        term.setBackgroundColor(colors.black)
      elseif not alive then
        term.setTextColor(colors.gray)
        term.write("\7")
      else
        term.setTextColor(colors.lime)
        term.write("\7")
      end

      -- Label
      term.setTextColor(
        not alive and colors.gray
        or alm    and colors.red
        or            colors.white
      )
      term.write(" " .. lbl:sub(1, lblW))

      -- Value column
      if node.app == "tank" then
        local pct      = node.percent or 0
        local trend    = node.trend or 0
        local barColor = (alm or pct <= 20) and colors.red
                      or pct <= 50          and colors.yellow
                      or                        colors.lime
        local tArrow, tColor = " ", colors.gray
        if math.abs(trend) > 10 then
          tArrow = trend > 0 and "\30" or "\31"
          tColor = trend > 0 and colors.lime or colors.red
        end
        term.setCursorPos(valCol, y)
        fillBar(pct, barColor, barW - 1)
        term.setTextColor(barColor)
        term.write(string.format("%3d%%", pct))
        term.setTextColor(tColor)
        term.write(tArrow)

      elseif node.app == "power" then
        local pct      = node.percent or 0
        local barColor = (alm or pct >= 90) and colors.red
                      or pct >= 75          and colors.yellow
                      or                        colors.lime
        term.setCursorPos(valCol, y)
        fillBar(pct, barColor, barW)
        term.setTextColor(barColor)
        term.write(string.format("%3d%%", pct))

      elseif node.app == "train" then
        term.setCursorPos(valCol, y)
        if not alive then
          term.setTextColor(colors.red)
          term.write("OFFLINE")
        elseif node.assembling then
          term.setTextColor(colors.yellow)
          term.write("ASSEMBLING")
        elseif node.present then
          term.setTextColor(colors.lime)
          local cStr = node.cars and (" " .. node.cars .. "c") or ""
          term.write(("PRSNT" .. cStr):sub(1, W - valCol + 1))
        else
          term.setTextColor(colors.gray)
          local dest = node.scheduleCurrent
          term.write(dest and ("\16 " .. dest):sub(1, W - valCol + 1) or "empty")
        end

      elseif node.app == "storage" then
        local overflow = 0
        for _, item in ipairs(node.items or {}) do
          if (item.overflow or 0) > 0 then overflow = overflow + 1 end
        end
        term.setCursorPos(valCol, y)
        if overflow > 0 then
          term.setTextColor(colors.red)
          term.write(overflow .. " overflow")
        else
          term.setTextColor(colors.lime)
          term.write("ok")
        end

      elseif node.app == "vault" then
        local pct      = node.spacePercent or 0
        local spColor  = (alm or pct >= 90) and colors.red
                      or pct >= 70           and colors.yellow
                      or                        colors.lime
        term.setCursorPos(valCol, y)
        fillBar(pct, spColor, barW)
        term.setTextColor(spColor)
        term.write(string.format("%3d%%", pct))

      else
        term.setCursorPos(valCol, y)
        term.setTextColor(colors.gray)
        term.write(tostring(node.app or "?"))
      end

      y = y + 1
    end
  end

  -- ── Footer: node count ────────────────────────────────
  local total = 0
  for _ in pairs(nodes) do total = total + 1 end
  term.setCursorPos(1, H)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.gray)
  local footer = " " .. total .. " node" .. (total == 1 and "" or "s")
  term.write(footer .. (" "):rep(math.max(0, W - #footer)))
end

-- =========================================================
--  Main loops
-- =========================================================

local function uiLoop()
  local heartbeat = false
  while true do
    heartbeat = not heartbeat
    pcall(drawUI, heartbeat)
    sleep(0.5)
  end
end

-- wireless.find() already opens rednet
parallel.waitForAny(networkLoop, uiLoop)
