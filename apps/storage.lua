-- =========================================================
--  Factory OS Storage Node
-- =========================================================

local CONFIG = {
  address = "Trash",
  refreshRate = 2,
  requestCooldown = 3,
  maxBatch = 1000,
  modemChannel = 777
}

-- =========================================================
--  Peripherals
-- =========================================================

local stock = peripheral.find("Create_StockTicker")
local depot = peripheral.find("inventory")
local modem = peripheral.find("modem", function(_, m)
  return m.isWireless()
end)

if not stock then
  error("No Stock Ticker found")
end

if not depot then
  error("No depot/container found")
end

if modem then
  rednet.open(peripheral.getName(modem))
end

-- =========================================================
--  Policies
-- =========================================================

local POLICY_FILE = "/data/policies.json"

if not fs.exists("/data") then
  fs.makeDir("/data")
end

local policies = {}

local function loadPolicies()

  if not fs.exists(POLICY_FILE) then
    return
  end

  local f = fs.open(POLICY_FILE, "r")

  local data = f.readAll()

  f.close()

  policies =
    textutils.unserializeJSON(data)
    or {}
end

local function savePolicies()

  local f = fs.open(POLICY_FILE, "w")

  f.write(
    textutils.serializeJSON(policies)
  )

  f.close()
end

loadPolicies()

-- =========================================================
--  Helpers
-- =========================================================

local function getStockMap()

  local map = {}

  local ok, data = pcall(function()
    return stock.stock()
  end)

  if not ok then
    return map
  end

  for _, item in ipairs(data) do
    map[item.name] = item.count
  end

  return map
end

local function getDepotItem()

  local item = depot.getItemDetail(1)

  if not item then
    return nil
  end

  return item.name
end

-- =========================================================
--  Config UI
-- =========================================================

local lastDepotItem = nil

local function configLoop()

  while true do

    local item = getDepotItem()

    if item and item ~= lastDepotItem then

      term.setBackgroundColor(colors.black)
      term.clear()
      term.setCursorPos(1,1)

      term.setTextColor(colors.orange)

      print("================================")
      print("      FACTORY OS STORAGE")
      print("================================")
      print("")

      term.setTextColor(colors.cyan)

      print("Item:")
      print(item)

      print("")

      local current =
        policies[item]
        and policies[item].limit
        or 0

      term.setTextColor(colors.lightGray)

      print("Current limit: " .. current)

      print("")

      term.setTextColor(colors.white)

      write("New limit > ")

      local input = read()

      local limit = tonumber(input)

      if limit then

        policies[item] = {
          limit = limit
        }

        savePolicies()

        term.setTextColor(colors.lime)

        print("")
        print("Saved.")

      else

        term.setTextColor(colors.red)

        print("")
        print("Invalid number")
      end

      sleep(2)

      term.clear()
    end

    lastDepotItem = item

    sleep(0.5)
  end
end

-- =========================================================
--  Overflow Logic
-- =========================================================

local lastRequest = -999

local function exportLoop()

  while true do

    local map = getStockMap()

    local selectedItem = nil
    local biggestOverflow = 0

    for item, cfg in pairs(policies) do

      local current = map[item] or 0

      local overflow =
        current - cfg.limit

      if overflow > biggestOverflow then

        biggestOverflow = overflow

        selectedItem = item
      end
    end

    if selectedItem then

      if os.clock() - lastRequest
        >= CONFIG.requestCooldown then

        local amount =
          math.min(
            biggestOverflow,
            CONFIG.maxBatch
          )

        pcall(function()

          stock.requestFiltered(
            CONFIG.address,
            {
              name = selectedItem,
              _requestCount = amount
            }
          )

          lastRequest = os.clock()

          -- =================================================
          --  Broadcast telemetry
          -- =================================================

          if modem then

            rednet.broadcast({
              type = "storage_update",

              node = os.getComputerLabel()
                or tostring(os.getComputerID()),

              item = selectedItem,

              amount = amount,

              overflow = biggestOverflow
            }, "factoryos")
          end
        end)
      end
    end

    sleep(CONFIG.refreshRate)
  end
end

-- =========================================================
--  Main
-- =========================================================

parallel.waitForAny(
  configLoop,
  exportLoop
)