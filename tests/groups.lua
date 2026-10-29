-- The group table drives discovery, the options rows, the Titan tooltip, saving
-- and reset, and its keys are a saved-variable contract (docs/saved-variables.md).
-- A duplicate or a typo there is quiet and affects all of those at once.
-- Run from the repository root: lua5.1 tests/groups.lua
local base = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\]groups%.lua$")) or "./"
assert(loadfile(base .. "tests/wow.lua"))()

local addon = {}
assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)

assert(type(addon.groups) == "table", "addon.groups missing")
assert(#addon.groups > 0, "addon.groups is empty")

local seenKey, seenFrame, seenLabel = {}, {}, {}
for index, group in ipairs(addon.groups) do
    local where = "group " .. index
    assert(type(group.key) == "string" and group.key ~= "", where .. " has no key")
    assert(group.key:match("^[a-z]+$"),
        where .. " key '" .. group.key .. "' should be lowercase letters: it is persisted in db.enabled")
    assert(not seenKey[group.key], "duplicate group key: " .. group.key)
    seenKey[group.key] = true

    assert(type(group.label) == "string" and group.label ~= "", where .. " has no label")
    assert(not seenLabel[group.label], "duplicate group label: " .. group.label)
    seenLabel[group.label] = true

    assert(type(group.frames) == "table" and #group.frames > 0, where .. " lists no frames")
    for _, frame in ipairs(group.frames) do
        assert(type(frame) == "string" and frame:match("^%a[%w_]*$"),
            where .. " has a suspicious frame name: " .. tostring(frame))
        -- Positions are keyed per frame name across all groups, so a name used
        -- twice would make two groups share one saved position.
        assert(not seenFrame[frame],
            "frame " .. frame .. " appears in more than one group")
        seenFrame[frame] = true
    end
end

-- Queries must be total over the declared keys, and must not invent answers for
-- keys that do not exist.
for _, group in ipairs(addon.groups) do
    assert(addon.IsEnabled(group.key) == true,
        "groups should default to enabled before saved variables load: " .. group.key)
    assert(addon.HasPosition(group.key) == false,
        "no group can have a position before saved variables load: " .. group.key)
end
assert(addon.HasPosition("no-such-group") == false, "unknown key must answer false")

local keys = 0
for _ in pairs(seenKey) do keys = keys + 1 end
local frames = 0
for _ in pairs(seenFrame) do frames = frames + 1 end
print(string.format("PASSED: %d groups, %d unique keys, %d unique frame names",
    #addon.groups, keys, frames))
