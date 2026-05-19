-- =========================================================
--  Factory OS Item Vault Node v1.1
--  Supports multiple named inventory peripherals.
--  Auto mode: when no items are tracked, shows top 3 by count.
--
--  Peripherals detected automatically via wired modem:
--    inventory  – any CC:Tweaked inventory peripheral
--                 (Create Item Vault, chest, barrel, etc.)
--
--  Press S  – configure tracked items
--  Press V  – rename individual vault containers
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

-- Discover inventory peripherals by name for stable ordering
local invPeriphNames = {}
for _, pname in ipairs(peripheral.getNames()) do
  if peripheral.getType(pname) == "inventory" then
    table.insert(invPeriphNames, pname)
  end
end
table.sort(invPeriphNames)

local monitors = { peripheral.find("monitor") }

if #invPeriphNames == 0 then
  ui.nodeHeader("vault", nodeLabel, nodeGroup, factoryName, wirelessSide ~= nil)
  ledTerm(colors.red,  "No inventory found!")
  ledTerm(colors.gray, "Connect a Create Vault,")
  ledTerm(colors.gray, "chest, or barrel via")
  ledTerm(colors.gray, "wired modem network.")
  error("No inventory peripheral")
end

-- Pre-wrap peripherals once for performance
local invList = {}
for i, pname in ipairs(invPeriphNames) do
  local inv = peripheral.wrap(pname)
  if inv then
    table.insert(invList, { pname = pname, inv = inv, idx = i })
  end
end

-- =========================================================
--  Vault names  (/config/vault_names.txt)
--  Format: peripheral_name=Friendly Label
--  Peripherals without an entry default to "Vault A", "B", …
-- =========================================================

local NAMES_FILE = "/config/vault_names.txt"
local ALPHA = {
  "A","B","C","D","E","F","G","H","I","J","K","L","M",
  "N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
}

local function loadVaultNames()
  local names = {}
  local raw = util.readFile(NAMES_FILE)
  if raw then
    for line in raw:gmatch("[^\n]+") do
      local k, v = line:match("^(.-)=(.+)$")
      if k and v then
        names[k:gsub("^%s+",""):gsub("%s+$","")] =
          v:gsub("^%s+",""):gsub("%s+$","")
      end
    end
  end
  return names
end

local function saveVaultNames(names)
  local f = fs.open(NAMES_FILE, "w")
  for k, v in pairs(names) do f.writeLine(k .. "=" .. v) end
  f.close()
end

local function getVaultLabel(names, pname, idx)
  return names[pname] or ("Vault " .. (ALPHA[idx] or tostring(idx)))
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
--  Setup wizards
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
      term.setTextColor(colors.yellow)
      print("  (none – auto top-3 mode active)")
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

local function setupVaultNames(names)
  while true do
    local W = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)

    term.setBackgroundColor(colors.cyan)
    term.setTextColor(colors.black)
    term.write(" VAULT NAMES ")
    term.setBackgroundColor(colors.black)
    print("")

    term.setTextColor(colors.gray)
    print(("-"):rep(W))

    for i, entry in ipairs(invList) do
      local label = getVaultLabel(names, entry.pname, entry.idx)
      term.setTextColor(colors.cyan)
      write(string.format("  %2d. ", i))
      term.setTextColor(colors.white)
      write(string.format("%-16s", label))
      term.setTextColor(colors.gray)
      print("  (" .. entry.pname .. ")")
    end

    term.setTextColor(colors.gray)
    print(("-"):rep(W))
    term.setTextColor(colors.lightGray)
    print("rename <#> <name>   done")
    print("")
    term.setTextColor(colors.white)
    write("> ")

    local input = read():gsub("^%s+", ""):gsub("%s+$", "")

    if input:sub(1, 6) == "rename" then
      local rest = input:sub(8):gsub("^%s+", "")
      local idx_str, newlabel = rest:match("^(%d+)%s+(.+)$")
      local idx = tonumber(idx_str)
      if idx and invList[idx] and newlabel and newlabel ~= "" then
        names[invList[idx].pname] = newlabel
        saveVaultNames(names)
      end
    elseif input == "done" or input == "exit" or input == "" then
      break
    end
  end

  return names
end

local trackedItems = loadTrackedItems()
local vaultNames   = loadVaultNames()

-- =========================================================
--  State
-- =========================================================

local vaultState = {
  vaults       = {},   -- per-vault: { label, usedSlots, totalSlots }
  items        = {},   -- tracked item totals
  topItems     = {},   -- top-3 by count (auto mode)
  usedSlots    = 0,
  totalSlots   = 0,
  freeSlots    = 0,
  spacePercent = 0,
  alarm        = false,
  autoMode     = false,
}

