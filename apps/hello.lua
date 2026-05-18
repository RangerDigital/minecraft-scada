-- =========================================================
--  Factory OS SCADA
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

local function clear(mon)

  mon.setBackgroundColor(colors.black)
  mon.clear()
  mon.setCursorPos(1,1)
end

local function center(mon, y, text, color)

  local w,h = mon.getSize()

  mon.setTextColor(color)

  mon.setCursorPos(
    math.floor((w - #text)/2),
    y
  )

  mon.write(text)
end

local function led(mon,x,y,color,on)

  mon.setCursorPos(x,y)

  mon.setBackgroundColor(
    on and color or colors.gray
  )

  mon.write(" ")

  mon.setBackgroundColor(colors.black)
end

-- =========================================================
--  Configure
-- =========================================================

for _, mon in ipairs(monitors) do

  pcall(function()
    mon.setTextScale(0.5)
  end)
end

-- =========================================================
--  Main Display
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
    "STORAGE NETWORK",
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
  mon.write("Export:")

  mon.setTextColor(colors.lime)
  mon.write(" " .. latest.amount)

  mon.setCursorPos(3,15)

  mon.setTextColor(colors.white)
  mon.write("Overflow:")

  mon.setTextColor(colors.red)
  mon.write(" +" .. latest.overflow)

  -- status

  mon.setTextColor(colors.lightGray)

  mon.setCursorPos(3,19)
  mon.write("Heartbeat")

  led(mon,16,19,colors.lime,heartbeat)

  mon.setCursorPos(3,21)
  mon.write("Wireless")

  led(mon,16,21,colors.cyan,modem)

  mon.setCursorPos(3,23)
  mon.write("Storage")

  led(mon,16,23,colors.orange,true)
end

-- =========================================================
--  Tiny Monitor
-- =========================================================

local function drawTiny(mon, heartbeat)

  clear(mon)

  local w,h = mon.getSize()

  paintutils.drawFilledBox(
    1,1,w,h,
    colors.black
  )

  mon.setCursorPos(2,2)
  mon.setTextColor(colors.lightGray)
  mon.write("HB")

  led(mon,5,2,colors.lime,heartbeat)

  mon.setCursorPos(2,4)
  mon.write("NET")

  led(mon,6,4,colors.cyan,modem)

  mon.setCursorPos(2,6)
  mon.write("STR")

  led(mon,6,6,colors.orange,true)
end

-- =========================================================
--  Network
-- =========================================================

local function networkLoop()

  while true do

    local _, msg, protocol =
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