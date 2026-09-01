local _, addon = ...
local L = addon.L

-- The tracker window: a movable/resizable frame that hosts the ListView list,
-- with a one-line collection summary under the title. Geometry persists to
-- addon.db.window; the list itself lives in ListView.lua.

local trackerWindow = nil

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 440, 360
local MIN_WIDTH, MIN_HEIGHT = 320, 220
local TITLE_BAR_HEIGHT = 22
local SUMMARY_HEIGHT = 16

-- ============================================================================
-- Window styles
--
-- The window commits fully to one visual language -- no mixing:
--   "stylized" -- flat dark semi-transparent panel, thin border, a custom title
--     strip, a minimal "x" close button and the slim MinimalScrollBar.
--   "classic"  -- a stock Blizzard frame (BasicFrameTemplateWithInset): its own
--     border, title bar, inset and close button, plus the grooved WowTrimScrollBar.
--
-- The style is read once, when the window is first built. Changing the setting
-- afterwards asks the user to /reload (see addon.NotifyWindowStyleChanged).
-- ============================================================================

local STYLE = {
	stylized = {
		frameTemplate = "BackdropTemplate",
		backdrop = {
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 14,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		},
		bgColor = { 0.06, 0.06, 0.08, 0.88 },
		borderColor = { 0.6, 0.6, 0.65, 1 },
		titleStrip = true,
		contentTop = TITLE_BAR_HEIGHT + 10,
		contentBottom = 22,
		contentSide = 10,
		summaryHeight = SUMMARY_HEIGHT,
		scrollTemplate = "MinimalScrollBar",
		scrollInset = 5,
		scrollGap = 4,
		scrollTrack = { 0, 0, 0, 0.25 },
		gripSize = 16,
		gripAlpha = 0.4,
		gripOffset = 4,
	},
	classic = {
		-- The template supplies the border, title bar, inset and close button;
		-- content anchors to frame.Inset.
		frameTemplate = "BasicFrameTemplateWithInset",
		titleStrip = false,
		contentTop = 28,
		contentBottom = 8,
		contentSide = 10,
		summaryHeight = SUMMARY_HEIGHT,
		scrollTemplate = "WowTrimScrollBar",
		scrollInset = 8,
		scrollGap = 4,
		gripSize = 16,
		gripAlpha = 1,
		gripOffset = 6,
	},
}

local function CurrentStyle()
	return STYLE[addon.db and addon.db.windowStyle] or STYLE.stylized
end

-- ============================================================================
-- Position / size persistence
-- ============================================================================

local function round(value)
	return math.floor(value + 0.5)
end

local function SetWindowTitle(frame, text)
	if frame.title then
		frame.title:SetText(text)
	elseif frame.SetTitle then
		frame:SetTitle(text)
	end
end

local function SaveGeometry()
	if not trackerWindow then
		return
	end

	local point, _, relativePoint, x, y = trackerWindow:GetPoint(1)
	if not point then
		return
	end

	local width, height = trackerWindow:GetSize()
	addon.db.window = {
		point = point,
		relPoint = relativePoint or point,
		x = round(x or 0),
		y = round(y or 0),
		w = round(width or DEFAULT_WIDTH),
		h = round(height or DEFAULT_HEIGHT),
	}
end

-- Always anchor to UIParent so a missing relativeTo frame can never break restore.
local function RestoreGeometry()
	if not trackerWindow then
		return
	end

	local cfg = addon.db and addon.db.window
	trackerWindow:ClearAllPoints()

	if cfg and cfg.point then
		trackerWindow:SetSize(cfg.w or DEFAULT_WIDTH, cfg.h or DEFAULT_HEIGHT)
		trackerWindow:SetPoint(cfg.point, UIParent, cfg.relPoint or cfg.point, cfg.x or 0, cfg.y or 0)
	else
		trackerWindow:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
		trackerWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

-- ============================================================================
-- Window construction
-- ============================================================================

local function MakeMovable(frame)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveGeometry()
	end)
end

local function MakeResizable(frame, style)
	frame:SetResizable(true)
	if type(frame.SetResizeBounds) == "function" then
		frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
	end

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(style.gripSize, style.gripSize)
	grip:SetFrameLevel(frame:GetFrameLevel() + 10)
	grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -style.gripOffset, style.gripOffset)

	-- One texture at the style's resting alpha; brightens while hovered. Stylized
	-- keeps it faint, classic shows the full Blizzard grabber.
	local tex = grip:CreateTexture(nil, "OVERLAY")
	tex:SetAllPoints()
	tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	tex:SetAlpha(style.gripAlpha)

	grip:SetScript("OnEnter", function()
		tex:SetAlpha(1)
	end)
	grip:SetScript("OnLeave", function()
		tex:SetAlpha(style.gripAlpha)
	end)
	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		SaveGeometry()
		addon.RefreshWindow()
	end)
	frame.resizeGrip = grip
