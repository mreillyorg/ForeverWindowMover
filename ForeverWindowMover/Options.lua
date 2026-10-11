-- Blizzard Options > AddOns integration, deliberately isolated from dragging.
local _, addon = ...

-- Every size, gap and column the panel uses. Widgets get their vertical
-- position from a cursor walked down the panel and their horizontal position
-- from a derived column or a sibling anchor, so inserting or reordering a row
-- does not mean re-deriving a column of hand-written offsets. The panel's own
-- height is whatever the cursor ends up at.
local LAYOUT = {
    width        = 640,
    padding      = 18,
    -- UICheckButtonTemplate carries a little internal padding, so its box
    -- lines up with text at the padding column when inset slightly less.
    checkInset   = 15,
    checkHeight  = 26,
    lineGap      = 9,
    sectionGap   = 16,
    inlineGap    = 8,
    -- Row pitch has to clear the tallest widget in a row (the 26px checkbox)
    -- and the total has to stay inside Blizzard's settings canvas, which does
    -- not scroll a canvas category. Keep the derived height near 550.
    rowHeight    = 34,
    textLine     = 14,
    headingLine  = 16,
    titleLine    = 20,
    -- Where the per-row Reset button starts, as a fraction of content width.
    actionColumn = 0.625,
    resetWidth   = 78,
    resetHeight  = 23,
    savedWidth   = 90,
    buttonWidth  = 144,
    buttonHeight = 26,
    urlWidth     = 330,
    urlHeight    = 19,
    bylineWidth  = 180,
    statusHeight = 28,
}

local function ContentWidth()
    return LAYOUT.width - LAYOUT.padding * 2
end

-- Left edge of the per-row Reset button.
local function ActionColumnX()
    return LAYOUT.padding + math.floor(ContentWidth() * LAYOUT.actionColumn)
end

-- Left edge of the per-row Saved / Not set text.
local function SavedColumnX()
    return ActionColumnX() + LAYOUT.resetWidth + LAYOUT.inlineGap + 2
end

-- Minimal top-down layout cursor. Place reserves a band of the given height
-- and returns the y offset to anchor it at; Skip opens a gap; Height reports
-- the total panel height needed so far, including bottom padding.
local function NewCursor()
    local cursor = {y = -LAYOUT.padding}

    function cursor:Place(height, gap)
        local y = self.y
        self.y = y - height - (gap or LAYOUT.lineGap)
        return y
    end

    function cursor:Skip(gap)
        self.y = self.y - (gap or LAYOUT.sectionGap)
    end

    -- Vertical middle of a band, for anchoring widgets of differing heights
    -- to each other along one row.
    function cursor:Middle(y, height)
        return y - height / 2
    end

    function cursor:Height()
        return -self.y + LAYOUT.padding
    end

    return cursor
end

local function Text(panel, template, y, x)
    local text = panel:CreateFontString(nil, "ARTWORK", template)
    text:SetPoint("TOPLEFT", x or LAYOUT.padding, y)
    text:SetJustifyH("LEFT")
    return text
