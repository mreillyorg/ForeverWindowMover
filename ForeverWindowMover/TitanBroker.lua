-- Optional LibDataBroker launcher for Titan Panel and other LDB displays.
-- Never creates or loads Titan itself. Missing libraries do not affect FWM.
local _, addon = ...

local brokerName = "ForeverWindowMover"
local object

local function BrokerText()
    return addon.HandlesVisible() and "Window Mover" or "Mover: OFF"
end

function addon.RefreshBroker()
    if object then object.text = BrokerText() end
end

local function OpenSettings()
    if addon.OpenOptions and addon.OpenOptions() then return end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff62c6ffForever Window Mover:|r Open Options > AddOns > Forever Window Mover.")
    end
end

local function ToggleHandles()
    if not addon.SetHandlesVisible(not addon.HandlesVisible()) then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff62c6ffForever Window Mover:|r Cannot toggle MOVE handles during combat.")
        end
    end
end

local function AddTooltipLine(tooltip, left, right)
    if type(tooltip.AddDoubleLine) == "function" then
        tooltip:AddDoubleLine(left, right, 1, 1, 1, 0.8, 0.8, 0.8)
    elseif type(tooltip.AddLine) == "function" then
        tooltip:AddLine(left .. ": " .. right)
    end
end

local function Tooltip(tooltip)
    if not tooltip or type(tooltip.AddLine) ~= "function" then return end
    tooltip:AddLine("Forever Window Mover")
    tooltip:AddLine("Left-click: AddOns settings")
    tooltip:AddLine("Right-click: Show / hide all MOVE handles")
    tooltip:AddLine(" ")
    AddTooltipLine(tooltip, "MOVE handles", addon.HandlesVisible() and "Shown" or "Hidden")
    for _, group in ipairs(addon.groups) do
        local enabled = addon.IsEnabled(group.key)
        local saved = addon.HasPosition(group.key)
        local status = enabled and (saved and "Enabled - saved" or "Enabled - no position") or "Disabled"
        AddTooltipLine(tooltip, group.label, status)
    end
    tooltip:AddLine(" ")
    tooltip:AddLine("By " .. addon.author .. "  |  v" .. addon.version)
    tooltip:AddLine("GitHub: " .. addon.website, 0.55, 0.82, 1, true)
    tooltip:AddLine("Copy the URL from Options > AddOns", 0.75, 0.75, 0.75)
end

local function TryBroker()
    if object then return end
    local libstub = _G.LibStub
    if type(libstub) ~= "table" and type(libstub) ~= "function" then return end

    -- LibStub's silent option avoids throwing when Titan isn't installed.
    local ok, ldb = pcall(libstub, "LibDataBroker-1.1", true)
    if not ok or not ldb or type(ldb.NewDataObject) ~= "function" then return end

    local okExisting, existing = pcall(ldb.GetDataObjectByName, ldb, brokerName)
    if okExisting and existing then
        object = existing
        addon.RefreshBroker()
        return
    end

    local okCreate, result = pcall(ldb.NewDataObject, ldb, brokerName, {
        type = "launcher",
        label = "Window Mover",
        text = BrokerText(),
        icon = "Interface\\Icons\\INV_Misc_Gear_01",
        OnClick = function(_, button)
            if button == "LeftButton" then
                OpenSettings()
            elseif button == "RightButton" then
                ToggleHandles()
            end
        end,
        -- The display supplies the tooltip. Do not own/reposition GameTooltip:
        -- Titan 9.3.x documents tooltip changes in modern WoW builds.
        OnTooltipShow = Tooltip,
    })
    if okCreate then object = result end
end

TryBroker()

-- ADDON_LOADED also catches Titan being enabled/loaded after FWM.
-- PLAYER_LOGIN is a final attempt for libraries that finish during startup.
-- Only these two universally supported events are registered, and only while
-- there is still something to retry: once the launcher exists the listener
-- unregisters itself rather than waking for every addon load for the rest of
-- the session. The core keeps the launcher's state current through
-- addon.RefreshBroker, which needs no events of its own.
if not object then
    local listener = CreateFrame("Frame")
    listener:RegisterEvent("ADDON_LOADED")
    listener:RegisterEvent("PLAYER_LOGIN")
    listener:SetScript("OnEvent", function(self)
        TryBroker()
        if object then
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
        end
    end)
end
