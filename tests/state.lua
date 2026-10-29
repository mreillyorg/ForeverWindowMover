-- Saved-variable bootstrap, the query defaults, the four mutators, combat
-- gating, and the anchor-capture rule that makes Disable and Reset trustworthy.
-- Run from the repository root: lua5.1 tests/state.lua
local base = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\]state%.lua$")) or "./"
local wow = assert(loadfile(base .. "tests/wow.lua"))()

-- Fresh addon with MerchantFrame present and saved variables already loaded.
-- `anchored` controls whether the frame has Blizzard anchors at install time;
-- a frame the client creates on first use has none, which is the case the
-- capture rule exists for.
local function boot(anchored)
    wow.reset()
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    local frame = wow.newRegion("Frame", "MerchantFrame", nil)
    if anchored then
        frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
    end
    wow.place(frame, 120, 60, 1)
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    return addon, frame, frame:FirstChildOfKind("Button")
end

local function hasCenterAnchor(frame)
    for _, p in ipairs(frame.points) do
        if p[1] == "CENTER" then return true end
    end
    return false
end

local function describePoints(frame)
    local out = {}
    for _, p in ipairs(frame.points) do
        out[#out + 1] = string.format("%s@%s(%s,%s)", tostring(p[1]), tostring(p[3]),
            tostring(p[4]), tostring(p[5]))
    end
    return table.concat(out, " ")
end

-- 1. Bootstrap replaces a corrupt or hand-edited saved-variable file rather
--    than erroring on it.
do
    for _, junk in ipairs({"a string", 42, true}) do
        wow.reset()
        _G.ForeverWindowMoverDB = junk
        local addon = {}
        assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
        wow.fire("ADDON_LOADED", "ForeverWindowMover")
        local db = _G.ForeverWindowMoverDB
        assert(type(db) == "table", "a " .. type(junk) .. " saved variable must be replaced")
        assert(type(db.positions) == "table" and type(db.enabled) == "table",
            "positions and enabled must be normalised to tables")
    end

    -- Wrong types for the sub-tables, with a good outer table.
    wow.reset()
    _G.ForeverWindowMoverDB = {positions = 5, enabled = "no"}
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    assert(type(_G.ForeverWindowMoverDB.positions) == "table", "positions not normalised")
    assert(type(_G.ForeverWindowMoverDB.enabled) == "table", "enabled not normalised")
end

-- 2. Defaults are absent-means-on, and only the literal false disables.
do
    _G.ForeverWindowMoverDB = nil
    local addon = boot(true)
    assert(addon.HandlesVisible() == true, "handles default to visible")
    assert(addon.IsEnabled("vendor") == true, "groups default to enabled")
    assert(addon.CanChangeFrames() == true, "not in combat, so changes are allowed")

    local db = _G.ForeverWindowMoverDB
    assert(db.showHandles == nil, "showHandles must not be written until changed")
    assert(next(db.enabled) == nil, "enabled must not be written until a group is toggled")

    db.enabled.vendor = "yes"
    assert(addon.IsEnabled("vendor") == true, "only the literal false disables a group")
    db.enabled.vendor = false
    assert(addon.IsEnabled("vendor") == false, "false must disable")
    db.showHandles = "sure"
    assert(addon.HandlesVisible() == true, "only the literal false hides handles")
end

-- 3. Show MOVE handles is independent of the per-group flags and of positions.
do
    _G.ForeverWindowMoverDB = nil
    local addon, _, handle = boot(true)
    assert(handle.shown, "handle should start visible")

    assert(addon.SetHandlesVisible(false) == true, "SetHandlesVisible should succeed")
    assert(handle.shown == false, "handle must hide")
    assert(_G.ForeverWindowMoverDB.showHandles == false, "showHandles must persist")
    assert(addon.IsEnabled("vendor") == true, "hiding handles must not disable a group")
    assert(next(_G.ForeverWindowMoverDB.enabled) == nil,
        "hiding handles must not write any enable flag")

    assert(addon.SetHandlesVisible(true) == true)
    assert(handle.shown == true, "handle must come back")
end

-- 4. Disable restores Blizzard's anchors and keeps the saved position;
--    re-enable puts the window back.
do
    _G.ForeverWindowMoverDB = nil
    local addon, frame, handle = boot(true)
    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)
    assert(addon.HasPosition("vendor"), "drag should save")
    assert(hasCenterAnchor(frame), "apply should have set a CENTER anchor")

    assert(addon.SetEnabled("vendor", false) == true)
    assert(addon.IsEnabled("vendor") == false)
    assert(handle.shown == false, "disabling must hide the handle")
    assert(addon.HasPosition("vendor"), "disabling must keep the saved position")
    assert(not hasCenterAnchor(frame),
        "disabling must restore Blizzard's anchors, got: " .. describePoints(frame))
    local p1, _, p3, x, y = frame:GetPoint(1)
    assert(p1 == "TOPLEFT" and p3 == "TOPLEFT" and x == 16 and y == -116,
        "restored the wrong anchor: " .. describePoints(frame))

    assert(addon.SetEnabled("vendor", true) == true)
    assert(handle.shown == true, "re-enabling must show the handle")
    assert(hasCenterAnchor(frame), "re-enabling must re-apply the saved position")
