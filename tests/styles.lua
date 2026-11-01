-- Tab appearance presets, the custom style, and the two drag mechanisms.
-- Run from the repository root: lua5.1 tests/styles.lua
local base = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\]styles%.lua$")) or "./"
local wow = assert(loadfile(base .. "tests/wow.lua"))()

local function boot(savedVariables)
    wow.reset()
    _G.ForeverWindowMoverDB = savedVariables
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    local frame = wow.newRegion("Frame", "MerchantFrame", nil)
    frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
    wow.place(frame, 0, 0, 1)
    frame.top = 300 -- room above, so the tab anchors outside
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    return addon, frame
end

-- The tab is the first Button child, the title-bar strip the second: the tab is
-- created first in InstallFrame.
local function parts(frame)
    local buttons = {}
    for _, child in ipairs(frame.children) do
        if child.kind == "Button" then buttons[#buttons + 1] = child end
    end
    return buttons[1], buttons[2]
end

local function near(a, b)
    return a and b and math.abs(a - b) < 0.001
end

local function sameColour(got, want)
    if type(got) ~= "table" then return false end
    for index = 1, 4 do
        if not near(got[index], want[index]) then return false end
    end
    return true
end

local function shownGrip(handle)
    local count = 0
    for _, child in ipairs(handle.children) do
        if child.kind == "Texture" and child.width == 2 and child.shown then count = count + 1 end
    end
    return count
end

-- 1. Default is dark, and an unknown stored name falls back to it rather than
--    leaving the tab unstyled.
do
    local addon = boot(nil)
    assert(addon.HandleStyleName() == "dark", "default style should be dark")
    local style = addon.HandleStyle()
    assert(style.width == 70 and style.height == 20, "dark is 70x20")
    assert(style.text == "MOVE", "dark shows the MOVE label")

    local withJunk = boot({positions = {}, enabled = {}, handleStyle = "no-such-style"})
    assert(withJunk.HandleStyleName() == "dark", "an unknown style name must fall back to dark")
end

-- 2. Every preset applies its own geometry, colour and label to the tab.
do
    local addon, frame = boot({positions = {}, enabled = {}})
    local handle = parts(frame)

    for _, name in ipairs({"dark", "blizzard", "minimal"}) do
        assert(addon.SetHandleStyle(name), "SetHandleStyle(" .. name .. ") should succeed")
        local style = addon.handleStyles[name]
        assert(handle.width == style.width and handle.height == style.height,
            string.format("%s should size the tab %dx%d, got %sx%s", name, style.width,
                style.height, tostring(handle.width), tostring(handle.height)))
        assert(handle.label == nil or true) -- label is a child, checked below
        if style.text then
            assert(handle:FirstChildOfKind("FontString").text == style.text,
                name .. " should show its label")
        else
            assert(handle:FirstChildOfKind("FontString").shown == false,
                name .. " should hide the label")
        end
    end
end

-- 3. blizzard draws a backdrop; the others clear it. The background texture is
--    hidden when a backdrop is in use so the two do not stack.
do
    local addon, frame = boot({positions = {}, enabled = {}})
    local handle = parts(frame)
    local background = handle:FirstChildOfKind("Texture")

    assert(addon.SetHandleStyle("blizzard"))
    assert(type(handle.backdrop) == "table", "blizzard should set a backdrop")
    assert(handle.backdrop.edgeFile, "the backdrop needs an edge file for the border")
    assert(background.shown == false, "the flat background should be hidden behind a backdrop")

    assert(addon.SetHandleStyle("dark"))
    assert(handle.backdrop == nil, "dark should clear the backdrop")
    assert(background.shown == true, "the flat background should come back")
end

-- 4. A build without BackdropTemplate. CreateFrame with that template fails
--    outright, so the tab must still install and blizzard must not error.
do
    wow.reset()
    wow.backdropTemplate = false
    _G.ForeverWindowMoverDB = {positions = {}, enabled = {}}
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    local frame = wow.newRegion("Frame", "MerchantFrame", nil)
    frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
    wow.fire("ADDON_LOADED", "ForeverWindowMover")

    local handle = parts(frame)
    assert(handle, "the tab must still install without BackdropTemplate")
    assert(handle.SetBackdrop == nil, "this case needs a frame with no SetBackdrop")
    assert(addon.SetHandleStyle("blizzard"), "selecting blizzard must still succeed")
    assert(handle.width == 70 and handle.height == 22, "geometry still applies")
    -- And dragging still works, which is the thing that actually matters.
    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)
    assert(addon.HasPosition("vendor"), "dragging must work without BackdropTemplate")
    wow.backdropTemplate = true
