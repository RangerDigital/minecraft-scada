```
wget run https://raw.githubusercontent.com/RangerDigital/minecraft-scada/master/install.lua
```

# Factory OS

Distributed industrial automation platform for Create + CC:Tweaked.

---

# Quick Start

Run the installer on any CC:Tweaked computer:

```
wget run https://raw.githubusercontent.com/RangerDigital/minecraft-scada/master/install.lua
```

---

# For Coding Agents

> **This section is the primary reference for AI coding assistants.**
> Read this before writing or modifying any code in this repository.

## Project Stack

| Layer | Technology |
|---|---|
| Scripting | Lua 5.2 (CC:Tweaked dialect) |
| In-game computers | CC:Tweaked advanced computers / pocket computers |
| Automation mod | Create (+ Create: Steam ''n'' Rails for trains) |
| Networking | `rednet` over wireless ender modems |
| Displays | CC:Tweaked monitors (text-mode, 0.5 scale) |

## Repository Layout

```
boot.lua          - Bootloader: downloads app from GitHub, launches it
startup.lua       - Minimal entry: just calls boot.lua
install.lua       - Interactive installer (sets /config/app.txt, etc.)
apps/
  supervisor.lua  - SCADA dashboard (receives all telemetry, drives monitors)
  storage.lua     - Create stock overflow management node
  tank.lua        - Fluid tank monitoring node
  trains.lua      - Create: S''n''R train station monitoring node
  power.lua       - Create stressometer + speedometer node
lib/
  ui.lua          - Monitor/terminal UI primitives
  util.lua        - shortName(), readFile()
  wireless.lua    - Modem discovery + rednet.open()
```

## Config Files (per node, on the computer''s filesystem)

| File | Purpose | Example |
|---|---|---|
| `/config/app.txt` | Which app to run | `trains` |
| `/config/node_name.txt` | Internal node ID (rednet key) | `station_north` |
| `/config/node_label.txt` | Human-friendly display name | `North Platform` |
| `/config/node_group.txt` | Group header on supervisor | `Trains` |

All read with `util.readFile(path)` — returns `nil` if file is missing.

## Boot Flow

```
startup.lua
  boot.lua
    downloads apps/{app}.lua from GitHub master
    downloads lib/*.lua
    dofile("apps/{app}.lua")
```

`boot.lua` always re-downloads on every boot — no stale code.

---

## App Template (boilerplate every node follows)

```lua
local CONFIG   = { telemetryRate = 2 }
local PROTOCOL = "factoryos"

local wireless = dofile("/lib/wireless.lua")
local ui       = dofile("/lib/ui.lua")
local util     = dofile("/lib/util.lua")

local nodeName  = util.readFile("/config/node_name.txt")
                  or os.getComputerLabel()
                  or ("appname_" .. os.getComputerID())
local nodeLabel = util.readFile("/config/node_label.txt") or nodeName
local nodeGroup = util.readFile("/config/node_group.txt") or ""

local _, wirelessSide = wireless.find()

local function try(fn)       -- safe peripheral call, never crashes
  local ok, v = pcall(fn)
  return ok and v or nil
end

local function broadcastStatus()
  rednet.broadcast({
    type      = "xxx_status",
    app       = "appname",
    node      = nodeName,
    label     = nodeLabel,
    group     = nodeGroup,
    alarm     = false,
    heartbeat = os.epoch("utc"),
  }, PROTOCOL)
end

local function telemetryLoop()
  while true do
    readState()
    broadcastStatus()
    drawTerminal()
    sleep(CONFIG.telemetryRate)
  end
end

ui.resetTerm()
telemetryLoop()
```

---

## Rednet Protocol

**Protocol name:** `"factoryos"`

All messages are Lua tables. Broadcast with `rednet.broadcast(tbl, "factoryos")`.

**Node alive threshold:** `os.epoch("utc") - node.lastSeen < 6000` (6 seconds).

### Message: `storage_status`

```lua
{
  type         = "storage_status",
  app          = "storage",
  node         = string,
  label        = string,
  group        = string,
  items        = { { item=string, current=int, limit=int, overflow=int }, ... },
  latestExport = string,   -- last exported item name or "none"
  alarm        = bool,
  heartbeat    = number,   -- ms from os.epoch("utc")
}
```

### Message: `tank_status`

