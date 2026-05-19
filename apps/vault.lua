-- =========================================================
--  Factory OS Item Vault Node v1.0
--  Monitors inventories (Create Vaults, chests, barrels)
--  and broadcasts vault_status telemetry over FactoryOS.
--
--  Peripherals detected automatically via wired modem:
--    inventory  – any CC:Tweaked inventory peripheral
--                 (Create Item Vault, chest, barrel, etc.)
--
--  Press S on the local terminal to reconfigure which
--  items are tracked.
-- =========================================================

local CONFIG = {
  telemetryRate = 3,
  alarmPercent  = 90,  -- slot utilisation % to trigger alarm
}

local wireless = dofile("/lib/wireless.lua")
local ui       = dofile("/lib/ui.lua")
local util     = dofile("/lib/util.lua")
local config   = dofile("/lib/config.lua")

local PROTOCOL = config.protocol()

-- =========================================================
--  Node identity
-- =========================================================

local _cfg        = config.load("vault")
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

-- Collect ALL reachable inventory peripherals
local inventories = { peripheral.find("inventory") }
local monitors    = { peripheral.find("monitor") }

if #inventories == 0 then
  ui.nodeHeader("vault", nodeLabel, nodeGroup, factoryName, wirelessSide ~= nil)
  ledTerm(colors.red,  "No inventory found!")
  ledTerm(colors.gray, "Connect a Create Vault,")
  ledTerm(colors.gray, "chest, or barrel via")
  ledTerm(colors.gray, "wired modem network.")
  error("No inventory peripheral")
end

-- =========================================================
--  Item config  (/config/vault_items.txt, one name per line)
-- =========================================================

local ITEMS_FILE = "/config/vault_items.txt"

local function loadTrackedItems()
  local raw = util.readFile(ITEMS_FILE)
  if not raw or raw == "" then return {} end
  local items = {}
  for line in raw:gmatch("[^\n]+") do
    local t = line:gsub("^%s+", ""):gsub("%s+$", "")
    if t ~= "" then table.insert(items, t) end
  end
  return items
end

local function saveTrackedItems(list)
  local f = fs.open(ITEMS_FILE, "w")
  for _, name in ipairs(list) do f.writeLine(name) end
  f.close()
end

-- =========================================================
--  Setup wizard  (press S on terminal to open)
-- =========================================================

local function setupItems(tracked)
  tracked = tracked or loadTrackedItems()

  while true do
    local W = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)

    term.setBackgroundColor(colors.orange)
    term.setTextColor(colors.black)
    term.write(" VAULT ITEMS ")
    term.setBackgroundColor(colors.black)
    print("")

    term.setTextColor(colors.gray)
    print(("-"):rep(W))

    if #tracked == 0 then
      term.setTextColor(colors.gray)
      print("  (no items tracked)")
    else
      for i, name in ipairs(tracked) do
        term.setTextColor(colors.cyan)
        write(string.format("  %2d. ", i))
        term.setTextColor(colors.white)
        print(name)
      end
    end

    term.setTextColor(colors.gray)
    print(("-"):rep(W))
    term.setTextColor(colors.lightGray)
    print("add <name>   remove <#>   done")
    print("")
    term.setTextColor(colors.white)
    write("> ")

    local input = read():gsub("^%s+", ""):gsub("%s+$", "")

    if input:sub(1, 3) == "add" then
      local name = input:sub(5):gsub("^%s+", "")
      if name ~= "" then
        -- Auto-add minecraft: namespace if omitted
        if not name:find(":") then name = "minecraft:" .. name end
        local dup = false
        for _, v in ipairs(tracked) do if v == name then dup = true; break end end
        if not dup then
          table.insert(tracked, name)
          saveTrackedItems(tracked)
        end
      end
    elseif input:sub(1, 6) == "remove" then
      local idx = tonumber(input:sub(8))
      if idx and tracked[idx] then
        table.remove(tracked, idx)
        saveTrackedItems(tracked)
      end
    elseif input == "done" or input == "exit" or input == "" then
      break
    end
  end

  return tracked
end

local trackedItems = loadTrackedItems()
if #trackedItems == 0 then
  trackedItems = setupItems(trackedItems)
end

-- =========================================================
--  State
-- =========================================================

