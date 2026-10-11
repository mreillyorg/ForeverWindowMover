-- Forever Window Mover 0.3.2
-- WoW: Forever (Interface 16001)
-- The merchant and trade mover code remains based on the working 0.1.0.
-- Frame discovery intentionally does NOT register optional, build-specific events.

local addonName, addon = ...

-- Display-only metadata; no impact on window saving or movement.
addon.version = "0.3.2"
addon.author = "Michael Reilly"
addon.website = "https://github.com/mreillyorg/ForeverWindowMover"

addon.groups = {
    { key = "vendor",      label = "Vendors / merchants", frames = {"MerchantFrame"} },
    { key = "trade",       label = "Player trades",       frames = {"TradeFrame"} },
    { key = "bank",        label = "Personal bank",       frames = {"BankFrame"} },
    { key = "guildbank",   label = "Guild bank",          frames = {"GuildBankFrame"} },
    { key = "trainer",     label = "Trainers",            frames = {"ClassTrainerFrame", "TrainerFrame"} },
    { key = "auction",     label = "Auction house",       frames = {"AuctionHouseFrame", "AuctionFrame"} },
    { key = "professions", label = "Professions",         frames = {"ProfessionsFrame", "TradeSkillFrame"} },
    { key = "craft",       label = "Crafting / enchanting",frames = {"CraftFrame"} },
}

local groupsByKey = {}
for _, group in ipairs(addon.groups) do groupsByKey[group.key] = group end

local HANDLE_WIDTH = 70
local HANDLE_HEIGHT = 20
local HANDLE_INSET_X = 18

-- Frame discovery runs as a short burst rather than a permanent OnUpdate.
-- See StartScan for why stopping is safe.
local SCAN_INTERVAL = 1
local SCAN_BURST_TICKS = 15

local installed = {}
local moving = {}
local originalPoints = {}
-- Frame name -> true once the live anchors came from this addon (an applied
-- position, or a drag) instead of from Blizzard's layout.
local movedByAddon = {}
local db
local applying = false

local function CanMove()
    return not (type(InCombatLockdown) == "function" and InCombatLockdown())
end
addon.CanChangeFrames = CanMove

