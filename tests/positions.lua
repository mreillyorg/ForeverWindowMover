-- Regression harness for the save/apply unit conversion.
--
-- Positions are stored as offsets from UIParent's centre in UIParent units, but
-- SetPoint offsets are measured in the ANCHORED frame's own coordinate space.
-- SavePosition multiplies by the scale ratio on the way in, so ApplyPosition
-- has to divide by it on the way out. Until 0.3.2 it did not, so a frame whose
-- scale differed from UIParent's landed at offset*ratio instead of offset: a
-- visible jump on mouse release that compounded toward the screen centre with
-- every further drag.
--
-- At ratio 1 -- every frame Blizzard ships, unless another addon rescales one --
-- the bug is invisible, which is why it survived. So the cases below include a
-- scaled frame deliberately.
--
-- Run from the repository root: lua5.1 tests/positions.lua
local base = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\]positions%.lua$")) or "./"
local wow = assert(loadfile(base .. "tests/wow.lua"))()

local function approx(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1)
end

-- Builds a fresh addon instance with one target frame placed as asked, drags it
-- once, and hands back everything a check might want to look at.
local function dragOnce(offsetX, offsetY, scale)
    wow.reset()
    _G.ForeverWindowMoverDB = nil

    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)

    -- Blizzard's own anchors, so there is a snapshot to restore later.
    local frame = wow.newRegion("Frame", "MerchantFrame", nil)
    frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
    wow.place(frame, offsetX, offsetY, scale)

    wow.fire("ADDON_LOADED", "ForeverWindowMover")

    local handle = frame:FirstChildOfKind("Button")
    assert(handle, "no MOVE handle was installed on MerchantFrame")
    assert(handle.dragButtons and handle.dragButtons[1] == "LeftButton",
        "handle must RegisterForDrag LeftButton, or a release off the handle is lost")

    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)

    local saved = _G.ForeverWindowMoverDB.positions.MerchantFrame
    assert(saved, "drag did not save a position")
    return addon, frame, handle, saved
end

-- 1. Unscaled frame: the simple case, and the one that always worked.
do
    local _, frame, _, saved = dragOnce(120, -80, 1)
    assert(saved.x == 120 and saved.y == -80,
        string.format("expected (120,-80), saved (%s,%s)", tostring(saved.x), tostring(saved.y)))
    local ox, oy = frame:CenterOffset()
    assert(approx(ox, 120) and approx(oy, -80),
        string.format("unscaled frame moved on apply: landed at (%g,%g)", ox, oy))
end

-- 2. Scaled frame: this is the case the conversion exists for. The frame must
--    land where it was dropped, not at offset * scale.
do
    local _, frame, _, saved = dragOnce(150, 90, 0.8)
    assert(saved.x == 150 and saved.y == 90,
        string.format("expected (150,90) in UIParent units, saved (%s,%s)",
            tostring(saved.x), tostring(saved.y)))

    local appliedX, appliedY = frame:AppliedOffset()
    assert(appliedX, "ApplyPosition set no CENTER anchor")
    -- The applied offset is in frame units, so it must be the saved offset
    -- divided by the ratio. Before the fix these were equal, not scaled.
    assert(approx(appliedX, 150 / 0.8, 0.01) and approx(appliedY, 90 / 0.8, 0.01),
        string.format("expected applied offset (187.5,112.5) in frame units, got (%g,%g)",
            appliedX, appliedY))

    local ox, oy = frame:CenterOffset()
    assert(approx(ox, 150) and approx(oy, 90),
        string.format("scaled frame landed at (%g,%g), not where it was dropped (150,90)", ox, oy))
end

-- 3. No drift. Re-applying, and dragging again without moving the mouse, must
--    not creep. Before the fix each cycle multiplied the offset by the ratio
--    again, walking the window toward the centre of the screen.
do
    local addon, frame, handle, saved = dragOnce(150, 90, 0.8)
    local firstX, firstY = saved.x, saved.y

    -- Every OnShow re-applies the saved position.
    for _ = 1, 5 do frame:FireHook("OnShow") end
    local ox, oy = frame:CenterOffset()
    assert(approx(ox, firstX) and approx(oy, firstY),
        string.format("five re-applies drifted to (%g,%g) from (%g,%g)", ox, oy, firstX, firstY))

    -- And a further drag that does not move the window must record the same spot.
    for _ = 1, 3 do
        handle.scripts.OnDragStart(handle)
        handle.scripts.OnDragStop(handle)
    end
    local again = _G.ForeverWindowMoverDB.positions.MerchantFrame
    assert(approx(again.x, firstX) and approx(again.y, firstY),
        string.format("three idle drags drifted the saved position to (%d,%d) from (%d,%d)",
            again.x, again.y, firstX, firstY))
    assert(addon.HasPosition("vendor"), "vendor group should report a saved position")
end

-- 4. A window closed mid-drag still saves, via the handle's OnHide.
do
    wow.reset()
    _G.ForeverWindowMoverDB = nil
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    local frame = wow.newRegion("Frame", "MerchantFrame", nil)
    frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
    wow.place(frame, -200, 40, 1)
    wow.fire("ADDON_LOADED", "ForeverWindowMover")

    local handle = frame:FirstChildOfKind("Button")
    handle.scripts.OnDragStart(handle)
    handle:Hide() -- fires OnHide, which finishes the move
    local saved = _G.ForeverWindowMoverDB.positions.MerchantFrame
    assert(saved and saved.x == -200 and saved.y == 40,
        "closing a window mid-drag must finalise and save the position")
end

-- 5. A click with no drag saves nothing. OnDragStart never fires, so there is
--    no zero-distance move to record.
do
    wow.reset()
    _G.ForeverWindowMoverDB = nil
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    local frame = wow.newRegion("Frame", "MerchantFrame", nil)
    frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    assert(frame:FirstChildOfKind("Button"), "handle missing")
    assert(not _G.ForeverWindowMoverDB.positions.MerchantFrame,
        "installing a handle must not save a position by itself")
    assert(addon.HasPosition("vendor") == false, "nothing dragged, nothing saved")
end

-- 6. Dragging is refused in combat, and nothing is recorded.
do
    wow.reset()
    _G.ForeverWindowMoverDB = nil
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    local frame = wow.newRegion("Frame", "MerchantFrame", nil)
    frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
    wow.place(frame, 10, 10, 1)
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    local handle = frame:FirstChildOfKind("Button")

    wow.inCombat = true
    handle.scripts.OnDragStart(handle)
    assert(not frame.moving, "StartMoving must not be called during combat lockdown")
    handle.scripts.OnDragStop(handle)
    assert(not _G.ForeverWindowMoverDB.positions.MerchantFrame,
        "a refused drag must not save a position")
    wow.inCombat = false
end

print("PASSED: unit conversion at scale 1 and 0.8, no drift over 5 re-applies and 3 drags, " ..
    "mid-drag close saves, click-without-drag saves nothing, combat refuses")
