-- =========================================================
--  Factory OS Bootloader
-- =========================================================

local BASE =
"https://raw.githubusercontent.com/RangerDigital/minecraft-scada/master"

-- =========================================================
--  UI
-- =========================================================

local COLORS = {
  INFO = colors.cyan,
  OK = colors.lime,
  WARN = colors.yellow,
  ERR = colors.red,
  BOOT = colors.orange
}

local function timestamp()
  return textutils.formatTime(os.time(), true)
end

local function log(level, text)

  term.setTextColor(COLORS[level] or colors.white)

  print(
    string.format(
      "[%s] [%s] %s",
      timestamp(),
      level,
      text
    )
  )

  term.setTextColor(colors.white)
end

-- =========================================================
--  Helpers
-- =========================================================

local function ensureDir(path)

  local dir = fs.getDir(path)

  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function readFile(path)

  if not fs.exists(path) then
    return nil
  end

  local f = fs.open(path, "r")

  local data = f.readAll()

  f.close()

  return data
end

local function writeFile(path, data)

  ensureDir(path)

  local f = fs.open(path, "w")

  f.write(data)

  f.close()
end

local function download(path)

  local url = BASE .. "/" .. path

  log("INFO", "GET " .. path)

  local h, err = http.get(url)

  if not h then
    error(err)
  end

  local body = h.readAll()

  h.close()

  return body
end

-- =========================================================
--  Boot screen
-- =========================================================

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)

log("BOOT", "Factory OS")
log("BOOT", "Node ID: " .. os.getComputerID())

-- =========================================================
--  Read app config
-- =========================================================

local APP_FILE = "/config/app.txt"

if not fs.exists(APP_FILE) then

  log("ERR", "Missing app config")

  sleep(5)

  return
end

local app = readFile(APP_FILE)

app = string.gsub(app, "%s+", "")

log("INFO", "Selected app: " .. app)

-- =========================================================
--  Update app
-- =========================================================

local files = {
  "boot.lua",
  "apps/" .. app .. ".lua",
  "lib/wireless.lua",
  "lib/ui.lua",
  "lib/util.lua",
}

local selfUpdated = false

for _, path in ipairs(files) do

  local ok, err = pcall(function()

    local remote = download(path)

    local localData = readFile(path)

    if remote ~= localData then

      log("WARN", "Updating " .. path)

      writeFile(path, remote)

      log("OK", "Updated " .. path)

      if path == "boot.lua" then
        selfUpdated = true
      end

    else

      log("OK", path .. " current")
    end
  end)

  if not ok then
    log("ERR", err)
  end
end

-- Re-run the new bootloader so updated file list takes effect immediately
if selfUpdated then
  log("BOOT", "Bootloader updated, restarting...")
  sleep(1)
  shell.run("/boot.lua")
  return
end

-- =========================================================
--  Launch app
-- =========================================================

local APP_PATH = "/apps/" .. app .. ".lua"

if not fs.exists(APP_PATH) then

  log("ERR", "Missing app:")
  print(APP_PATH)

  sleep(5)

  return
end

log("BOOT", "Launching app")

sleep(1)

local ok, err = xpcall(function()

  shell.run(APP_PATH)

end, debug.traceback)

if not ok then

  term.setTextColor(colors.red)

  print("")
  print("====================================")
  print("          APP CRASH")
  print("====================================")
  print("")
  print(err)

  sleep(5)

  os.reboot()
end