```lua
{
  type      = "tank_status",
  app       = "tank",
  node      = string,
  label     = string,
  group     = string,
  fluid     = string,    -- e.g. "minecraft:lava"
  amount    = number,    -- mB
  capacity  = number,    -- mB
  percent   = number,    -- 0-100
  level     = string,    -- "LOW" / "HALF" / "HIGH" / "FULL"
  alarm     = bool,
  heartbeat = number,
}
```

### Message: `train_status`

```lua
{
  type             = "train_status",
  app              = "train",
  node             = string,
  label            = string,
  group            = string,
  station          = string,   -- in-game station name (getStationName())
  present          = bool,
  train            = string,   -- train name, nil if absent
  cars             = number,   -- car count, nil if absent
  assembling       = bool,
  idle             = bool,
  scheduleCurrent  = string,
  scheduleNext     = string,
  scheduleTotal    = number,
  scheduleCyclic   = bool,
  route            = {         -- one entry per schedule stop
    { dest=string, waitTicks=number|nil, current=bool },
    ...
  },
  presentSince     = number,   -- os.epoch ms when train arrived, nil if absent
  currentWaitTicks = number,   -- timed wait at current stop, nil if none
  alarm            = bool,
  heartbeat        = number,
}
```

### Message: `power_status`

```lua
{
  type      = "power_status",
  app       = "power",
  node      = string,
  label     = string,
  group     = string,
  stress    = number,   -- SU used (sum across all stressometers)
  capacity  = number,   -- SU capacity (sum)
  percent   = number,   -- 0-100
  speeds    = {         -- one entry per speedometer
    { name=string, rpm=number },
    ...
  },
  alarm     = bool,     -- true when percent >= 90
  heartbeat = number,
}
```

### Message: `alarm`

```lua
{ type="alarm", node=string, message=string }
```

---

## CC:Tweaked API Rules and Gotchas

| Topic | Rule |
|---|---|
| Terminal | Always `term.clear()` before full redraws — persistent framebuffer |
| Monitor scale | Always `mon.setTextScale(0.5)` — gives ~50 cols x 19 rows on a 3x2 monitor |
| `read()` | Blocks all coroutines. Avoid in display loops. Use `parallel.waitForAny` |
| Unicode | CC terminals do NOT support UTF-8 box-drawing characters. Use ASCII `-` for lines |
| Char `\16` | CC font codepoint 16 = right-pointing triangle (like arrow). Use for current-item indicators |
| `os.epoch("utc")` | Returns milliseconds. 1 tick = 50 ms. 20 ticks = 1 second |
| Pocket computer | Advanced pocket computer terminal = 26 cols x 20 rows |
| Peripheral find | `peripheral.find()` can behave oddly — always iterate `peripheral.getNames()` manually |
| Parallel | `parallel.waitForAny(f1, f2)` runs two loops concurrently; restarts if either returns |

### Peripheral discovery pattern

```lua
for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)
  if type(p) == "table" and type(p.someMethod) == "function" then
    table.insert(found, { name = name, p = p })
  end
end
```

---

## Create Mod Peripheral Reference

### Peripheral type names (exact strings)

| Block | CC type string | Key methods |
|---|---|---|
| Stock Ticker | `Create_StockTicker` | inventory-like |
| Depot | `create:depot` | inventory-like |
| Train Station | `Create_Station` | see Train Station section |
| Stressometer | `Create_Stressometer` | `getStress()`, `getStressCapacity()` |
| Speedometer | `Create_Speedometer` | `getSpeed()` |
| Display Link | (has `write`, `clear`, `getSize`, `update`) | text surface |

### Train Station API (Create: Steam ''n'' Rails)

```lua
local s = peripheral.wrap("Create_Station_0")
s.isTrainPresent()    -- bool
s.isAssembling()      -- bool
s.getTrainName()      -- string | nil
s.getCarCount()       -- number | nil  (may not exist; fall back to #getTrainCars())
s.getTrainCars()      -- table of car descriptors
s.isCurrentlyIdle()   -- bool
s.getStationName()    -- string  (in-game configured name of this station)
s.getSchedule()       -- table   (see Schedule Format)
```

### Schedule Format

```lua
-- IMPORTANT: destination name is at entry.instruction.data.text
-- NOT at entry.destination (that field does not exist in most versions)
{
  cyclic       = bool,
  currentEntry = number,  -- 1-based index
  entries = {
    {
      instruction = {
        id   = "create_railways:destination",
        data = { text = "StationName" }   -- <-- destination here
      },
      conditions = {
        {
          id   = "create:time_passed",
          data = { value=number, timeUnit=number }
          -- timeUnit: 0=ticks, 1=seconds, 2=minutes
        }
      }
    }
  }
}
```