end

-- 5. Reset clears the position, restores anchors and clears SetUserPlaced.
do
    _G.ForeverWindowMoverDB = nil
    local addon, frame, handle = boot(true)
    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)
    assert(addon.HasPosition("vendor"))

    assert(addon.ResetGroup("vendor") == true)
    assert(addon.HasPosition("vendor") == false, "reset must clear the saved position")
    assert(frame.userPlaced == false, "reset must clear SetUserPlaced")
    assert(not hasCenterAnchor(frame),
        "reset must restore Blizzard's anchors, got: " .. describePoints(frame))

    assert(addon.ResetGroup("no-such-group") == false, "unknown group must be refused")
end

-- 6. Reset all clears every group.
do
    _G.ForeverWindowMoverDB = nil
    wow.reset()
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)
    local frames = {}
    for _, name in ipairs({"MerchantFrame", "TradeFrame", "BankFrame"}) do
        local f = wow.newRegion("Frame", name, nil)
        f:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
        wow.place(f, 60, 30, 1)
        frames[name] = f
    end
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    for _, f in pairs(frames) do
        local h = f:FirstChildOfKind("Button")
        h.scripts.OnDragStart(h)
        h.scripts.OnDragStop(h)
    end
    assert(addon.HasPosition("vendor") and addon.HasPosition("trade") and addon.HasPosition("bank"),
        "all three should have positions")

    assert(addon.ResetAll() == true)
    for _, key in ipairs({"vendor", "trade", "bank"}) do
        assert(addon.HasPosition(key) == false, key .. " should be cleared by ResetAll")
    end
    assert(next(_G.ForeverWindowMoverDB.positions) == nil, "positions table should be empty")
end

-- 7. Every mutator refuses during combat lockdown and changes nothing.
do
    _G.ForeverWindowMoverDB = nil
    local addon, _, handle = boot(true)
    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)
    local before = _G.ForeverWindowMoverDB.positions.MerchantFrame
    local beforeX, beforeY = before.x, before.y

    wow.inCombat = true
    assert(addon.CanChangeFrames() == false, "CanChangeFrames must report combat")
    assert(addon.SetEnabled("vendor", false) == false, "SetEnabled must refuse in combat")
    assert(addon.SetHandlesVisible(false) == false, "SetHandlesVisible must refuse in combat")
    assert(addon.ResetGroup("vendor") == false, "ResetGroup must refuse in combat")
    assert(addon.ResetAll() == false, "ResetAll must refuse in combat")

    assert(addon.IsEnabled("vendor") == true, "a refused SetEnabled must not have written")
    assert(addon.HandlesVisible() == true, "a refused SetHandlesVisible must not have written")
    local after = _G.ForeverWindowMoverDB.positions.MerchantFrame
    assert(after and after.x == beforeX and after.y == beforeY,
        "a refused reset must not touch the saved position")
    assert(handle.shown == true, "nothing should have been hidden")
    wow.inCombat = false
end

-- 8. The anchor-capture rule. A frame the client creates with no anchors has
--    nothing to snapshot at install time. Blizzard's layout anchors it by the
--    time OnShow runs, so capture happens there -- BEFORE the deferred apply.
--    Without that ordering the snapshot records the addon's own CENTER anchor
--    as "original", and Reset then restores the addon's position instead of
--    Blizzard's. That was the 0.3.2 fix.
do
    _G.ForeverWindowMoverDB = nil
    local addon, frame, handle = boot(false)
    assert(handle, "a frame with no anchors should still get a handle")
    assert(frame:GetNumPoints() == 0, "this case needs a frame with no anchors")

    -- Blizzard's panel manager anchors it, then the window opens.
    frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
    frame:FireHook("OnShow")

    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)
    assert(hasCenterAnchor(frame), "the drag should have applied a CENTER anchor")

    assert(addon.ResetGroup("vendor") == true)
    assert(not hasCenterAnchor(frame),
        "reset restored the addon's own anchor instead of Blizzard's: " .. describePoints(frame))
    local p1, _, p3, x, y = frame:GetPoint(1)
    assert(p1 == "TOPLEFT" and p3 == "TOPLEFT" and x == 16 and y == -116,
        "reset should restore the anchors captured at OnShow, got: " .. describePoints(frame))
end

-- 9. Once the addon has moved a frame, no later capture may overwrite the
--    original snapshot with the addon's own anchors.
do
    _G.ForeverWindowMoverDB = nil
    local addon, frame, handle = boot(true)
    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)
    -- Plenty of chances to re-capture the wrong thing.
    for _ = 1, 5 do frame:FireHook("OnShow") end
    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)

    assert(addon.ResetGroup("vendor") == true)
    local p1, _, p3, x, y = frame:GetPoint(1)
    assert(p1 == "TOPLEFT" and p3 == "TOPLEFT" and x == 16 and y == -116,
        "the original snapshot was overwritten after the addon moved the frame: "
        .. describePoints(frame))
