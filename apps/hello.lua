-- =========================================================
--  Factory OS SCADA v1.4
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
  node = "none",
  latestExport = "none",
  items = {}
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

local function statusLine(
  mon,
  y,
  color,
  text,
  on
)

  led(mon,3,y,color,on)

  mon.setCursorPos(5,y)

  mon.setTextColor(colors.lightGray)

  mon.write(text)
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

  -- Header

  paintutils.drawFilledBox(
    1,1,w,2,
    colors.orange
  )

  center(
    mon,
    1,
    "Factory OS SCADA v1.4",
    colors.black
  )

  -- Status

  statusLine(
    mon,
    5,
    colors.lime,
    "Heartbeat",
    heartbeat
  )

  statusLine(
    mon,
    7,
    colors.cyan,
    "Wireless",
    modem ~= nil
  )

  statusLine(
    mon,
    9,
    colors.orange,
    "Storage Network",
    true
  )

  -- Node

  mon.setTextColor(colors.white)

  mon.setCursorPos(3,12)
  mon.write("Node:")

  mon.setTextColor(colors.lightGray)
  mon.write(" " .. latest.node)

  -- Export

  mon.setCursorPos(3,14)

  mon.setTextColor(colors.white)
  mon.write("Latest Export:")

  mon.setCursorPos(3,15)

  mon.setTextColor(colors.orange)
  mon.write(latest.latestExport)

  -- Items

  mon.setTextColor(colors.cyan)

  mon.setCursorPos(3,18)
  mon.write("Monitored Items")

  local y = 20

  for _, item in ipairs(latest.items) do

    mon.setCursorPos(3,y)

    local short =
      item.item
      :gsub("minecraft:", "")
      :sub(1,12)

    if item.overflow > 0 then

      mon.setTextColor(colors.red)

      mon.write(string.format(
        "%-12s %5d/%-5d +%d",
        short,
        item.current,
        item.limit,
        item.overflow
      ))

    else

      mon.setTextColor(colors.lime)

      mon.write(string.format(
        "%-12s %5d/%-5d",
        short,
        item.current,
        item.limit
      ))
    end

    y = y + 1

    if y > h then
      break
    end
  end
end

-- =========================================================
--  Tiny Monitor
-- =========================================================

local function drawTiny(mon, heartbeat)

  clear(mon)

  center(
    mon,
    1,
    "Factory OS",
    colors.orange
  )

  statusLine(
    mon,
    3,
    colors.lime,
    "HB",
    heartbeat
  )

  statusLine(
    mon,
    5,
    colors.cyan,
    "NET",
    modem ~= nil
  )

  statusLine(
    mon,
    7,
    colors.orange,
    "STR",
    true
  )
end

-- =========================================================
--  Network
-- =========================================================

local function networkLoop()

  while true do

    local _, msg =
      rednet.receive("factoryos")

    if type(msg) == "table" then

      if msg.type == "storage_status" then

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