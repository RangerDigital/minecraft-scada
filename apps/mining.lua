-- =========================================================
--  Mining Vehicle Controller v1.2
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
--    1  Fuel Pump      – relay left
--    2  Drills         – relay right
--    3  Ejec. Port     – computer itself
--
--  Relay HIGH = device OFF  (normally-energised / inverted logic)
--  Relay LOW  = device ON
--  All channels default HIGH (all devices OFF at startup).
-- =========================================================

local ui   = dofile("/lib/ui.lua")
local util = dofile("/lib/util.lua")

local IN_SIDE       = "back"
local OUT_SIDE      = "front"
local VAULT_REFRESH = 2   -- seconds between vault reads

-- =========================================================
--  Node identity
-- =========================================================

local nodeLabel = util.readFile("/config/node_label.txt")
               or os.getComputerLabel()
               or ("MNR-" .. os.getComputerID())

-- =========================================================
--  Peripheral discovery
--  (use method-checking per project rules; peripheral.hasType
--   can behave oddly for custom peripheral types)
-- =========================================================

-- Redstone relays: identified by having getInput + setOutput + getBundledInput
local relayList = {}
for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)
  if type(p) == "table"
  and type(p.getInput)        == "function"
  and type(p.setOutput)       == "function"
  and type(p.getBundledInput) == "function" then
    table.insert(relayList, { name = name, p = p })
  end
end
table.sort(relayList, function(a, b) return a.name < b.name end)

-- Monitors: identified by getSize + setCursorPos + setTextColor
local monList = {}
for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)
  if type(p) == "table"
  and type(p.getSize)      == "function"
  and type(p.setCursorPos) == "function"
  and type(p.setTextColor) == "function" then
    table.insert(monList, { name = name, p = p })
  end
end
table.sort(monList, function(a, b) return a.name < b.name end)

if #relayList < 2 then
  error("Need 2 redstone_relay peripherals on the wired modem network. Found: " .. #relayList)
end
if #monList < 2 then
  error("Need 2 monitor peripherals on the wired modem network. Found: " .. #monList)
end

local relayLeft  = relayList[1].p
local relayRight = relayList[2].p
local monStatus  = monList[1].p   -- vehicle status panel
local monVault   = monList[2].p   -- vault fill panel

monStatus.setTextScale(0.5)
monVault.setTextScale(0.5)

-- Vault: first inventory peripheral that is not a relay
local vault = nil
for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)
  if type(p) == "table"
  and type(p.list) == "function"
  and type(p.size) == "function"
  and type(p.getInput) ~= "function" then   -- exclude relays
    vault = p
    break
  end
end

-- =========================================================
--  Channel definitions
-- =========================================================

-- input/output = nil means use the computer's own redstone API
local CHANNELS = {
  { label = "Fuel Pump",  input = relayLeft,  output = relayLeft  },
  { label = "Drills",     input = relayRight, output = relayRight },
  { label = "Ejec. Port", input = nil,        output = nil        },
}

-- =========================================================
--  State
--
--  outputs[i] = true  → relay HIGH → device is OFF
--  outputs[i] = false → relay LOW  → device is ON
-- =========================================================

local outputs = { true, true, true }
local prevIn  = { false, false, false }

local function readInput(ch)
  if ch.input then return ch.input.getInput(IN_SIDE) end
  return redstone.getInput(IN_SIDE)
end

local function writeOutput(ch, val)
  if ch.output then ch.output.setOutput(OUT_SIDE, val)
  else redstone.setOutput(OUT_SIDE, val) end
end

local function applyOutputs()
  for i, ch in ipairs(CHANNELS) do writeOutput(ch, outputs[i]) end
end

-- =========================================================
--  Vault helpers
-- =========================================================

local function vaultFill()
  if not vault then return nil, nil end
  local slots    = vault.size()
  local total    = 0
  local capacity = slots * 64
  for _, item in pairs(vault.list()) do total = total + item.count end
  return total, capacity
end

-- =========================================================
--  Monitor draw helpers
-- =========================================================

local function monSep(mon, row, char)
  local W = mon.getSize()
  mon.setCursorPos(1, row)
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.gray)
  mon.write(string.rep(char or "-", W))
end

