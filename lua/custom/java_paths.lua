-- Centralized resolution for Java + Mason paths so version bumps don't
-- silently break LSP. Cached after first lookup.
local M = {}

--- Glob a path. `$HOME` (literal) is expanded first so the glob receives a
--- real prefix; wildcards in the rest of the path are then resolved by glob().
---@param glob string
---@return string|nil
local function first_match(glob)
  local pattern = glob:gsub('%$HOME', vim.env.HOME or '~')
  local hits = vim.fn.glob(pattern, true, true)
  if hits and #hits > 0 then return hits[#hits] end
  return nil
end

local cached = {}

--- Mason `share` directory.
---@return string
function M.mason_share()
  cached.mason_share = cached.mason_share or vim.fn.stdpath 'data' .. '/mason/share'
  return cached.mason_share
end

--- Resolve a JDK home suitable for running jdtls. Tries (in order):
---   1. $JAVA_HOME
---   2. The highest-versioned Homebrew openjdk keg
---   3. macOS `/usr/libexec/java_home`
---@return string|nil
function M.jdk_home()
  if cached.jdk_home ~= nil then return cached.jdk_home end

  local env = vim.env.JAVA_HOME
  if env and env ~= '' then
    cached.jdk_home = env
    return env
  end

  local brew = first_match '/opt/homebrew/Cellar/openjdk/*/libexec/openjdk.jdk/Contents/Home'
  if brew then
    cached.jdk_home = brew
    return brew
  end

  if vim.fn.executable 'java_home' == 1 or vim.fn.filereadable '/usr/libexec/java_home' == 1 then
    local out = vim.fn.system '/usr/libexec/java_home'
    if vim.v.shell_error == 0 then
      local trimmed = vim.trim(out)
      if trimmed ~= '' then
        cached.jdk_home = trimmed
        return trimmed
      end
    end
  end

  return nil
end

--- Resolve a Java 21 `java` binary (sonarlint needs 21 specifically right now).
--- Looks at corretto-21.* under ~/Library/Java/JavaVirtualMachines, then
--- falls back to a PATH `java`.
---@return string
function M.java21_executable()
  if cached.java21 ~= nil then return cached.java21 end

  local corretto = first_match '$HOME/Library/Java/JavaVirtualMachines/corretto-21*/Contents/Home/bin/java'
  if corretto then
    cached.java21 = corretto
    return corretto
  end

  cached.java21 = 'java'
  return cached.java21
end

return M
