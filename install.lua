-- =========================================================
--  Factory OS Installer
-- =========================================================

local BASE =
"https://raw.githubusercontent.com/RangerDigital/minecraft-scada/master"

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)

term.setTextColor(colors.orange)

print("====================================")
print("         FACTORY OS INSTALL")
print("====================================")
print("")

term.setTextColor(colors.lightGray)

print("Enter app name")
print("")

term.setTextColor(colors.cyan)

print("Examples:")
print("- supervisor")
print("- storage")
print("- tank")
print("- trains")
print("- power")
print("- vault")

print("")

term.setTextColor(colors.white)

write("> ")

local app = read()

app = string.lower(app)
app = string.gsub(app, "%s+", "")

if app == "" then

  term.setTextColor(colors.red)

  print("")
  print("Invalid app")

  sleep(2)

  return
end

-- =========================================================
--  Save config
-- =========================================================

if not fs.exists("/config") then
  fs.makeDir("/config")
end

local f = fs.open("/config/app.txt", "w")

f.write(app)

f.close()

term.setTextColor(colors.lime)

print("")
print("Selected app: " .. app)

-- =========================================================
--  Download lib/config.lua so the wizard can run
-- =========================================================

term.setTextColor(colors.cyan)
print("")
print("Downloading lib/config.lua")

if not fs.exists("/lib") then
  fs.makeDir("/lib")
end

shell.run(
  "wget",
  BASE .. "/lib/config.lua",
  "/lib/config.lua"
)

-- =========================================================
--  Node configuration wizard
-- =========================================================

local cfg = dofile("/lib/config.lua")
cfg.setup()

-- =========================================================
--  Download boot files
-- =========================================================

local files = {
  "startup.lua",
  "boot.lua"
}

for _, file in ipairs(files) do

  term.setTextColor(colors.cyan)

  print("")
  print("Downloading " .. file)

  shell.run(
    "wget",
    BASE .. "/" .. file,
    file
  )
end

term.setTextColor(colors.lime)

print("")
print("Install complete")
print("Rebooting...")

sleep(2)

os.reboot()