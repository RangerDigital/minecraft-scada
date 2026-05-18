-- =========================================================
--  Factory OS - Monitor Discovery
-- =========================================================

term.setBackgroundColor(colors.black)
term.clear()

-- =========================================================
--  Helpers
-- =========================================================

local function center(mon, y, text, color)

  local w, h = mon.getSize()

  mon.setTextColor(color or colors.white)

  mon.setCursorPos(
    math.floor((w - #text) / 2),
    y
  )

  mon.write(text)
end

local function clear(mon)

  mon.setBackgroundColor(colors.black)
  mon.clear()
  mon.setCursorPos(1,1)
end

-- =========================================================
--  Find monitors
-- =========================================================

local monitors = { peripheral.find("monitor") }

term.setTextColor(colors.orange)

print("====================================")
print("         FACTORY OS")
print("====================================")
print("")

if #monitors == 0 then

  term.setTextColor(colors.red)

  print("No monitors found")

  return
end

term.setTextColor(colors.lime)

print("Detected monitors: " .. #monitors)

-- =========================================================
--  Configure + Draw
-- =========================================================

for i, mon in ipairs(monitors) do

  pcall(function()

    mon.setTextScale(0.5)

    clear(mon)

    local w, h = mon.getSize()

    -- Header

    paintutils.drawFilledBox(
      1,1,w,3,
      colors.gray
    )

    mon.setBackgroundColor(colors.gray)

    center(mon, 2, "FACTORY OS", colors.black)

    mon.setBackgroundColor(colors.black)

    -- Main

    center(mon, 6, "MONITOR #" .. i, colors.lime)

    mon.setTextColor(colors.lightGray)

    center(mon, 9, w .. " x " .. h)

    center(mon, 11, peripheral.getName(mon))

  end)
end

-- =========================================================
--  Heartbeat
-- =========================================================

local tick = 0

while true do

  tick = tick + 1

  for i, mon in ipairs(monitors) do

    pcall(function()

      local w, h = mon.getSize()

      mon.setCursorPos(2, h - 1)

      mon.setTextColor(colors.cyan)

      mon.clearLine()

      mon.write(
        "ONLINE  #" .. i ..
        "  TICK " .. tick
      )

    end)
  end

  sleep(1)
end