end

-- 10. The OnShow hook captures twice: once synchronously, once inside the
--     C_Timer.After callback just before applying. The deferred one sees the
--     anchors Blizzard's panel manager settled on, so it is the better
--     snapshot -- but on a build with no C_Timer the addon applies inline and
--     the synchronous capture is the ONLY protection Reset has. Remove it and
--     this case is what notices.
do
    _G.ForeverWindowMoverDB = nil
    local realTimer = _G.C_Timer
    _G.C_Timer = nil

    local addon, frame, handle = boot(false)
    frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
    frame:FireHook("OnShow")

    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)
    assert(hasCenterAnchor(frame), "the drag should have applied a CENTER anchor")

    assert(addon.ResetGroup("vendor") == true)
    local p1, _, p3, x, y = frame:GetPoint(1)
    assert(p1 == "TOPLEFT" and p3 == "TOPLEFT" and x == 16 and y == -116,
        "with no C_Timer the synchronous OnShow capture must still protect Reset, got: "
        .. describePoints(frame))

    _G.C_Timer = realTimer
end

-- 11. A frame Blizzard never anchors at all. There is nothing to snapshot, so
--     the addon must record NOTHING rather than recording its own anchor and
--     later "restoring" a stale position as if it were the client's. This is
--     the case the movedByAddon guard exists for: with a snapshot already
--     taken the guard is redundant, so only this path can detect its removal.
do
    _G.ForeverWindowMoverDB = nil
    local addon, frame, handle = boot(false)
    assert(frame:GetNumPoints() == 0, "this case needs a frame with no anchors at all")

    wow.place(frame, 100, 50, 1)
    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)
    assert(_G.ForeverWindowMoverDB.positions.MerchantFrame.x == 100, "first drag should save 100")

    -- Several chances to snapshot the addon's own anchor by mistake.
    for _ = 1, 3 do frame:FireHook("OnShow") end

    -- Move it somewhere else and drag again.
    wow.place(frame, -140, 20, 1)
    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)
    assert(_G.ForeverWindowMoverDB.positions.MerchantFrame.x == -140,
        "the second drag should record the new spot")

    assert(addon.ResetGroup("vendor") == true)
    local ox, oy = frame:CenterOffset()
    assert(not (math.abs(ox - 100) <= 1 and math.abs(oy - 50) <= 1), string.format(
        "reset put the window back at the addon's own earlier position (%g,%g) as if it " ..
        "were Blizzard's layout", ox, oy))
end

-- 12. The 0.3.2 bug in the form users actually hit: a position saved in a
--     previous session, on a window the client only creates when first opened.
--     At install the frame is still hidden, so ApplyPosition skips it and there
--     are no anchors to snapshot. Blizzard's layout anchors it, the window
--     opens, and OnShow re-applies the saved position -- so by the time the
--     user drags, the only anchor on the frame is the addon's own CENTER. The
--     capture therefore has to happen at OnShow, BEFORE that apply. Without it
--     the snapshot is the addon's position and Reset "restores" that.
do
    wow.reset()
    _G.ForeverWindowMoverDB = {positions = {MerchantFrame = {x = 100, y = 50}}, enabled = {}}
    local addon = {}
    assert(loadfile(base .. "ForeverWindowMover.lua"))("ForeverWindowMover", addon)

    local frame = wow.newRegion("Frame", "MerchantFrame", nil)
    frame.shown = false -- a vendor window is closed at login
    wow.place(frame, 0, 0, 1)
    wow.fire("ADDON_LOADED", "ForeverWindowMover")
    local handle = frame:FirstChildOfKind("Button")
    assert(handle, "handle should install even on a hidden frame")
    assert(frame:GetNumPoints() == 0,
        "a hidden frame with no anchors must not be positioned at install time")

    -- Blizzard's panel manager anchors it, then the player opens the vendor.
    frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
    frame.shown = true
    frame:FireHook("OnShow")
    assert(hasCenterAnchor(frame), "OnShow should have re-applied the saved position")

    -- The player drags it somewhere new.
    wow.place(frame, -60, 10, 1)
    handle.scripts.OnDragStart(handle)
    handle.scripts.OnDragStop(handle)
    assert(_G.ForeverWindowMoverDB.positions.MerchantFrame.x == -60, "drag should re-save")

    assert(addon.ResetGroup("vendor") == true)
    local p1, _, p3, x, y = frame:GetPoint(1)
    assert(p1 == "TOPLEFT" and p3 == "TOPLEFT" and x == 16 and y == -116,
        "reset must restore the anchors captured at OnShow, not the addon's own: "
        .. describePoints(frame))
end

print("PASSED: bootstrap resilience, absent-means-on defaults, handles independent of " ..
    "enables, disable/enable round trip, reset and reset-all, combat refuses all four " ..
    "mutators, anchor capture at OnShow with and without C_Timer, capture refused after a " ..
    "move, no stale self-position restored, and reset after a cross-session re-apply")
