```
wget run https://raw.githubusercontent.com/RangerDigital/minecraft-scada/master/install.lua
```

# Factory OS

Distributed industrial automation platform for Create + CC:Tweaked.

Inspired by:

- SCADA systems
- industrial HMIs
- distributed telemetry
- factory automation
- PLC infrastructure

Built inside Minecraft using:

- CC:Tweaked
- Create
- Stock Tickers
- Wireless Modems
- Monitors

---

# Philosophy

Factory OS is designed around:

- simplicity first
- modular apps
- distributed nodes
- live telemetry
- physical interaction
- immersive UX

The goal is:
NOT giant monolithic scripts.

Instead:
small specialized industrial nodes.

---

# Architecture

Each computer runs:

startup.lua
→ boot.lua
→ selected app

Apps are stored in:

/apps/

Selected app stored in:

/config/app.txt

Example:

hello
supervisor
storage
trains

---

# Bootloader

Factory OS bootloader:

- updates apps from GitHub
- auto-launches apps
- supports distributed deployment
- keeps startup.lua minimal

Design rule:
bootloader should stay tiny and stable.

---

# Networking

Uses:

- wireless modems
- rednet
- protocol: "factoryos"

Nodes broadcast:

- telemetry
- status
- heartbeat
- alarms

SCADA nodes visualize:

- network state
- node discovery
- overflow status
- live telemetry

---

# Storage Node

Storage node responsibilities:

- monitor Create stock network
- export overflow items
- manage item limits
- broadcast telemetry
- provide local config terminal

Physical workflow:

1. Place item on depot
2. Enter limit
3. Policy saved
4. Overflow auto-managed

No code editing needed.

---

# Why Depot Configuration

Instead of:

- config files
- hardcoded tables
- command interfaces

Factory OS uses:
physical interaction.

Advantages:

- immersive
- multiplayer friendly
- Create-like UX
- easy to maintain

---

# Telemetry Design

Important lesson learned:

SCADA should NOT depend on events only.

Wrong:
only send updates when export happens

Correct:
broadcast current state periodically

Result:
SCADA always knows:

- alive nodes
- current limits
- overflow status
- telemetry freshness

---

# Node Discovery

SCADA automatically discovers nodes through heartbeat telemetry.

Each node broadcasts:

{
type = "storage_status",
node = "storage_1",
heartbeat = ...
}

SCADA tracks:

- last seen time
- node state
- telemetry

This creates:
distributed self-discovering infrastructure.

---

# UI Philosophy

Factory OS UI is inspired by:

- industrial HMIs
- Create aesthetics
- clean telemetry dashboards

Important lessons:

- minimal headers look better
- LEDs should come before labels
- vertical spacing matters
- full-screen redraws are important

---

# Important CC:Tweaked Lessons

## Always redraw full screen

CC terminals are persistent framebuffers.

Partial redraws create artifacts.

Always:
clear
→ redraw entire UI

---

## read() blocks terminal

read() pauses terminal interaction.

Fine for:
v1 config systems

Later:
event-driven UI is better.

---

## Peripheral Types Matter

Create peripherals use custom names:

create:depot
Create_StockTicker

NOT generic inventory.

---

## Wireless Modem Detection

Safer approach:
iterate peripherals manually.

peripheral.find() with isWireless()
can behave inconsistently.

---

# Future Ideas

## SCADA Alarm System

Centralized alarms:

- storage overflow
- boiler low fuel
- train offline
- stress overload

---

## Train Control

Distributed train dispatch:

- station telemetry
- occupancy
- routing

---

## Boiler Automation

Monitor:

- lava
- water
- steam
- fuel

Broadcast warnings automatically.

---

## Wall Displays

Large monitor walls:

- factory overview
- power grid
- storage analytics
- train map

---

## Touchscreen HMIs

Future:
monitor_touch support

Allows:

- buttons
- menus
- alarm acknowledge
- direct control

---

# Core Design Principles

1. Simple > Clever
2. Physical UX > Commands
3. State replication > event spam
4. Distributed nodes > giant scripts
5. Stable bootloader > complex runtime
6. Modular apps > monoliths

---

# Current Apps

## supervisor.lua

SCADA / telemetry dashboard

## storage.lua

Overflow management node

---

# Future Apps

boiler.lua
trains.lua
power.lua
alarms.lua
security.lua
radar.lua

---

# Long-Term Goal

Factory OS should feel like:

industrial automation infrastructure

inside Minecraft.
