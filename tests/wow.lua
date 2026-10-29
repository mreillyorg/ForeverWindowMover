-- Minimal stand-in for the WoW client, for the offline harnesses.
--
-- Load it first, then load the addon's files against the table it hands back:
--
--     local wow = assert(loadfile("tests/wow.lua"))()
--     local addon = {}
--     assert(loadfile("ForeverWindowMover.lua"))("ForeverWindowMover", addon)
--     wow.fire("ADDON_LOADED", "ForeverWindowMover")
--
-- Only what the addon actually calls is implemented, and every frame gets the
-- full method set rather than branching on template name -- the addon never
-- depends on a template behaving differently, so one generic region is simpler
-- and has fewer places to be wrong than three near-identical ones.
--
-- Geometry is a deliberate fiction with real arithmetic. UIParent is 800x600 at
-- effective scale 1, so a frame at a different scale exercises the unit
-- conversion in SavePosition and ApplyPosition for real. See tests/positions.lua.

local wow = {}

-- Frames that have registered for an event, keyed by event name.
local listeners = {}
-- Every frame created, in order, so a harness can find the addon's own.
wow.frames = {}
-- Names this stub has published into _G, so reset can take them back out.
wow.named = {}
wow.inCombat = false
wow.tickers = {}

local SCREEN_WIDTH, SCREEN_HEIGHT = 800, 600

local function noop() end

