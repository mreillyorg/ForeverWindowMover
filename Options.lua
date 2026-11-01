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

-- Panels register a refresher here so the core's single addon.RefreshOptions
-- call reaches every page. Each one checks its own panel's visibility.
local refreshers = {}

local function RunRefreshers()
    for _, refresh in ipairs(refreshers) do refresh() end
end

-- Opens the colour picker on `colour` and calls back with r, g, b, a.
--
-- The API changed in 10.0: SetupColorPickerAndShow takes an info table, while
-- before that you set fields on ColorPickerFrame and showed it yourself. Both
-- are supported because the addon has to load on either, and reading the alpha
-- back differs too -- GetColorAlpha on current builds, OpacitySliderFrame
-- before it. Returns false if there is no usable picker at all.
local function ShowColourPicker(colour, apply)
    local picker = ColorPickerFrame
    if not picker then return false end

    local r, g, b, a = colour[1], colour[2], colour[3], colour[4] or 1
    -- The picker reports opacity, which is the inverse of alpha.
    local function currentAlpha()
        if type(picker.GetColorAlpha) == "function" then
            local ok, value = pcall(picker.GetColorAlpha, picker)
            if ok and type(value) == "number" then return value end
        end
        if OpacitySliderFrame and type(OpacitySliderFrame.GetValue) == "function" then
            local ok, value = pcall(OpacitySliderFrame.GetValue, OpacitySliderFrame)
            if ok and type(value) == "number" then return 1 - value end
        end
        return a
    end
    local function onChange()
        local ok, nr, ng, nb = pcall(picker.GetColorRGB, picker)
        if ok and type(nr) == "number" then apply(nr, ng, nb, currentAlpha()) end
    end
    local function onCancel()
        apply(r, g, b, a)
    end

    if type(picker.SetupColorPickerAndShow) == "function" then
        return (pcall(picker.SetupColorPickerAndShow, picker, {
            r = r, g = g, b = b, opacity = 1 - a, hasOpacity = true,
            swatchFunc = onChange, opacityFunc = onChange, cancelFunc = onCancel,
        }))
    end

    -- Pre-10.0: assign the callbacks, seed the colour, then show the frame.
    return (pcall(function()
        picker.func = onChange
        picker.opacityFunc = onChange
        picker.cancelFunc = onCancel
        picker.hasOpacity = true
        picker.opacity = 1 - a
        picker:SetColorRGB(r, g, b)
        picker:Hide() -- forces OnShow to run again if it was already open
        if type(ShowUIPanel) == "function" then
            ShowUIPanel(picker)
        else
            picker:Show()
        end
    end))
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

