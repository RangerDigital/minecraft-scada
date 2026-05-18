-- =========================================================
--  Factory OS Utilities
-- =========================================================

-- Strip common mod namespaces (minecraft:, create:) and
-- truncate to maxLen characters (default 14).
local function shortName(name, maxLen)
  return tostring(name)
    :gsub("minecraft:", "")
    :gsub("create:", "")
    :sub(1, maxLen or 14)
end

-- Read a text file, strip trailing whitespace, and return
-- its contents.  Returns nil if the file does not exist.
local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  local v = f.readAll()
  f.close()
  return v:gsub("%s+$", "")
end

return {
  shortName = shortName,
  readFile  = readFile,
}
