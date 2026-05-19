-- =========================================================
--  Factory OS Shared Config
-- =========================================================
--  Reads and writes all per-node configuration fields:
--    node_name     - internal rednet ID
--    node_label    - human-friendly display name
--    node_group    - group header on supervisor
--    factory_name  - factory namespace (default "main")
--                    Two factories with different names
--                    won't see each other's telemetry.
-- =========================================================

local CONFIG_DIR = "/config"

local FILES = {
  name         = CONFIG_DIR .. "/node_name.txt",
  label        = CONFIG_DIR .. "/node_label.txt",
  group        = CONFIG_DIR .. "/node_group.txt",
  factory_name = CONFIG_DIR .. "/factory_name.txt",
}

-- =========================================================
--  Internal helpers
-- =========================================================

local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  local v = f.readAll()
  f.close()
  return v:gsub("%s+$", "")
end

local function writeFile(path, value)
  if not fs.exists(CONFIG_DIR) then
    fs.makeDir(CONFIG_DIR)
  end
  local f = fs.open(path, "w")
  f.write(value)
  f.close()
end

local function prompt(label, current, default)
  term.setTextColor(colors.lightGray)
  write(label .. " ")
  if current and current ~= "" then
    term.setTextColor(colors.cyan)
    write("[" .. current .. "]")
  elseif default then
    term.setTextColor(colors.gray)
    write("[" .. default .. "]")
  end
  term.setTextColor(colors.white)
  write(": ")
  local v = read()
  v = v:gsub("%s+$", ""):gsub("^%s+", "")
  if v == "" then
    return current or default or ""
  end
  return v
end

-- =========================================================
--  Public API
-- =========================================================

-- Load all config values and return them as a table.
-- Missing files fall back to sensible defaults.
local function load(appPrefix)
  local name = readFile(FILES.name)
             or os.getComputerLabel()
             or ((appPrefix or "node") .. "_" .. os.getComputerID())

  return {
    name         = name,
    label        = readFile(FILES.label)        or name,
    group        = readFile(FILES.group)        or "",
    factory_name = readFile(FILES.factory_name) or "main",
  }
end

-- Return the rednet protocol string for this node's factory.
-- Nodes with different factory names are fully isolated.
local function protocol()
  local factoryName = readFile(FILES.factory_name) or "main"
  return "factoryos_" .. factoryName
end

-- Interactive wizard – prompts the user to set all shared
-- config fields.  Existing values are shown as defaults.
local function setup()

  local current = {
    name         = readFile(FILES.name)         or "",
    label        = readFile(FILES.label)        or "",
    group        = readFile(FILES.group)        or "",
    factory_name = readFile(FILES.factory_name) or "",
  }

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.orange)
  print("")
  print("====================================")
  print("       NODE CONFIGURATION")
  print("====================================")
  print("")
  term.setTextColor(colors.lightGray)
  print("Press Enter to keep current value.")
  print("")

  -- Node name
  term.setTextColor(colors.yellow)
  print("Node Name  (internal ID, no spaces)")
  local name = prompt(">", current.name, "node_" .. os.getComputerID())
  name = name:gsub("%s+", "_"):lower()
  writeFile(FILES.name, name)

  -- Node label
  term.setTextColor(colors.yellow)
  print("")
  print("Friendly Label  (shown on supervisor)")
  local label = prompt(">", current.label, name)
  writeFile(FILES.label, label)

  -- Node group
  term.setTextColor(colors.yellow)
  print("")
  print("Group  (section header on supervisor)")
  local group = prompt(">", current.group, "")
  writeFile(FILES.group, group)

  -- Factory name
  term.setTextColor(colors.yellow)
  print("")
  print("Factory Name  (isolates this system;")
  print("  nodes must share the same name)")
  local factory_name = prompt(">", current.factory_name, "main")
  factory_name = factory_name:gsub("%s+", "_"):lower()
  writeFile(FILES.factory_name, factory_name)

  term.setTextColor(colors.lime)
  print("")
  print("Config saved.")
  term.setTextColor(colors.white)

  return {
    name         = name,
    label        = label,
    group        = group,
    factory_name = factory_name,
  }
end

return {
  load     = load,
  protocol = protocol,
  setup    = setup,
}
