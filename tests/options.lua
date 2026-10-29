-- The Options > AddOns panel: registration, the derived layout, and the combat
-- gating that 0.3.2 extended to the per-group checkboxes.
-- Run from the repository root: lua5.1 tests/options.lua
local base = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\]options%.lua$")) or "./"
local wow = assert(loadfile(base .. "tests/wow.lua"))()

-- Blizzard's settings canvas does not scroll a canvas category, so the panel
-- has to fit the container. docs/supported-windows.md records the budget.
local HEIGHT_BUDGET = 600

local function load(withSettings, categoryId)
    wow.reset()
    _G.ForeverWindowMoverDB = nil
    if withSettings then wow.installSettings(categoryId) end
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    assert(loadfile(base .. "Options.lua"))("ForeverWindowMover", addon)
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    return addon
end

local function childrenOfKind(frame, kind)
    local found = {}
    for _, child in ipairs(frame.children) do
        if child.kind == kind then found[#found + 1] = child end
    end
    return found
end

local function buttonWithText(frame, wanted)
    for _, child in ipairs(childrenOfKind(frame, "Button")) do
        if child.text == wanted then return child end
    end
    return nil
end

local function anyTextContains(frame, needle)
    for _, child in ipairs(frame.children) do
        if type(child.text) == "string" and child.text:find(needle, 1, true) then
            return child.text
        end
    end
    return nil
end

-- 1. Without Blizzard's settings API the addon must still load, and opening the
--    panel must report failure rather than erroring. The Titan launcher relies
--    on that false to fall back to a chat hint.
do
    local addon = load(false)
    assert(not addon.optionsCreated, "no Settings API, so no panel should be registered")
    assert(addon.OpenOptions() == false, "OpenOptions must report false without Settings")
    assert(#_G.DEFAULT_CHAT_FRAME.messages == 0,
        "a missing settings API is expected, not worth a chat warning: "
        .. table.concat(_G.DEFAULT_CHAT_FRAME.messages, " | "))
end

-- 2. With the API present the panel registers itself into the AddOns list.
do
    local addon = load(true)
    assert(addon.optionsCreated, "panel should be registered at ADDON_LOADED")
    local panel = addon.optionsPanel
    assert(panel, "no options panel was built")
    assert(panel.name == "Forever Window Mover", "panel name is what shows in the list")
    assert(#_G.Settings.registered == 1, "exactly one canvas category should be registered")
    assert(_G.Settings.registered[1].inAddOnList, "category must be added to the AddOns list")
    assert(addon.optionsCategory == _G.Settings.registered[1], "category not recorded on addon")

    -- Blizzard's canvas registration calls these.
    assert(type(panel.OnRefresh) == "function", "OnRefresh is required by the canvas API")
    assert(type(panel.OnCommit) == "function", "OnCommit is required by the canvas API")
    assert(type(panel.OnDefault) == "function", "OnDefault is required by the canvas API")
end

-- 3. The layout is derived from a cursor, so the panel must size itself to its
--    content and nothing may be placed below its bottom edge.
do
    local addon = load(true)
    local panel = addon.optionsPanel
    assert(type(panel.width) == "number" and type(panel.height) == "number",
        "panel must call SetSize")
    assert(panel.width > 0 and panel.height > 0, "panel size must be positive")
    assert(panel.height <= HEIGHT_BUDGET, string.format(
        "panel is %gpx tall, over the %gpx settings canvas budget; reduce LAYOUT.rowHeight",
        panel.height, HEIGHT_BUDGET))

    for _, child in ipairs(panel.children) do
        local depth = child:LowestOffset()
        assert(depth <= panel.height, string.format(
            "a %s reaches %gpx down but the panel is only %gpx tall",
            child.kind, depth, panel.height))
    end
end

-- 4. One row per group, plus the global handles checkbox and reset-all.
do
    local addon = load(true)
    local panel = addon.optionsPanel
    local checks = childrenOfKind(panel, "CheckButton")
    local buttons = childrenOfKind(panel, "Button")
    local edits = childrenOfKind(panel, "EditBox")

    assert(#checks == #addon.groups + 1, string.format(
        "expected %d checkboxes (one per group plus Show MOVE handles), got %d",
        #addon.groups + 1, #checks))
    assert(#buttons == #addon.groups + 1, string.format(
        "expected %d buttons (one Reset per group plus Reset all), got %d",
        #addon.groups + 1, #buttons))
    assert(#edits == 1, "expected exactly one URL box")
    assert(edits[1].text == addon.website, "URL box must show addon.website")
    assert(buttonWithText(panel, "Reset all positions"), "Reset all positions button missing")

    -- Each group's label is on the panel, so a row cannot be silently missing.
    for _, group in ipairs(addon.groups) do
        assert(anyTextContains(panel, group.label),
            "no row label for group " .. group.key .. " (" .. group.label .. ")")
    end
    assert(anyTextContains(panel, addon.version), "version byline missing")
end

-- 5. Combat disables every control, including the per-group checkboxes. Before
--    0.3.2 those stayed clickable and only printed a refusal after the fact.
do
    local addon = load(true)
    local panel = addon.optionsPanel
    local checks = childrenOfKind(panel, "CheckButton")
    local resetAll = buttonWithText(panel, "Reset all positions")

    wow.inCombat = true
    panel.scripts.OnShow(panel)
    for index, check in ipairs(checks) do
        assert(check.enabled == false,
            "checkbox " .. index .. " still enabled during combat lockdown")
    end
    assert(resetAll.enabled == false, "Reset all must be disabled during combat")
    assert(anyTextContains(panel, "combat"), "the status line should explain the lockdown")

    -- 6. Leaving combat with the panel open re-enables the controls, without the
    --    addon registering PLAYER_REGEN_ENABLED (removed in 0.2.1).
    wow.inCombat = false
    panel.scripts.OnUpdate(panel, 1.0)
    for index, check in ipairs(checks) do
        assert(check.enabled == true,
            "checkbox " .. index .. " was not re-enabled after combat ended")
    end
    assert(resetAll.enabled == true, "Reset all was not re-enabled after combat ended")
end

-- 7. Toggling a group checkbox drives SetEnabled for that group.
do
    local addon = load(true)
    local panel = addon.optionsPanel
    local checks = childrenOfKind(panel, "CheckButton")
    -- Rows are created in addon.groups order; the global handles checkbox is last.
    local firstGroup = addon.groups[1]
    local row = checks[1]
    local handlesCheck = checks[#checks]

    panel.scripts.OnShow(panel)
    assert(row.checked == true, "a group starts enabled, so its box starts checked")

    row:SetChecked(false)
    row:Click()
    assert(addon.IsEnabled(firstGroup.key) == false,
        "unchecking the first row must disable " .. firstGroup.key)
    assert(anyTextContains(panel, "disabled"), "the status line should confirm the change")

    row:SetChecked(true)
    row:Click()
    assert(addon.IsEnabled(firstGroup.key) == true, "re-checking must re-enable the group")

    handlesCheck:SetChecked(false)
    handlesCheck:Click()
    assert(addon.HandlesVisible() == false, "unchecking the last box must hide the handles")
    assert(addon.IsEnabled(firstGroup.key) == true,
        "hiding handles must not disable any group")
end

-- 8. Blizzard's Defaults button resets positions, re-enables every group and
--    turns the handles back on.
do
    local addon = load(true)
    local panel = addon.optionsPanel
    addon.SetEnabled(addon.groups[1].key, false)
    addon.SetHandlesVisible(false)
    assert(addon.IsEnabled(addon.groups[1].key) == false)

    panel.OnDefault()
    for _, group in ipairs(addon.groups) do
        assert(addon.IsEnabled(group.key) == true, group.key .. " should be re-enabled")
    end
    assert(addon.HandlesVisible() == true, "handles should be shown again")
end

-- 9. OpenOptions accepts whichever id type the build hands back. Requiring a
--    number meant a string-id build fell back to the chat hint for no reason.
do
    for _, id in ipairs({7, "ForeverWindowMover"}) do
        local addon = load(true, id)
        assert(addon.OpenOptions() == true,
            "OpenOptions should succeed with a " .. type(id) .. " category id")
        assert(_G.Settings.opened[1] == id, "OpenToCategory received the wrong id")
    end

    -- Something that is neither must still be refused rather than passed on.
    local addon = load(true, {})
    assert(addon.OpenOptions() == false, "a table id must be refused")
end

print("PASSED: registration with and without the Settings API, derived panel size within " ..
    "budget, one row per group, combat disables and re-enables every control, group and " ..
    "handles toggles, Defaults, and numeric plus string category ids")