local function Report(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff62c6ffForever Window Mover:|r " .. tostring(message))
    end
end

function addon.IsEnabled(key)
    return not db or not db.enabled or db.enabled[key] ~= false
end

function addon.HasPosition(key)
    local group = groupsByKey[key]
    if not group or not db or not db.positions then return false end
    for _, name in ipairs(group.frames) do
        if db.positions[name] then return true end
    end
    return false
end

-- This switch is separate from the per-window enable flags. Turning all
-- handles off does not erase positions or alter which groups are enabled.
function addon.HandlesVisible()
    return not db or db.showHandles ~= false
end

local function RefreshBroker()
    if addon.RefreshBroker then addon.RefreshBroker() end
end

-- SetPoint offsets are measured in the anchored frame's own coordinate space,
-- while saved positions are stored in UIParent units. This ratio converts
-- between the two; it is 1 for every frame that keeps Blizzard's default scale.
local function ScaleRatio(frame)
    local frameScale = type(frame.GetEffectiveScale) == "function" and frame:GetEffectiveScale() or nil
    local parentScale = UIParent and type(UIParent.GetEffectiveScale) == "function"
        and UIParent:GetEffectiveScale() or nil
    if type(frameScale) ~= "number" or frameScale <= 0 then frameScale = 1 end
    if type(parentScale) ~= "number" or parentScale <= 0 then parentScale = 1 end
    return frameScale / parentScale
end

-- The window is clamped to the screen but its handle is not, so a window
-- pushed against the top of the display would leave its MOVE tab above the
-- viewport and unclickable. Flip the tab inside the frame when that happens.
local function UpdateHandleAnchor(name)
    local info = installed[name]
    if not info then return end
    local frame, handle = info.frame, info.handle
    local top = frame:GetTop()
    local screenTop = UIParent and UIParent:GetTop()
    local inside = top and screenTop and (top * ScaleRatio(frame) + HANDLE_HEIGHT) > screenTop
    pcall(function()
        handle:ClearAllPoints()
        if inside then
            handle:SetPoint("TOPLEFT", frame, "TOPLEFT", HANDLE_INSET_X, -2)
        else
            handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", HANDLE_INSET_X, 0)
        end
    end)
end

local function UpdateHandles()
    for _, group in ipairs(addon.groups) do
        for _, name in ipairs(group.frames) do
            local info = installed[name]
            if info then
                if addon.HandlesVisible() and addon.IsEnabled(group.key) then
                    UpdateHandleAnchor(name)
                    info.handle:Show()
                else
                    info.handle:Hide()
                end
            end
        end
    end
end

function addon.SetHandlesVisible(visible)
    if not db or not CanMove() then return false end
    db.showHandles = visible and true or false
    UpdateHandles()
    if addon.RefreshOptions then addon.RefreshOptions() end
    RefreshBroker()
    return true
end

-- Never snapshot anchors this addon put on the frame: that would make Disable
-- and Reset "restore" our own position instead of Blizzard's layout.
local function CaptureOriginalPoints(name, frame)
    if originalPoints[name] or movedByAddon[name] then return end
    local points = {}
    for i = 1, frame:GetNumPoints() do
        local point, relative, relativePoint, x, y = frame:GetPoint(i)
        points[#points + 1] = {point, relative, relativePoint, x, y}
    end
    if #points > 0 then originalPoints[name] = points end
end

local function RestoreOriginalPoints(name)
    local frame = _G[name]
    local points = originalPoints[name]
    if not frame or not points or not CanMove() then return end
    local ok = pcall(function()
        frame:ClearAllPoints()
        for _, point in ipairs(points) do
            frame:SetPoint(point[1], point[2], point[3], point[4], point[5])
        end
    end)
    if ok then
        originalPoints[name] = nil
        movedByAddon[name] = nil
    end
end

local function ApplyPosition(name, groupKey)
    if applying or moving[name] or not db or not CanMove() or not addon.IsEnabled(groupKey) then return end
    local saved = db.positions[name]
    local frame = _G[name]
    if not saved or not frame then return end
    if type(saved.x) ~= "number" or type(saved.y) ~= "number" then return end
    if type(frame.IsShown) == "function" and not frame:IsShown() then return end

    -- Undo the scale conversion SavePosition applied, or a frame whose scale
    -- differs from UIParent's lands short of where it was dropped.
    local ratio = ScaleRatio(frame)
    applying = true
    -- A bank/profession frame may be protected on some beta builds.
    -- Failing to reposition one frame must not break every other frame.
    local ok = pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", saved.x / ratio, saved.y / ratio)
    end)
    applying = false
    if ok then
        movedByAddon[name] = true
        UpdateHandleAnchor(name)
    end
end

local function ApplyAllVisible()
    for _, group in ipairs(addon.groups) do
        for _, name in ipairs(group.frames) do
            ApplyPosition(name, group.key)
        end
    end
end

local function SavePosition(name, groupKey)
    local frame = _G[name]
    if not db or not frame then return end
    local x, y = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not x or not y or not parentX or not parentY then return end

    local ratio = ScaleRatio(frame)
    db.positions[name] = {
        x = math.floor(x * ratio - parentX + 0.5),
        y = math.floor(y * ratio - parentY + 0.5),
    }
    ApplyPosition(name, groupKey)
    if addon.RefreshOptions then addon.RefreshOptions() end
end

local function InstallFrame(name, groupKey, label)
    if installed[name] or not CanMove() then return end
    local frame = _G[name]
    if not frame or type(frame.SetMovable) ~= "function" then return end

    -- Ignore frames that the client explicitly refuses to make movable.
    local ok = pcall(function()
        CaptureOriginalPoints(name, frame)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
    end)
    if not ok then return end

    local handle = CreateFrame("Button", nil, frame)
    handle:SetSize(HANDLE_WIDTH, HANDLE_HEIGHT)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", HANDLE_INSET_X, 0)
    handle:SetFrameLevel(frame:GetFrameLevel() + 12)
    handle:EnableMouse(true)

    local background = handle:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.06, 0.09, 0.13, 0.93)

    local labelText = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("CENTER", handle, "CENTER", 0, 0)
    labelText:SetText("MOVE")

    handle:SetScript("OnEnter", function()
        background:SetColorTexture(0.12, 0.25, 0.34, 0.97)
        if GameTooltip then
            GameTooltip:SetOwner(handle, "ANCHOR_TOP")
            GameTooltip:SetText("Drag to move: " .. label)
            GameTooltip:Show()
        end
    end)
    handle:SetScript("OnLeave", function()
        background:SetColorTexture(0.06, 0.09, 0.13, 0.93)
        if GameTooltip then GameTooltip:Hide() end
    end)

    local function StartMove()
        if moving[name] or not CanMove() or not addon.IsEnabled(groupKey) then return end
        CaptureOriginalPoints(name, frame)
        if GameTooltip then GameTooltip:Hide() end
        if pcall(function() frame:StartMoving() end) then
            moving[name] = true
            -- Blizzard's anchors are gone from here on, however the drag ends.
            movedByAddon[name] = true
        end
    end

    local function FinishMove()
        if not moving[name] then return end
        pcall(function() frame:StopMovingOrSizing() end)
        moving[name] = nil
        SavePosition(name, groupKey)
        UpdateHandleAnchor(name)
    end

    -- OnDragStart/OnDragStop rather than OnMouseDown/OnMouseUp: the window is
    -- clamped to the screen while the cursor is not, so releasing the button at
    -- a screen edge can happen away from the handle. OnMouseUp is delivered by
    -- cursor position and would be missed, leaving the window stuck to the
    -- mouse; OnDragStop always fires for whoever started the drag.
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", StartMove)
    handle:SetScript("OnDragStop", FinishMove)
    handle:SetScript("OnHide", FinishMove)

    installed[name] = {frame = frame, handle = handle}
    UpdateHandleAnchor(name)
    if not addon.IsEnabled(groupKey) or not addon.HandlesVisible() then handle:Hide() end

    frame:HookScript("OnShow", function()
        -- Blizzard's layout has put real anchors on the frame by now, so take
        -- the snapshot here. A frame created with no anchors at all had nothing
        -- to capture at install time, and capturing later -- after our own
        -- CENTER anchor was applied -- used to record our position as the
        -- "original" and break Reset.
        CaptureOriginalPoints(name, frame)
        -- As with 0.1.0, defer until after Blizzard's panel manager runs.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                CaptureOriginalPoints(name, frame)
                ApplyPosition(name, groupKey)
            end)
        else
            ApplyPosition(name, groupKey)
        end
    end)
    ApplyPosition(name, groupKey)