local function monCentre(mon, row, text, col)
  local W = mon.getSize()
  mon.setCursorPos(math.max(1, math.floor((W - #text) / 2) + 1), row)
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(col or colors.white)
  mon.write(text)
end

-- =========================================================
--  Monitor 1: vehicle status panel
-- =========================================================

local function drawStatus()
  local W = monStatus.getSize()
  monStatus.setBackgroundColor(colors.black)
  monStatus.clear()

  -- Row 1: orange title bar with vehicle name
  monStatus.setCursorPos(1, 1)
  monStatus.setBackgroundColor(colors.orange)
  monStatus.setTextColor(colors.black)
  local title = string.upper(" " .. nodeLabel)
  monStatus.write(string.sub(title, 1, W) .. string.rep(" ", math.max(0, W - #title)))
  monStatus.setBackgroundColor(colors.black)

  -- Row 2: blank padding
  -- (empty row)

  -- Row 3: system status
  ui.led(monStatus, 1, 3, colors.lime, true)
  monStatus.setCursorPos(3, 3)
  monStatus.setTextColor(colors.cyan)
  monStatus.write("MINING CONTROLLER")

  -- Row 4: section separator
  monSep(monStatus, 4, "-")

  -- Row 5: subsystems header
  monStatus.setCursorPos(1, 5)
  monStatus.setBackgroundColor(colors.black)
  monStatus.setTextColor(colors.orange)
  monStatus.write(" SUBSYSTEMS")

  -- Rows 6-8: channel status rows
  for i, ch in ipairs(CHANNELS) do
    local row    = 5 + i
    local isOn   = not outputs[i]
    local badge  = isOn and "[ON ]" or "[OFF]"
    local labelW = math.max(1, W - 2 - #badge)
    local label  = string.format("%-" .. labelW .. "s", ch.label)

    ui.led(monStatus, 1, row, colors.lime, isOn)
    monStatus.setCursorPos(3, row)
    monStatus.setBackgroundColor(colors.black)
    monStatus.setTextColor(isOn and colors.white or colors.gray)
    monStatus.write(string.sub(label, 1, labelW))
    monStatus.setCursorPos(W - #badge + 1, row)
    monStatus.setTextColor(isOn and colors.lime or colors.red)
    monStatus.write(badge)
  end

  -- Row 9: separator
  monSep(monStatus, 9, "-")

  -- Row 10: channel source legend
  monStatus.setCursorPos(1, 10)
  monStatus.setBackgroundColor(colors.black)
  monStatus.setTextColor(colors.gray)
  monStatus.write(" RLY-L  RLY-R  CTRL")
end

-- =========================================================
--  Monitor 2: vault fill panel
-- =========================================================

local function drawVault(items, capacity)
  local W = monVault.getSize()
  monVault.setBackgroundColor(colors.black)
  monVault.clear()

  -- Row 1: title bar
  monVault.setCursorPos(1, 1)
  monVault.setBackgroundColor(colors.orange)
  monVault.setTextColor(colors.black)
  local title = " STORAGE UNIT "
  monVault.write(string.sub(title, 1, W) .. string.rep(" ", math.max(0, W - #title)))
  monVault.setBackgroundColor(colors.black)

  -- Row 2: blank padding
  -- (empty row)

  if not items then
    ui.led(monVault, 1, 3, colors.red, true)
    monVault.setCursorPos(3, 3)
    monVault.setTextColor(colors.red)
    monVault.write("NO VAULT CONN.")
    return
  end

  local pct     = items / capacity * 100
  local pctInt  = math.floor(pct + 0.5)
  local barFill = math.min(math.floor(items / capacity * W + 0.5), W)
  local barCol  = pctInt >= 90 and colors.red
               or pctInt >= 50 and colors.yellow
               or colors.lime

  -- Row 3: percentage (centred)
  monCentre(monVault, 3, string.format("%d%%", pctInt), colors.white)

  -- Row 4: fill bar (full width)
  monVault.setCursorPos(1, 4)
  monVault.setTextColor(colors.black)
  monVault.setBackgroundColor(barCol)
  monVault.write(string.rep(" ", barFill))
  monVault.setBackgroundColor(colors.gray)
  monVault.write(string.rep(" ", W - barFill))
  monVault.setBackgroundColor(colors.black)

  -- Row 5: item count (centred, use k suffix for large numbers)
  local countStr
  if capacity >= 1000 then
    countStr = string.format("%dk/%dk", math.floor(items / 1000), math.floor(capacity / 1000))
  else
    countStr = string.format("%d/%d", items, capacity)
  end
  monCentre(monVault, 5, countStr, colors.lightGray)

  -- Row 6: separator
  monSep(monVault, 6, "-")

  -- Row 7: status LED
  local statusText = pctInt >= 90 and "VAULT CRITICAL"
                  or pctInt >= 50 and "VAULT FILLING"
                  or "VAULT NOMINAL"
  local statusCol  = pctInt >= 90 and colors.red
                  or pctInt >= 50 and colors.yellow
                  or colors.lime
  ui.led(monVault, 1, 7, statusCol, true)
  monVault.setCursorPos(3, 7)
  monVault.setTextColor(statusCol)
  monVault.write(statusText)
end

-- =========================================================
--  Terminal: live debug display
-- =========================================================

-- Raw current readings captured each poll (updated in main loop)
local rawIn = { false, false, false }
local toggleCount = { 0, 0, 0 }

local SIDES = { "front", "back", "left", "right", "top", "bottom" }

local function boolStr(v)
  return v and "HI" or "lo"
end

local function drawTerm()
  local W = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)

  -- Title bar
  term.setBackgroundColor(colors.orange)
  term.setTextColor(colors.black)
  local title = " MINING CTRL  [DEBUG] "
  term.write(title .. string.rep(" ", math.max(0, W - #title)))
  term.setCursorPos(1, 2)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.gray)
  print(string.rep("-", W))

  -- Relay discovery summary
  term.setTextColor(colors.orange)
  print(" PERIPHERALS FOUND:")
  term.setTextColor(colors.lightGray)
  print(string.format("  relay[1]: %s", relayList[1] and relayList[1].name or "NONE"))
  print(string.format("  relay[2]: %s", relayList[2] and relayList[2].name or "NONE"))
  term.setTextColor(colors.gray)
  print(string.rep("-", W))

  -- Live raw inputs: all 6 sides of each relay + computer
  term.setTextColor(colors.orange)
  print(" RAW INPUTS  (side: relay-L / relay-R / cpu)")
  term.setTextColor(colors.black)
  for _, side in ipairs(SIDES) do
    local vL   = relayList[1] and relayList[1].p.getInput(side) or false
    local vR   = relayList[2] and relayList[2].p.getInput(side) or false
    local vCPU = redstone.getInput(side)
    local anyHi = vL or vR or vCPU
    term.setBackgroundColor(colors.black)
    term.setTextColor(anyHi and colors.white or colors.gray)
    print(string.format("  %-6s  %s  /  %s  /  %s",
      side,
      boolStr(vL), boolStr(vR), boolStr(vCPU)
    ))
  end
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.gray)
  print(string.rep("-", W))

  -- Channel toggle counters
  term.setTextColor(colors.orange)
  print(" TOGGLE EVENTS")
  for i, ch in ipairs(CHANNELS) do
    local isOn = not outputs[i]
    ui.ledTerm(
      isOn and colors.lime or colors.red,
      string.format("%-10s [%s] x%d", ch.label,
        isOn and "ON " or "OFF", toggleCount[i])
    )
  end
end

-- =========================================================
--  Main loop
-- =========================================================

applyOutputs()

local vItems, vCap  = vaultFill()
local lastVaultTime = os.epoch("utc")

drawStatus()
drawVault(vItems, vCap)
-- drawTerm() called in main loop below

while true do
  -- Poll all inputs
  local curIn = {}
  for i, ch in ipairs(CHANNELS) do
    curIn[i] = readInput(ch)
  end
  rawIn = curIn

  -- Rising edge → toggle output
  local changed = false
  for i = 1, #CHANNELS do
    if curIn[i] and not prevIn[i] then
      outputs[i] = not outputs[i]
      toggleCount[i] = toggleCount[i] + 1
      changed = true
    end
  end

  if changed then
    applyOutputs()
    drawStatus()
  end

  -- Always redraw terminal so raw values update live
  drawTerm()

  prevIn = curIn

  -- Periodic vault refresh
  if os.epoch("utc") - lastVaultTime >= VAULT_REFRESH * 1000 then
    vItems, vCap  = vaultFill()
    lastVaultTime = os.epoch("utc")
    drawVault(vItems, vCap)
  end

  os.sleep(0.05)
end
