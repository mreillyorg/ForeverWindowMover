-- luacheck configuration for Forever Window Mover.
--
-- Run from the repository root:   luacheck .
-- Install (needs Lua + LuaRocks): luarocks install luacheck
-- Or on Debian/Ubuntu:            apt-get install lua-check
--
-- The WoW client supplies a large global environment that luacheck knows nothing
-- about, so every API this addon touches is declared below. Keeping the list
-- explicit rather than pulling in a community WoW std is deliberate: an
-- unrecognised name is then a real finding -- a typo, or an API used without the
-- feature-detect guard the rest of the addon uses -- instead of being silently
-- absorbed by a catch-all.

std = "lua51"

-- Line length is a review convention here, not a machine rule. Several comment
-- blocks explain client behaviour at length and wrapping them to satisfy a
-- linter would make them harder to read, not easier.
max_line_length = false

-- Don't report the implicit `self` of a method that never uses it. Not many
-- methods here, but the handle and panel scripts take `self` from the client
-- and legitimately ignore it.
self = false

exclude_files = {
    ".release",
    "dist",
    ".git",
}

-- Globals this addon is allowed to create. Everything else assigned at file
-- scope is an accident: the addon publishes nothing to _G except its saved
-- variable, which is the contract documented in docs/saved-variables.md.
globals = {
    "ForeverWindowMoverDB",
}

read_globals = {
    -- Frames and UI
    "CreateFrame",
    "UIParent",
    "GameTooltip",
    "DEFAULT_CHAT_FRAME",
    -- Blizzard's settings canvas. Feature-detected before use, because the
    -- addon has to load on builds where it is not present yet.
    "Settings",
    -- Panel layout manager. Both read as a function and hooked by name.
    "UpdateUIPanelPositions",
    "hooksecurefunc",
    -- Timers. Feature-detected: C_Timer.NewTicker is absent on some builds,
    -- which is why StartScan has an OnUpdate fallback.
    "C_Timer",
    -- Combat lockdown gate
    "InCombatLockdown",
    -- Optional, feature-detected at runtime for the LibDataBroker launcher.
    -- Must never become a TOC dependency: Titan Panel is OptionalDeps only.
    "LibStub",
}

-- Assigned as a whole table rather than via `files[pattern] = ...` so this file
-- also loads under a plain Lua interpreter, which is how tests/syntax.lua
-- sanity-checks it.
files = {
    ["tests/*.lua"] = {
        -- The offline harnesses install stub globals (CreateFrame, UIParent,
        -- the saved-variable table, ...) to stand in for the client, so global
        -- warnings here would all be false positives. Everything else applies.
        global = false,
    },
}