end

local function InstallFrames()
    if not db then return end
    for _, group in ipairs(addon.groups) do
        for _, name in ipairs(group.frames) do
            InstallFrame(name, group.key, group.label)
        end
    end
end

local function UpdateNativeLayout()
    if type(UpdateUIPanelPositions) == "function" then
        pcall(UpdateUIPanelPositions)
    end
end

function addon.SetEnabled(key, enabled)
    local group = groupsByKey[key]
    if not db or not group or not CanMove() then return false end
    db.enabled[key] = enabled and true or false
    for _, name in ipairs(group.frames) do
        local info = installed[name]
        if info then
            if enabled then
                ApplyPosition(name, key)
            else
                RestoreOriginalPoints(name)
            end
        end
    end
    UpdateHandles()
    if not enabled then UpdateNativeLayout() end
    if addon.RefreshOptions then addon.RefreshOptions() end
    RefreshBroker()
    return true
end

local function ResetName(name)
    db.positions[name] = nil
    if moving[name] then
        local info = installed[name]
        if info then pcall(function() info.frame:StopMovingOrSizing() end) end
        moving[name] = nil
    end
    RestoreOriginalPoints(name)
    local frame = _G[name]
    if frame and frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
    UpdateHandleAnchor(name)
end

function addon.ResetGroup(key)
    local group = groupsByKey[key]
    if not db or not group or not CanMove() then return false end
    for _, name in ipairs(group.frames) do ResetName(name) end
    UpdateNativeLayout()
    if addon.RefreshOptions then addon.RefreshOptions() end
    return true
