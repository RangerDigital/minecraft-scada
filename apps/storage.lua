-- =========================================================
--  Factory OS Storage Node v1.6
-- =========================================================

local CONFIG = {
  address = "Trash",
  refreshRate = 2,
  requestCooldown = 3,
  maxBatch = 1000,
  telemetryRate = 2
}

-- =========================================================
--  Shared libraries
-- =========================================================

local wireless = dofile("/lib/wireless.lua")
local ui       = dofile("/lib/ui.lua")
local util     = dofile("/lib/util.lua")
local config   = dofile("/lib/config.lua")

local PROTOCOL = config.protocol()

local resetTerm = ui.resetTerm
local ledTerm   = ui.ledTerm

-- =========================================================
--  Peripherals
-- =========================================================

local stock = peripheral.find("Create_StockTicker")
local depot = peripheral.find("create:depot")

if not stock then
  error("No Stock Ticker")
end

if not depot then
  error("No Depot")
end

-- =========================================================
--  Wireless modem
-- =========================================================

local _, wirelessSide = wireless.find()

-- =========================================================
--  Data
-- =========================================================

if not fs.exists("/data") then
  fs.makeDir("/data")
end

local POLICY_FILE = "/data/policies.json"

local policies = {}

local latestExport = "none"

local stockMap = {}

local _cfg        = config.load("storage")
local nodeName    = _cfg.name
local nodeLabel   = _cfg.label
local nodeGroup   = _cfg.group
local factoryName = _cfg.factory_name

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
--  Stock
-- =========================================================

local function updateStock()

  local map = {}

  local ok, data = pcall(function()
    return stock.stock()
  end)

  if not ok then
    return
  end

  for _, item in ipairs(data) do
    map[item.name] = item.count
  end

  stockMap = map
end

-- =========================================================
--  Depot
-- =========================================================

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
--  Telemetry
-- =========================================================

local function buildItems()

  local items = {}

  for item, cfg in pairs(policies) do

    local current =
      stockMap[item] or 0

    local overflow =
      current - cfg.limit

    table.insert(items, {

      item = item,

      current = current,

      limit = cfg.limit,

      overflow = overflow
    })
  end

  return items
end

local function broadcastStatus()

  if not wirelessSide then
    return
  end

  rednet.broadcast({

    type = "storage_status",

    node = nodeName,

    label = nodeLabel,

    group = nodeGroup,

    latestExport = latestExport,

    items = buildItems(),

    heartbeat = os.epoch("utc")

  }, PROTOCOL)
end

-- =========================================================
--  Status UI
-- =========================================================

local function drawStatus()
  ui.nodeHeader("storage", nodeLabel, nodeGroup, factoryName, wirelessSide ~= nil)

  ledTerm(colors.orange, "Export: " .. latestExport)

  print("")

  local sorted = {}

  for item in pairs(policies) do
    table.insert(sorted, item)
  end

  table.sort(sorted)

  for _, item in ipairs(sorted) do

    local cfg = policies[item]

    local current =
      stockMap[item] or 0

    local overflow =
      current - cfg.limit

    local short =
      item:gsub("minecraft:", "")
      :sub(1,12)

    if overflow > 0 then

      term.setTextColor(colors.red)

      print(string.format(
        "%-12s %5d/%-5d +%d",
        short,
        current,
        cfg.limit,
        overflow
      ))

    else

      term.setTextColor(colors.lime)

      print(string.format(
        "%-12s %5d/%-5d",
        short,
        current,
        cfg.limit
      ))
    end
  end
end

-- =========================================================
--  Config
-- =========================================================

local lastDepotItem = nil

local function configLoop()

  while true do

    local item = getDepotItem()

    if item and item ~= lastDepotItem then

      resetTerm()

      term.setTextColor(colors.orange)

      print("Factory OS Storage Node v1.6")

      print("")

      term.setTextColor(colors.cyan)

      print(item)

      local current =
        policies[item]
        and policies[item].limit
        or 0

      print("")

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

        broadcastStatus()
      end

      sleep(1)
    end

    lastDepotItem = item

    sleep(0.5)
  end
end

-- =========================================================
--  Export
-- =========================================================

local lastRequest = -999

local function exportLoop()

  while true do

    updateStock()

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

        local ok = pcall(function()

          stock.requestFiltered(
            CONFIG.address,
            {
              name = selectedItem,
              _requestCount = amount
            }
          )
        end)

        if ok then

          latestExport =
            amount
            .. " "
            .. selectedItem

          lastRequest = os.clock()

          broadcastStatus()
        end
      end
    end

    sleep(CONFIG.refreshRate)
  end
end

-- =========================================================
--  Heartbeat
-- =========================================================

local function telemetryLoop()

  while true do

    broadcastStatus()

    sleep(CONFIG.telemetryRate)
  end
end

-- =========================================================
--  UI
-- =========================================================

local function uiLoop()

  while true do

    if not getDepotItem() then
      drawStatus()
    end

    sleep(1)
  end
end

parallel.waitForAny(
  configLoop,
  exportLoop,
  telemetryLoop,
  uiLoop
)