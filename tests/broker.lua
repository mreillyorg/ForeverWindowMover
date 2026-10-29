-- The optional LibDataBroker launcher. Titan Panel is OptionalDeps only, so the
-- addon has to behave identically when no LDB provider exists.
-- Run from the repository root: lua5.1 tests/broker.lua
local base = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\]broker%.lua$")) or "./"
local wow = assert(loadfile(base .. "tests/wow.lua"))()

local BROKER = "ForeverWindowMover"

-- TitanBroker.lua calls TryBroker at load time, before saved variables exist,
-- so the order here matters: core, then broker, then the event.
local function load(withLdb, savedVariables)
    wow.reset()
    _G.ForeverWindowMoverDB = savedVariables
    local ldb = withLdb and wow.installLibDataBroker() or nil
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    assert(loadfile(base .. "TitanBroker.lua"))("ForeverWindowMover", addon)
    return addon, ldb
end

-- 1. No LibStub at all: the launcher silently does not register and nothing
--    else is affected. This is the common case, so it must be quiet.
do
    local addon = load(false)
    assert(type(addon.RefreshBroker) == "function",
        "RefreshBroker should exist even with no LDB, the core calls it unconditionally")
    addon.RefreshBroker()
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    wow.fire("PLAYER_LOGIN")
    assert(#_G.DEFAULT_CHAT_FRAME.messages == 0,
        "a missing LDB is expected and must not warn: "
        .. table.concat(_G.DEFAULT_CHAT_FRAME.messages, " | "))
end

-- 2. A LibStub that does not serve LibDataBroker is handled the same way.
do
    wow.reset()
    _G.ForeverWindowMoverDB = nil
    _G.LibStub = function() return nil end
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    assert(loadfile(base .. "TitanBroker.lua"))("ForeverWindowMover", addon)
    addon.RefreshBroker()
    assert(#_G.DEFAULT_CHAT_FRAME.messages == 0, "LibStub without LDB must stay quiet")
end

-- 3. With LDB present the launcher registers with the right shape.
do
    local _, ldb = load(true)
    local object = ldb:GetDataObjectByName(BROKER)
    assert(object, "launcher was not registered")
    assert(object.type == "launcher", "must be a launcher, not a data source")
    assert(object.label == "Window Mover", "unexpected label: " .. tostring(object.label))
    assert(type(object.icon) == "string" and object.icon ~= "", "launcher needs an icon")
    assert(type(object.OnClick) == "function", "launcher needs OnClick")
    assert(type(object.OnTooltipShow) == "function", "launcher needs OnTooltipShow")
end

-- 4. The text reflects handle visibility, including when LDB registered before
--    saved variables loaded. That ordering is why the core calls RefreshBroker
--    from ADDON_LOADED.
do
    local _, ldb = load(true, {positions = {}, enabled = {}, showHandles = false})
    local object = ldb:GetDataObjectByName(BROKER)
    -- At load time db is still nil, so the default wins.
    assert(object.text == "Window Mover",
        "before saved variables load the launcher should show the default")

    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    assert(object.text == "Mover: OFF", string.format(
        "after saved variables load the launcher should show the stored state, got %q",
        tostring(object.text)))
end

-- 5. Right-click toggles the handles and the text follows. Left-click with no
--    settings API available falls back to a chat hint rather than failing.
do
    local addon, ldb = load(true, {positions = {}, enabled = {}})
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    local object = ldb:GetDataObjectByName(BROKER)
    assert(object.text == "Window Mover")

    object.OnClick(nil, "RightButton")
    assert(addon.HandlesVisible() == false, "right-click should hide the handles")
    assert(object.text == "Mover: OFF", "launcher text should follow the toggle")

    object.OnClick(nil, "RightButton")
    assert(addon.HandlesVisible() == true, "right-click again should show them")
    assert(object.text == "Window Mover")

    object.OnClick(nil, "LeftButton")
    assert(#_G.DEFAULT_CHAT_FRAME.messages == 1,
        "with no Settings API, left-click should print how to open the panel")
    assert(_G.DEFAULT_CHAT_FRAME.messages[1]:find("Options", 1, true),
        "the hint should name Options: " .. _G.DEFAULT_CHAT_FRAME.messages[1])

    -- An unmapped button must do nothing at all.
    local before = addon.HandlesVisible()
    object.OnClick(nil, "MiddleButton")
    assert(addon.HandlesVisible() == before, "middle-click should be inert")
end

-- 6. Right-click is refused during combat, with an explanation.
do
    local addon, ldb = load(true, {positions = {}, enabled = {}})
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    local object = ldb:GetDataObjectByName(BROKER)

    wow.inCombat = true
    object.OnClick(nil, "RightButton")
    assert(addon.HandlesVisible() == true, "combat must prevent the toggle")
    assert(#_G.DEFAULT_CHAT_FRAME.messages == 1, "a refused toggle should say why")
    assert(_G.DEFAULT_CHAT_FRAME.messages[1]:lower():find("combat", 1, true),
        "the message should mention combat: " .. _G.DEFAULT_CHAT_FRAME.messages[1])
    wow.inCombat = false
end

-- 7. The tooltip lists every group with its state, plus the attribution the
--    0.3.1 notes promise.
do
    local addon, ldb = load(true, {positions = {MerchantFrame = {x = 10, y = 20}},
                                   enabled = {trade = false}})
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    local object = ldb:GetDataObjectByName(BROKER)

    _G.GameTooltip.lines = {}
    object.OnTooltipShow(_G.GameTooltip)
    local text = table.concat(_G.GameTooltip.lines, "\n")

    for _, group in ipairs(addon.groups) do
        assert(text:find(group.label, 1, true), "tooltip omits group " .. group.label)
    end
    assert(text:find("Enabled - saved", 1, true), "vendor has a position, so it should say saved")
    assert(text:find("Disabled", 1, true), "trade is disabled, so it should say Disabled")
    assert(text:find("Enabled - no position", 1, true), "other groups have no position")
    assert(text:find(addon.author, 1, true), "tooltip omits the author")
    assert(text:find(addon.version, 1, true), "tooltip omits the version")
    assert(text:find(addon.website, 1, true), "tooltip omits the repository URL")

    -- A tooltip without AddDoubleLine must still work.
    local plain = {lines = {}}
    function plain:AddLine(line) self.lines[#self.lines + 1] = line end
    _G.GameTooltip.lines = {}
    object.OnTooltipShow(plain)
    assert(#plain.lines > 0, "a tooltip with only AddLine must still be filled")

    -- And something that is not a tooltip at all must be ignored, not error.
    object.OnTooltipShow(nil)
    object.OnTooltipShow({})
end

-- 8. An object another addon already registered under this name is reused
--    rather than duplicated.
do
    wow.reset()
    _G.ForeverWindowMoverDB = nil
    local ldb = wow.installLibDataBroker()
    local existing = {type = "launcher", label = "Someone else", text = "x"}
    ldb:NewDataObject(BROKER, existing)

    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    assert(loadfile(base .. "TitanBroker.lua"))("ForeverWindowMover", addon)
    assert(ldb:GetDataObjectByName(BROKER) == existing, "the existing object should be reused")
    assert(existing.text == "Window Mover", "the reused object should be refreshed")
    assert(existing.label == "Someone else", "reuse must not overwrite the other fields")
end

print("PASSED: silent without LDB or without LibDataBroker, correct launcher shape, text " ..
    "follows saved state and toggles, left-click hint, combat refusal, full tooltip on both " ..
    "tooltip shapes, and reuse of an existing object")
