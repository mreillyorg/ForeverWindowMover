-- Forever Window Mover 0.3.4
-- WoW: Forever (Interface 16001)
-- The merchant and trade mover code remains based on the working 0.1.0.
-- Frame discovery intentionally does NOT register optional, build-specific events.

local addonName, addon = ...

-- Display-only metadata; no impact on window saving or movement.
addon.version = "0.3.4"
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

local HANDLE_INSET_X = 18

-- The invisible drag strip over a window's own title bar, for people who would
-- rather not have a MOVE tab at all.
--
-- There is no portable title-bar object to hook: MerchantFrame's title is a
-- FontString, which cannot take mouse input, and only some of the newer frames
-- expose a TitleContainer. So this is a strip of our own, stretched across the
-- top of the window.
--
-- RIGHT_INSET keeps it clear of the close button, which sits top-right on every
-- frame in addon.groups. The strip also takes the window's OWN frame level
-- rather than the +12 the tab uses, so a genuine interactive child still wins
-- the click. Belt and braces, because swallowing a close button is the one way
-- this feature could be worse than no feature.
local TITLEBAR_HEIGHT = 24
local TITLEBAR_RIGHT_INSET = 40

-- Tab appearance presets. `minimal` is drawn rather than textured: a Blizzard
-- texture path that does not exist on this build fails silently, and an invisible
-- handle is indistinguishable from a broken addon.
addon.handleStyles = {
    dark = {
        label = "Dark",
        width = 70, height = 20, text = "MOVE",
        bg = {0.06, 0.09, 0.13, 0.93},
        hover = {0.12, 0.25, 0.34, 0.97},
    },
    blizzard = {
        label = "Blizzard",
        width = 70, height = 22, text = "MOVE",
        bg = {0.09, 0.09, 0.19, 0.95},
        hover = {0.20, 0.20, 0.40, 0.98},
        backdrop = true,
    },
    minimal = {
        label = "Minimal",
        width = 22, height = 16, text = nil,
        bg = {0.00, 0.00, 0.00, 0.55},
        hover = {0.35, 0.60, 0.85, 0.85},
        grip = true,
    },
}
-- Order for the options page, so it does not depend on table iteration order.
addon.handleStyleOrder = {"dark", "blizzard", "minimal", "custom"}

local DEFAULT_CUSTOM = {
    label = "Custom",
    width = 70, height = 20, text = "MOVE",
    bg = {0.10, 0.10, 0.10, 0.90},
    hover = {0.45, 0.45, 0.45, 0.95},
}

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

-- The master switch, and the one Titan's right-click toggles. Separate from the
-- per-window enable flags: turning all handles off does not erase positions or
-- alter which groups are enabled. It also sits above the two mechanisms below --
-- with this off, neither the tab nor the title-bar strip is live.
function addon.HandlesVisible()
    return not db or db.showHandles ~= false
end

-- The two drag mechanisms, independently toggleable. The tab is on by default
-- because it is discoverable; the title-bar strip is invisible, so opting in is
-- the right way round.
function addon.TabEnabled()
    return not db or db.handleTab ~= false
end

function addon.TitlebarEnabled()
    return not not (db and db.handleTitlebar == true)
end

-- True when the master switch is on but neither mechanism is, which leaves
-- nothing draggable. The options page says so rather than letting you wonder.
function addon.NothingDraggable()
    return addon.HandlesVisible() and not addon.TabEnabled() and not addon.TitlebarEnabled()
end

function addon.CustomStyle()
    local stored = db and db.handleCustom
    local style = {label = DEFAULT_CUSTOM.label}
    for _, key in ipairs({"width", "height"}) do
        local value = stored and stored[key]
        style[key] = (type(value) == "number" and value > 0) and value or DEFAULT_CUSTOM[key]
    end
    -- `text` is a tri-state on disk: absent means the default, false means no
    -- label at all, which is the whole point of a custom narrow handle.
    if stored and stored.text == false then
        style.text = nil
    else
        style.text = DEFAULT_CUSTOM.text
    end
    for _, key in ipairs({"bg", "hover"}) do
        local colour = stored and stored[key]
        if type(colour) == "table" and type(colour[1]) == "number" and type(colour[2]) == "number"
            and type(colour[3]) == "number" then
            style[key] = {colour[1], colour[2], colour[3],
                          type(colour[4]) == "number" and colour[4] or 1}
        else
            style[key] = DEFAULT_CUSTOM[key]
        end
    end
    return style
