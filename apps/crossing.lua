-- =========================================================
--  Factory OS Rail Crossing Node v1.0
--  Monitors redstone signal on the back of the computer
--  and blinks two Create Nixie Tubes over the wired
--  modem network to act as a rail crossing display.
--
--  Wiring:
--    back side  – redstone input (train detector / contact)
--    wired modem network – two Create_NixieTube peripherals
-- =========================================================

local CONFIG = {
  pollRate    = 0.1,   -- redstone poll interval in seconds

  -- Nixie display characters
  activeChar  = "X",   -- shown while crossing is active
  idleChar    = "-",   -- shown while crossing is clear

  -- Active blink signal (red, fast blink)
  activeSignal = {
    { r=255, g=30,  b=0,  glowWidth=4, glowHeight=4,
      blinkPeriod=10, blinkOffTime=5  },  -- tube 1
    { r=255, g=30,  b=0,  glowWidth=4, glowHeight=4,
      blinkPeriod=10, blinkOffTime=5  },  -- tube 2 (offset)
  },

  -- Idle signal (dim green, no blink)
  idleSignal = {
    { r=0, g=180, b=0, glowWidth=1, glowHeight=1,
      blinkPeriod=1, blinkOffTime=0 },
    { r=0, g=180, b=0, glowWidth=1, glowHeight=1,
      blinkPeriod=1, blinkOffTime=0 },
  },
}

local wireless = dofile("/lib/wireless.lua")
local ui       = dofile("/lib/ui.lua")
local config   = dofile("/lib/config.lua")

-- =========================================================
--  Node identity
-- =========================================================

local _cfg        = config.load("crossing")
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

-- Discover the first two Create Nixie Tubes on the network.
local nixies = {}
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "Create_NixieTube" then
    table.insert(nixies, { name = name, p = peripheral.wrap(name) })
    if #nixies >= 2 then break end
  end
end

local monitors = { peripheral.find("monitor") }

-- =========================================================
--  State
-- =========================================================

local crossingActive = false   -- current computed state
local lastActive     = nil     -- previous state (force redraw on change)

-- =========================================================
--  Helpers
-- =========================================================

local function try(fn)
  local ok, v = pcall(fn)
  return ok and v or nil
end

-- Apply a signal table { r,g,b,glowWidth,glowHeight,blinkPeriod,blinkOffTime }
-- to a single nixie peripheral using setSignal.
local function applySignal(nixie, sig1, sig2)
  try(function()
    nixie.setSignal(sig1, sig2)
  end)
end

-- Apply display text to a nixie.
local function applyText(nixie, text, colour)
  try(function()
    nixie.setText(text, colour)
  end)
end

-- =========================================================
--  Display update
-- =========================================================

local function updateNixies(active)
  if #nixies == 0 then return end

  if active then
    -- Each tube shows "X" and blinks in red.
    -- Tube 2 blinkOffTime is offset so they alternate.
    local sig1 = CONFIG.activeSignal[1]
    local sig2 = CONFIG.activeSignal[2]

    for i, n in ipairs(nixies) do
      -- Set signal for blinking effect.
      -- Both tubes are controlled through the first tube's
      -- setSignal when they form a row; pass both as
      -- positional args so tube 1 and tube 2 get their own
      -- settings.
      if i == 1 then
        applySignal(n.p, sig1, sig2)
      end
      applyText(n.p, CONFIG.activeChar, "red")
    end
  else
    local sig1 = CONFIG.idleSignal[1]
    local sig2 = CONFIG.idleSignal[2]

    for i, n in ipairs(nixies) do
      if i == 1 then
        applySignal(n.p, sig1, sig2)
      end
      applyText(n.p, CONFIG.idleChar, "green")
    end
  end
end

-- =========================================================
--  Terminal & monitor UI
-- =========================================================

local function drawTerminal()
  ui.nodeHeader("CROSSING", nodeLabel, nodeGroup, factoryName,
    wirelessSide ~= nil)

  ledTerm(colors.yellow, "Mode:   Rail Crossing Display")
  ledTerm(
    #nixies > 0 and colors.lime or colors.red,
    "Nixies: " .. #nixies .. " found"
  )
  term.setTextColor(colors.gray)
  local W = term.getSize()
  print(("-"):rep(W))

  statusLine(term, 1, nil, colors.red,
    "Crossing: " .. (crossingActive and "ACTIVE  (trains!)" or "clear"),
    crossingActive)
end

local function drawMonitor(mon)
  ui.clearMon(mon)
  local W, H = mon.getSize()
  mon.setTextScale(H >= 10 and 1.5 or 1)
  W, H = mon.getSize()

  -- Title
  mon.setCursorPos(1, 1)
  mon.setBackgroundColor(colors.orange)
  mon.setTextColor(colors.black)
  local title = " RAIL CROSSING "
  local pad   = math.floor((W - #title) / 2)
  mon.write((" "):rep(pad) .. title .. (" "):rep(W - pad - #title))
  mon.setBackgroundColor(colors.black)

  -- Status
  local row = math.floor(H / 2)
  if crossingActive then
    mon.setTextColor(colors.red)
    local msg = "!! TRAIN !!"
    mon.setCursorPos(math.floor((W - #msg) / 2) + 1, row)
    mon.write(msg)
  else
    mon.setTextColor(colors.lime)
    local msg = "TRACK CLEAR"
    mon.setCursorPos(math.floor((W - #msg) / 2) + 1, row)
    mon.write(msg)
  end
end

local function redraw()
  term.clear()
  term.setCursorPos(1, 1)
  drawTerminal()
  for _, mon in ipairs(monitors) do
    pcall(drawMonitor, mon)
  end
end

-- =========================================================
--  Main loop
-- =========================================================

resetTerm()
redraw()

while true do
  -- Read redstone from back face.
  local powered = redstone.getInput("back")

  if powered ~= crossingActive then
    crossingActive = powered
    updateNixies(crossingActive)
    redraw()
  end

  -- Also redraw if monitors are attached/detached.
  os.sleep(CONFIG.pollRate)
end