end

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
    -- Category IDs are numeric on current builds, but some return a string.
    -- Accept either rather than silently falling back to the chat hint.
    if not ok or (type(id) ~= "number" and type(id) ~= "string") then return false end
    return (pcall(Settings.OpenToCategory, id))
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
        local combatNotice = "In combat: window controls are locked until combat ends."
        local panel = CreateFrame("Frame", nil, UIParent)
        panel.name = "Forever Window Mover"

        local cursor = NewCursor()

        local title = Text(panel, "GameFontNormalLarge", cursor:Place(LAYOUT.titleLine))
        title:SetText("Forever Window Mover")

        local intro = Text(panel, "GameFontHighlightSmall", cursor:Place(LAYOUT.textLine))
        intro:SetWidth(ContentWidth())
        intro:SetText("Drag the MOVE tab above each window. Each window remembers its own position.")

        -- Attribution and selectable website link, laid out as one row: WoW
        -- cannot open an external browser from an addon, so the URL sits in an
        -- edit box to be selected and copied with Ctrl+C.
        local metaY = cursor:Place(LAYOUT.urlHeight)
        local metaMiddle = cursor:Middle(metaY, LAYOUT.urlHeight)

        local byline = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        byline:SetPoint("LEFT", panel, "TOPLEFT", LAYOUT.padding, metaMiddle)
        byline:SetWidth(LAYOUT.bylineWidth)
        byline:SetJustifyH("LEFT")
        byline:SetText("By " .. addon.author .. "  |  v" .. addon.version)

        local githubLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        githubLabel:SetPoint("LEFT", byline, "RIGHT", LAYOUT.lineGap, 0)
        githubLabel:SetText("GitHub:")

        local websiteBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        websiteBox:SetPoint("LEFT", githubLabel, "RIGHT", LAYOUT.lineGap, 0)
        websiteBox:SetSize(LAYOUT.urlWidth, LAYOUT.urlHeight)
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

        cursor:Skip(LAYOUT.lineGap)

        local headingY = cursor:Place(LAYOUT.headingLine)
        Text(panel, "GameFontNormal", headingY):SetText("Enable dragging")
        Text(panel, "GameFontNormal", headingY, SavedColumnX()):SetText("Saved position")

        local rows = {}
        local resetAll
        local handlesCheck
        local status

        local function Refresh()
            local canChange = addon.CanChangeFrames()
            for _, group in ipairs(addon.groups) do
                local row = rows[group.key]
                row.check:SetChecked(addon.IsEnabled(group.key))
                -- Combat-gated like every other control: SetEnabled refuses
                -- during lockdown, so the checkbox should not look live.
                row.check:SetEnabled(canChange)
                local saved = addon.HasPosition(group.key)
                row.status:SetText(saved and "Saved" or "Not set")
                row.reset:SetEnabled(saved and canChange)
            end
            if resetAll then resetAll:SetEnabled(canChange) end
            if handlesCheck then
                handlesCheck:SetChecked(addon.HandlesVisible())
                handlesCheck:SetEnabled(canChange)
            end
        end
        local function SetStatus(text) status:SetText(text) end

        for _, group in ipairs(addon.groups) do
            local key = group.key
            local label = group.label
            local y = cursor:Place(LAYOUT.rowHeight, 0)

            local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
            check:SetPoint("TOPLEFT", LAYOUT.checkInset, y)

            local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            text:SetPoint("LEFT", check, "RIGHT", LAYOUT.inlineGap, 0)
            text:SetText(label)

            local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            reset:SetSize(LAYOUT.resetWidth, LAYOUT.resetHeight)
            reset:SetPoint("TOPLEFT", ActionColumnX(), y - 1)
            reset:SetText("Reset")

            local saved = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            saved:SetPoint("LEFT", reset, "RIGHT", LAYOUT.inlineGap, 0)
            saved:SetWidth(LAYOUT.savedWidth)
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

        cursor:Skip()

        local handlesY = cursor:Place(LAYOUT.checkHeight)
        handlesCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        handlesCheck:SetPoint("TOPLEFT", LAYOUT.checkInset, handlesY)
        local handlesText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        handlesText:SetPoint("LEFT", handlesCheck, "RIGHT", LAYOUT.inlineGap, 0)
        handlesText:SetText("Show MOVE handles (also toggled by Titan right-click)")
        handlesCheck:SetScript("OnClick", function(self)
            if addon.SetHandlesVisible(not not self:GetChecked()) then
                SetStatus(addon.HandlesVisible() and "MOVE handles shown." or "MOVE handles hidden; positions retained.")
            else
                SetStatus("Cannot change MOVE handles during combat.")
            end
            Refresh()
        end)

        local resetAllY = cursor:Place(LAYOUT.buttonHeight)
        resetAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        resetAll:SetSize(LAYOUT.buttonWidth, LAYOUT.buttonHeight)
        resetAll:SetPoint("TOPLEFT", LAYOUT.padding, resetAllY)
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
        note:SetPoint("LEFT", resetAll, "RIGHT", LAYOUT.sectionGap, 0)
        note:SetWidth(ContentWidth() - LAYOUT.buttonWidth - LAYOUT.sectionGap)
        note:SetJustifyH("LEFT")
        note:SetText("Disabling a window keeps its saved position.")

        cursor:Skip()

        status = Text(panel, "GameFontHighlightSmall", cursor:Place(LAYOUT.statusHeight, 0))
        status:SetWidth(ContentWidth())
        status:SetText("")

        panel:SetSize(LAYOUT.width, cursor:Height())

        -- Combat state is polled from the panel's own OnUpdate rather than
        -- watched with PLAYER_REGEN_ENABLED / PLAYER_REGEN_DISABLED: 0.2.1
        -- removed those registrations because an unrecognised event can abort
        -- the addon on Forever. OnUpdate does not run while the panel is
        -- hidden, so this costs nothing when the page is closed.
        local POLL_INTERVAL = 0.25
        local pollElapsed = 0
        local lastCanChange
        panel:SetScript("OnUpdate", function(_, elapsed)
            pollElapsed = pollElapsed + elapsed
            if pollElapsed < POLL_INTERVAL then return end
            pollElapsed = 0
            local canChange = addon.CanChangeFrames()
            if canChange == lastCanChange then return end
            lastCanChange = canChange
            Refresh()
            if canChange then
                if status:GetText() == combatNotice then SetStatus("") end
            else
                SetStatus(combatNotice)
            end
        end)

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
        panel:SetScript("OnShow", function()
            lastCanChange = addon.CanChangeFrames()
            pollElapsed = 0
            if not lastCanChange then SetStatus(combatNotice) end
            Refresh()
        end)
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