end

-- Stylized: a slim title strip with a faint wash, a 1px divider and left-aligned
-- title text. Returns the strip so the close button can anchor inside it.
local function BuildStylizedTitle(frame)
	local titleBar = CreateFrame("Frame", nil, frame)
	titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
	titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	titleBar:SetHeight(TITLE_BAR_HEIGHT)

	local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
	titleBg:SetAllPoints()
	titleBg:SetColorTexture(1, 1, 1, 0.07)

	local divider = frame:CreateTexture(nil, "BORDER")
	divider:SetColorTexture(1, 1, 1, 0.12)
	divider:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
	divider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
	divider:SetHeight(1)

	frame.title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("LEFT", titleBar, "LEFT", 6, 0)
	frame.title:SetPoint("RIGHT", titleBar, "RIGHT", -26, 0)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWordWrap(false)

	return titleBar
end

-- Stylized: a bare "x" texture (no Blizzard button art) that tints red on hover.
local function BuildMinimalClose(frame, anchor)
	local close = CreateFrame("Button", nil, frame)
	close:SetSize(18, 18)
	close:SetPoint("RIGHT", anchor, "RIGHT", -4, 0)

	local tex = close:CreateTexture(nil, "OVERLAY")
	tex:SetAllPoints()
	tex:SetTexture("Interface\\Buttons\\UI-StopButton")
	tex:SetVertexColor(0.8, 0.8, 0.82)

	close:SetScript("OnEnter", function()
		tex:SetVertexColor(1, 0.35, 0.35)
	end)
	close:SetScript("OnLeave", function()
		tex:SetVertexColor(0.8, 0.8, 0.82)
	end)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)
end

local function BuildChrome(frame, style)
	if style.titleStrip then
		-- Stylized: hand-rolled flat panel.
		frame:SetBackdrop(style.backdrop)
		frame:SetBackdropColor(style.bgColor[1], style.bgColor[2], style.bgColor[3], style.bgColor[4])
		frame:SetBackdropBorderColor(style.borderColor[1], style.borderColor[2], style.borderColor[3], style.borderColor[4])
		BuildMinimalClose(frame, BuildStylizedTitle(frame))
		return
	end

	-- Classic: the template already drew the border, title bar and close button.
	-- Point frame.title at whatever FontString it created (fields vary by build);
	-- SetWindowTitle falls back to frame:SetTitle when there is none.
	frame.title = (frame.TitleContainer and frame.TitleContainer.TitleText)
		or frame.TitleText
		or _G[(frame:GetName() or "") .. "TitleText"]
	if frame.CloseButton then
		frame.CloseButton:SetScript("OnClick", function()
			frame:Hide()
		end)
	end
end

