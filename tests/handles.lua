-- The MOVE tab: where it anchors, and when it is visible.
--
-- SetClampedToScreen keeps the WINDOW on screen but not its child handle, so a
-- window dragged to the top of the display used to push its own tab above the
-- viewport where it could not be clicked. Since 0.3.2 the tab flips to just
-- inside the window's top edge when there is no room above it.
--
-- Run from the repository root: lua5.1 tests/handles.lua
local base = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\]handles%.lua$")) or "./"
local wow = assert(loadfile(base .. "tests/wow.lua"))()

local HANDLE_HEIGHT = 20
local SCREEN_TOP = 600

-- `frameTop` is the window's top edge in UIParent units. Anything above
-- SCREEN_TOP - HANDLE_HEIGHT leaves no room for a tab above the window.
local function install(frameTop, scale)
    wow.reset()
    _G.ForeverWindowMoverDB = nil
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    local frame = wow.newRegion("Frame", "MerchantFrame", nil)
    frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
    wow.place(frame, 0, 0, scale or 1) -- sets scale, so do this before top
    frame.top = frameTop
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    return addon, frame, frame:FirstChildOfKind("Button")
end

-- The live anchor is the most recently set one: UpdateHandleAnchor clears and
-- re-sets rather than adding.
local function anchorOf(handle)
    local p = handle.points[#handle.points]
    assert(p, "handle has no anchor at all")
    return p[1], p[3], p[4], p[5]
end

-- 1. Room above: the tab sits on top of the window, outside it.
do
    local _, _, handle = install(300)
    local point, relativePoint, x, y = anchorOf(handle)
    assert(point == "BOTTOMLEFT" and relativePoint == "TOPLEFT", string.format(
        "with room above, expected BOTTOMLEFT->TOPLEFT, got %s->%s", point, relativePoint))
    assert(y == 0, "the tab should sit flush on the window's top edge, y=" .. tostring(y))
    assert(x > 0, "the tab should be inset from the left corner, x=" .. tostring(x))
    assert(handle.width == 70 and handle.height == HANDLE_HEIGHT,
        "unexpected tab size: " .. tostring(handle.width) .. "x" .. tostring(handle.height))
end

-- 2. No room above: the tab flips inside the window so it stays clickable.
do
    local _, _, handle = install(SCREEN_TOP)
    local point, relativePoint, _, y = anchorOf(handle)
    assert(point == "TOPLEFT" and relativePoint == "TOPLEFT", string.format(
        "against the screen top, expected TOPLEFT->TOPLEFT, got %s->%s", point, relativePoint))
    assert(type(y) == "number" and y <= 0,
        "flipped inside, the tab must hang below the window top, y=" .. tostring(y))
end

-- 3. The boundary. One pixel of room is enough; none is not.
do
    local _, _, handle = install(SCREEN_TOP - HANDLE_HEIGHT - 1)
    local point = anchorOf(handle)
    assert(point == "BOTTOMLEFT", "just enough room above should keep the tab outside")

    local _, _, tight = install(SCREEN_TOP - HANDLE_HEIGHT + 1)
    local tightPoint = anchorOf(tight)
    assert(tightPoint == "TOPLEFT", "one pixel short should flip the tab inside")
end

-- 4. A scaled window is compared in UIParent units, not its own. GetTop reports
--    in frame units, so without the conversion a scaled window would flip at
--    the wrong height.
do
    local _, _, handle = install(SCREEN_TOP, 0.8)
    local point = anchorOf(handle)
    assert(point == "TOPLEFT",
        "a scaled window at the screen top should still flip its tab inside")

    local _, _, low = install(200, 0.8)
    assert(anchorOf(low) == "BOTTOMLEFT",
        "a scaled window with room above should keep its tab outside")
end

-- 5. Dragging a window up to the top edge flips the tab on release.
do
    local _, frame, handle = install(300)
    assert(anchorOf(handle) == "BOTTOMLEFT", "starts outside")

    frame.top = SCREEN_TOP
    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)
    assert(anchorOf(handle) == "TOPLEFT",
        "finishing a drag at the screen top should flip the tab inside")
end

-- 6. Visibility is the product of the global switch and the per-group flag, and
--    showing the tab again re-evaluates its anchor.
do
    local addon, frame, handle = install(300)
    assert(handle.shown, "the tab starts visible")

    assert(addon.SetHandlesVisible(false))
    assert(handle.shown == false, "the global switch should hide the tab")
    assert(addon.SetHandlesVisible(true))
    assert(handle.shown == true, "and show it again")

    assert(addon.SetEnabled("vendor", false))
    assert(handle.shown == false, "a disabled group should hide its tab")
    assert(addon.SetEnabled("vendor", true))
    assert(handle.shown == true, "re-enabling should show it")

    -- Both off, then only one back on: still hidden.
    assert(addon.SetHandlesVisible(false))
    assert(addon.SetEnabled("vendor", false))
    assert(handle.shown == false)
    assert(addon.SetEnabled("vendor", true))
    assert(handle.shown == false,
        "the group is enabled but the global switch is off, so the tab stays hidden")

    -- Re-showing after the window moved should pick the right anchor.
    frame.top = SCREEN_TOP
    assert(addon.SetHandlesVisible(true))
    assert(handle.shown == true)
    assert(anchorOf(handle) == "TOPLEFT",
        "showing the tab again should re-evaluate where it belongs")
end

-- 7. A disabled group refuses to drag at all.
do
    local addon, _, handle = install(300)
    assert(addon.SetEnabled("vendor", false))
    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)
    assert(addon.HasPosition("vendor") == false,
        "a disabled group must not record a position")
end

print("PASSED: tab outside with room above, flipped inside against the screen top, correct " ..
    "at the boundary and at a non-default scale, flips on drag release, visibility is the " ..
    "product of both switches, and a disabled group refuses to drag")