### Stressometer API

```lua
s.getStress()          -- number: SU currently used
s.getStressCapacity()  -- number: SU capacity
-- percent = math.floor(stress / capacity * 100)
-- ALARM at >= 90% (network freezes at 100%)
```

### Speedometer API

```lua
s.getSpeed()  -- number: RPM (negative = reversed shaft direction)
```

---

## Supervisor Architecture

`supervisor.lua` runs two coroutines via `parallel.waitForAny`:
- `networkLoop()` — receives rednet messages, updates `nodes[id]` table
- `uiLoop()` — redraws all monitors every 2 seconds

**Node table entry shape:**

```lua
nodes[nodeId] = {
  app      = string,          -- "storage" | "tank" | "train" | "power"
  label    = string,
  group    = string,
  lastSeen = number,          -- os.epoch("utc") ms
  alarm    = bool,
  -- app-specific fields ...
}
```

### Widget contract

Every `widgetXxx(mon, name, node, ox, y, w, budget)`:
- `ox` = left column offset (always 2)
- `y` = top row (1-based)
- `w` = full monitor width
- `budget` = max rows available
- Returns the number of rows actually used (must not exceed budget)

Row allocation: `perNode = math.max(2, math.floor(contentH / totalLive))`

### Color conventions

| Color | Meaning |
|---|---|
| `colors.lime` | OK / present / active |
| `colors.yellow` | Warning (50-80%) |
| `colors.orange` | Section / group headers |
| `colors.red` | Alarm / offline / critical (>90%) |
| `colors.gray` | Inactive / empty / secondary |
| `colors.cyan` | Identity / label info |
| `colors.lightGray` | Secondary data rows |

### Log vs Alarm

- `addLog(text)` — informational; **only called on state change**, never on every heartbeat
- `addAlarm(text)` — triggered by `alarm`-type messages from any node

---

## Adding a New App — Checklist

1. Create `apps/myapp.lua` following the App Template
2. Choose a unique `type` string: `"myapp_status"`
3. Add handler in `supervisor.lua` `networkLoop()` (read `prev` before writing `nodes[msg.node]`)
4. Add `widgetMyapp(mon, name, node, ox, y, w, budget)` returning rows used
5. Add dispatch in `drawMain`: `elseif entry.node.app == "myapp" then`
6. Update `install.lua` examples list
7. Update this README message type table and current apps table

---

## Library API

### lib/ui.lua

```lua
ui.resetTerm()                               -- clear terminal, reset colors
ui.ledTerm(color, text)                      -- colored LED + label on terminal stdout
ui.clearMon(mon)                             -- clear monitor, black background
ui.led(mon, x, y, color, on)                 -- single colored cell; gray when on=false
ui.statusLine(mon, x, y, color, text, on)    -- LED + label at (x,y)
```

### lib/util.lua

```lua
util.shortName(name, maxLen)   -- strips "minecraft:"/"create:", truncates (default 14 chars)
util.readFile(path)            -- reads file, strips trailing whitespace; nil if missing
```

### lib/wireless.lua

```lua
local modem, side = wireless.find()
-- Finds first wireless ender modem, calls rednet.open(side)
-- Returns (nil, nil) if no wireless modem present
```

---

## Design Principles

1. **Simple > Clever** — no abstractions for one-off operations
2. **State replication > event spam** — broadcast full state every cycle, not deltas
3. **Distributed nodes > monoliths** — one focused app per physical role
4. **Physical UX > commands** — use depot/peripheral interaction for config
5. **Stable bootloader** — `boot.lua` and `startup.lua` stay minimal and rarely change
6. **Always full redraws** — clear then redraw everything; never partial monitor updates
7. **`try()` all peripheral calls** — peripherals can disconnect; always wrap in pcall
8. **Log only on change** — check previous state before calling `addLog`

---

# Current Apps

| App | Node type | Peripheral(s) needed |
|---|---|---|
| `supervisor` | SCADA dashboard | monitors, wireless modem |
| `storage` | Overflow management | Create_StockTicker, create:depot |
| `tank` | Fluid monitoring | any fluid tank peripheral |
| `trains` | Train station | Create_Station (Steam ''n'' Rails) |
| `power` | Kinetic network | Create_Stressometer, Create_Speedometer |

---

# Long-Term Goal

Factory OS should feel like industrial automation infrastructure inside Minecraft.