end

-- Returns the style NAME, which is always one the options page can display.
function addon.HandleStyleName()
    local name = db and db.handleStyle
    if name == "custom" or addon.handleStyles[name] then return name end
    return "dark"
end

-- Returns the resolved style TABLE, with custom built from saved variables.
function addon.HandleStyle()
    local name = addon.HandleStyleName()
    if name == "custom" then return addon.CustomStyle() end
    return addon.handleStyles[name]
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
    local height = info.styleHeight or 20
    local top = frame:GetTop()
    local screenTop = UIParent and UIParent:GetTop()
    local inside = top and screenTop and (top * ScaleRatio(frame) + height) > screenTop
    pcall(function()
        handle:ClearAllPoints()
        if inside then
            handle:SetPoint("TOPLEFT", frame, "TOPLEFT", HANDLE_INSET_X, -2)
        else
            handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", HANDLE_INSET_X, 0)
        end
    end)
end

-- Applies the current style to one installed tab. Every visual property lives
-- here so a style change needs no reinstall, which matters because frames
-- cannot be re-created once Blizzard has made them.
local function ApplyHandleStyle(name)
    local info = installed[name]
    if not info then return end
    local style = addon.HandleStyle()
    info.styleHeight = style.height

    pcall(function()
        info.handle:SetSize(style.width, style.height)
        info.background:SetColorTexture(style.bg[1], style.bg[2], style.bg[3], style.bg[4])

        -- A label, or nothing. `minimal` and a text-less custom style use the
        -- grip dots instead, which are drawn rather than loaded from a texture
        -- path that might not exist on this build.
        if style.text then
            info.label:SetText(style.text)
            info.label:Show()
        else
            info.label:SetText("")
            info.label:Hide()
        end
        -- Grip dots stand in for the label whenever there is no label, so a
        -- text-less custom style does not end up as a blank rectangle.
        local showGrip = style.grip or not style.text
        for _, dot in ipairs(info.grip) do
            if showGrip then dot:Show() else dot:Hide() end
        end

        -- SetBackdrop only exists on a frame created with BackdropTemplate, and
        -- that template only exists from 9.0 onward, so both are checked.
        if info.handle.SetBackdrop then
            if style.backdrop then
                info.handle:SetBackdrop({
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 12,
                    insets = {left = 3, right = 3, top = 3, bottom = 3},
                })
                info.handle:SetBackdropColor(style.bg[1], style.bg[2], style.bg[3], style.bg[4])
                info.background:Hide()
            else
                info.handle:SetBackdrop(nil)
                info.background:Show()
            end
        end
    end)
    UpdateHandleAnchor(name)
end

local function UpdateHandles()
    for _, group in ipairs(addon.groups) do
        for _, name in ipairs(group.frames) do
            local info = installed[name]
            if info then
                local live = addon.HandlesVisible() and addon.IsEnabled(group.key)
                if live and addon.TabEnabled() then
                    ApplyHandleStyle(name)
                    info.handle:Show()
                else
                    info.handle:Hide()
                end
                -- The strip has no visuals, so showing it is purely about
                -- whether it accepts mouse input.
                if info.titlebar then
                    if live and addon.TitlebarEnabled() then
                        info.titlebar:Show()
                    else
                        info.titlebar:Hide()
                    end
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

function addon.SetTabEnabled(enabled)
    if not db or not CanMove() then return false end
    db.handleTab = enabled and true or false
    UpdateHandles()
    if addon.RefreshOptions then addon.RefreshOptions() end
    return true
end

function addon.SetTitlebarEnabled(enabled)
    if not db or not CanMove() then return false end
    db.handleTitlebar = enabled and true or false
    UpdateHandles()
    if addon.RefreshOptions then addon.RefreshOptions() end
    return true
end

function addon.SetHandleStyle(name)
    if not db or not CanMove() then return false end
    if name ~= "custom" and not addon.handleStyles[name] then return false end
    db.handleStyle = name
    UpdateHandles()
    if addon.RefreshOptions then addon.RefreshOptions() end
    return true