local vaultState = {
  items        = {},
  usedSlots    = 0,
  totalSlots   = 0,
  freeSlots    = 0,
  spacePercent = 0,
  alarm        = false,
}

-- =========================================================
--  Readings
-- =========================================================

local function readVault()
  local itemCounts = {}
  local usedSlots  = 0
  local totalSlots = 0

  for _, inv in ipairs(inventories) do
    local ok1, slots = pcall(function() return inv.list() end)
    local ok2, size  = pcall(function() return inv.size() end)
    if ok1 and type(slots) == "table" then
      for _, stack in pairs(slots) do
        usedSlots = usedSlots + 1
        itemCounts[stack.name] = (itemCounts[stack.name] or 0) + stack.count
      end
    end
    if ok2 and type(size) == "number" then
      totalSlots = totalSlots + size
    end
  end

  local items = {}
  for _, name in ipairs(trackedItems) do
    table.insert(items, {
      name    = name,
      display = util.shortName(name, 24),
      count   = itemCounts[name] or 0,
    })
  end

  local pct = (totalSlots > 0)
    and math.min(100, math.floor(usedSlots / totalSlots * 100))
    or 0

  vaultState = {
    items        = items,
    usedSlots    = usedSlots,
    totalSlots   = totalSlots,
    freeSlots    = math.max(0, totalSlots - usedSlots),
    spacePercent = pct,
    alarm        = pct >= CONFIG.alarmPercent,
  }
end

-- =========================================================
--  Broadcast
-- =========================================================

local function broadcastStatus()
  if not wirelessSide then return end

  rednet.broadcast({
    type         = "vault_status",
    app          = "vault",
    node         = nodeName,
    label        = nodeLabel,
    group        = nodeGroup,
    items        = vaultState.items,
    usedSlots    = vaultState.usedSlots,
    totalSlots   = vaultState.totalSlots,
    freeSlots    = vaultState.freeSlots,
    spacePercent = vaultState.spacePercent,
    alarm        = vaultState.alarm,
    heartbeat    = os.epoch("utc"),
  }, PROTOCOL)
end

-- =========================================================
--  Status monitor (tiny 1×1 block monitor)
-- =========================================================

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
    vaultState.alarm and colors.red or colors.gray, "ALARM", vaultState.alarm)
end

-- =========================================================
--  Local terminal
-- =========================================================

local heartbeat = false

local function drawTerminal()
  local W = term.getSize()
  ui.nodeHeader("vault", nodeLabel, nodeGroup, factoryName, wirelessSide ~= nil)

  local pct     = vaultState.spacePercent or 0
  local spColor = vaultState.alarm and colors.red
               or pct >= 70          and colors.yellow
               or                       colors.lime

  ledTerm(spColor, string.format(
    "Space:  %d/%d slots  (%d%% full)",
    vaultState.usedSlots, vaultState.totalSlots, pct
  ))
  ledTerm(heartbeat and colors.lime or colors.gray, "Heartbeat")

  term.setTextColor(colors.gray)
  print(("-"):rep(W))

  if #vaultState.items == 0 then
    term.setTextColor(colors.gray)
    print("  No items tracked.")
    print("  Press S to configure.")
  else
    for _, item in ipairs(vaultState.items) do
      term.setTextColor(item.count > 0 and colors.white or colors.gray)
      print(string.format("  %-22s %6d", item.display, item.count))
    end
  end

  term.setTextColor(colors.gray)
  print("")
  print("  [S] Configure items")
end

-- =========================================================
--  Loops
-- =========================================================

local function telemetryLoop()
  while true do
    readVault()
    broadcastStatus()
    sleep(CONFIG.telemetryRate)
  end
end

local function uiLoop()
  while true do
    heartbeat = not heartbeat
    drawTerminal()
    for _, mon in ipairs(monitors) do
      pcall(function() drawMonitorStatus(mon, heartbeat) end)
    end
    sleep(0.5)
  end
end

-- Press S to open item setup wizard
local function inputLoop()
  while true do
    local _, key = os.pullEvent("key")
    if key == keys.s then
      trackedItems = setupItems(trackedItems)
    end
  end
end

-- =========================================================
--  Boot
-- =========================================================

resetTerm()
if wirelessSide == nil then
  ledTerm(colors.red, "No wireless modem!")
  sleep(3)
end

parallel.waitForAny(telemetryLoop, uiLoop, inputLoop)
