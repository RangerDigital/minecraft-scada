-- =========================================================
--  Mining Vehicle Controller v1.1
-- =========================================================
--
--  Wired modem network (computer top → cable to all blocks):
--
--    [Relay Left] [Computer] [Relay Right]
--
--    Relay Left   – front = input ch1,  back = output ch1
--    Relay Right  – front = input ch2,  back = output ch2
--    Computer     – front = input ch3,  back = output ch3
--    Monitor 1    – 1×2 vehicle status panel   (sorted name[1])
--    Monitor 2    – 1×2 vault fill display      (sorted name[2])
--    Item Vault   – any inventory peripheral
--
--  Channels:
--    1  Engine Fuel Pump       – relay left
--    2  Mining Drills          – relay right
--    3  Unloading Ejec. Port   – computer itself
--
--  Relay HIGH = device OFF  (normally-energised / inverted logic)
--  Relay LOW  = device ON
--  All channels default HIGH (all devices OFF at startup).
-- =========================================================

local ui = dofile("/lib/ui.lua")

local IN_SIDE  = "front"
local OUT_SIDE = "back"

local VAULT_REFRESH = 2   -- seconds between vault reads

-- =========================================================
--  Peripheral discovery
-- =========================================================

local function findAll(ptype)
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, ptype) then
      table.insert(found, { name = name, p = peripheral.wrap(name) })
    end
  end
  table.sort(found, function(a, b) return a.name < b.name end)
  return found
end

local relayList = findAll("redstone_relay")
local monList   = findAll("monitor")

if #relayList < 2 then
  error("Need 2 redstone_relay peripherals on the wired modem network.")
end
if #monList < 2 then
  error("Need 2 monitor peripherals on the wired modem network.")
end

local relayLeft  = relayList[1].p
local relayRight = relayList[2].p

local monStatus = monList[1].p   -- vehicle status
local monVault  = monList[2].p   -- vault fill

monStatus.setTextScale(0.5)
monVault.setTextScale(0.5)

-- Find vault: first inventory peripheral that is not a relay or modem
local vault = nil
for _, name in ipairs(peripheral.getNames()) do
  if not peripheral.hasType(name, "redstone_relay")
  and not peripheral.hasType(name, "modem") then
    local p = peripheral.wrap(name)
    if type(p) == "table"
    and type(p.list) == "function"
    and type(p.size) == "function" then
      vault = p
      break
    end
  end
end

-- =========================================================
--  Channel definitions
-- =========================================================

-- input/output fields: nil = use computer's own redstone API
local CHANNELS = {
  { label = "Fuel Pump",   input = relayLeft,  output = relayLeft  },
  { label = "Drills",      input = relayRight, output = relayRight },
  { label = "Ejec. Port",  input = nil,        output = nil        },
}

-- =========================================================
--  State
--
--  outputs[i] = true  → relay HIGH → device is OFF
--  outputs[i] = false → relay LOW  → device is ON
-- =========================================================

local outputs = { true, true, true }
local prevIn  = { false, false, false }

-- =========================================================
--  I/O helpers
-- =========================================================

local function readInput(ch)
  if ch.input then
    return ch.input.getInput(IN_SIDE)
  else
    return redstone.getInput(IN_SIDE)
  end
end

local function writeOutput(ch, val)
  if ch.output then
    ch.output.setOutput(OUT_SIDE, val)
  else
    redstone.setOutput(OUT_SIDE, val)
  end
end

local function applyOutputs()
  for i, ch in ipairs(CHANNELS) do
    writeOutput(ch, outputs[i])
  end
end

-- =========================================================
--  Vault helpers
-- =========================================================

local function vaultFill()
  if not vault then return nil, nil end
  local slots    = vault.size()
  local items    = vault.list()
  local total    = 0
  local capacity = slots * 64
  for _, item in pairs(items) do
    total = total + item.count
  end
  return total, capacity
end

-- =========================================================
--  Monitor 1: vehicle status panel
-- =========================================================

