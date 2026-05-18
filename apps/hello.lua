-- =========================================================
--  Factory OS SCADA Test
-- =========================================================

local monitors = {
  peripheral.find("monitor")
}

local modem = peripheral.find(
  "modem",
  function(_, m)

    local ok, wireless = pcall(function()
      return m.isWireless()
    end)

    return ok and wireless
  end
)

if modem then
  rednet.open(peripheral.getName(modem))
end

local latest = {
  item = "none",
  amount = 0,
  overflow = 0,
  node = "none"
}

-- =========================================================
--  Helpers
-- =========================================================

local function center(mon, y, text, color)

  local w,h = mon.getSize()

  mon.setTextColor(color)

  mon.setCursorPos(
    math.floor((w - #text)/2),
    y
  )

  mon.write(text)
end

local function clear(mon)

  mon.setBackgroundColor(colors.black)
  mon.clear()
  mon.setCursorPos(1,1)
end

local function led(mon, x, y, color, on)

  if on then
    mon.setBackgroundColor(color)
  else
    mon.setBackgroundColor(colors.gray)
  end

  mon.setCursorPos(x,y)
  mon.write(" ")

  mon.setBackgroundColor(colors.black)
end

-- =========================================================
--  Configure monitors
-- =========================================================

for _, mon in ipairs(monitors) do

  pcall(function()

    mon.setTextScale(0.5)

  end)
end

-- =========================================================
--  Main monitor
-- =========================================================

local function drawMain(mon, heartbeat)

  clear(mon)

  local w,h = mon.getSize()

  paintutils.drawFilledBox(
    1,1,w,3,
    colors.orange
  )

  center(
    mon,
    2,
    "FACTORY OS",
    colors.black
  )

  center(
    mon,
    6,
    "SCADA TELEMETRY",
    colors.cyan
  )

  mon.setTextColor(colors.white)

  mon.setCursorPos(3,9)
  mon.write("Node:")

  mon.setTextColor(colors.lightGray)
  mon.write(" " .. latest.node)

  mon.setCursorPos(3,11)

  mon.setTextColor(colors.white)
  mon.write("Item:")

  mon.setTextColor(colors.orange)
  mon.write(" " .. latest.item)

  mon.setCursorPos(3,13)

  mon.setTextColor(colors.white)
  mon.write("Batch:")

  mon.setTextColor(colors.lime)
  mon.write(" " .. latest.amount)

  mon.setCursorPos(3,15)

  mon.setTextColor(colors.white)
  mon.write("Overflow:")

  mon.setTextColor(colors.red)
  mon.write(" +" .. latest.overflow)

  -- status leds

  mon.setTextColor(colors.lightGray)

  mon.setCursorPos(3,19)
  mon.write("Heartbeat")

  led(
    mon,
    16,
    19,
    colors.lime,
    heartbeat
  )

  mon.setCursorPos(3,21)
  mon.write("Wireless")

  led(
    mon,
    16,
    21,
    modem and colors.cyan or colors.red,
    heartbeat
  )

  mon.setCursorPos(3,23)
  mon.write("Monitors")

  led(
    mon,
    16,
    23,
    colors.orange,
    true
  )
end

-- =========================================================
--  Tiny monitor
-- =========================================================

local function drawTiny(mon, heartbeat)

  clear(mon)

  local w,h = mon.getSize()

  paintutils.drawFilledBox(
    1,1,w,h,
    colors.gray
  )

  local centerX = math.floor(w/2)

  led(
    mon,
    centerX,
    3,
    colors.lime,
    heartbeat
  )

  led(
    mon,
    centerX,
    6,
    modem and colors.cyan or colors.red,
    heartbeat
  )

  led(
    mon,
    centerX,
    9,
    colors.orange,
    true
  )

  mon.setTextColor(colors.black)

  center(mon, 2, "HB", colors.black)
  center(mon, 5, "NET", colors.black)
  center(mon, 8, "MON", colors.black)
end

-- =========================================================
--  Network
-- =========================================================

local function networkLoop()

  while true do

    local id, msg, protocol =
      rednet.receive("factoryos")

    if type(msg) == "table" then

      if msg.type == "storage_update" then

        latest = msg
      end
    end
  end
end

-- =========================================================
--  UI
-- =========================================================

local function uiLoop()

  local heartbeat = false

  while true do

    heartbeat = not heartbeat

    for i, mon in ipairs(monitors) do

      pcall(function()

        if i == 4 then
          drawTiny(mon, heartbeat)
        else
          drawMain(mon, heartbeat)
        end

      end)
    end

    sleep(0.5)
  end
end

parallel.waitForAny(
  networkLoop,
  uiLoop
)