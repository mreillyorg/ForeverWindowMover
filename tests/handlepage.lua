-- The Handles options page: registration as a subcategory, the drag-mechanism
-- toggles, the style radio group, and the custom-tab editor.
-- Run from the repository root: lua5.1 tests/handlepage.lua
local base = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\]handlepage%.lua$")) or "./"
local wow = assert(loadfile(base .. "tests/wow.lua"))()

local HEIGHT_BUDGET = 600

local function load(savedVariables)
    wow.reset()
    _G.ForeverWindowMoverDB = savedVariables
    wow.installSettings()
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    assert(loadfile(base .. "Options.lua"))("ForeverWindowMover", addon)
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    assert(addon.handlePanel, "the Handles page was not built")
    return addon, addon.handlePanel
end

local function kind(frame, wanted)
    local found = {}
    for _, child in ipairs(frame.children) do
        if child.kind == wanted then found[#found + 1] = child end
    end
    return found
end

-- Checkbuttons are created in a known order: the two mechanisms, then one per
-- style in addon.handleStyleOrder, then the custom label toggle.
local function checks(panel, addon)
    local all = kind(panel, "CheckButton")
    local expected = 2 + #addon.handleStyleOrder + 1
    assert(#all == expected, string.format("expected %d checkboxes, got %d", expected, #all))
    local styles = {}
    for index, name in ipairs(addon.handleStyleOrder) do
        styles[name] = all[2 + index]
    end
    return {tab = all[1], titlebar = all[2], styles = styles, label = all[#all]}
end

local function buttonWithText(panel, wanted)
    for _, button in ipairs(kind(panel, "Button")) do
        if button.text == wanted then return button end
    end
    return nil
end

local function texts(panel)
    local out = {}
    for _, child in ipairs(panel.children) do
        if type(child.text) == "string" then out[#out + 1] = child.text end
    end
    return table.concat(out, "\n")
end

-- 1. Registered as a subcategory of the main page, not a second top-level entry.
do
    local addon, panel = load(nil)
    assert(panel.name == "Handles", "unexpected page name: " .. tostring(panel.name))
    assert(addon.handleCategory, "the page was not registered")
    assert(addon.handleCategory.parent == addon.optionsCategory,
        "the Handles page should be nested under the main category")
    assert(#_G.Settings.registered == 2, "two categories should be registered in total")
    assert(type(panel.OnRefresh) == "function" and type(panel.OnDefault) == "function",
        "the canvas API requires these")
end

-- 2. On a build with no subcategory API it falls back to its own entry rather
--    than becoming unreachable.
do
    wow.reset()
    wow.subcategories = false
    _G.ForeverWindowMoverDB = nil
    wow.installSettings()
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    assert(loadfile(base .. "Options.lua"))("ForeverWindowMover", addon)
    wow.fire("ADDON_LOADED", "ForeverWindowMover")

    assert(_G.Settings.RegisterCanvasLayoutSubcategory == nil, "this case needs the API absent")
    assert(addon.handlePanel, "the page should still be built")
    assert(addon.handleCategory, "the page should still be registered somewhere")
    assert(addon.handleCategory.parent == nil, "the fallback is a top-level entry")
    assert(addon.handleCategory.inAddOnList, "and it must be added to the AddOns list")
    wow.subcategories = true
end

-- 3. The page fits the canvas, like the main one.
do
    local _, panel = load(nil)
    assert(panel.height <= HEIGHT_BUDGET, string.format(
        "the Handles page is %gpx tall, over the %gpx budget", panel.height, HEIGHT_BUDGET))
    for _, child in ipairs(panel.children) do
        assert(child:LowestOffset() <= panel.height, string.format(
            "a %s reaches %gpx down but the page is only %gpx tall",
            child.kind, child:LowestOffset(), panel.height))
    end
end

-- 4. The mechanism toggles drive the core and reflect its state.
do
    local addon, panel = load({positions = {}, enabled = {}})
    local box = checks(panel, addon)
    panel.scripts.OnShow(panel)

    assert(box.tab.checked == true, "the tab is on by default")
    assert(box.titlebar.checked == false, "the strip is opt-in")

    box.titlebar:SetChecked(true)
    box.titlebar:Click()
    assert(addon.TitlebarEnabled() == true, "clicking should enable the strip")

    box.tab:SetChecked(false)
    box.tab:Click()
    assert(addon.TabEnabled() == false, "clicking should disable the tab")

    -- Re-show and confirm the page reads back from the core, not from itself.
    panel.scripts.OnShow(panel)
    assert(box.tab.checked == false and box.titlebar.checked == true,
        "the page should reflect the stored state")
end

-- 5. Switching both off warns, because the state is legal but useless.
do
    local addon, panel = load({positions = {}, enabled = {}})
    local box = checks(panel, addon)
    panel.scripts.OnShow(panel)
    assert(not texts(panel):find("Nothing is draggable", 1, true),
        "no warning while the tab is on")

    box.tab:SetChecked(false)
    box.tab:Click()
    assert(addon.NothingDraggable() == true, "both mechanisms are now off")
    assert(texts(panel):find("Nothing is draggable", 1, true),
        "the page should say that nothing is draggable")

    box.titlebar:SetChecked(true)
    box.titlebar:Click()
    assert(not texts(panel):find("Nothing is draggable", 1, true),
        "the warning should clear once a mechanism is back")
end

-- 6. The style checkboxes behave as a radio group: exactly one checked.
do
    local addon, panel = load({positions = {}, enabled = {}})
    local box = checks(panel, addon)
    panel.scripts.OnShow(panel)

    local function checkedStyles()
        local on = {}
        for name, check in pairs(box.styles) do
            if check.checked then on[#on + 1] = name end
        end
        return on
    end

    assert(#checkedStyles() == 1 and checkedStyles()[1] == "dark",
        "dark should start as the only selected style")

    for _, name in ipairs(addon.handleStyleOrder) do
        box.styles[name]:Click()
        assert(addon.HandleStyleName() == name, "clicking should select " .. name)
        local on = checkedStyles()
        assert(#on == 1 and on[1] == name,
            "exactly one style may be checked, got " .. table.concat(on, ", "))
    end
end

-- 7. The colour swatches open the picker and save what it returns, on both the
--    modern and the pre-10.0 API.
do
    for _, modern in ipairs({true, false}) do
        local addon, panel = load({positions = {}, enabled = {}})
        local picker = wow.installColorPicker(modern)
        panel.scripts.OnShow(panel)

        local background = buttonWithText(panel, "Background")
        assert(background, "no Background swatch")
        background:Click()
        assert(picker.opened == 1, "the picker should have opened ("
            .. (modern and "modern" or "legacy") .. " API)")

        picker:Choose(0.25, 0.5, 0.75, 0.6)
        local style = addon.CustomStyle()
        assert(math.abs(style.bg[1] - 0.25) < 0.001 and math.abs(style.bg[3] - 0.75) < 0.001,
            "the chosen colour should be saved")
        assert(math.abs(style.bg[4] - 0.6) < 0.001,
            "the chosen alpha should be saved, got " .. tostring(style.bg[4]))

        -- Cancelling restores what was there before.
        local hover = buttonWithText(panel, "Hover")
        local before = addon.CustomStyle().hover
        hover:Click()
        picker:Choose(1, 1, 1, 1)
        picker:Cancel()
        local after = addon.CustomStyle().hover
        for index = 1, 4 do
            assert(math.abs(after[index] - before[index]) < 0.001,
                "cancelling the picker should restore the previous colour")
        end
    end
end

-- 8. With no colour picker at all the page says so instead of erroring.
do
    local _, panel = load({positions = {}, enabled = {}})
    panel.scripts.OnShow(panel)
    assert(_G.ColorPickerFrame == nil, "this case needs no picker")
    buttonWithText(panel, "Background"):Click()
    assert(texts(panel):find("no colour picker", 1, true),
        "the status line should explain that there is no picker")
end

-- 9. The label toggle and the size steppers edit the custom style, clamped.
do
    local addon, panel = load({positions = {}, enabled = {}})
    local box = checks(panel, addon)
    panel.scripts.OnShow(panel)

    assert(box.label.checked == true, "the custom style shows its label by default")
    box.label:SetChecked(false)
    box.label:Click()
    assert(addon.CustomStyle().text == nil, "unchecking should remove the label")

    local plus = {}
    local minus = {}
    for _, button in ipairs(kind(panel, "Button")) do
        if button.text == "+" then plus[#plus + 1] = button end
        if button.text == "-" then minus[#minus + 1] = button end
    end
    assert(#plus == 2 and #minus == 2, "expected a stepper pair for width and height")

    local startWidth = addon.CustomStyle().width
    plus[1]:Click()
    assert(addon.CustomStyle().width == startWidth + 5, "+ should widen by the step")
    minus[1]:Click()
    assert(addon.CustomStyle().width == startWidth, "- should undo it")

    -- Clamped at the bottom: many clicks must not produce a zero-width tab.
    for _ = 1, 40 do minus[1]:Click() end
    assert(addon.CustomStyle().width == 20, "width should clamp at its minimum, got "
        .. tostring(addon.CustomStyle().width))
    for _ = 1, 60 do plus[1]:Click() end
    assert(addon.CustomStyle().width == 200, "width should clamp at its maximum")

    for _ = 1, 40 do minus[2]:Click() end
    assert(addon.CustomStyle().height == 12, "height should clamp at its minimum")
end

-- 10. Combat disables every control on the page, and leaving it restores them.
do
    local addon, panel = load({positions = {}, enabled = {}})
    local box = checks(panel, addon)
    wow.installColorPicker(true)

    wow.inCombat = true
    panel.scripts.OnShow(panel)
    for _, check in ipairs(kind(panel, "CheckButton")) do
        assert(check.enabled == false, "every checkbox should be disabled in combat")
    end
    assert(buttonWithText(panel, "Background").enabled == false,
        "the swatches should be disabled in combat")

    -- And a click that slips through changes nothing.
    box.styles.minimal:Click()
    assert(addon.HandleStyleName() == "dark", "a refused style change must not be written")

    wow.inCombat = false
    panel.scripts.OnShow(panel)
    for _, check in ipairs(kind(panel, "CheckButton")) do
        assert(check.enabled == true, "controls should come back after combat")
    end
end

-- 11. Blizzard's Defaults button on this page resets only the handle settings.
do
    local addon, panel = load({positions = {}, enabled = {}})
    addon.SetTabEnabled(false)
    addon.SetTitlebarEnabled(true)
    addon.SetHandleStyle("minimal")

    panel.OnDefault()
    assert(addon.TabEnabled() == true, "the tab should be back on")
    assert(addon.TitlebarEnabled() == false, "the strip should be off again")
    assert(addon.HandleStyleName() == "dark", "the style should be back to dark")
end

-- 12. A change made on this page refreshes the main page too, since both read
--     the same state and the core only calls RefreshOptions once.
do
    local addon, panel = load({positions = {}, enabled = {}})
    local main = addon.optionsPanel
    main.scripts.OnShow(main)
    panel.scripts.OnShow(panel)

    local box = checks(panel, addon)
    box.styles.minimal:Click()
    assert(addon.HandleStyleName() == "minimal", "the style changed")
    -- RefreshOptions must reach both panels without erroring on either.
    addon.RefreshOptions()
end

print("PASSED: nested subcategory with a top-level fallback, page fits the canvas, mechanism " ..
    "toggles and the nothing-draggable warning, style radio group, colour swatches on both " ..
    "picker APIs including cancel and no-picker, label toggle and clamped steppers, combat " ..
    "gating, Defaults, and cross-page refresh")
