-- =========================================================
--  Factory OS Rail Crossing Node v1.0
--  Monitors redstone signal on the back of the computer
--  and blinks two Create Nixie Tubes over the wired
--  modem network to act as a rail crossing display.
--
--  Wiring:
--    back side  – redstone input (train detector / contact)
--    wired modem network – two Create_NixieTube peripherals
--    speaker (any side or wired)  – plays Polish PKP bell alarm
-- =========================================================

local CONFIG = {
  pollRate    = 0.1,   -- redstone poll interval in seconds

  -- Idle display character (shown when crossing is clear; no signal active)
  idleChar    = "-",

  -- Speaker alarm (Polish PKP two-tone bell)
  beepRate    = 0.5,         -- seconds between bell strikes
  beepVolume  = 3.0,         -- 0-3
  beepPitches = { 18, 12 },  -- alternating pitches: B4 then F#4

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

-- Discover speaker (any attached side or wired modem network).
local speaker = nil
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "speaker" then
    speaker = peripheral.wrap(name)
    break
  end
end

local monitors = { peripheral.find("monitor") }

-- =========================================================
--  State
-- =========================================================

local crossingActive = false   -- current computed state
local lastActive     = nil     -- previous state (force redraw on change)
local lastBeepTime   = 0       -- os.epoch ms of last bell strike
local beepPhase      = 1       -- alternates between CONFIG.beepPitches indices

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

-- Play one bell strike and advance the two-tone phase.
local function playBeep()
  if not speaker then return end
  local pitch = CONFIG.beepPitches[beepPhase]
  try(function()
    speaker.playNote("bell", CONFIG.beepVolume, pitch)
  end)
  beepPhase    = (beepPhase % #CONFIG.beepPitches) + 1
  lastBeepTime = os.epoch("utc")
end

-- =========================================================
--  Display update
-- =========================================================

local function updateNixies(active)
  if #nixies == 0 then return end

  if active then
    -- setSignal only affects the single tube it is called on (unlike setText
    -- which walks the whole physical row).  Call it on every nixie individually.
    for _, n in ipairs(nixies) do
      applySignal(n.p, CONFIG.activeSignal[1], CONFIG.activeSignal[2])
    end
  else
    for _, n in ipairs(nixies) do
      -- Zero the signal first so blinkPeriod is forced to 0 server-side,
      -- then setText clears computerSignal and sets the idle character.
      -- Doing both guarantees the blink stops even if setText fails silently.
      try(function()
        n.p.setSignal(
          { r=0, g=0, b=0, glowWidth=1, glowHeight=1, blinkPeriod=1, blinkOffTime=0 },
          { r=0, g=0, b=0, glowWidth=1, glowHeight=1, blinkPeriod=1, blinkOffTime=0 }
        )
      end)
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
  ledTerm(
    speaker and colors.lime or colors.gray,
    "Speaker: " .. (speaker and "ready" or "not found")
  )
  term.setTextColor(colors.gray)
  local W = term.getSize()
  print(("-"):rep(W))

  ledTerm(
    crossingActive and colors.red or colors.lime,
    "Crossing: " .. (crossingActive and "ACTIVE  (trains!)" or "clear")
  )
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
updateNixies(false)  -- initialise tubes to green idle state on boot
redraw()

while true do
  -- Read redstone from back face.
  local powered = redstone.getInput("back")

  if powered ~= crossingActive then
    crossingActive = powered
    updateNixies(crossingActive)
    if not crossingActive then
      beepPhase = 1  -- reset two-tone sequence when crossing clears
    end
    redraw()
  end

  -- Ring the bell on every beepRate interval while active.
  if crossingActive then
    local now = os.epoch("utc")
    if now - lastBeepTime >= CONFIG.beepRate * 1000 then
      playBeep()
    end
  end

  os.sleep(CONFIG.pollRate)
end
