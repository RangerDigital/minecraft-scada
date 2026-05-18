-- =========================================================
--  Factory OS Storage Node
-- =========================================================

local CONFIG = {
  address = "Trash",
  refreshRate = 2,
  requestCooldown = 3,
  maxBatch = 1000
}

-- =========================================================
--  Screen Helpers
-- =========================================================

local function resetScreen()

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)

  term.clear()
  term.setCursorPos(1,1)
end

local function drawHome()

  resetScreen()

  term.setTextColor(colors.orange)

  print("================================")
  print("      FACTORY OS STORAGE")
  print("================================")
  print("")

  term.setTextColor(colors.lime)

  print("Storage node online")

  term.setTextColor(colors.lightGray)

  print("")
  print("Place item on depot")
  print("to edit overflow limit")
end

-- =========================================================
--  Peripherals
-- =========================================================

local stock = peripheral.find("Create_StockTicker")
local depot = peripheral.find("create:depot")

local modem = peripheral.find(
  "modem",
  function(_, m)

    local ok, wireless = pcall(function()
      return m.isWireless()
    end)

    return ok and wireless
  end
)

if not stock then
  error("No Stock Ticker found")
end

if not depot then
  error("No Create Depot found")
end

if modem then
  rednet.open(peripheral.getName(modem))
end

-- =========================================================
--  Data
-- =========================================================

if not fs.exists("/data") then
  fs.makeDir("/data")
end

local POLICY_FILE = "/data/policies.json"

local policies = {}

-- =========================================================
--  Policies
-- =========================================================

local function loadPolicies()

  if not fs.exists(POLICY_FILE) then
    return
  end

  local f = fs.open(POLICY_FILE, "r")

  local raw = f.readAll()

  f.close()

  local data =
    textutils.unserializeJSON(raw)

  if type(data) == "table" then
    policies = data
  end
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

  local ok, item = pcall(function()

    return depot.getItemDetail(1)

  end)

  if not ok or not item then
    return nil
  end

  return item.name
end

-- =========================================================
--  Config Loop
-- =========================================================

local lastDepotItem = nil

local function configLoop()

  while true do

    local item = getDepotItem()

    if item and item ~= lastDepotItem then

      resetScreen()

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

        if modem then

          rednet.broadcast({

            type = "storage_policy",

            node =
              os.getComputerLabel()
              or tostring(os.getComputerID()),

            item = item,

            limit = limit

          }, "factoryos")
        end

      else

        term.setTextColor(colors.red)

        print("")
        print("Invalid number")
      end

      sleep(2)

      drawHome()
    end

    lastDepotItem = item

    sleep(0.5)
  end
end

-- =========================================================
--  Export Loop
-- =========================================================

local lastRequest = -999

local function exportLoop()

  while true do

    local stockMap = getStockMap()

    local selectedItem = nil
    local biggestOverflow = 0

    for item, cfg in pairs(policies) do

      local current =
        stockMap[item] or 0

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

        local ok, err = pcall(function()

          stock.requestFiltered(
            CONFIG.address,
            {
              name = selectedItem,
              _requestCount = amount
            }
          )

        end)

        if ok then

          lastRequest = os.clock()

          if modem then

            rednet.broadcast({

              type = "storage_update",

              node =
                os.getComputerLabel()
                or tostring(os.getComputerID()),

              item = selectedItem,

              amount = amount,

              overflow = biggestOverflow

            }, "factoryos")
          end
        end
      end
    end

    sleep(CONFIG.refreshRate)
  end
end

-- =========================================================
--  Boot
-- =========================================================

drawHome()

parallel.waitForAny(
  configLoop,
  exportLoop
)