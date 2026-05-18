-- =========================================================
--  Factory OS Hello
-- =========================================================

term.setBackgroundColor(colors.black)
term.clear()

local w, h = term.getSize()

local function center(y, text, color)

  term.setTextColor(color or colors.white)

  term.setCursorPos(
    math.floor((w - #text) / 2),
    y
  )

  write(text)
end

paintutils.drawFilledBox(1,1,w,3,colors.gray)

center(2, "FACTORY OS", colors.black)

center(6, "HELLO WORLD", colors.lime)

term.setTextColor(colors.lightGray)

center(9, "Industrial automation runtime online")

while true do

  term.setTextColor(colors.cyan)

  center(
    13,
    "Heartbeat: " ..
    textutils.formatTime(os.time(), true)
  )

  sleep(1)
end