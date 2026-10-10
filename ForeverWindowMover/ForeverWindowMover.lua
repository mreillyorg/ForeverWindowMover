-- Forever Window Mover 0.3.1
-- WoW: Forever (Interface 16001)
-- The merchant and trade mover code remains based on the working 0.1.0.
-- Frame discovery intentionally does NOT register optional, build-specific events.

local addonName, addon = ...

-- Display-only metadata; no impact on window saving or movement.
addon.version = "0.3.1"
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

local installed = {}
local moving = {}
local originalPoints = {}
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

local function UpdateHandles()
    for _, group in ipairs(addon.groups) do
        for _, name in ipairs(group.frames) do
            local info = installed[name]
            if info then
                if addon.HandlesVisible() and addon.IsEnabled(group.key) then
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

local function CaptureOriginalPoints(name, frame)
    if originalPoints[name] then return end
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
    if ok then originalPoints[name] = nil end
end

local function ApplyPosition(name, groupKey)
    if applying or moving[name] or not db or not CanMove() or not addon.IsEnabled(groupKey) then return end
    local saved = db.positions[name]
    local frame = _G[name]
    if not saved or not frame then return end
    if type(saved.x) ~= "number" or type(saved.y) ~= "number" then return end
    if type(frame.IsShown) == "function" and not frame:IsShown() then return end

    applying = true
    -- A bank/profession frame may be protected on some beta builds.
    -- Failing to reposition one frame must not break every other frame.
    pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
    end)
    applying = false
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

    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
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
    handle:SetSize(70, 20)
    handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 18, 0)
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

    local function FinishMove()
        if not moving[name] then return end
        pcall(function() frame:StopMovingOrSizing() end)
        moving[name] = nil
        SavePosition(name, groupKey)
    end

    handle:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not CanMove() or not addon.IsEnabled(groupKey) then return end
        CaptureOriginalPoints(name, frame)
        if GameTooltip then GameTooltip:Hide() end
        if pcall(function() frame:StartMoving() end) then
            moving[name] = true
        end
    end)
    handle:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then FinishMove() end
    end)
    handle:SetScript("OnHide", FinishMove)

    installed[name] = {frame = frame, handle = handle}
    if not addon.IsEnabled(groupKey) or not addon.HandlesVisible() then handle:Hide() end

    frame:HookScript("OnShow", function()
        -- As with 0.1.0, defer until after Blizzard's panel manager runs.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() ApplyPosition(name, groupKey) end)
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

local elapsedSinceScan = 0
local events = CreateFrame("Frame")
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
    elseif event == "PLAYER_LOGIN" then
        InstallFrames()
        TryOptions()
        if type(UpdateUIPanelPositions) == "function" and type(hooksecurefunc) == "function" then
            pcall(hooksecurefunc, "UpdateUIPanelPositions", ApplyAllVisible)
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Low-frequency discovery catches lazily created frames without depending on
-- build-specific events (some unsupported events abort an addon on Forever).
events:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceScan = elapsedSinceScan + elapsed
    if elapsedSinceScan < 1 then return end
    elapsedSinceScan = 0
    if db then
        InstallFrames()
        TryOptions()
    end
end)
