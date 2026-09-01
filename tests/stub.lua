-- Minimal WoW client stub for headless smoke testing.
--
-- This is NOT a faithful model of the WoW API. It exists only to let the addon
-- files LOAD and RUN their lifecycle without throwing. Almost every function is a
-- no-op; the few that return values return the blandest plausible value.
--
-- Installs globals into _G and returns a control table the harness uses to drive
-- events / timers and to swap in a tiny "mounts loaded" data set.

local Stub = {}

-- ============================================================================
-- Universal permissive object: indexing it or calling it yields itself, so any
-- unforeseen `frame:SomeMethod():Chained()` is a safe no-op. Numeric / stateful
-- methods are given real stubs on the frame itself (below) because arithmetic on
-- this object would error -- which is the point: it surfaces gaps.
-- ============================================================================

local UNIVERSAL = {}
setmetatable(UNIVERSAL, {
    __index = function() return UNIVERSAL end,
    __call = function() return UNIVERSAL end,
    __concat = function() return "" end,
})
Stub.UNIVERSAL = UNIVERSAL

local function noop() end

-- ============================================================================
-- Frames
-- ============================================================================

local allFrames = {}
local eventFrames = {} -- [eventName] = { frame, ... }

local frameMethods = {}

local function makeFrame(frameType, name)
    local f = {
        _type = frameType or "Frame",
        _name = name,
        _shown = false,
        _scripts = {},
        _hooks = {},
        _events = {},
        _points = {},
        _width = 400,
        _height = 300,
        _level = 5,
    }
    setmetatable(f, {
        __index = function(_, key)
            local m = frameMethods[key]
            if m then return m end
            return UNIVERSAL
        end,
    })
    allFrames[#allFrames + 1] = f
    if name then _G[name] = f end
    return f
end

function frameMethods.RegisterEvent(self, event)
    self._events[event] = true
    eventFrames[event] = eventFrames[event] or {}
    eventFrames[event][#eventFrames[event] + 1] = self
end
function frameMethods.UnregisterEvent(self, event) self._events[event] = nil end
function frameMethods.UnregisterAllEvents(self) self._events = {} end
function frameMethods.IsEventRegistered(self, event) return self._events[event] == true end
function frameMethods.SetScript(self, name, fn) self._scripts[name] = fn end
function frameMethods.GetScript(self, name) return self._scripts[name] end
function frameMethods.HookScript(self, name, fn)
    self._hooks[name] = self._hooks[name] or {}
    self._hooks[name][#self._hooks[name] + 1] = fn
end
function frameMethods.Show(self) self._shown = true end
function frameMethods.Hide(self) self._shown = false end
function frameMethods.SetShown(self, v) self._shown = v and true or false end
function frameMethods.IsShown(self) return self._shown end
function frameMethods.IsVisible(self) return self._shown end
function frameMethods.SetWidth(self, w) self._width = w or self._width end
function frameMethods.SetHeight(self, h) self._height = h or self._height end
function frameMethods.SetSize(self, w, h) self._width, self._height = w or self._width, h or self._height end
function frameMethods.GetWidth(self) return self._width end
function frameMethods.GetHeight(self) return self._height end
function frameMethods.GetSize(self) return self._width, self._height end
function frameMethods.GetFrameLevel(self) return self._level end
function frameMethods.SetFrameLevel(self, l) self._level = l or self._level end
function frameMethods.GetID() return 1 end
function frameMethods.GetName(self) return self._name end
function frameMethods.GetNumPoints(self) return #self._points end
function frameMethods.GetPoint(self)
    local p = self._points[1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
    return "CENTER", nil, "CENTER", 0, 0
end
function frameMethods.SetPoint(self, point, relTo, relPoint, x, y)
    self._points[1] = { point, relTo, relPoint, x or 0, y or 0 }
end
function frameMethods.ClearAllPoints(self) self._points = {} end
function frameMethods.GetParent(self) return self._parent end
function frameMethods.CreateFontString() return UNIVERSAL end
function frameMethods.CreateTexture() return UNIVERSAL end
function frameMethods.CreateAnimationGroup() return UNIVERSAL end
function frameMethods.SetScrollChild(self, c) self._scrollChild = c end
function frameMethods.GetScrollChild(self) return self._scrollChild end
frameMethods.StartMoving = noop
frameMethods.StopMovingOrSizing = noop
frameMethods.StartSizing = noop
frameMethods.RegisterForClicks = noop
frameMethods.RegisterForDrag = noop

Stub.fireScript = function(frame, name, ...)
    local fn = frame._scripts and frame._scripts[name]
    if fn then fn(frame, ...) end
    local hooks = frame._hooks and frame._hooks[name]
    if hooks then
        for _, h in ipairs(hooks) do h(frame, ...) end
    end
end

Stub.fireEvent = function(event, ...)
    for _, frame in ipairs(eventFrames[event] or {}) do
        local fn = frame._scripts.OnEvent
        if fn then fn(frame, event, ...) end
    end
end

-- ============================================================================
-- Timers
-- ============================================================================

local timerQueue = {}

Stub.runTimers = function(maxCycles)
    maxCycles = maxCycles or 25
    local cycles = 0
    while #timerQueue > 0 and cycles < maxCycles do
        cycles = cycles + 1
        local batch = timerQueue
        timerQueue = {}
        table.sort(batch, function(a, b) return a.delay < b.delay end)
        for _, t in ipairs(batch) do
            t.fn()
        end
    end
    return cycles
end

Stub.pendingTimers = function() return #timerQueue end

-- ============================================================================
-- Output capture
-- ============================================================================

local printed = {}
Stub.getPrints = function() return printed end
Stub.clearPrints = function() printed = {} end

-- ============================================================================
-- Mount / map / zone data (swappable by the harness)
-- ============================================================================

local D = {
    zone = "Elwynn Forest",
    subZone = "",
    faction = "Alliance",
    mapID = nil,
    mapInfo = {},        -- [mapID] = { name=, mapID=, parentMapID= }
    mountIDs = {},       -- C_MountJournal.GetMountIDs
    mountInfo = {},      -- [mountID] = { name=, spellID=, icon=, isUsable=, isCollected=, ... }
    money = 0,           -- GetMoney (copper)
    factions = {},       -- [factionID] = { currentStanding=, renownLevel= }
    currencies = {},     -- [currencyID] = { quantity= }
    questsCompleted = {}, -- [questID] = true
    achievements = {},   -- [achID] = { name=, completed= }
    openedCategory = nil, -- last Settings.OpenToCategory argument
    settings = {},       -- [variableKey] = { get=, set=, fireChanged= } (options panel bindings)
    worldPins = 0,       -- HBDPins:AddWorldMapIconMap call count since the last RemoveAll
    minimapPins = 0,     -- HBDPins:AddMinimapIconMap call count since the last RemoveAll
}
Stub.data = D

-- ============================================================================
-- Global install
-- ============================================================================

function Stub.install()
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        printed[#printed + 1] = table.concat(parts, "\t")
    end

    _G.wipe = function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end
    _G.CreateFrame = function(frameType, name, parent, template)
        local f = makeFrame(frameType, name)
        f._parent, f._template = parent, template
        return f
    end
    _G.UIParent = makeFrame("Frame", "UIParent")
    _G.WorldFrame = makeFrame("Frame", "WorldFrame")
    _G.DEFAULT_CHAT_FRAME = { editBox = { SetText = noop, ClearFocus = noop } }
    _G.SlashCmdList = {}
    _G.GameTooltip = setmetatable({}, { __index = function() return noop end })
    _G.InCombatLockdown = function() return false end

    -- Mount journal + collection UI
    _G.C_MountJournal = {
        GetMountIDs = function()
            local out = {}
            for i, id in ipairs(D.mountIDs) do out[i] = id end
            return out
        end,
        GetMountInfoByID = function(mountID)
            local m = D.mountInfo[mountID]
            if not m then return nil end
            return m.name, m.spellID or (mountID * 10), m.icon or "Interface\\ICONS\\Ability_Mount_RidingHorse",
                m.isActive or false, m.isUsable ~= false, m.sourceType or 1, m.isFavorite or false,
                m.isFactionSpecific or false, m.faction, m.shouldHideOnChar or false,
                m.isCollected or false, mountID
        end,
        GetMountInfoExtraByID = function()
            return 0, 0, false, false, "", false
        end,
        SummonByID = noop,
    }
    _G.ToggleCollectionsJournal = noop
    _G.MountJournal_SelectByMountID = noop

    _G.C_Spell = {
        GetSpellLink = function(spellID)
            return "|cff71d5ff|Hspell:" .. tostring(spellID) .. "|h[Mount Spell]|h|r"
        end,
    }

    -- Obtainability inputs
    _G.GetMoney = function() return D.money end
    _G.C_Reputation = {
        GetFactionDataByID = function(id)
            local f = D.factions[id]
            if not f then return nil end
            return { currentStanding = f.currentStanding, currentReactionThreshold = f.threshold }
        end,
    }
    _G.C_MajorFactions = {
        GetMajorFactionData = function(id)
            local f = D.factions[id]
            if not f or not f.renownLevel then return nil end
            return { renownLevel = f.renownLevel }
        end,
        HasMajorFactionRenown = function(id)
            return D.factions[id] and D.factions[id].renownLevel ~= nil
        end,
    }
    _G.C_CurrencyInfo = {
        GetCurrencyInfo = function(id)
            return D.currencies[id]
        end,
    }
    _G.C_QuestLog = {
        IsQuestFlaggedCompleted = function(questID) return D.questsCompleted[questID] == true end,
    }
    _G.GetAchievementInfo = function(achID)
        local a = D.achievements[achID]
        if not a then return achID, "Achievement " .. tostring(achID), 10, false end
        return achID, a.name or ("Achievement " .. achID), 10, a.completed or false
    end

    -- Row / map-pin interactions
    _G.ChatEdit_InsertLink = function() return true end
    _G.ChatFrame_OpenChat = noop
    _G.IsModifiedClick = function() return false end
    _G.MenuUtil = { CreateContextMenu = noop }
    _G.C_AddOns = { IsAddOnLoaded = function() return false end }
    _G.C_SuperTrack = { SetSuperTrackedUserWaypoint = noop }
    _G.UiMapPoint = {
        CreateFromCoordinates = function(uiMapID, x, y)
            return { uiMapID = uiMapID, position = { x = x, y = y } }
        end,
    }

    -- Blizzard ScrollBox surface used by ListView.lua. No-ops: the smoke net
    -- only cares that the calls resolve, not that anything actually scrolls.
    _G.CreateScrollBoxListLinearView = function() return UNIVERSAL end
    _G.CreateDataProvider = function() return UNIVERSAL end
    _G.ScrollUtil = { InitScrollBoxListWithScrollBar = noop }
    _G.ScrollBoxConstants = { RetainScrollPosition = 2, DiscardScrollPosition = 1 }
    _G.CreateSettingsListSectionHeaderInitializer = function(name) return { name = name } end

    _G.C_Timer = {
        After = function(delay, fn)
            timerQueue[#timerQueue + 1] = { delay = delay or 0, fn = fn }
        end,
        NewTimer = function(_, fn)
            timerQueue[#timerQueue + 1] = { delay = 0, fn = fn }
            return { Cancel = noop }
        end,
        NewTicker = function() return { Cancel = noop } end,
    }

    _G.Settings = {
        RegisterVerticalLayoutCategory = function(name)
            return { GetID = function() return 1 end, name = name }, { AddInitializer = noop }
        end,
        -- Write-through so a proxy-table-bound setting (the "Filter by source"
        -- checkboxes) actually flips db.hiddenSources when a test drives it. The
        -- binding is also recorded in Stub.data.settings so a test can toggle it.
        RegisterAddOnSetting = function(_, _, key, tbl, _, _, default)
            if tbl and key ~= nil and tbl[key] == nil then
                tbl[key] = default
            end
            local onChanged
            local setting = {
                SetValueChangedCallback = function(_, fn) onChanged = fn end,
                GetValue = function() return tbl and key ~= nil and tbl[key] end,
                SetValue = function(_, v)
                    if tbl and key ~= nil then tbl[key] = v end
                    if onChanged then onChanged() end
                end,
            }
            if key ~= nil then
                D.settings[key] = {
                    get = function() return tbl and tbl[key] end,
                    set = function(v)
                        if tbl then tbl[key] = v end
                        if onChanged then onChanged() end
                    end,
                }
            end
            return setting
        end,
        CreateCheckbox = noop,
        CreateDropdown = noop,
        RegisterCanvasLayoutSubcategory = function()
            return { GetID = function() return 2 end }, { AddInitializer = noop }
        end,
        CreateControlTextContainer = function()
            return { Add = noop, GetData = function() return {} end }
        end,
        RegisterAddOnCategory = noop,
        OpenToCategory = function(id) D.openedCategory = id end,
    }

    -- LibStub + just enough of the embedded libs that Map / MinimapButton run
    -- their real code paths instead of bailing at the `nil` guard.
    local aceLocaleApps = {}
    local libs = {
        -- Faithful-enough AceLocale-3.0: `= true` resolves to the key; the stub
        -- client is always enUS, so non-default locales get no write proxy;
        -- missing keys fall back to the key string (silent default locale).
        ["AceLocale-3.0"] = {
            NewLocale = function(_, app, locale, isDefault)
                local t = aceLocaleApps[app]
                if not t then
                    t = setmetatable({}, { __index = function(_, k) return k end })
                    aceLocaleApps[app] = t
                end
                if locale ~= "enUS" and not isDefault then return nil end
                return setmetatable({}, {
                    __newindex = function(_, k, v) rawset(t, k, v == true and k or v) end,
                    __index = function(_, k) return t[k] end,
                })
            end,
            GetLocale = function(_, app)
                return aceLocaleApps[app]
                    or setmetatable({}, { __index = function(_, k) return k end })
            end,
        },
        ["HereBeDragons-Pins-2.0"] = {
            RemoveAllWorldMapIcons = function() D.worldPins = 0 end,
            RemoveAllMinimapIcons = function() D.minimapPins = 0 end,
            AddWorldMapIconMap = function() D.worldPins = D.worldPins + 1; return true end,
            AddMinimapIconMap = function() D.minimapPins = D.minimapPins + 1 end,
        },
        ["LibDataBroker-1.1"] = {
            NewDataObject = function(_, _, obj) return obj end,
        },
        ["LibDBIcon-1.0"] = {
            Register = noop,
            IsRegistered = function() return false end,
            Show = noop,
            Hide = noop,
        },
    }
    _G.LibStub = setmetatable({
        GetLibrary = function(_, name) return libs[name] end,
        NewLibrary = function() return nil end,
    }, { __call = function(_, name) return libs[name] end })
    _G.HBD_PINS_WORLDMAP_SHOW_PARENT = 1

    -- Zone / faction
    _G.GetRealZoneText = function() return D.zone end
    _G.GetZoneText = function() return D.zone end
    _G.GetSubZoneText = function() return D.subZone end
    _G.GetMinimapZoneText = function() return D.subZone end
    _G.UnitFactionGroup = function() return D.faction end
    _G.GetLocale = function() return "enUS" end

    -- Map
    _G.C_Map = {
        GetBestMapForUnit = function() return D.mapID end,
        GetMapInfo = function(id) return D.mapInfo[id] end,
        GetPlayerMapPosition = function() return nil end,
        CanSetUserWaypointOnMap = function() return true end,
        SetUserWaypoint = noop,
    }

    return Stub
end

return Stub