-- =========================================================
--  Readings
-- =========================================================

local function readVault()
  local itemCounts = {}
  local usedSlots  = 0
  local totalSlots = 0
  local vaults     = {}

  for _, entry in ipairs(invList) do
    local vUsed  = 0
    local vTotal = 0

    local ok1, slots = pcall(function() return entry.inv.list() end)
    local ok2, size  = pcall(function() return entry.inv.size() end)

    if ok1 and type(slots) == "table" then
      for _, stack in pairs(slots) do
        vUsed = vUsed + 1
        itemCounts[stack.name] = (itemCounts[stack.name] or 0) + stack.count
      end
    end
    if ok2 and type(size) == "number" then
      vTotal = size
    end

    usedSlots  = usedSlots  + vUsed
    totalSlots = totalSlots + vTotal

    table.insert(vaults, {
      label      = getVaultLabel(vaultNames, entry.pname, entry.idx),
      periph     = entry.pname,
      usedSlots  = vUsed,
      totalSlots = vTotal,
    })
  end

  -- Tracked items
  local items = {}
  for _, name in ipairs(trackedItems) do
    table.insert(items, {
      name    = name,
      display = util.shortName(name, 24),
      count   = itemCounts[name] or 0,
    })
  end

  -- Auto top-3 mode (no items configured)
  local topItems = {}
  if #trackedItems == 0 then
    local sorted = {}
    for name, count in pairs(itemCounts) do
      table.insert(sorted, { name = name, count = count })
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    for i = 1, math.min(3, #sorted) do
      table.insert(topItems, {
        name    = sorted[i].name,
        display = util.shortName(sorted[i].name, 24),
        count   = sorted[i].count,
      })
    end
  end

  local pct = (totalSlots > 0)
    and math.min(100, math.floor(usedSlots / totalSlots * 100))
    or 0

  vaultState = {
    vaults       = vaults,
    items        = items,
    topItems     = topItems,
    usedSlots    = usedSlots,
    totalSlots   = totalSlots,
    freeSlots    = math.max(0, totalSlots - usedSlots),
    spacePercent = pct,
    alarm        = pct >= CONFIG.alarmPercent,
    autoMode     = #trackedItems == 0,
  }
end

-- =========================================================
--  Broadcast
-- =========================================================

local function broadcastStatus()
  if not wirelessSide then return end

  local broadcastItems = vaultState.autoMode
    and vaultState.topItems or vaultState.items

  rednet.broadcast({
    type         = "vault_status",
    app          = "vault",
    node         = nodeName,
    label        = nodeLabel,
    group        = nodeGroup,
    vaults       = vaultState.vaults,
    items        = broadcastItems,
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

  -- Per-vault breakdown (only shown when more than one vault)
  if #vaultState.vaults > 1 then
    for _, v in ipairs(vaultState.vaults) do
      local vpct = v.totalSlots > 0
        and math.floor(v.usedSlots / v.totalSlots * 100) or 0
      local vc = vpct >= CONFIG.alarmPercent and colors.red
              or vpct >= 70                  and colors.yellow
              or                                 colors.lime
      term.setTextColor(vc)
      write("  " .. string.format("%-14s", v.label))
      term.setTextColor(colors.gray)
      print(string.format(" %d/%d (%d%%)", v.usedSlots, v.totalSlots, vpct))
    end
    term.setTextColor(colors.gray)
    print(("-"):rep(W))
  end

  -- Items / auto-mode section
  if vaultState.autoMode then
    term.setTextColor(colors.yellow)
    print("  [auto] Top items:")
    if #vaultState.topItems == 0 then
      term.setTextColor(colors.gray)
      print("  (all inventories empty)")
    else
      for _, item in ipairs(vaultState.topItems) do
        term.setTextColor(colors.white)
        print(string.format("  %-22s %6d", item.display, item.count))
      end
    end
  else
    for _, item in ipairs(vaultState.items) do
      term.setTextColor(item.count > 0 and colors.white or colors.gray)
      print(string.format("  %-22s %6d", item.display, item.count))
    end
  end

  term.setTextColor(colors.gray)
  print("")
  print("  [S] Configure items   [V] Rename vaults")
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

local function inputLoop()
  while true do
    local _, key = os.pullEvent("key")
    if key == keys.s then
      trackedItems = setupItems(trackedItems)
    elseif key == keys.v then
      vaultNames = setupVaultNames(vaultNames)
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
