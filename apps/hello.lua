-- =========================================================
--  Factory OS SCADA v1.6
-- =========================================================

local monitors = {
  peripheral.find("monitor")
}

-- =========================================================
--  Wireless modem ONLY
-- =========================================================

local wirelessSide = nil

for _, side in ipairs(peripheral.getNames()) do

  if peripheral.getType(side) == "modem" then

    local modem = peripheral.wrap(side)

    local ok, wireless = pcall(function()
      return modem.isWireless()
    end)

    if ok and wireless then

      wirelessSide = side

      break
    end
  end
end

if wirelessSide then
  rednet.open(wirelessSide)
end

local nodes = {}

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

local function drawMain(mon, heartbeat, id)

  clear(mon)

  local w,h = mon.getSize()

  -- Header

  paintutils.drawFilledBox(
    1,1,w,1,
    colors.orange
  )

  mon.setTextColor(colors.black)

  mon.setCursorPos(2,1)
  mon.write("Factory OS")

  local info =
    "#" .. id ..
    " " ..
    w .. "x" .. h

  mon.setCursorPos(
    w - #info - 3,
    1
  )

  mon.write(info)

  led(
    mon,
    w,
    1,
    colors.lime,
    heartbeat
  )

  -- Status

  statusLine(
    mon,
    3,
    colors.lime,
    "Heartbeat",
    heartbeat
  )

  statusLine(
    mon,
    5,
    colors.cyan,
    "Wireless",
    wirelessSide ~= nil
  )

  statusLine(
    mon,
    7,
    colors.orange,
    "Discovery",
    true
  )

  mon.setCursorPos(3,9)

  mon.setTextColor(colors.gray)

  mon.write(
    "MODEM: " ..
    tostring(wirelessSide)
  )

  -- Nodes

  mon.setTextColor(colors.cyan)

  mon.setCursorPos(3,12)
  mon.write("Network Nodes")

  local y = 14

  for name, node in pairs(nodes) do

    local alive =
      (os.epoch("utc") - node.lastSeen)
      < 6000

    led(
      mon,
      3,
      y,
      alive and colors.lime or colors.red,
      true
    )

    mon.setCursorPos(5,y)

    mon.setTextColor(colors.white)

    mon.write(name)

    y = y + 2
  end

  y = y + 1

  mon.setTextColor(colors.cyan)

  mon.setCursorPos(3,y)
  mon.write("Storage Status")

  y = y + 2

  for _, node in pairs(nodes) do

    for _, item in ipairs(node.items or {}) do

      local short =
        item.item
        :gsub("minecraft:", "")
        :sub(1,12)

      mon.setCursorPos(3,y)

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
        return
      end
    end
  end
end

-- =========================================================
--  Tiny Status Monitor
-- =========================================================

local function drawTiny(mon, heartbeat)

  clear(mon)

  center(mon,1,"STATUS",colors.orange)

  local aliveCount = 0

  for _, node in pairs(nodes) do

    local alive =
      (os.epoch("utc") - node.lastSeen)
      < 6000

    if alive then
      aliveCount = aliveCount + 1
    end
  end

  led(
    mon,
    3,
    3,
    colors.lime,
    heartbeat
  )

  mon.setCursorPos(5,3)
  mon.setTextColor(colors.lightGray)
  mon.write("HB")

  led(
    mon,
    3,
    5,
    colors.cyan,
    wirelessSide ~= nil
  )

  mon.setCursorPos(5,5)
  mon.write("NET")

  led(
    mon,
    3,
    7,
    aliveCount > 0
      and colors.orange
      or colors.red,
    true
  )

  mon.setCursorPos(5,7)
  mon.write("NODES")
end

-- =========================================================
--  Network
-- =========================================================

local function networkLoop()

  while true do

    local id, msg, protocol =
      rednet.receive("factoryos")

    if type(msg) == "table" then

      if msg.type == "storage_status" then

        nodes[msg.node] = {

          lastSeen = os.epoch("utc"),

          items = msg.items,

          latestExport = msg.latestExport
        }
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
          drawMain(mon, heartbeat, i)
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