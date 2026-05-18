-- =========================================================
--  Factory OS Wireless Helper
-- =========================================================
--  Find the first wireless ender modem, open rednet, and
--  return (modem, side).  Returns (nil, nil) if not found.
-- =========================================================

local function find()
  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" then
      local modem = peripheral.wrap(side)
      local ok, isWireless = pcall(function()
        return modem.isWireless()
      end)
      if ok and isWireless then
        rednet.open(side)
        return modem, side
      end
    end
  end
  return nil, nil
end

return { find = find }
