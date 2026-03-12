local ADDON_NAME, MT = ...
-- Forward-declare module-state locals that closures in constant tables need
-- to reference before the full state block is reached.
local db ---@type MinimapTweaksDB
local RebuildPassThrough -- defined in the click-actions section below
-- ============================================================
-- Anchor helpers
-- ============================================================
local ANCHOR_POINTS = {
	"TOPLEFT", "TOP", "TOPRIGHT",
	"LEFT", "CENTER", "RIGHT",
	"BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
-- Keyed by integer 1-9; used as AceConfig select values.
local ANCHOR_SELECT = {
	[1] = "Top Left",
	[2] = "Top",
	[3] = "Top Right",
	[4] = "Left",
	[5] = "Center",
	[6] = "Right",
	[7] = "Bottom Left",
	[8] = "Bottom",
	[9] = "Bottom Right",
}
local function AnchorPoint(v)
	-- v is always an integer 1-9 from an AceConfig select widget; no rounding needed.
	return ANCHOR_POINTS[v or 3] or "TOPRIGHT"
end

-- ============================================================
-- Font / justify helpers
-- ============================================================
-- Built-in WoW fonts keyed by display name (these are also the standard LSM keys).
local BUILTIN_FONTS = {
	["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
	["Arial Narrow"] = "Fonts\\ARIALN.TTF",
	["Skurri"] = "Fonts\\SKURRI.TTF",
	["Morpheus"] = "Fonts\\MORPHEUS.TTF",
}
-- Returns a name→name table for AceConfig selects.
-- Called as a function reference so the list is always current when a dropdown opens.
-- Uses LibSharedMedia-3.0 if available; falls back to the four built-ins.
local function GetFontList()
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if LSM then
		local list = {}
		for _, name in ipairs(LSM:List("font")) do
			list[name] = name
		end

		return list
	end

	local list = {}
	for name in pairs(BUILTIN_FONTS) do list[name] = name end

	return list
end
-- Resolve a font display-name to a file path via LSM, then built-ins, then fallback.
local function ResolveFontPath(name)
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if LSM and LSM:IsValid("font", name) then
		return LSM:Fetch("font", name)
	end

	return BUILTIN_FONTS[name] or BUILTIN_FONTS["Friz Quadrata TT"]
end

local OUTLINE_SELECT = {
	["NONE"] = "None",
	["OUTLINE"] = "Outline",
	["THICKOUTLINE"] = "Thick Outline",
	["MONOCHROME"] = "Monochrome",
}
-- Built-in border textures (always available; also serve as LSM fallbacks).
-- "Solid" uses WHITE8X8 — a 1-pixel white square that tiles into a flat block border.
local BUILTIN_BORDERS = {
	["Solid"] = "Interface\\Buttons\\WHITE8X8",
	["Tooltip"] = "Interface\\Tooltips\\UI-Tooltip-Border",
	["Dialog"] = "Interface\\DialogFrame\\UI-DialogBox-Border",
}
-- Returns a name→name table for AceConfig selects.
-- Uses LibSharedMedia-3.0 if available; always includes the built-ins.
local function GetBorderList()
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	local list = {}
	if LSM then
		for _, name in ipairs(LSM:List("border")) do
			list[name] = name
		end
	else
		for name in pairs(BUILTIN_BORDERS) do list[name] = name end
	end

	-- Solid is always present even if LSM doesn't register it.
	list["Solid"] = "Solid"
	return list
end
-- Resolve a border display-name to a texture path via LSM, then built-ins, then fallback.
local function ResolveBorderPath(name)
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if LSM and LSM:IsValid("border", name) then
		return LSM:Fetch("border", name)
	end

	return BUILTIN_BORDERS[name] or BUILTIN_BORDERS["Solid"]
end
local JUSTIFY_SELECT = { [1] = "Left", [2] = "Center", [3] = "Right" }
local JUSTIFY_H = { [1] = "LEFT", [2] = "CENTER", [3] = "RIGHT" }
-- ============================================================
-- Click action tables
-- ============================================================
-- Display names for the AceConfig select widget.
local CLICK_ACTION_VALUES = {
	ping = "Ping",
	worldmap = "World Map",
	tracking = "Tracking Menu",
	zoomin = "Zoom In",
	zoomout = "Zoom Out",
	calendar = "Calendar",
	timer = "Timer / Alarm",
	none = "None",
}
-- Actions valid for any widget that sits above the minimap surface (not the minimap itself).
-- "ping" is excluded because these frames are not the minimap surface and cannot
-- pass a ping through to Blizzard's untainted OnMouseUp handler.
local OVERLAY_CLICK_ACTION_VALUES = {
	worldmap = "World Map",
	tracking = "Tracking Menu",
	zoomin = "Zoom In",
	zoomout = "Zoom Out",
	calendar = "Calendar",
	timer = "Timer / Alarm",
	none = "None",
}
-- Forward-declared; assigned below alongside ApplyClickActions.
local CLICK_ACTION_FUNCS
-- ============================================================
-- Managed Blizzard button definitions
-- ============================================================
-- Each entry describes one Blizzard-owned button near the minimap.
-- shown = true  → reanchor onto Minimap, let Blizzard manage visibility.
-- shown = false → force-hide and keep hidden (hook blocks Blizzard re-shows).
-- No entry here ever calls Show(); that is always Blizzard's responsibility.
local BLIZZ_BUTTON_DEFS = {
	{
		key = "addonCompartment",
		label = "Addon Compartment",
		get = function() return _G["AddonCompartmentFrame"] end,
	},
	{
		key = "calendar",
		label = "Calendar",
		get = function() return _G["GameTimeFrame"] end,
	},
	-- TimeManagerClockButton is NOT a child of MinimapCluster.BorderTop.
	-- Hiding the zone-text header leaves it behind, so we reposition it.
	-- shouldHide blocks it from showing whenever our custom clock is active.
	{
		key = "clock",
		label = "Clock (Blizzard)",
		shouldHide = function() return db and db.profile.clock and db.profile.clock.enabled end,
		get = function() return _G["TimeManagerClockButton"] end,
	},
	{
		key = "mail",
		label = "Mail & Notifications",
		get = function()
			local mc = _G["MinimapCluster"]
			return mc and mc.IndicatorFrame
		end,
	},
	{
		key = "tracking",
		label = "Tracking",
		get = function()
			local mc = _G["MinimapCluster"]
			return mc and mc.Tracking
		end,
	},
	{
		key = "expansionLanding",
		label = "Expansion Button",
		get = function() return _G["ExpansionLandingPageMinimapButton"] end,
	},
	{
		key = "battlefield",
		label = "Battlefield",
		get = function() return _G["MiniMapBattlefieldFrame"] end,
	},
	{
		key = "instanceDifficulty",
		label = "Instance Difficulty",
		get = function()
			local mc = _G["MinimapCluster"]
			return _G["MiniMapInstanceDifficulty"]
					or (mc and mc.InstanceDifficulty)
		end,
	},
	{
		key = "challengeMode",
		label = "Challenge Mode",
		get = function() return _G["MiniMapChallengeMode"] end,
	},
	{
		key = "voiceChat",
		label = "Voice Chat",
		get = function() return _G["MiniMapVoiceChatFrame"] end,
	},
	{
		key = "zoomIn",
		label = "Zoom In",
		get = function() return Minimap and Minimap["ZoomIn"] end,
	},
	{
		key = "zoomOut",
		label = "Zoom Out",
		get = function() return Minimap and Minimap["ZoomOut"] end,
	},
}
-- ============================================================
-- AceDB defaults
-- ============================================================
local DB_DEFAULTS = {
	profile = {
		-- Minimap
		size = 210,
		scale = 1,
		buttonOffset = 0,
		-- MinimapContainer anchor offset
		mapOffsetX = 0,
		mapOffsetY = -4,
		-- Zoom auto-reset
		zoomResetEnabled = true,
		zoomResetDelay = 5,
		zoomResetLevel = 0,
		-- Border
		border = {
			enabled = true,
			size = 2,
			r = 0.251,
			g = 0.251,
			b = 0.251,
			a = 1.0,
			texture = "Solid",
			offset = 1,
		},
		-- Per-button settings.  anchor: 1-9 index into ANCHOR_POINTS.
		-- shown = true  → reanchor, let Blizzard manage visibility.
		-- shown = false → force-hide and block Blizzard re-shows.
		blizzButtons = {
			addonCompartment = { shown = true, anchor = 3, x = -6, y = -20 },
			calendar = { shown = true, anchor = 3, x = -2, y = -2 },
			clock = { shown = false, anchor = 9, x = 0, y = 0 },
			mail = { shown = true, anchor = 3, x = -25, y = -2 },
			tracking = { shown = true, anchor = 1, x = 2, y = -2 },
			expansionLanding = { shown = true, anchor = 7, x = -29, y = -23 },
			battlefield = { shown = true, anchor = 8, x = -60, y = -2 },
			instanceDifficulty = { shown = true, anchor = 1, x = 23, y = -2 },
			challengeMode = { shown = true, anchor = 1, x = 35, y = -2 },
			voiceChat = { shown = true, anchor = 8, x = 50, y = 0 },
			zoomIn = { shown = true, anchor = 9, x = -5, y = 26 },
			zoomOut = { shown = true, anchor = 9, x = -16, y = 15 },
		},
		-- Zone text label
		zoneText = {
			enabled = true,
			anchor = 2,
			x = 0,
			y = 4,
			font = "Friz Quadrata TT",
			fontSize = 12,
			justify = 2,
			outline = "OUTLINE",
		},
		-- Custom clock widget
		clock = {
			enabled = true,
			anchor = 9,
			x = -2,
			y = 2,
			font = "Friz Quadrata TT",
			fontSize = 11,
			justify = 3,
			width = 50,
			height = 10,
			outline = "OUTLINE",
		},
		-- Addon compartment count text font
		compartment = {
			font = "Friz Quadrata TT",
			fontSize = 12,
			outline = "NONE",
		},
		-- Per-mouse-button actions on the minimap
		clicks = {
			left = "ping",
			middle = "worldmap",
			right = "tracking",
		},
		-- Per-mouse-button actions on the custom clock widget
		clockClicks = {
			left = "calendar",
			middle = "none",
			right = "timer",
		},
		-- Coordinates display
		coords = {
			enabled = true,
			anchor = 8,
			x = 0,
			y = 2,
			font = "Friz Quadrata TT",
			fontSize = 11,
			justify = 2,
			width = 120,
			height = 10,
			decimals = 1,
			outline = "OUTLINE",
		},
		-- Per-mouse-button actions on the coordinates widget
		coordsClicks = {
			left = "none",
			middle = "none",
			right = "none",
		},
	},
}
-- ============================================================
-- Module state
-- ============================================================
---@class MinimapTweaksProfile
---@field size              number
---@field scale             number
---@field buttonOffset      number
---@field mapOffsetX        number
---@field mapOffsetY        number
---@field zoomResetEnabled  boolean
---@field zoomResetDelay    number
---@field zoomResetLevel    number
---@field border            {enabled: boolean, size: number, r: number, g: number, b: number, a: number, texture: string, offset: number}
---@field blizzButtons      table<string, {shown: boolean, anchor: number, x: number, y: number}>
---@field zoneText          {enabled: boolean, anchor: number, x: number, y: number, font: string, fontSize: number, justify: number, outline: string}
---@field clock             {enabled: boolean, anchor: number, x: number, y: number, font: string, fontSize: number, justify: number, width: number, height: number, outline: string}
---@field compartment       {font: string, fontSize: number, outline: string}
---@field clicks            {left: string, middle: string, right: string}
---@field clockClicks       {left: string, middle: string, right: string}
---@field coords            {enabled: boolean, anchor: number, x: number, y: number, font: string, fontSize: number, justify: number, width: number, height: number, decimals: number, outline: string}
---@field coordsClicks      {left: string, middle: string, right: string}
---@class MinimapTweaksDB : AceDBObject-3.0
---@field profile      MinimapTweaksProfile
---@field ResetProfile fun(self: MinimapTweaksDB)
-- db is forward-declared at the top of the file; the assignment below
-- just re-applies the annotation so the linter tracks the type here too.
db = db ---@type MinimapTweaksDB
---@type table|Frame|nil
local borderFrame = nil         -- BackdropTemplate frame for the square border
---@type table|Frame|nil
local zoneTextFrame = nil       -- Our zone text FontString container
---@type table|Frame|nil
local clockFrame = nil          -- Our custom clock widget
local clockTicker = nil         -- C_Timer ticker for the clock
---@type table|Frame|nil
local coordsFrame = nil         -- Our coordinates widget
local coordsTicker = nil        -- C_Timer ticker for coordinates
local _applyingSettings = false -- suppresses zoom-reset hook during apply
-- Capture SetPoint from a fresh, unnamed frame whose method table carries no
-- addon hooks.  We deliberately do NOT grab this from MinimapContainer, because
-- Blizzard's ResizeLayoutFrame mixin hooks that specific frame's SetPoint before
-- our addon loads — meaning mco.SetPoint would already be wrapped and would undo
-- our anchor on every cluster resize.  A new frame's SetPoint is always the raw
-- C-level method; the hook lives on mco's table, not on the shared metatable.
local _rawSetPoint = CreateFrame("Frame").SetPoint
-- ============================================================
-- Zone text label
-- ============================================================
-- UpdateZoneText copies text and color from Blizzard's hidden MinimapZoneText
-- so we benefit from its PvP coloring logic without duplicating it.
local function UpdateZoneText()
	if not zoneTextFrame or not db or not db.profile.zoneText.enabled then return end

	if not zoneTextFrame:IsShown() then return end

	zoneTextFrame.label:SetText(GetMinimapZoneText())
	-- MinimapZoneText is hidden but its color is still updated by Minimap_Update().
	local r, g, b = MinimapZoneText:GetTextColor()
	zoneTextFrame.label:SetTextColor(r, g, b)
end

local function ApplyZoneText()
	local p = db.profile
	if not zoneTextFrame then
		zoneTextFrame = CreateFrame("Frame", "MinimapTweaksZoneText", Minimap)
		zoneTextFrame:SetFrameStrata("MEDIUM")
		zoneTextFrame:SetFrameLevel(10)
		local fs = zoneTextFrame:CreateFontString(nil, "OVERLAY")
		fs:SetAllPoints()
		zoneTextFrame.label = fs
	end

	if not p.zoneText.enabled then
		zoneTextFrame:Hide()
		return
	end

	-- Width tracks the live minimap size; height accommodates the font.
	zoneTextFrame:SetSize(p.size, math.max(20, p.zoneText.fontSize + 6))
	local pt = AnchorPoint(p.zoneText.anchor)
	zoneTextFrame:ClearAllPoints()
	zoneTextFrame:SetPoint(pt, Minimap, pt, p.zoneText.x, p.zoneText.y)
	local fontPath = ResolveFontPath(p.zoneText.font)
	local outline = p.zoneText.outline or "OUTLINE"
	if outline == "NONE" then outline = "" end

	zoneTextFrame.label:SetFont(fontPath, p.zoneText.fontSize, outline)
	zoneTextFrame.label:SetJustifyH(JUSTIFY_H[p.zoneText.justify] or "CENTER")
	zoneTextFrame:Show()
	zoneTextFrame.label:SetText("") -- force layout reset before UpdateZoneText refills it
	UpdateZoneText()
end

-- ============================================================
-- Custom clock widget
-- ============================================================
local function UpdateClock()
	if not clockFrame or not clockFrame:IsShown() then return end

	-- GameTime_GetTime respects the player's 12/24h and local/realm prefs.
	clockFrame.label:SetText(GameTime_GetTime(true))
end

local function ApplyClockWidget()
	local p = db.profile
	if not clockFrame then
		clockFrame = CreateFrame("Button", "MinimapTweaksClock", Minimap)
		clockFrame:SetFrameStrata("MEDIUM")
		clockFrame:SetFrameLevel(10)
		clockFrame:RegisterForClicks("AnyUp")
		local fs = clockFrame:CreateFontString(nil, "OVERLAY")
		fs:SetAllPoints()
		clockFrame.label = fs
		clockFrame:SetScript("OnClick", function(_, button)
			local action
			if button == "LeftButton" then
				action = db.profile.clockClicks.left
			elseif button == "RightButton" then
				action = db.profile.clockClicks.right
			elseif button == "MiddleButton" then
				action = db.profile.clockClicks.middle
			end

			-- "ping" is a no-op on the clock since it is not the minimap surface.
			local fn = CLICK_ACTION_FUNCS[action or "none"]
			if fn then fn() end
		end)
		MT.clockFrame = clockFrame
	end

	if not p.clock.enabled then
		clockFrame:Hide()
		if clockTicker then
			clockTicker:Cancel(); clockTicker = nil
		end

		-- Allow the Blizzard clock to reappear if it is not explicitly hidden.
		local blizzClock = _G["TimeManagerClockButton"]
		local bs = db.profile.blizzButtons.clock
		if blizzClock and bs and bs.shown then
			blizzClock:Show()
		end

		return
	end

	-- Custom clock is active — hide the Blizzard one.
	-- Future Show() calls are also blocked by the shouldHide hook.
	local blizzClock = _G["TimeManagerClockButton"]
	if blizzClock then blizzClock:Hide() end

	clockFrame:SetSize(p.clock.width, p.clock.height)
	local pt = AnchorPoint(p.clock.anchor)
	clockFrame:ClearAllPoints()
	clockFrame:SetPoint(pt, Minimap, pt, p.clock.x, p.clock.y)
	local fontPath = ResolveFontPath(p.clock.font)
	local outline = p.clock.outline or "OUTLINE"
	if outline == "NONE" then outline = "" end

	clockFrame.label:SetFont(fontPath, p.clock.fontSize, outline)
	clockFrame.label:SetJustifyH(JUSTIFY_H[p.clock.justify] or "CENTER")
	clockFrame:Show()
	clockFrame.label:SetText("") -- force layout reset before UpdateClock refills it
	UpdateClock()
	RebuildPassThrough(clockFrame, p.clockClicks)
	-- Guard: only create the ticker if one isn't already running.  ApplyClockWidget
	-- is called on every settings change, so we avoid cancelling and recreating a
	-- perfectly healthy ticker on every minor tweak (font size, anchor, etc.).
	if not clockTicker then
		clockTicker = C_Timer.NewTicker(1, UpdateClock)
	end
end

-- ============================================================
-- Coordinates widget
-- ============================================================
local function UpdateCoords()
	if not coordsFrame or not coordsFrame:IsShown() then return end

	local decimals = db.profile.coords.decimals
	local fmt = "%." .. decimals .. "f, %." .. decimals .. "f"
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if pos then
		coordsFrame.label:SetText(fmt:format(pos.x * 100, pos.y * 100))
	else
		-- Unmappable area (some phased zones, loading screens, etc.)
		coordsFrame.label:SetText("---, ---")
	end
end

local function ApplyCoords()
	local p = db.profile
	if not coordsFrame then
		coordsFrame = CreateFrame("Button", "MinimapTweaksCoords", Minimap)
		coordsFrame:SetFrameStrata("MEDIUM")
		coordsFrame:SetFrameLevel(10)
		coordsFrame:RegisterForClicks("AnyUp")
		local fs = coordsFrame:CreateFontString(nil, "OVERLAY")
		fs:SetAllPoints()
		coordsFrame.label = fs
		coordsFrame:SetScript("OnClick", function(_, button)
			local action
			if button == "LeftButton" then
				action = db.profile.coordsClicks.left
			elseif button == "RightButton" then
				action = db.profile.coordsClicks.right
			elseif button == "MiddleButton" then
				action = db.profile.coordsClicks.middle
			end

			local fn = CLICK_ACTION_FUNCS[action or "none"]
			if fn then fn() end
		end)
		MT.coordsFrame = coordsFrame
	end

	-- Unconditionally cancel and recreate the ticker on every apply so that
	-- any setting change (anchor, font, size) takes effect on the next tick
	-- without waiting for the old ticker to fire.  Unlike the clock ticker,
	-- there is no guard here because ApplyCoords is only called from explicit
	-- settings callbacks, never from a high-frequency path.
	if coordsTicker then
		coordsTicker:Cancel(); coordsTicker = nil
	end

	if not p.coords.enabled then
		coordsFrame:Hide()
		return
	end

	coordsFrame:SetSize(p.coords.width, p.coords.height)
	local pt = AnchorPoint(p.coords.anchor)
	coordsFrame:ClearAllPoints()
	coordsFrame:SetPoint(pt, Minimap, pt, p.coords.x, p.coords.y)
	local fontPath = ResolveFontPath(p.coords.font)
	local outline = p.coords.outline or "OUTLINE"
	if outline == "NONE" then outline = "" end

	coordsFrame.label:SetFont(fontPath, p.coords.fontSize, outline)
	coordsFrame.label:SetJustifyH(JUSTIFY_H[p.coords.justify] or "CENTER")
	coordsFrame:Show()
	coordsFrame.label:SetText("") -- force layout reset before UpdateCoords refills it
	UpdateCoords()
	RebuildPassThrough(coordsFrame, p.coordsClicks)
	coordsTicker = C_Timer.NewTicker(0.1, UpdateCoords)
end

-- ============================================================
-- Addon compartment count text font
-- ============================================================
local function ApplyCompartmentFont()
	local text = _G["AddonCompartmentFrame"] and _G["AddonCompartmentFrame"].Text
	if not text then return end

	local p = db.profile
	local fontPath = ResolveFontPath(p.compartment.font)
	local outline = p.compartment.outline or "NONE"
	if outline == "NONE" then outline = "" end

	text:SetFont(fontPath, p.compartment.fontSize, outline)
end

-- ============================================================
-- Minimap click actions  (invisible overlay + SetPassThroughButtons)
-- ============================================================
-- "ping" means: pass this button through to Minimap so Blizzard's untainted
-- OnMouseUp handler can call PingLocation freely.
CLICK_ACTION_FUNCS = {
	ping = nil, -- handled via pass-through on the overlay, no local function needed
	worldmap = function() ToggleWorldMap() end,
	tracking = function()
		local btn = MinimapCluster
				and MinimapCluster.Tracking
				and MinimapCluster.Tracking.Button
		if btn then
			-- Ensure the menu description is populated (no-op if already done).
			btn:GenerateMenu()
			local desc = btn:GetMenuDescription()
			if desc then
				local anchor = AnchorUtil.CreateAnchor("TOPRIGHT", Minimap, "TOPRIGHT", 0, 0)
				Menu.GetManager():OpenMenu(Minimap, desc, anchor)
			end
		end
	end,
	zoomin = function() Minimap_ZoomIn() end,
	zoomout = function() Minimap_ZoomOut() end,
	calendar = function() GameTimeFrame_OnClick(GameTimeFrame) end,
	timer = function()
		if not _G["TimeManagerClockButton"] then
			UIParentLoadAddOn("Blizzard_TimeManager")
		end

		if _G["TimeManagerClockButton"] then
			TimeManagerClockButton:Click()
		end
	end,
	none = function() end,
}
local clickOverlay = nil
-- Rebuild the SetPassThroughButtons list for any Button that sits above Minimap.
-- Any mouse button whose action is "none" is passed through so Minimap can ping.
RebuildPassThrough = function(frame, clicks)
	if not frame then return end

	local passthrough = {}
	if (clicks.left or "none") == "none" then passthrough[#passthrough + 1] = "LeftButton" end

	if (clicks.right or "none") == "none" then passthrough[#passthrough + 1] = "RightButton" end

	if (clicks.middle or "none") == "none" then passthrough[#passthrough + 1] = "MiddleButton" end

	frame:SetPassThroughButtons(unpack(passthrough))
end
local function ApplyClickActions()
	-- Create the overlay once, parented to Minimap so it auto-scales with it.
	if not clickOverlay then
		clickOverlay = CreateFrame("Frame", "MinimapTweaksClickOverlay", Minimap)
		clickOverlay:SetAllPoints(Minimap)
		clickOverlay:EnableMouse(true)
		clickOverlay:SetPropagateMouseMotion(true)
		clickOverlay:SetFrameStrata("MEDIUM")
		clickOverlay:SetFrameLevel(Minimap:GetFrameLevel() + 5)
		clickOverlay:SetScript("OnMouseUp", function(_, button)
			local action
			if button == "LeftButton" then
				action = db.profile.clicks.left
			elseif button == "RightButton" then
				action = db.profile.clicks.right
			elseif button == "MiddleButton" then
				action = db.profile.clicks.middle
			end

			-- "ping" and nil fall through; overlay already passes those buttons
			-- through to Minimap so Blizzard handles them untainted.
			local fn = CLICK_ACTION_FUNCS[action or "none"]
			if fn then fn() end
		end)
	end

	-- Build the pass-through list: any button whose action is "ping" (or unset)
	-- should reach Minimap underneath.
	local c = db.profile.clicks
	local passthrough = {}
	if c.left == "ping" then passthrough[#passthrough + 1] = "LeftButton" end

	if c.right == "ping" then passthrough[#passthrough + 1] = "RightButton" end

	if c.middle == "ping" then passthrough[#passthrough + 1] = "MiddleButton" end

	-- SetPassThroughButtons takes a variadic list of button name strings.
	clickOverlay:SetPassThroughButtons(unpack(passthrough))
end

-- ============================================================
-- Square border  (Minimap child — scales with Minimap)
-- ============================================================
local function ApplyBorder()
	local p = db.profile
	if not borderFrame then
		borderFrame = CreateFrame("Frame", "MinimapTweaksBorder", Minimap, "BackdropTemplate")
		borderFrame:SetFrameStrata("BACKGROUND")
		borderFrame:SetFrameLevel(1)
	end

	-- borderOffset controls how far the frame extends beyond the minimap edge on each side.
	-- borderSize is the edgeSize: how large each texture tile is rendered.
	-- At offset=0 the border tiles straddle the minimap edge (half inside, half outside),
	-- keeping the border visually flush rather than floating away from the map.
	local b = p.border
	local offset = b.offset or 0
	borderFrame:SetSize(p.size + offset * 2, p.size + offset * 2)
	borderFrame:ClearAllPoints()
	borderFrame:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
	if b.enabled and b.size > 0 then
		borderFrame:SetBackdrop({
			edgeFile = ResolveBorderPath(b.texture or "Solid"),
			edgeSize = b.size,
		})
		borderFrame:SetBackdropBorderColor(b.r, b.g, b.b, b.a)
		borderFrame:Show()
	else
		borderFrame:SetBackdrop(nil)
		borderFrame:Hide()
	end
end

-- ============================================================
-- Zoom auto-reset
-- ============================================================
local zoomResetTimer = nil
local function CancelZoomReset()
	if zoomResetTimer then
		zoomResetTimer:Cancel(); zoomResetTimer = nil
	end
end

local function ScheduleZoomReset()
	local p = db.profile
	if not p.zoomResetEnabled then return end

	CancelZoomReset()
	zoomResetTimer = C_Timer.NewTimer(p.zoomResetDelay, function()
		zoomResetTimer = nil
		if Minimap:GetZoom() ~= db.profile.zoomResetLevel then
			_applyingSettings = true
			Minimap:SetZoom(db.profile.zoomResetLevel)
			_applyingSettings = false
		end
	end)
end

local function HookZoomReset()
	hooksecurefunc(Minimap, "SetZoom", function(_, level)
		if _applyingSettings then return end

		local p = db.profile
		if not p.zoomResetEnabled then return end

		if level ~= p.zoomResetLevel then
			ScheduleZoomReset()
		else
			CancelZoomReset()
		end
	end)
end

-- ============================================================
-- Addon button positioning  (LibDBIcon via GetMinimapShape)
-- ============================================================
local function SyncButtonRadius()
	local LibDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
	if not LibDBIcon then return end

	-- SetButtonRadius expects the gap beyond the minimap edge, not the total
	-- distance from centre.  LibDBIcon reads the live frame width itself and
	-- adds it internally when positioning each button.
	LibDBIcon:SetButtonRadius(db.profile.buttonOffset)
	-- LibDBIcon has no public "refresh all buttons" API; the only way to trigger
	-- a repositioning pass for every registered button is to iterate the internal
	-- `objects` table.  This is a known compromise against a private field — if
	-- the library reorganises its internals this loop will silently stop working,
	-- but it will not error or break anything else.
	if LibDBIcon.objects then
		for name, button in pairs(LibDBIcon.objects) do
			LibDBIcon:Refresh(name, button.db)
		end
	end
end

-- ============================================================
-- Blizzard button repositioning
-- ============================================================
local function HideBlizzHeader()
	local mc = _G["MinimapCluster"]
	if mc then
		if mc.BorderTop then mc.BorderTop:Hide() end

		if mc.ZoneTextButton then mc.ZoneTextButton:Hide() end

		-- Blizzard anchors MinimapContainer at x=10, y=-30 to visually centre
		-- the circular map under the BorderTop header.  With the header hidden
		-- that offset misaligns the map.  Use the user-configurable offsets.
		local mco = mc.MinimapContainer
		if mco then
			local p = db.profile
			mco:ClearAllPoints()
			_rawSetPoint(mco, "TOP", mc, "TOP", p.mapOffsetX, p.mapOffsetY)
		end
	end
end

local function RepositionBlizzButtons()
	local bb = db.profile.blizzButtons
	if not bb then return end

	for _, def in ipairs(BLIZZ_BUTTON_DEFS) do
		local frame = def.get()
		local bs = bb[def.key]
		if frame and bs then
			if bs.shown then
				-- Reanchor onto Minimap. Visibility is entirely Blizzard's
				-- responsibility; we never call Show() from here.
				local pt = AnchorPoint(bs.anchor)
				frame:ClearAllPoints()
				frame:SetPoint(pt, Minimap, pt, bs.x or 0, bs.y or 0)
				-- Blizzard buttons default to MinimapCluster's "LOW" strata.
				-- After reanchoring onto Minimap they fall behind the map render
				-- surface.  MEDIUM matches LibDBIcon buttons and stays above it.
				frame:SetFrameStrata("MEDIUM")
			else
				-- User explicitly disabled this button — hide it and the Show
				-- hook installed in HookBlizzButtonReanchors will keep it hidden.
				frame:Hide()
			end
		end
	end
end

local function HookBlizzButtonReanchors()
	-- For every managed button: if Blizzard tries to Show() it while the user
	-- has it disabled (shown = false) or a shouldHide condition is true, hide it
	-- immediately.  Otherwise let the Show() through and reanchor.
	for _, def in ipairs(BLIZZ_BUTTON_DEFS) do
		local frame = def.get()
		if frame then
			hooksecurefunc(frame, "Show", function(self)
				local bs = db and db.profile.blizzButtons[def.key]
				if not bs then return end

				if not bs.shown or (def.shouldHide and def.shouldHide()) then
					self:Hide()
				else
					-- Blizzard just showed it; make sure it is in our position.
					C_Timer.After(0, RepositionBlizzButtons)
				end
			end)
		end
	end

	-- Edit Mode calls SetHeaderUnderneath when toggling header position, and
	-- also on save/cancel/restore.  It calls ResetFramePoints internally which
	-- restores MinimapContainer's default anchor (x=10, y=-30), undoing ours.
	-- Hook the actual frame instance, not the mixin table.
	local mc = _G["MinimapCluster"]
	if mc and mc.SetHeaderUnderneath then
		hooksecurefunc(mc, "SetHeaderUnderneath", function()
			C_Timer.After(0, HideBlizzHeader)
			C_Timer.After(0, RepositionBlizzButtons)
		end)
	end
end

-- ============================================================
-- Hide circular Blizzard art
-- ============================================================
local function HideCircularArt()
	for _, name in ipairs({ "MinimapBorder", "MinimapBorderTop" }) do
		local f = _G[name]; if f then f:Hide() end
	end

	-- MinimapBackdrop is a Frame whose children include ExpansionLandingPageMinimapButton.
	-- Hiding the frame would suppress that button even after reanchoring, because
	-- SetPoint does not reparent.  Hide only the decorative textures inside it instead.
	local backdrop = _G["MinimapBackdrop"]
	if backdrop then
		-- StaticOverlayTexture (housing indoor overlay) and MinimapCompassTexture
		-- (the circular frame art) are the only visual elements we want gone.
		if backdrop.StaticOverlayTexture then backdrop.StaticOverlayTexture:Hide() end

		local compass = _G["MinimapCompassTexture"]
		if compass then compass:Hide() end
	end

	-- Also hide any named child of MinimapCluster whose name contains "Border" —
	-- catches cluster-level art the explicit list above may miss.
	-- Deliberately skip anything containing "Backdrop" to avoid the parent-hide problem.
	local cluster = _G["MinimapCluster"]
	if cluster and cluster.GetChildren then
		for _, child in ipairs({ cluster:GetChildren() }) do
			local n = child:GetName() or ""
			if n:find("Border", 1, true) then
				child:Hide()
			end
		end
	end

	Minimap:SetQuestBlobRingAlpha(0)
	Minimap:SetTaskBlobRingAlpha(0)
	Minimap:SetArchBlobRingAlpha(0)
end

-- ============================================================
-- Core apply
-- ============================================================
local function ApplySettings()
	local p = db.profile
	_applyingSettings = true
	Minimap:SetMaskTexture("Interface\\Buttons\\WHITE8X8")
	HideCircularArt()
	HideBlizzHeader()
	Minimap:SetSize(p.size, p.size)
	-- Nudge zoom by one step and back to force the engine to recalculate the
	-- render layer for the new frame dimensions, then land on the configured
	-- reset level (or 0 if auto-reset is disabled).
	local targetZoom = p.zoomResetEnabled and p.zoomResetLevel or 0
	local nudge = targetZoom < 5 and targetZoom + 1 or targetZoom - 1
	Minimap:SetZoom(nudge)
	Minimap:SetZoom(targetZoom)
	Minimap:SetScale(p.scale)
	_applyingSettings = false
	ApplyBorder()
	ApplyZoneText()
	ApplyClockWidget()
	ApplyCoords()
	ApplyCompartmentFont()
	ApplyClickActions()
	C_Timer.After(0.2, SyncButtonRadius)
	C_Timer.After(0.2, RepositionBlizzButtons)
end

local function OpenSettings()
	local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
	local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
	if AceConfigDialog then
		AceConfigDialog:Open(ADDON_NAME)
	end

	if AceConfigRegistry then
		AceConfigRegistry:NotifyChange(ADDON_NAME)
	end
end

-- ============================================================
-- Shared namespace  (MT — read by MinimapTweaksOptions.lua)
-- ============================================================
-- Constants used by the options UI.
MT.ANCHOR_POINTS = ANCHOR_POINTS
MT.ANCHOR_SELECT = ANCHOR_SELECT
MT.GetFontList = GetFontList
MT.GetBorderList = GetBorderList
MT.OUTLINE_SELECT = OUTLINE_SELECT
MT.JUSTIFY_SELECT = JUSTIFY_SELECT
MT.CLICK_ACTION_VALUES = CLICK_ACTION_VALUES
MT.OVERLAY_CLICK_ACTION_VALUES = OVERLAY_CLICK_ACTION_VALUES
MT.BLIZZ_BUTTON_DEFS = BLIZZ_BUTTON_DEFS
-- Apply functions called by options set callbacks.
MT.ApplySettings = ApplySettings
MT.ApplyBorder = ApplyBorder
MT.ApplyZoneText = ApplyZoneText
MT.ApplyClockWidget = ApplyClockWidget
MT.ApplyCoords = ApplyCoords
MT.ApplyCompartmentFont = ApplyCompartmentFont
MT.ApplyClickActions = ApplyClickActions
MT.RepositionBlizzButtons = RepositionBlizzButtons
MT.SyncButtonRadius = SyncButtonRadius
MT.HideBlizzHeader = HideBlizzHeader
MT.RebuildPassThrough = RebuildPassThrough
MT.UpdateCoords = UpdateCoords
MT.OpenSettings = OpenSettings
-- MT.clockFrame / MT.coordsFrame are set by ApplyClockWidget / ApplyCoords
-- when those frames are first created (on PLAYER_LOGIN).
-- MT.db is set in the ADDON_LOADED handler once AceDB creates it.
-- MT.SetupSettings is set by MinimapTweaksOptions.lua.
-- ============================================================
-- Addon Compartment entry point
-- ============================================================
function MinimapTweaks_OnAddonCompartmentClick(_, buttonName)
	if buttonName == "LeftButton" then
		OpenSettings()
	end
end

function MinimapTweaks_OnAddonCompartmentEnter(_, menuButtonFrame)
	MenuUtil.ShowTooltip(menuButtonFrame, function(tooltip)
		tooltip:SetText("Minimap|cff00ff00Tweaks|r", 1, 1, 1)
		tooltip:AddLine("Left click: Open settings", 1, 1, 1, false)
	end)
end

function MinimapTweaks_OnAddonCompartmentLeave(_, menuButtonFrame)
	MenuUtil.HideTooltip(menuButtonFrame)
end

-- ============================================================
-- Slash command  /mmt
-- ============================================================
SLASH_MINIMAPTWEAKS1 = "/mmt"
SlashCmdList["MINIMAPTWEAKS"] = function(msg)
	msg = msg and msg:lower():match("^%s*(.-)%s*$") or ""
	if msg == "reload" then
		ApplySettings()
		print("|cff88aaff[MinimapTweaks]|r Settings re-applied.")
	elseif msg == "reset" then
		db:ResetProfile()
		ApplySettings()
		print("|cff88aaff[MinimapTweaks]|r Profile reset to defaults.")
	else
		OpenSettings()
	end
end
-- ============================================================
-- Initialisation
-- ============================================================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		-- Set here rather than at file-parse time so that all addons have had a
		-- chance to load first.  Any addon that loaded after us and also sets
		-- GetMinimapShape would still win, but that is the correct behaviour —
		-- last writer at ADDON_LOADED time is a fair contest; parse-time is not.
		GetMinimapShape = function() return "SQUARE" end
		db = LibStub("AceDB-3.0"):New("MinimapTweaksDB", DB_DEFAULTS, true) --[[@as MinimapTweaksDB]]
		MT.db = db -- share with options file
		MT.SetupSettings()
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		ApplySettings()
		HookZoomReset()
		HookBlizzButtonReanchors()
		-- Minimap_Update is called by MinimapCluster on every zone-change event
		-- and sets MinimapZoneText's color.  We hook it to keep our label in sync.
		hooksecurefunc("Minimap_Update", UpdateZoneText)
		self:UnregisterEvent("PLAYER_LOGIN")
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(0.5, SyncButtonRadius)
		C_Timer.After(0.5, RepositionBlizzButtons)
		-- Map ID can change on zone transitions; update coords immediately.
		C_Timer.After(0.5, UpdateCoords)
	end
end)
