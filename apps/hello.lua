-- =========================================================
--  Factory OS SCADA Test
-- =========================================================

local monitors = {
  peripheral.find("monitor")
}

local modem = peripheral.find(
  "modem",
  function(_, m)
    return m.isWireless()
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

local function draw(mon, heartbeat)

  mon.setBackgroundColor(colors.black)
  mon.clear()

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
    "STORAGE TELEMETRY",
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

  -- heartbeat led

  mon.setCursorPos(w-3,2)

  if heartbeat then
    mon.setBackgroundColor(colors.lime)
  else
    mon.setBackgroundColor(colors.green)
  end

  mon.write(" ")

  mon.setBackgroundColor(colors.black)
end

-- =========================================================
--  Receive telemetry
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
--  UI loop
-- =========================================================

local function uiLoop()

  local heartbeat = false

  while true do

    heartbeat = not heartbeat

    for _, mon in ipairs(monitors) do

      pcall(function()

        mon.setTextScale(0.5)

        draw(mon, heartbeat)

      end)
    end

    sleep(0.5)
  end
end

parallel.waitForAny(
  networkLoop,
  uiLoop
)