-- One region type for frames, buttons, textures and font strings.
local function newRegion(kind, name, parent)
    local region = {
        kind = kind,
        name = name,
        parent = parent,
        children = {},
        points = {},
        scripts = {},
        hooks = {},
        events = {},
        shown = true,
        enabled = true,
        checked = false,
        text = nil,
        level = 0,
        -- Centre and top in UIParent units. Harnesses overwrite these to
        -- position a frame; GetCenter converts back into frame units below.
        centerX = SCREEN_WIDTH / 2,
        centerY = SCREEN_HEIGHT / 2,
        top = SCREEN_HEIGHT,
        scale = 1,
    }

    function region:SetSize(w, h) self.width, self.height = w, h end
    function region:SetWidth(w) self.width = w end
    function region:SetHeight(h) self.height = h end

    -- SetPoint has two forms in the client and the addon uses both:
    --   SetPoint(point, relativeTo, relativePoint, x, y)   -- window anchors
    --   SetPoint(point, x, y)                              -- options widgets
    -- Points are stored normalised to the long form, with relativeTo and
    -- relativePoint defaulted the way GetPoint reports them, so a captured
    -- point can be replayed through SetPoint unchanged.
    function region:SetPoint(a, b, c, d, e)
        local point, relativeTo, relativePoint, x, y
        if type(b) == "number" or b == nil then
            point, x, y = a, b, c
            relativeTo, relativePoint = self.parent, a
        else
            point, relativeTo, relativePoint, x, y = a, b, c, d, e
            relativePoint = relativePoint or a
        end
        self.points[#self.points + 1] = {point, relativeTo, relativePoint, x, y}

        -- Keep the fictional geometry self-consistent: an anchor of the shape
        -- ApplyPosition uses really does move the frame here, so a harness can
        -- assert where it landed and can repeat a save/apply cycle to prove the
        -- position does not drift. SetPoint offsets are in the anchored frame's
        -- own units, hence the scale conversion.
        if point == "CENTER" and relativeTo == _G.UIParent and relativePoint == "CENTER"
            and type(x) == "number" and type(y) == "number" then
            local ratio = self.scale / _G.UIParent.scale
            self.centerX = SCREEN_WIDTH / 2 + x * ratio
            self.centerY = SCREEN_HEIGHT / 2 + y * ratio
        end
    end

    -- True offset of this frame's centre from UIParent's, in UIParent units.
    -- This is the quantity a saved position is supposed to reproduce.
    function region:CenterOffset()
        return self.centerX - SCREEN_WIDTH / 2, self.centerY - SCREEN_HEIGHT / 2
    end
    function region:ClearAllPoints() self.points = {} end
    function region:GetNumPoints() return #self.points end
    function region:GetPoint(index)
        local p = self.points[index or 1]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    -- The anchor this addon applied, if any: the last CENTER-on-UIParent point.
    function region:AppliedOffset()
        for i = #self.points, 1, -1 do
            local p = self.points[i]
            if p[1] == "CENTER" then return p[4], p[5] end
        end
        return nil
    end
    -- Lowest edge this region's own anchors reach, as a positive distance below
    -- its parent's top. Used to check nothing is laid out past a panel's bottom.
    function region:LowestOffset()
        local lowest = 0
        for _, p in ipairs(self.points) do
            local y = p[5]
            if type(y) == "number" and y < 0 then
                local depth = -y + (self.height or 0)
                if depth > lowest then lowest = depth end
            end
        end
        return lowest
    end

    function region:SetAllPoints() end
    function region:SetColorTexture() end
    function region:SetJustifyH() end
    function region:SetFrameLevel(v) self.level = v end
    function region:GetFrameLevel() return self.level end
    function region:EnableMouse() end
    function region:SetMovable(v) self.movable = v end
    function region:SetClampedToScreen(v) self.clamped = v end
    function region:StartMoving() self.moving = true end
    function region:StopMovingOrSizing() self.moving = false end
    function region:SetUserPlaced(v) self.userPlaced = v end
    function region:RegisterForDrag(...) self.dragButtons = {...} end

    function region:SetScript(script, handler) self.scripts[script] = handler end
    function region:GetScript(script) return self.scripts[script] end
    function region:HookScript(script, handler)
        self.hooks[script] = self.hooks[script] or {}
        local list = self.hooks[script]
        list[#list + 1] = handler
    end

    function region:RegisterEvent(event)
        self.events[event] = true
        listeners[event] = listeners[event] or {}
        local list = listeners[event]
        for _, f in ipairs(list) do
            if f == self then return end
        end
        list[#list + 1] = self
    end
    function region:UnregisterEvent(event)
        self.events[event] = nil
        local list = listeners[event]
        if not list then return end
        for i = #list, 1, -1 do
            if list[i] == self then table.remove(list, i) end
        end
    end
    function region:UnregisterAllEvents()
        for event in pairs(self.events) do self:UnregisterEvent(event) end
    end

    function region:Show() self.shown = true end
    function region:Hide()
        self.shown = false
        -- The client fires OnHide, and the addon relies on it to finish a drag
        -- when a window closes mid-move.
        local handler = self.scripts.OnHide
        if handler then handler(self) end
    end
    function region:IsShown() return self.shown end

    function region:SetEnabled(v) self.enabled = not not v end
    function region:IsEnabled() return self.enabled end
    function region:SetChecked(v) self.checked = not not v end
    function region:GetChecked() return self.checked end
    function region:SetText(v) self.text = v end
    function region:GetText() return self.text end
    function region:SetAutoFocus() end
    function region:HighlightText() self.highlighted = true end
    function region:ClearFocus() self.focused = false end

    function region:GetEffectiveScale() return self.scale end
    -- GetCenter reports in the frame's OWN coordinate space, which is the whole
    -- reason SavePosition multiplies by the scale ratio.
    function region:GetCenter()
        return self.centerX / self.scale, self.centerY / self.scale
    end
    function region:GetTop() return self.top / self.scale end

    function region:CreateTexture() return newRegion("Texture", nil, self) end
    function region:CreateFontString() return newRegion("FontString", nil, self) end

    -- Helpers for harnesses, not client API.
    function region:FirstChildOfKind(wanted)
        for _, child in ipairs(self.children) do
            if child.kind == wanted then return child end
        end
        return nil
    end
    function region:FireHook(script, ...)
        for _, handler in ipairs(self.hooks[script] or {}) do handler(self, ...) end
    end
    function region:Click(...)
        local handler = self.scripts.OnClick
        assert(handler, "region has no OnClick")
        handler(self, ...)
    end

    if parent then parent.children[#parent.children + 1] = region end
    wow.frames[#wow.frames + 1] = region
    if name then
        _G[name] = region
        wow.named[name] = true
    end
    return region
end

wow.newRegion = newRegion

-- Positions a stub frame so its true centre sits at the given offset from
-- UIParent's centre, in UIParent units, at the given effective scale.
function wow.place(frame, offsetX, offsetY, scale)
    frame.scale = scale or 1
    frame.centerX = SCREEN_WIDTH / 2 + offsetX
    frame.centerY = SCREEN_HEIGHT / 2 + offsetY
    return frame
end

function wow.fire(event, ...)
    for _, frame in ipairs(listeners[event] or {}) do
        local handler = frame.scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

-- Clears registrations and removes every named frame this stub put into _G, so
-- one case cannot leave a Blizzard frame behind for the next. UIParent stays:
-- the client never destroys it and the addon holds a direct reference.
function wow.reset()
    listeners = {}
    wow.frames = {}
    wow.tickers = {}
    wow.inCombat = false
    for name in pairs(wow.named) do
        if name ~= "UIParent" then _G[name] = nil end
    end
    wow.named = {UIParent = true}
    _G.GameTooltip.lines = {}
    _G.DEFAULT_CHAT_FRAME.messages = {}
    -- Opt-in globals, so each case starts from "the client does not have it".
    _G.Settings = nil
    _G.LibStub = nil
end

-- --- globals the addon reads ------------------------------------------------

_G.UIParent = newRegion("Frame", "UIParent", nil)
_G.UIParent.top = SCREEN_HEIGHT

_G.CreateFrame = function(kind, name, parent)
    return newRegion(kind or "Frame", name, parent)
end

_G.GameTooltip = {
    lines = {},
    SetOwner = function(self) self.owner = true end,
    SetText = function(self, text) self.lines[#self.lines + 1] = text end,
    AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
    AddDoubleLine = function(self, left, right)
        self.lines[#self.lines + 1] = tostring(left) .. ": " .. tostring(right)
    end,
    Show = noop,
    Hide = noop,
}

_G.DEFAULT_CHAT_FRAME = {
    messages = {},
    AddMessage = function(self, text) self.messages[#self.messages + 1] = text end,
}

_G.InCombatLockdown = function() return wow.inCombat end

-- After runs inline: the addon only uses it to defer past Blizzard's panel
-- manager, and a harness has no panel manager to wait for. NewTicker records
-- rather than running, or the discovery scan would never stop.
_G.C_Timer = {
    After = function(_, callback) callback() end,
    NewTicker = function(interval, callback)
        local ticker = {interval = interval, callback = callback, cancelled = false}
        function ticker:Cancel() self.cancelled = true end
        wow.tickers[#wow.tickers + 1] = ticker
        return ticker
    end,
}

_G.UpdateUIPanelPositions = noop
_G.hooksecurefunc = function() end

-- Blizzard's settings canvas, and LibDataBroker, are NOT installed by default.
-- Both are feature-detected by the addon because it has to load without them,
-- and the harnesses check that path too, so a test opts in explicitly.

function wow.installSettings(categoryId)
    local registered = {}
    _G.Settings = {
        registered = registered,
        opened = {},
        RegisterCanvasLayoutCategory = function(panel, name)
            local category = {name = name, panel = panel, id = categoryId or 42}
            function category:GetID() return self.id end
            registered[#registered + 1] = category
            return category
        end,
        RegisterAddOnCategory = function(category) category.inAddOnList = true end,
        OpenToCategory = function(id)
            _G.Settings.opened[#_G.Settings.opened + 1] = id
            return true
        end,
    }
    return _G.Settings
end

-- A LibStub that serves a minimal LibDataBroker-1.1. Returns the broker table
-- so a harness can inspect what was registered.
function wow.installLibDataBroker()
    local ldb = {objects = {}}
    function ldb:NewDataObject(name, tbl)
        self.objects[name] = tbl
        return tbl
    end
    function ldb:GetDataObjectByName(name) return self.objects[name] end

    _G.LibStub = function(name)
        if name == "LibDataBroker-1.1" then return ldb end
        return nil
    end
    return ldb
end

return wow