-- The Handles page: which drag mechanisms are live, and what the tab looks
-- like. A separate page rather than more rows on the main one, because the
-- window list already comes to 552px against a settings canvas that does not
-- scroll. See docs/development.md.
local function BuildHandlePage()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.name = "Handles"

    local cursor = NewCursor()
    local status
    local rows = {}
    local styleChecks = {}
    local swatches = {}
    local sizeLabels = {}
    local labelCheck, warning

    local function SetStatus(text) status:SetText(text) end

    Text(panel, "GameFontNormalLarge", cursor:Place(LAYOUT.titleLine))
        :SetText("Forever Window Mover: handles")

    local intro = Text(panel, "GameFontHighlightSmall", cursor:Place(LAYOUT.textLine * 2))
    intro:SetWidth(ContentWidth())
    intro:SetText("Choose how windows are dragged, and what the MOVE tab looks like. "
        .. "These settings apply to every window group.")

    cursor:Skip(LAYOUT.lineGap)
    Text(panel, "GameFontNormal", cursor:Place(LAYOUT.headingLine)):SetText("Dragging")

    -- The two mechanisms.
    local function mechanism(labelText, note, getter, setter)
        local y = cursor:Place(LAYOUT.checkHeight, 2)
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", LAYOUT.checkInset, y)
        local caption = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        caption:SetPoint("LEFT", check, "RIGHT", LAYOUT.inlineGap, 0)
        caption:SetText(labelText)

        local hint = Text(panel, "GameFontDisableSmall", cursor:Place(LAYOUT.textLine),
            LAYOUT.checkInset + 26)
        hint:SetWidth(ContentWidth() - 26)
        hint:SetText(note)

        check:SetScript("OnClick", function(self)
            if setter(not not self:GetChecked()) then
                SetStatus(labelText .. (self:GetChecked() and " enabled." or " disabled."))
            else
                SetStatus("Cannot change handles during combat.")
            end
            RunRefreshers()
        end)
        rows[#rows + 1] = {check = check, getter = getter}
        return check
    end

    mechanism("Show the MOVE tab",
        "A small tab above each window's top-left corner.",
        addon.TabEnabled, addon.SetTabEnabled)
    mechanism("Drag by the window's title bar",
        "No tab: drag the window by its own title bar. There is nothing to see, "
        .. "so hover the title bar to confirm it is active.",
        addon.TitlebarEnabled, addon.SetTitlebarEnabled)

    warning = Text(panel, "GameFontRedSmall", cursor:Place(LAYOUT.textLine))
    warning:SetWidth(ContentWidth())
    warning:SetText("")

    cursor:Skip(LAYOUT.lineGap)
    Text(panel, "GameFontNormal", cursor:Place(LAYOUT.headingLine)):SetText("Tab appearance")

    -- Style selection. Checkbuttons used as a radio group: Refresh keeps
    -- exactly one checked, so there is no separate radio template to depend on.
    for _, name in ipairs(addon.handleStyleOrder) do
        local style = name == "custom" and addon.CustomStyle() or addon.handleStyles[name]
        local y = cursor:Place(LAYOUT.checkHeight, 2)
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", LAYOUT.checkInset, y)
        local caption = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        caption:SetPoint("LEFT", check, "RIGHT", LAYOUT.inlineGap, 0)
        caption:SetText(style.label)

        check:SetScript("OnClick", function()
            if addon.SetHandleStyle(name) then
                SetStatus(style.label .. " tab style selected.")
            else
                SetStatus("Cannot change the tab style during combat.")
            end
            RunRefreshers()
        end)
        styleChecks[name] = check
    end

    cursor:Skip(LAYOUT.lineGap)
    Text(panel, "GameFontNormal", cursor:Place(LAYOUT.headingLine))
        :SetText("Custom tab (used when Custom is selected above)")

    -- Both colour swatches on one row, to keep the page inside the canvas.
    local swatchY = cursor:Place(LAYOUT.checkHeight)
    local function swatch(field, caption, offsetX)
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(118, 22)
        button:SetPoint("TOPLEFT", offsetX, swatchY)
        button:SetText(caption)
        local chip = button:CreateTexture(nil, "OVERLAY")
        chip:SetSize(14, 14)
        chip:SetPoint("RIGHT", button, "RIGHT", -6, 0)
        button:SetScript("OnClick", function()
            local current = addon.CustomStyle()[field]
            local opened = ShowColourPicker(current, function(r, g, b, a)
                addon.SetCustomStyle(field, {r, g, b, a})
                RunRefreshers()
            end)
            if not opened then
                SetStatus("This build has no colour picker; edit handleCustom in the "
                    .. "saved variables instead.")
            end
        end)
        swatches[field] = {button = button, chip = chip}
    end
    swatch("bg", "Background", LAYOUT.padding)
    swatch("hover", "Hover", LAYOUT.padding + 130)

    local labelY = cursor:Place(LAYOUT.checkHeight, 2)
    labelCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    labelCheck:SetPoint("TOPLEFT", LAYOUT.checkInset, labelY)
    local labelCaption = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    labelCaption:SetPoint("LEFT", labelCheck, "RIGHT", LAYOUT.inlineGap, 0)
    labelCaption:SetText("Show the MOVE label (off gives a grip instead)")
    labelCheck:SetScript("OnClick", function(self)
        if addon.SetCustomStyle("text", not not self:GetChecked()) then
            SetStatus("Custom tab label updated.")
        else
            SetStatus("Cannot change the tab style during combat.")
        end
        RunRefreshers()
    end)

    -- Size steppers rather than sliders: OptionsSliderTemplate is not present
    -- on every build, and a failed CreateFrame would take the whole page with
    -- it. Buttons use a template this file already relies on.
    local sizeY = cursor:Place(LAYOUT.checkHeight)
    local function stepper(field, caption, step, minimum, maximum, offsetX)
        local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("TOPLEFT", offsetX, sizeY - 4)
        text:SetText(caption)

        local function nudge(delta, x)
            local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            button:SetSize(24, 22)
            button:SetPoint("TOPLEFT", x, sizeY)
            button:SetText(delta > 0 and "+" or "-")
            button:SetScript("OnClick", function()
                local value = addon.CustomStyle()[field] + delta
                if value < minimum then value = minimum end
                if value > maximum then value = maximum end
                if not addon.SetCustomStyle(field, value) then
                    SetStatus("Cannot resize the tab during combat.")
                end
                RunRefreshers()
            end)
            return button
        end
        nudge(-step, offsetX + 58)
        local value = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        value:SetPoint("TOPLEFT", offsetX + 86, sizeY - 4)
        value:SetWidth(30)
        value:SetJustifyH("CENTER")
        nudge(step, offsetX + 118)
        sizeLabels[field] = value
    end
    stepper("width", "Width", 5, 20, 200, LAYOUT.padding)
    stepper("height", "Height", 2, 12, 60, LAYOUT.padding + 160)

    cursor:Skip()
    status = Text(panel, "GameFontHighlightSmall", cursor:Place(LAYOUT.statusHeight, 0))
    status:SetWidth(ContentWidth())
    status:SetText("")

    panel:SetSize(LAYOUT.width, cursor:Height())

    local function Refresh()
        local canChange = addon.CanChangeFrames()
        for _, row in ipairs(rows) do
            row.check:SetChecked(row.getter())
            row.check:SetEnabled(canChange)
        end
        warning:SetText(addon.NothingDraggable()
            and "Nothing is draggable: switch on the tab, the title bar, or both."
            or "")

        local selected = addon.HandleStyleName()
        for name, check in pairs(styleChecks) do
            check:SetChecked(name == selected)
            check:SetEnabled(canChange)
        end

        -- The custom controls stay usable whichever style is selected, so you
        -- can set a custom tab up before switching to it.
        local custom = addon.CustomStyle()
        for field, parts in pairs(swatches) do
            local colour = custom[field]
            parts.chip:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
            parts.button:SetEnabled(canChange)
        end
        labelCheck:SetChecked(custom.text ~= nil)
        labelCheck:SetEnabled(canChange)
        for field, label in pairs(sizeLabels) do
            label:SetText(tostring(custom[field]))
        end
    end

    panel.OnRefresh = Refresh
    panel.OnCommit = function() end
    panel.OnDefault = function()
        if not (addon.SetTabEnabled(true) and addon.SetTitlebarEnabled(false)
            and addon.SetHandleStyle("dark")) then
            SetStatus("Cannot restore defaults during combat.")
            return
        end
        SetStatus("Handle settings restored to defaults.")
        RunRefreshers()
    end
    panel:SetScript("OnShow", Refresh)
    refreshers[#refreshers + 1] = function()
        if panel:IsShown() then Refresh() end
    end
    return panel
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
        refreshers[#refreshers + 1] = function()
            if panel:IsShown() then Refresh() end
        end
        addon.RefreshOptions = RunRefreshers
        addon.optionsPanel = panel
    end

    if not addon.handlePanel then
        addon.handlePanel = BuildHandlePage()
    end

    local category = Settings.RegisterCanvasLayoutCategory(addon.optionsPanel, addon.optionsPanel.name)
    Settings.RegisterAddOnCategory(category)
    addon.optionsCreated = true
    addon.optionsCategory = category

    -- Nested under the main entry where the API allows it. On a build without
    -- RegisterCanvasLayoutSubcategory, fall back to a second top-level entry:
    -- less tidy in the list, but the settings stay reachable, which matters
    -- more than where they sit.
    local nested = false
    if type(Settings.RegisterCanvasLayoutSubcategory) == "function" then
        local ok, subcategory = pcall(Settings.RegisterCanvasLayoutSubcategory,
            category, addon.handlePanel, addon.handlePanel.name)
        if ok and subcategory then
            addon.handleCategory = subcategory
            nested = true
        end
    end
    if not nested then
        local ok, standalone = pcall(Settings.RegisterCanvasLayoutCategory,
            addon.handlePanel, "Forever Window Mover: handles")
        if ok and standalone then
            pcall(Settings.RegisterAddOnCategory, standalone)
            addon.handleCategory = standalone
        end
    end
end