local function InitializeWindow()
	if trackerWindow then
		return
	end

	local style = CurrentStyle()
	local listTop = style.contentTop + (style.summaryHeight or 0)

	trackerWindow = CreateFrame("Frame", "MountTrackerWindow", UIParent, style.frameTemplate)
	trackerWindow:SetFrameStrata("HIGH")
	BuildChrome(trackerWindow, style)
	SetWindowTitle(trackerWindow, L["Mount Tracker"])

	MakeMovable(trackerWindow)

	local content = trackerWindow

	-- One-line collection summary, between the title and the list.
	trackerWindow.summary = trackerWindow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	trackerWindow.summary:SetPoint("TOPLEFT", content, "TOPLEFT", style.contentSide, -style.contentTop)
	trackerWindow.summary:SetPoint("TOPRIGHT", content, "TOPRIGHT", -style.contentSide, -style.contentTop)
	trackerWindow.summary:SetHeight(style.summaryHeight or SUMMARY_HEIGHT)
	trackerWindow.summary:SetJustifyH("LEFT")
	trackerWindow.summary:SetWordWrap(false)

	-- Scrollbar inside the right border; the list fills the rest.
	local scrollBar = CreateFrame("EventFrame", nil, trackerWindow, style.scrollTemplate)
	scrollBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -style.scrollInset, -listTop)
	scrollBar:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -style.scrollInset, style.contentBottom)

	if style.scrollTrack then
		local track = scrollBar:CreateTexture(nil, "BACKGROUND")
		track:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", -1, 1)
		track:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 1, -1)
		track:SetColorTexture(style.scrollTrack[1], style.scrollTrack[2], style.scrollTrack[3], style.scrollTrack[4])
	end

	local scrollBox = CreateFrame("Frame", nil, trackerWindow, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", content, "TOPLEFT", style.contentSide, -listTop)
	scrollBox:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMLEFT", -style.scrollGap, 0)

	addon.ListView.Init(scrollBox, scrollBar)

	trackerWindow.message = trackerWindow:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	trackerWindow.message:SetPoint("TOPLEFT", scrollBox, "TOPLEFT", 4, -8)
	trackerWindow.message:SetPoint("TOPRIGHT", scrollBox, "TOPRIGHT", -4, -8)
	trackerWindow.message:SetJustifyH("CENTER")
	trackerWindow.message:SetWordWrap(true)
	trackerWindow.message:Hide()

	-- Grip created last so it sits above the scroll frame and stays clickable.
	MakeResizable(trackerWindow, style)
	RestoreGeometry()

	trackerWindow:Hide()
end

addon.InitializeWindow = InitializeWindow

-- The style is baked in when the window is built. If it is toggled afterwards
-- the existing frame keeps its old look until the UI reloads.
function addon.NotifyWindowStyleChanged()
	if trackerWindow then
		addon.Print(L["Reload your UI (/reload) to apply the new window style."])
	end
end

-- ============================================================================
-- Rendering
-- ============================================================================

local function SummaryText(zoneName)
	local summary = addon.MountModel.Summary()
	local text = L["%s \226\128\148 %d / %d collected"]:format(
		zoneName or L["Unknown"],
		summary.zoneCollected,
		summary.zoneTotal
	)
	if (summary.zoneAvailable or 0) > 0 then
		text = text .. " " .. ("|cff66cc66\194\183 %s|r"):format(L["%d available"]:format(summary.zoneAvailable))
	end
	if summary.accountTotal and summary.accountTotal > 0 then
		text = text .. " " .. ("|cff9d9d9d\194\183 %s|r"):format(
			L["%d / %d account"]:format(summary.accountCollected or 0, summary.accountTotal)
		)
	end
	return text
end

local function RefreshTrackerWindow()
	if not trackerWindow or not trackerWindow:IsShown() then
		return -- nothing to draw; skip the zone scan
	end

	local groups, zoneName = addon.MountModel.GetZoneMounts()
	SetWindowTitle(trackerWindow, L["Mounts: %s"]:format(zoneName or L["Unknown"]))
	trackerWindow.summary:SetText(SummaryText(zoneName))

	local message = addon.MountModel.StatusFor(groups)
	if not message and addon.ListView.Layout(groups) == 0 then
		message = L["Every mount here is already collected."]
	end

	if message then
		addon.ListView.Clear()
		trackerWindow.message:SetText(message)
		trackerWindow.message:Show()
	else
		trackerWindow.message:Hide()
	end
end

addon.RefreshWindow = RefreshTrackerWindow

-- ============================================================================
-- Public actions
-- ============================================================================

-- Whether the tracker window exists and is currently on screen. Read at logout to
-- decide whether to reopen it next login.
function addon.IsWindowShown()
	return trackerWindow ~= nil and trackerWindow:IsShown()
end

local function ToggleTrackerWindow()
	InitializeWindow()

	if trackerWindow:IsShown() then
		trackerWindow:Hide()
		return
	end

	trackerWindow:Show()
	if not addon.IsMountApiReady() then
		addon.ScheduleMountRetry()
	end
	RefreshTrackerWindow()
end

addon.ToggleWindow = ToggleTrackerWindow

local function ResetWindow()
	addon.db.window = nil
	RestoreGeometry()
end

addon.ResetWindow = ResetWindow

local function PrintZoneMountListToChat()
	local groups, zoneName = addon.MountModel.GetZoneMounts()
	addon.Print(L["Mounts for %s:"]:format(zoneName or L["Unknown"]))

	local message = addon.MountModel.StatusFor(groups)
	if message then
		addon.Print(message)
		return
	end

	local printedGlobalDivider = false
	for _, group in ipairs(groups) do
		if group.isGlobal and not printedGlobalDivider then
			printedGlobalDivider = true
			addon.Print(("-- %s --"):format(L["Global"]))
		end
		addon.Print(string.format("%s (%d/%d)", group.label, group.collected, group.total))
		for _, entry in ipairs(group.rows) do
			addon.Print(string.format("  %s - %s", entry.name, entry.detail or entry.state))
		end
	end
end

addon.PrintZoneList = PrintZoneMountListToChat
