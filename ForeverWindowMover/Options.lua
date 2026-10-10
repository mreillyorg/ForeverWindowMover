-- Blizzard Options > AddOns integration, deliberately isolated from dragging.
local _, addon = ...

function addon.OpenOptions()
    -- The settings page is normally registered at login, but can also be
    -- initialized on demand if Blizzard's settings UI loaded later.
    if not addon.optionsCreated and addon.CreateOptions then
        pcall(addon.CreateOptions)
    end
    if not (Settings and type(Settings.OpenToCategory) == "function") then
        return false
    end
    local category = addon.optionsCategory
    if not category or type(category.GetID) ~= "function" then return false end
    local ok, id = pcall(category.GetID, category)
    if not ok or type(id) ~= "number" then return false end
    return pcall(Settings.OpenToCategory, id)
end

function addon.CreateOptions()
    if addon.optionsCreated then return end

    -- Canvas settings are present in the Forever (modern/Mainline) UI.
    -- If they are not loaded yet, the main addon will retry later.
    if not (Settings and type(Settings.RegisterCanvasLayoutCategory) == "function"
        and type(Settings.RegisterAddOnCategory) == "function") then
        return
    end

    if not addon.optionsPanel then
        local panel = CreateFrame("Frame", nil, UIParent)
        panel.name = "Forever Window Mover"
        panel:SetSize(640, 550)

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 18, -18)
        title:SetText("Forever Window Mover")

        local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -9)
        intro:SetWidth(575)
        intro:SetJustifyH("LEFT")
        intro:SetText("Drag the MOVE tab above each window. Each window remembers its own position.")

        -- Attribution and selectable website link. WoW cannot open an
        -- external browser from an addon; click the box and press Ctrl+C.
        local byline = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        byline:SetPoint("TOPLEFT", 18, -68)
        byline:SetText("By " .. addon.author .. "  |  v" .. addon.version)

        local githubLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        githubLabel:SetPoint("TOPLEFT", 208, -68)
        githubLabel:SetText("GitHub:")

        local websiteBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        websiteBox:SetPoint("TOPLEFT", 273, -64)
        websiteBox:SetSize(330, 19)
        websiteBox:SetAutoFocus(false)
        websiteBox:SetText(addon.website)
        websiteBox:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
        websiteBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        websiteBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        websiteBox:SetScript("OnEditFocusLost", function(self)
            -- Restore the true URL if someone accidentally edits the field.
            self:SetText(addon.website)
        end)

        local enableHeading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        enableHeading:SetPoint("TOPLEFT", 18, -89)
        enableHeading:SetText("Enable dragging")

        local savedHeading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        savedHeading:SetPoint("TOPLEFT", 407, -89)
        savedHeading:SetText("Saved position")

        local rows = {}
        local status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        status:SetPoint("BOTTOMLEFT", 18, 15)
        status:SetWidth(590)
        status:SetJustifyH("LEFT")
        status:SetText("")

        local resetAll
        local handlesCheck
        local function Refresh()
            for _, group in ipairs(addon.groups) do
                local row = rows[group.key]
                row.check:SetChecked(addon.IsEnabled(group.key))
                local saved = addon.HasPosition(group.key)
                row.status:SetText(saved and "Saved" or "Not set")
                row.reset:SetEnabled(saved and addon.CanChangeFrames())
            end
            if resetAll then resetAll:SetEnabled(addon.CanChangeFrames()) end
            if handlesCheck then
                handlesCheck:SetChecked(addon.HandlesVisible())
                handlesCheck:SetEnabled(addon.CanChangeFrames())
            end
        end
        local function SetStatus(text) status:SetText(text) end

        for i, group in ipairs(addon.groups) do
            local key = group.key
            local label = group.label
            local y = -116 - (i - 1) * 42

            local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
            check:SetPoint("TOPLEFT", 15, y)

            local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            text:SetPoint("LEFT", check, "RIGHT", 7, 0)
            text:SetText(label)

            local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            reset:SetSize(78, 23)
            reset:SetPoint("TOPLEFT", 395, y - 1)
            reset:SetText("Reset")

            local saved = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            saved:SetPoint("LEFT", reset, "RIGHT", 10, 0)
            saved:SetWidth(90)
            saved:SetJustifyH("LEFT")

            rows[key] = {check = check, reset = reset, status = saved}

            check:SetScript("OnClick", function(self)
                local enabled = not not self:GetChecked()
                if addon.SetEnabled(key, enabled) then
                    SetStatus(label .. (enabled and " enabled." or " disabled; saved position retained."))
                else
                    SetStatus("Cannot change window settings during combat.")
                end
                Refresh()
            end)

            reset:SetScript("OnClick", function()
                if addon.ResetGroup(key) then
                    SetStatus(label .. " position reset. Reopen the window if needed.")
                else
                    SetStatus("Cannot reset windows during combat.")
                end
                Refresh()
            end)
        end

        handlesCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        handlesCheck:SetPoint("TOPLEFT", 15, -444)
        local handlesText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        handlesText:SetPoint("LEFT", handlesCheck, "RIGHT", 7, 0)
        handlesText:SetText("Show MOVE handles (also toggled by Titan right-click)")
        handlesCheck:SetScript("OnClick", function(self)
            if addon.SetHandlesVisible(not not self:GetChecked()) then
                SetStatus(addon.HandlesVisible() and "MOVE handles shown." or "MOVE handles hidden; positions retained.")
            else
                SetStatus("Cannot change MOVE handles during combat.")
            end
            Refresh()
        end)

        resetAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        resetAll:SetSize(144, 26)
        resetAll:SetPoint("TOPLEFT", 18, -490)
        resetAll:SetText("Reset all positions")
        resetAll:SetScript("OnClick", function()
            if addon.ResetAll() then
                SetStatus("All window positions reset. Reopen any currently open windows.")
            else
                SetStatus("Cannot reset windows during combat.")
            end
            Refresh()
        end)

        local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        note:SetPoint("LEFT", resetAll, "RIGHT", 15, 0)
        note:SetWidth(395)
        note:SetJustifyH("LEFT")
        note:SetText("Disabling a window keeps its saved position.")

        -- Required by Blizzard's canvas settings registration API.
        panel.OnRefresh = Refresh
        panel.OnCommit = function() end
        panel.OnDefault = function()
            if not addon.ResetAll() then
                SetStatus("Cannot restore defaults during combat.")
                return
            end
            for _, group in ipairs(addon.groups) do
                addon.SetEnabled(group.key, true)
            end
            addon.SetHandlesVisible(true)
            SetStatus("All settings restored to defaults.")
            Refresh()
        end
        panel:SetScript("OnShow", Refresh)
        addon.RefreshOptions = function()
            if panel:IsShown() then Refresh() end
        end
        addon.optionsPanel = panel
    end

    local category = Settings.RegisterCanvasLayoutCategory(addon.optionsPanel, addon.optionsPanel.name)
    Settings.RegisterAddOnCategory(category)
    addon.optionsCreated = true
    addon.optionsCategory = category
end
