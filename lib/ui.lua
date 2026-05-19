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

-- Standard node identity header for the local terminal.
-- Clears the screen and draws: orange title bar, then
-- label / group / net rows with LED dots, then a separator.
-- Each app adds its own status rows after calling this.
local function nodeHeader(appName, label, group, factory, netOk)
  local W = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)

  -- Title bar
  term.setBackgroundColor(colors.orange)
  term.setTextColor(colors.black)
  term.write(" FACTORY OS ")
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.lightGray)
  term.write(" " .. string.upper(appName))
  if factory and factory ~= "" and factory ~= "main" then
    term.setTextColor(colors.gray)
    term.write("  [" .. factory .. "]")
  end
  print("")

  term.setTextColor(colors.gray)
  print(("-"):rep(W))

  ledTerm(colors.cyan,   "Label:  " .. (label or "?"))
  ledTerm(
    (group and group ~= "") and colors.orange or colors.gray,
    "Group:  " .. ((group and group ~= "") and group or "(none)")
  )
  ledTerm(
    netOk and colors.lime or colors.red,
    "Net:    " .. (netOk and "online" or "no modem")
  )
  term.setTextColor(colors.gray)
  print(("-"):rep(W))
end

return {
  resetTerm  = resetTerm,
  ledTerm    = ledTerm,
  clearMon   = clearMon,
  led        = led,
  statusLine = statusLine,
  nodeHeader = nodeHeader,
}
