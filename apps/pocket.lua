-- =========================================================
--  Factory OS Pocket SCADA v1.0
--  Compact status viewer for advanced pocket computer.
-- =========================================================

local PROTOCOL = "factoryos"

local wireless = dofile("/lib/wireless.lua")
local util     = dofile("/lib/util.lua")

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
          app        = "train",
          label      = msg.label or msg.node,
          group      = msg.group or "",
          lastSeen   = os.epoch("utc"),
          present    = msg.present,
          train      = msg.train,
          assembling = msg.assembling,
          alarm      = false,
        }
      elseif msg.type == "alarm" then
        addAlarm(tostring(msg.node) .. " " .. tostring(msg.message))
      end
    end
  end
end

-- =========================================================
--  UI – pocket screen (26×20)
-- =========================================================

local W, H = term.getSize()
local BAR_W = 12   -- fill-bar width for tank/boiler rows

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

local function fillBar(pct, color)
  local filled = math.floor(BAR_W * math.min(pct, 100) / 100)
  for i = 1, BAR_W do
    term.setBackgroundColor(i <= filled and color or colors.gray)
    term.write(" ")
  end
  term.setBackgroundColor(colors.black)
end

local function drawUI(heartbeat)
  W, H = term.getSize()

  term.setBackgroundColor(colors.black)
  term.clear()

  -- ── Header row ───────────────────────────────────────
  term.setCursorPos(1, 1)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.orange)
  term.write("FactoryOS")

  -- heartbeat blink right side
  term.setCursorPos(W - 5, 1)
  term.setTextColor(colors.gray)
  term.write("HB:")
  term.setTextColor(heartbeat and colors.lime or colors.gray)
  term.write(heartbeat and "\7" or " ")

  -- NET indicator
  term.setCursorPos(W - 1, 1)
  term.setTextColor(wirelessModem and colors.cyan or colors.red)
  term.write("N")

  -- ── Alarm banner ─────────────────────────────────────
  local y = 2
  if anyAlarm() then
    term.setCursorPos(1, y)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    local line = "! ALARM"
    if #alarms > 0 then
      line = ("! " .. alarms[1]):sub(1, W)
    end
    term.write(line .. (" "):rep(math.max(0, W - #line)))
    term.setBackgroundColor(colors.black)
    y = y + 1
  end

  -- ── Separator ─────────────────────────────────────────
  term.setCursorPos(1, y)
  term.setTextColor(colors.gray)
  term.write(("-"):rep(W))
  y = y + 1

  -- ── Node list ─────────────────────────────────────────
  -- Collect nodes, grouped by node.group
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
    term.setCursorPos(1, y)
    term.setTextColor(colors.gray)
    term.write("Waiting for nodes...")
    return
  end

  for _, g in ipairs(ordering) do
    -- Group header for named groups
    if g ~= "" and y <= H then
      term.setCursorPos(1, y)
      term.setTextColor(colors.orange)
      local hdr = g:sub(1, W)
      term.write(hdr .. (" "):rep(math.max(0, W - #hdr)))
      y = y + 1
    end

    for _, e in ipairs(groups[g]) do
      if y > H then break end

      local node  = e.node
      local alive = nodeAlive(node)
      local alm   = node.alarm
      local lbl   = node.label or e.name

      -- LED dot
      term.setCursorPos(1, y)
      term.setBackgroundColor(colors.black)
      if not alive then
        term.setTextColor(colors.gray)
        term.write("\7")
      elseif alm then
        term.setTextColor(colors.red)
        term.write("\7")
      else
        term.setTextColor(colors.lime)
        term.write("\7")
      end

      -- Label (truncated)
      local nameW = math.min(#lbl, 10)
      term.setTextColor(alive and colors.white or colors.gray)
      term.write(" " .. lbl:sub(1, nameW))

      -- Value / status
      if node.app == "tank" then
        local pct = node.percent or 0
        local barColor = (alm or pct <= 20) and colors.red
                      or pct <= 50          and colors.yellow
                      or colors.orange
        term.setCursorPos(13, y)
        fillBar(pct, barColor)
        term.setTextColor(barColor)
        term.write(string.format("%3d%%", pct))

      elseif node.app == "train" then
        term.setCursorPos(13, y)
        if not alive then
          term.setTextColor(colors.red)
          term.write("offline")
        elseif node.assembling then
          term.setTextColor(colors.yellow)
          term.write("assembling")
        elseif node.present then
          term.setTextColor(colors.lime)
          term.write((node.train or "?"):sub(1, W - 13))
        else
          term.setTextColor(colors.gray)
          term.write("empty")
        end

      elseif node.app == "storage" then
        local overflow = 0
        for _, item in ipairs(node.items or {}) do
          if (item.overflow or 0) > 0 then overflow = overflow + 1 end
        end
        term.setCursorPos(12, y)
        if overflow > 0 then
          term.setTextColor(colors.red)
          term.write(overflow .. " overflow")
        else
          term.setTextColor(colors.lime)
          term.write("nominal")
        end
      else
        term.setCursorPos(12, y)
        term.setTextColor(colors.gray)
        term.write(tostring(node.app or "?"))
      end

      y = y + 1
    end
  end

  -- ── Footer ────────────────────────────────────────────
  if y <= H then
    term.setCursorPos(1, H)
    term.setTextColor(colors.gray)
    term.write(("-"):rep(W))
  end
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