end

-- Writes one field of the custom style. Kept field-at-a-time so the colour
-- picker and the text checkbox can each save independently without having to
-- round-trip the whole table.
function addon.SetCustomStyle(field, value)
    if not db or not CanMove() then return false end
    local allowed = {bg = "table", hover = "table", text = "boolean",
                     width = "number", height = "number"}
    if type(value) ~= allowed[field] then return false end
    if allowed[field] == "number" and (value <= 0 or value > 400) then return false end
    db.handleCustom = type(db.handleCustom) == "table" and db.handleCustom or {}
    db.handleCustom[field] = value
    UpdateHandles()
    if addon.RefreshOptions then addon.RefreshOptions() end
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

    -- BackdropTemplate is what provides SetBackdrop from 9.0 onward. Asking for
    -- a template the build does not have would fail the whole CreateFrame, so
    -- fall back to a plain Button and let ApplyHandleStyle skip the backdrop.
    local handle
    local okTemplate = pcall(function()
        handle = CreateFrame("Button", nil, frame, "BackdropTemplate")
    end)
    if not okTemplate or not handle then
        handle = CreateFrame("Button", nil, frame)
    end
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", HANDLE_INSET_X, 0)
    handle:SetFrameLevel(frame:GetFrameLevel() + 12)
    handle:EnableMouse(true)

    local background = handle:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()

    local labelText = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("CENTER", handle, "CENTER", 0, 0)

    -- Three dots for the text-less styles. Drawn, not textured, so there is no
    -- asset path that could be missing on a given build.
    local grip = {}
    for index = 1, 3 do
        local dot = handle:CreateTexture(nil, "OVERLAY")
        dot:SetSize(2, 2)
        dot:SetColorTexture(0.85, 0.85, 0.85, 0.9)
        dot:SetPoint("CENTER", handle, "CENTER", (index - 2) * 5, 0)
        dot:Hide()
        grip[index] = dot
    end

    local function Hover(entering)
        local style = addon.HandleStyle()
        local colour = entering and style.hover or style.bg
        pcall(function()
            background:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
            if handle.SetBackdropColor and style.backdrop then
                handle:SetBackdropColor(colour[1], colour[2], colour[3], colour[4])
            end
        end)
    end

    handle:SetScript("OnEnter", function()
        Hover(true)
        if GameTooltip then
            GameTooltip:SetOwner(handle, "ANCHOR_TOP")
            GameTooltip:SetText("Drag to move: " .. label)
            GameTooltip:Show()
        end
    end)
    handle:SetScript("OnLeave", function()
        Hover(false)
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

    -- The title-bar strip. Same drag handlers, no visuals. See TITLEBAR_HEIGHT
    -- for why it is inset from the right and sits at the window's own frame
    -- level rather than above it.
    local titlebar
    pcall(function()
        titlebar = CreateFrame("Button", nil, frame)
        titlebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        titlebar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TITLEBAR_RIGHT_INSET, 0)
        titlebar:SetHeight(TITLEBAR_HEIGHT)
        titlebar:SetFrameLevel(frame:GetFrameLevel())
        titlebar:EnableMouse(true)
        titlebar:RegisterForDrag("LeftButton")
        titlebar:SetScript("OnDragStart", StartMove)
        titlebar:SetScript("OnDragStop", FinishMove)
        titlebar:SetScript("OnHide", FinishMove)
        -- Invisible, so the tooltip is the only thing that tells you it is
        -- there. Without it the feature is undiscoverable.
        titlebar:SetScript("OnEnter", function()
            if GameTooltip then
                GameTooltip:SetOwner(titlebar, "ANCHOR_TOP")
                GameTooltip:SetText("Drag to move: " .. label)
                GameTooltip:Show()
            end
        end)
        titlebar:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        titlebar:Hide()
    end)

    installed[name] = {frame = frame, handle = handle, titlebar = titlebar,
                       background = background, label = labelText, grip = grip}
    ApplyHandleStyle(name)
    local live = addon.IsEnabled(groupKey) and addon.HandlesVisible()
    if not (live and addon.TabEnabled()) then handle:Hide() end
    if titlebar and live and addon.TitlebarEnabled() then titlebar:Show() end

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
