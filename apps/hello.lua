-- =========================================================
--  Factory OS SCADA v1.5
-- =========================================================

local monitors = {
  peripheral.find("monitor")
}

local modemName = nil

for _, name in ipairs(peripheral.getNames()) do

  if peripheral.getType(name) == "modem" then

    local modem = peripheral.wrap(name)

    local ok, wireless = pcall(function()
      return modem.isWireless()
    end)

    if ok and wireless then
      modemName = name
      break
    end
  end
end

if modemName then
  rednet.open(modemName)
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
--  Main
-- =========================================================

local function drawMain(mon, heartbeat, id)

  clear(mon)

  local w,h = mon.getSize()

  paintutils.drawFilledBox(
    1,1,w,2,
    colors.orange
  )

  mon.setTextColor(colors.black)

  mon.setCursorPos(2,1)
  mon.write("Factory OS SCADA")

  local info =
    "#" .. id ..
    "  " ..
    w .. "x" .. h

  mon.setCursorPos(
    w - #info - 4,
    1
  )

  mon.write(info)

  led(
    mon,
    w - 1,
    1,
    colors.lime,
    heartbeat
  )

  statusLine(
    mon,
    4,
    colors.lime,
    "Heartbeat",
    heartbeat
  )

  statusLine(
    mon,
    6,
    colors.cyan,
    "Wireless",
    modemName ~= nil
  )

  statusLine(
    mon,
    8,
    colors.orange,
    "Discovery",
    true
  )

  mon.setTextColor(colors.cyan)

  mon.setCursorPos(3,11)
  mon.write("Network Nodes")

  local y = 13

  for name, node in pairs(nodes) do

    local alive =
      (os.clock() - node.lastSeen) < 6

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
--  Tiny Monitor
-- =========================================================

local function drawTiny(mon, heartbeat, id)

  clear(mon)

  local w,h = mon.getSize()

  paintutils.drawFilledBox(
    1,1,w,2,
    colors.orange
  )

  mon.setTextColor(colors.black)

  mon.setCursorPos(2,1)
  mon.write("#" .. id)

  led(
    mon,
    w - 1,
    1,
    colors.lime,
    heartbeat
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
    modemName ~= nil
  )

  local nodeCount = 0

  for _ in pairs(nodes) do
    nodeCount = nodeCount + 1
  end

  statusLine(
    mon,
    7,
    colors.orange,
    tostring(nodeCount),
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

        nodes[msg.node] = {

          lastSeen = os.clock(),

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
          drawTiny(mon, heartbeat, i)
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