end

function addon.ResetAll()
    if not db or not CanMove() then return false end
    for _, group in ipairs(addon.groups) do
        for _, name in ipairs(group.frames) do ResetName(name) end
    end
    UpdateNativeLayout()
    if addon.RefreshOptions then addon.RefreshOptions() end
    return true
end

local settingsFailureReported = false
local function TryOptions()
    if addon.optionsCreated or not addon.CreateOptions then return end
    local ok, err = pcall(addon.CreateOptions)
    if not ok and not settingsFailureReported then
        Report("Options page could not be registered: " .. tostring(err))
        settingsFailureReported = true
    end
end

local events = CreateFrame("Frame")

local scanTicker
local scanOnUpdate = false
local scanTicksLeft = 0
local scanElapsed = 0

local function AllFramesInstalled()
    for _, group in ipairs(addon.groups) do
        for _, name in ipairs(group.frames) do
            if not installed[name] then return false end
        end
    end
    return true
end

local function StopScan()
    if scanTicker then
        if type(scanTicker) == "table" and type(scanTicker.Cancel) == "function" then
            pcall(scanTicker.Cancel, scanTicker)
        end
        scanTicker = nil
    end
    if scanOnUpdate then
        events:SetScript("OnUpdate", nil)
        scanOnUpdate = false
    end
end

local function Scan()
    if not db then return end
    InstallFrames()
    TryOptions()
    -- Installation is refused in combat, so a locked-down burst is not spent.
    if not CanMove() then return end
    scanTicksLeft = scanTicksLeft - 1
    if scanTicksLeft <= 0 or (addon.optionsCreated and AllFramesInstalled()) then
        StopScan()
    end
end

-- Low-frequency discovery catches lazily created frames without depending on
-- build-specific events (some unsupported events abort an addon on Forever).
-- It runs as a bounded burst, not for the whole session: native frames appear
-- at login or when the addon owning them loads, and both of those restart the
-- burst, so there is nothing left for a permanent timer to find. Groups whose
-- frame name does not exist on this build are why the scan cannot simply wait
-- for every declared frame to turn up.
local function StartScan()
    scanTicksLeft = SCAN_BURST_TICKS
    if scanTicker or scanOnUpdate then return end
    if C_Timer and type(C_Timer.NewTicker) == "function" then
        local ok, ticker = pcall(C_Timer.NewTicker, SCAN_INTERVAL, Scan)
        if ok and ticker then
            scanTicker = ticker
            return
        end
    end
    -- Builds without C_Timer tickers fall back to a throttled OnUpdate, which
    -- StopScan removes in exactly the same way.
    scanElapsed = 0
    scanOnUpdate = true
    events:SetScript("OnUpdate", function(_, elapsed)
        scanElapsed = scanElapsed + elapsed
        if scanElapsed < SCAN_INTERVAL then return end
        scanElapsed = 0
        Scan()
    end)
end

-- Only use standard events known to work in the original addon.
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            ForeverWindowMoverDB = type(ForeverWindowMoverDB) == "table" and ForeverWindowMoverDB or {}
            ForeverWindowMoverDB.positions = type(ForeverWindowMoverDB.positions) == "table" and ForeverWindowMoverDB.positions or {}
            ForeverWindowMoverDB.enabled = type(ForeverWindowMoverDB.enabled) == "table" and ForeverWindowMoverDB.enabled or {}
            db = ForeverWindowMoverDB
            RefreshBroker() -- LDB may have registered before SavedVariables were loaded.
            TryOptions()
        end
        InstallFrames() -- Addons loading on demand create additional native frames.
        StartScan()
    elseif event == "PLAYER_LOGIN" then
        InstallFrames()
        TryOptions()
        if type(UpdateUIPanelPositions) == "function" and type(hooksecurefunc) == "function" then
            pcall(hooksecurefunc, "UpdateUIPanelPositions", ApplyAllVisible)
        end
        StartScan()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