local function drawStatus()
  local W = monStatus.getSize()
  monStatus.setBackgroundColor(colors.black)
  monStatus.clear()

  -- Title bar
  monStatus.setCursorPos(1, 1)
  monStatus.setBackgroundColor(colors.orange)
  monStatus.setTextColor(colors.black)
  local title = " VEHICLE STATUS "
  monStatus.write(title .. string.rep(" ", math.max(0, W - #title)))
  monStatus.setBackgroundColor(colors.black)

  -- Separator
  monStatus.setCursorPos(1, 2)
  monStatus.setTextColor(colors.gray)
  monStatus.write(string.rep("-", W))

  -- Channel rows
  for i, ch in ipairs(CHANNELS) do
    local row  = 2 + i
    local isOn = not outputs[i]
    local badge = isOn and " ON " or " OFF"
    ui.statusLine(monStatus, 1, row, colors.lime, ch.label, isOn)
    monStatus.setCursorPos(W - #badge + 1, row)
    monStatus.setTextColor(isOn and colors.lime or colors.red)
    monStatus.write(badge)
  end

  -- Bottom separator
  monStatus.setCursorPos(1, 6)
  monStatus.setTextColor(colors.gray)
  monStatus.write(string.rep("-", W))
end

-- =========================================================
--  Monitor 2: vault fill display
-- =========================================================

local function drawVault(items, capacity)
  local W = monVault.getSize()
  monVault.setBackgroundColor(colors.black)
  monVault.clear()

  -- Title bar
  monVault.setCursorPos(1, 1)
  monVault.setBackgroundColor(colors.orange)
  monVault.setTextColor(colors.black)
  local title = " ITEM VAULT "
  monVault.write(title .. string.rep(" ", math.max(0, W - #title)))
  monVault.setBackgroundColor(colors.black)

  -- Separator
  monVault.setCursorPos(1, 2)
  monVault.setTextColor(colors.gray)
  monVault.write(string.rep("-", W))

  if not items then
    monVault.setCursorPos(1, 3)
    monVault.setTextColor(colors.gray)
    monVault.write("  No vault")
    return
  end

  local pct      = math.floor(items / capacity * 100 + 0.5)
  local barWidth = W
  local filledW  = math.floor(items / capacity * barWidth + 0.5)

  -- Percentage label (centred)
  monVault.setCursorPos(1, 3)
  local pctStr = string.format("%3d%%", pct)
  local pad    = math.floor((W - #pctStr) / 2)
  monVault.setTextColor(colors.white)
  monVault.write(string.rep(" ", math.max(0, pad)) .. pctStr)

  -- Fill bar
  monVault.setCursorPos(1, 4)
  monVault.setTextColor(colors.black)
  monVault.setBackgroundColor(pct >= 90 and colors.red or colors.lime)
  monVault.write(string.rep(" ", filledW))
  monVault.setBackgroundColor(colors.gray)
  monVault.write(string.rep(" ", barWidth - filledW))
  monVault.setBackgroundColor(colors.black)

  -- Item count (centred)
  monVault.setCursorPos(1, 5)
  local countStr = string.format("%d/%d", items, capacity)
  local pad2     = math.floor((W - #countStr) / 2)
  monVault.setTextColor(colors.lightGray)
  monVault.write(string.rep(" ", math.max(0, pad2)) .. countStr)

  -- Bottom separator
  monVault.setCursorPos(1, 6)
  monVault.setTextColor(colors.gray)
  monVault.write(string.rep("-", W))
end

-- =========================================================
--  Terminal display
-- =========================================================

local function drawTerm()
  local W = term.getSize()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)

  term.setBackgroundColor(colors.orange)
  term.setTextColor(colors.black)
  local title = " MINING VEHICLE CONTROLLER "
  term.write(title .. string.rep(" ", math.max(0, W - #title)))
  term.setCursorPos(1, 2)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.gray)
  print(string.rep("-", W))

  for i, ch in ipairs(CHANNELS) do
    local isOn = not outputs[i]
    ui.ledTerm(
      isOn and colors.lime or colors.red,
      ch.label .. ": " .. (isOn and "ON" or "OFF")
    )
  end

  term.setTextColor(colors.gray)
  print(string.rep("-", W))
end

-- =========================================================
--  Main loop
-- =========================================================

applyOutputs()

local vItems, vCap  = vaultFill()
local lastVaultTime = os.epoch("utc")

drawStatus()
drawVault(vItems, vCap)
drawTerm()

while true do
  -- Poll all inputs
  local curIn = {}
  for i, ch in ipairs(CHANNELS) do
    curIn[i] = readInput(ch)
  end

  -- Rising edge → toggle output
  local changed = false
  for i = 1, #CHANNELS do
    if curIn[i] and not prevIn[i] then
      outputs[i] = not outputs[i]
      changed = true
    end
  end

  if changed then
    applyOutputs()
    drawStatus()
    drawTerm()
  end

  prevIn = curIn

  -- Periodic vault refresh
  if os.epoch("utc") - lastVaultTime >= VAULT_REFRESH * 1000 then
    vItems, vCap  = vaultFill()
    lastVaultTime = os.epoch("utc")
    drawVault(vItems, vCap)
  end

  os.sleep(0.05)
end