end

-- 5. minimal replaces the label with grip dots, so it is never a blank box.
do
    local addon, frame = boot({positions = {}, enabled = {}})
    local handle = parts(frame)

    assert(addon.SetHandleStyle("dark"))
    assert(shownGrip(handle) == 0, "dark shows no grip dots")
    assert(addon.SetHandleStyle("minimal"))
    assert(shownGrip(handle) == 3, "minimal should show three grip dots")
    assert(handle:FirstChildOfKind("FontString").shown == false, "minimal hides the label")
end

-- 6. The custom style: defaults when nothing is saved, stored values honoured,
--    and nonsense on disk falls back rather than producing an invisible tab.
do
    local addon = boot(nil)
    local fallback = addon.CustomStyle()
    assert(fallback.width == 70 and fallback.height == 20, "custom defaults to 70x20")
    assert(fallback.text == "MOVE", "custom defaults to showing the label")
    assert(#fallback.bg == 4 and #fallback.hover == 4, "custom defaults carry both colours")

    local stored = boot({positions = {}, enabled = {}, handleStyle = "custom",
        handleCustom = {width = 40, height = 14, text = false,
                        bg = {1, 0, 0, 0.5}, hover = {0, 1, 0}}})
    local style = stored.HandleStyle()
    assert(style.width == 40 and style.height == 14, "stored size should be used")
    assert(style.text == nil, "text=false means no label")
    assert(sameColour(style.bg, {1, 0, 0, 0.5}), "stored background colour should be used")
    assert(sameColour(style.hover, {0, 1, 0, 1}), "a colour with no alpha should default to opaque")

    local junk = boot({positions = {}, enabled = {}, handleStyle = "custom",
        handleCustom = {width = -5, height = "tall", bg = "red", hover = {0, 1}}})
    local safe = junk.HandleStyle()
    assert(safe.width == 70 and safe.height == 20, "invalid sizes must fall back")
    assert(sameColour(safe.bg, {0.10, 0.10, 0.10, 0.90}), "an invalid colour must fall back")
    assert(#safe.hover == 4, "a short colour table must fall back to a complete one")
end

-- 7. The custom style reaches the tab, and SetCustomStyle validates its input.
do
    local addon, frame = boot({positions = {}, enabled = {}})
    local handle = parts(frame)
    local background = handle:FirstChildOfKind("Texture")

    assert(addon.SetHandleStyle("custom"))
    assert(addon.SetCustomStyle("bg", {0.2, 0.4, 0.6, 1}), "setting a colour should succeed")
    assert(sameColour(background.colour, {0.2, 0.4, 0.6, 1}),
        "the custom colour should be applied to the tab immediately")
    assert(addon.SetCustomStyle("width", 120))
    assert(handle.width == 120, "the custom width should be applied immediately")
    assert(addon.SetCustomStyle("text", false))
    assert(handle:FirstChildOfKind("FontString").shown == false, "text=false hides the label")
    assert(shownGrip(handle) == 3, "a text-less custom style should show grip dots")

    assert(addon.SetCustomStyle("bg", "red") == false, "a string is not a colour")
    assert(addon.SetCustomStyle("width", 0) == false, "zero width must be refused")
    assert(addon.SetCustomStyle("width", 10000) == false, "an absurd width must be refused")
    assert(addon.SetCustomStyle("height", "tall") == false, "a string is not a height")
    assert(addon.SetCustomStyle("nonsense", 1) == false, "an unknown field must be refused")

    assert(addon.SetHandleStyle("no-such-style") == false, "an unknown style must be refused")
end

-- 8. The two mechanisms are independent, and the master switch sits above both.
do
    local addon, frame = boot({positions = {}, enabled = {}})
    local handle, titlebar = parts(frame)
    assert(titlebar, "a title-bar strip should have been installed")

    assert(addon.TabEnabled() == true, "the tab is on by default")
    assert(addon.TitlebarEnabled() == false, "the invisible strip is opt-in")
    assert(handle.shown == true and titlebar.shown == false, "default visibility")
    assert(addon.NothingDraggable() == false, "the tab is available")

    assert(addon.SetTitlebarEnabled(true))
    assert(titlebar.shown == true, "the strip should become live")
    assert(handle.shown == true, "enabling the strip must not hide the tab")

    assert(addon.SetTabEnabled(false))
    assert(handle.shown == false, "the tab should hide")
    assert(titlebar.shown == true, "the strip stays live")
    assert(addon.NothingDraggable() == false, "the strip is still available")

    assert(addon.SetTitlebarEnabled(false))
    assert(titlebar.shown == false, "turning the strip off must actually hide it")
    assert(handle.shown == false, "the tab is still off too")
    assert(addon.NothingDraggable() == true, "both mechanisms off means nothing is draggable")

    -- Turning the strip back on and off again, to pin the hide path rather than
    -- only the initial state set at install time.
    assert(addon.SetTitlebarEnabled(true))
    assert(titlebar.shown == true, "the strip should come back")
    assert(addon.SetTitlebarEnabled(false))
    assert(titlebar.shown == false, "and go away again")

    -- The master switch overrides both.
    assert(addon.SetTabEnabled(true))
    assert(addon.SetTitlebarEnabled(true))
    assert(addon.SetHandlesVisible(false))
    assert(handle.shown == false and titlebar.shown == false,
        "the master switch must silence both mechanisms")
    assert(addon.NothingDraggable() == false,
        "with the master switch off, the question does not arise")
    assert(addon.SetHandlesVisible(true))
    assert(handle.shown == true and titlebar.shown == true, "and bring both back")
end

-- 9. The strip covers the top of the window, is inset from the right to clear
--    the close button, and sits at the window's own frame level so a genuine
--    button still wins the click.
do
    local _, frame = boot({positions = {}, enabled = {}, handleTitlebar = true})
    local handle, titlebar = parts(frame)

    assert(titlebar.height == 24, "unexpected strip height: " .. tostring(titlebar.height))
    assert(titlebar.level == frame.level, string.format(
        "the strip must sit at the window's own frame level (%s), not above it (%s)",
        tostring(frame.level), tostring(titlebar.level)))
    assert(handle.level > frame.level, "the visible tab should still sit above the window")

    local anchors = {}
    for _, p in ipairs(titlebar.points) do anchors[p[1]] = p end
    assert(anchors.TOPLEFT and anchors.TOPRIGHT, "the strip should span the window's top edge")
    assert(anchors.TOPLEFT[4] == 0, "flush with the left edge")
    assert(anchors.TOPRIGHT[4] == -40, string.format(
        "the strip must be inset from the right to clear the close button, got %s",
        tostring(anchors.TOPRIGHT[4])))
end

-- 9b. Clicks propagate through the strip, so a close button underneath still
--     responds. This is the real protection against the strip swallowing input;
--     the right-hand inset is only the fallback for builds without the API.
do
    local _, frame = boot({positions = {}, enabled = {}, handleTitlebar = true})
    local _, titlebar = parts(frame)
    assert(titlebar.propagateClicks == true,
        "the strip must propagate clicks so controls underneath keep working")

    -- Motion is deliberately NOT propagated: the strip owns GameTooltip to show
    -- "Drag to move", and propagating motion lets the region beneath compete
    -- for it. A title bar has nothing to hover, so this costs little.
    assert(titlebar.propagateMotion ~= true,
        "motion must not be propagated, or the strip loses the tooltip that makes it findable")
end

-- 9c. A build with no propagation API. The strip must still install, still
--     drag, and still be inset from the right, which is the whole reason the
--     inset was kept rather than replaced.
do
    wow.reset()
    wow.mousePropagation = false
    _G.ForeverWindowMoverDB = {positions = {}, enabled = {}, handleTitlebar = true}
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    local frame = wow.newRegion("Frame", "MerchantFrame", nil)
    frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
    wow.place(frame, 0, 0, 1)
    wow.fire("ADDON_LOADED", "ForeverWindowMover")

    local _, titlebar = parts(frame)
    assert(titlebar, "the strip must still install without the propagation API")
    assert(titlebar.SetPropagateMouseClicks == nil, "this case needs the API absent")
    assert(titlebar.shown == true, "and still be live")

    local anchors = {}
    for _, p in ipairs(titlebar.points) do anchors[p[1]] = p end
    assert(anchors.TOPRIGHT[4] == -40,
        "without propagation the right-hand inset is the only protection, so it must remain")

    wow.place(frame, 55, 15, 1)
    titlebar.scripts.OnDragStart(titlebar)
    titlebar.scripts.OnDragStop(titlebar)
    local saved = _G.ForeverWindowMoverDB.positions.MerchantFrame
    assert(saved and saved.x == 55, "dragging must still work without the propagation API")
    wow.mousePropagation = true
end

-- 10. Dragging by the strip saves a position, exactly as the tab does.
do
    local _, frame = boot({positions = {}, enabled = {}, handleTitlebar = true})
    local _, titlebar = parts(frame)
    wow.place(frame, 90, -30, 1)

    titlebar.scripts.OnDragStart(titlebar)
    titlebar.scripts.OnDragStop(titlebar)
    local saved = _G.ForeverWindowMoverDB.positions.MerchantFrame
    assert(saved and saved.x == 90 and saved.y == -30,
        "dragging the title-bar strip should save the position")

    -- And it refuses in combat, like every other mutation.
    wow.inCombat = true
    wow.place(frame, 10, 10, 1)
    titlebar.scripts.OnDragStart(titlebar)
    assert(frame.moving ~= true, "the strip must refuse to drag during combat")
    wow.inCombat = false
end

-- 11. Style height feeds the screen-top flip, so a shorter tab flips later.
do
    local addon, frame = boot({positions = {}, enabled = {}})
    local handle = parts(frame)
    local function anchorPoint()
        return handle.points[#handle.points][1]
    end

    -- 584 leaves 16px of room: enough for minimal (16) but not dark (20).
    frame.top = 584
    assert(addon.SetHandleStyle("dark"))
    assert(anchorPoint() == "TOPLEFT", "a 20px tab has no room and should flip inside")
    assert(addon.SetHandleStyle("minimal"))
    assert(anchorPoint() == "BOTTOMLEFT", "a 16px tab just fits and should stay outside")
end

-- 12. Every style change is refused during combat and nothing is written.
do
    local addon = boot({positions = {}, enabled = {}})
    wow.inCombat = true
    assert(addon.SetHandleStyle("minimal") == false, "SetHandleStyle must refuse in combat")
    assert(addon.SetTabEnabled(false) == false, "SetTabEnabled must refuse in combat")
    assert(addon.SetTitlebarEnabled(true) == false, "SetTitlebarEnabled must refuse in combat")
    assert(addon.SetCustomStyle("width", 50) == false, "SetCustomStyle must refuse in combat")
    assert(addon.HandleStyleName() == "dark", "nothing should have been written")
    assert(addon.TabEnabled() == true and addon.TitlebarEnabled() == false, "flags unchanged")
    wow.inCombat = false
end

-- 13. All four names the options page offers resolve to a usable style.
do
    local addon = boot({positions = {}, enabled = {}})
    assert(#addon.handleStyleOrder == 4, "four styles are offered")
    for _, name in ipairs(addon.handleStyleOrder) do
        assert(addon.SetHandleStyle(name), "should be able to select " .. name)
        local style = addon.HandleStyle()
        assert(type(style.width) == "number" and style.width > 0, name .. " needs a width")
        assert(type(style.height) == "number" and style.height > 0, name .. " needs a height")
        assert(#style.bg == 4 and #style.hover == 4, name .. " needs both colours")
        assert(type(style.label) == "string" and style.label ~= "",
            name .. " needs a display label for the options page")
    end
end

print("PASSED: dark default and fallback, all three presets applied, backdrop set and cleared, " ..
    "works without BackdropTemplate, grip dots replace the label, custom style defaults and " ..
    "validation, independent tab and title-bar toggles under the master switch, strip geometry " ..
    "and frame level, dragging by the strip, style height feeds the flip, and combat refuses all")
