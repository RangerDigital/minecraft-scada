-- =========================================================
--  Factory OS UI Primitives
-- =========================================================

-- =========================================================
--  Terminal
-- =========================================================

local function resetTerm()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

local function ledTerm(color, text)
  term.setBackgroundColor(color)
  write(" ")
  term.setBackgroundColor(colors.black)
  write(" ")
  term.setTextColor(colors.lightGray)
  print(text)
end

-- =========================================================
--  Monitor
-- =========================================================

local function clearMon(mon)
  mon.setBackgroundColor(colors.black)
  mon.clear()
  mon.setCursorPos(1, 1)
end

-- Single-cell coloured LED dot.
-- on=true uses `color`, on=false uses gray.
local function led(mon, x, y, color, on)
  mon.setCursorPos(x, y)
  mon.setBackgroundColor(on and color or colors.gray)
  mon.write(" ")
  mon.setBackgroundColor(colors.black)
end

-- LED dot at (x,y) + label at (x+2,y).
-- Text is white when on, gray when off.
local function statusLine(mon, x, y, color, text, on)
  led(mon, x, y, color, on)
  mon.setCursorPos(x + 2, y)
  mon.setTextColor(on and colors.white or colors.gray)
  mon.write(text)
end

return {
  resetTerm  = resetTerm,
  ledTerm    = ledTerm,
  clearMon   = clearMon,
  led        = led,
  statusLine = statusLine,
}
