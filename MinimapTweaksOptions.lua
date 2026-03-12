local ADDON_NAME, MT = ...
-- ============================================================
-- AceConfig options table
-- ============================================================
local function BuildOptionsTable()
	local function get(key)
		return function() return MT.db.profile[key] end
	end
	local function set(key, applyFn)
		return function(_, v)
			MT.db.profile[key] = v; (applyFn or MT.ApplySettings)()
		end
	end
	-- Helpers for one level of nesting into a profile sub-table (e.g. border).
	local function getb(tbl, key)
		return function() return MT.db.profile[tbl][key] end
	end
	local function setb(tbl, key, applyFn)
		return function(_, v)
			MT.db.profile[tbl][key] = v; (applyFn or MT.ApplySettings)()
		end
	end

	-- ── Preview ghost frames ──────────────────────────────────────────────────
	-- key → Frame; lives only for the current UI session.
	local previewFrames = {}
	-- Repositions an existing preview frame to match current profile values,
	-- or does nothing if no preview is active for that key.
	local function refreshPreview(key, anchor, x, y)
		local f = previewFrames[key]
		if not f then return end

		local pt = MT.ANCHOR_POINTS[anchor] or "TOPRIGHT"
		f:ClearAllPoints()
		f:SetPoint(pt, Minimap, pt, x, y)
	end

	-- Returns an AceConfig toggle widget that spawns/destroys a coloured ghost
	-- square on the minimap at the widget's currently configured position.
	-- getPos: function() → anchor (1-9), x, y
	local function makePreviewToggle(key, getPos)
		return {
			type = "toggle",
			name = "Preview Position",
			desc = "Show a coloured marker on the minimap at this widget's current position",
			order = 1.5,
			width = 1,
			get = function() return previewFrames[key] ~= nil end,
			set = function(_, v)
				if v then
					local anchor, x, y = getPos()
					local pt = MT.ANCHOR_POINTS[anchor] or "TOPRIGHT"
					local f = CreateFrame("Frame", nil, Minimap)
					f:SetSize(24, 24)
					f:SetPoint(pt, Minimap, pt, x, y)
					f:SetFrameStrata("TOOLTIP")
					f:SetFrameLevel(100)
					-- Random tint so multiple open previews are distinguishable.
					local tex = f:CreateTexture(nil, "OVERLAY")
					tex:SetAllPoints()
					tex:SetColorTexture(math.random(), math.random(), math.random(), 0.8)
					-- Label above the square.
					local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
					lbl:SetPoint("BOTTOM", f, "TOP", 0, 2)
					lbl:SetText(key)
					previewFrames[key] = f
				else
					if previewFrames[key] then
						previewFrames[key]:Hide()
						previewFrames[key] = nil
					end
				end
			end,
		}
	end

	-- ── Widget entries: { name, key, args } ──────────────────────────────────
	-- Collected here so we can sort alphabetically before assigning order values.
	local widgetEntries = {}
	-- ── Blizzard buttons (all except addonCompartment, handled separately) ───
	for _, def in ipairs(MT.BLIZZ_BUTTON_DEFS) do
		local bkey = def.key
		if bkey ~= "addonCompartment" then
			widgetEntries[#widgetEntries + 1] = {
				name = def.label,
				key = bkey,
				args = {
					preview = makePreviewToggle(bkey, function()
						local bs = MT.db.profile.blizzButtons[bkey]
						return bs.anchor, bs.x, bs.y
					end),
					shown = {
						type = "toggle",
						name = "Show",
						order = 1,
						width = 1,
						get = function() return MT.db.profile.blizzButtons[bkey].shown end,
						set = function(_, v)
							MT.db.profile.blizzButtons[bkey].shown = v
							MT.RepositionBlizzButtons()
						end,
					},
					anchor = {
						type = "select",
						name = "Anchor",
						desc = "Which corner of the minimap to anchor this button to",
						order = 2,
						width = 2,
						values = MT.ANCHOR_SELECT,
						get = function() return MT.db.profile.blizzButtons[bkey].anchor end,
						set = function(_, v)
							MT.db.profile.blizzButtons[bkey].anchor = v
							MT.RepositionBlizzButtons()
							local bs = MT.db.profile.blizzButtons[bkey]
							refreshPreview(bkey, bs.anchor, bs.x, bs.y)
						end,
						disabled = function() return not MT.db.profile.blizzButtons[bkey].shown end,
					},
					x = {
						type = "range",
						name = "X",
						desc = "Horizontal offset from the anchor point (pixels)",
						order = 3,
						min = -300,
						max = 300,
						step = 1,
						get = function() return MT.db.profile.blizzButtons[bkey].x end,
						set = function(_, v)
							MT.db.profile.blizzButtons[bkey].x = v
							MT.RepositionBlizzButtons()
							local bs = MT.db.profile.blizzButtons[bkey]
							refreshPreview(bkey, bs.anchor, bs.x, bs.y)
						end,
						disabled = function() return not MT.db.profile.blizzButtons[bkey].shown end,
					},
					y = {
						type = "range",
						name = "Y",
						desc = "Vertical offset from the anchor point (pixels)",
						order = 4,
						min = -300,
						max = 300,
						step = 1,
						get = function() return MT.db.profile.blizzButtons[bkey].y end,
						set = function(_, v)
							MT.db.profile.blizzButtons[bkey].y = v
							MT.RepositionBlizzButtons()
							local bs = MT.db.profile.blizzButtons[bkey]
							refreshPreview(bkey, bs.anchor, bs.x, bs.y)
						end,
						disabled = function() return not MT.db.profile.blizzButtons[bkey].shown end,
					},
				},
			}
		end
	end

	-- ── Addon Compartment (blizz button + Count Text merged in) ──────────────
	widgetEntries[#widgetEntries + 1] = {
		name = "Addon Compartment",
		key = "addonCompartment",
		args = {
			preview = makePreviewToggle("addonCompartment", function()
				local bs = MT.db.profile.blizzButtons.addonCompartment
				return bs.anchor, bs.x, bs.y
			end),
			shown = {
				type = "toggle",
				name = "Show",
				order = 1,
				width = 1,
				get = function() return MT.db.profile.blizzButtons.addonCompartment.shown end,
				set = function(_, v)
					MT.db.profile.blizzButtons.addonCompartment.shown = v
					MT.RepositionBlizzButtons()
				end,
			},
			anchor = {
				type = "select",
				name = "Anchor",
				desc = "Which corner of the minimap to anchor this button to",
				order = 2,
				width = 2,
				values = MT.ANCHOR_SELECT,
				get = function() return MT.db.profile.blizzButtons.addonCompartment.anchor end,
				set = function(_, v)
					MT.db.profile.blizzButtons.addonCompartment.anchor = v
					MT.RepositionBlizzButtons()
					local bs = MT.db.profile.blizzButtons.addonCompartment
					refreshPreview("addonCompartment", bs.anchor, bs.x, bs.y)
				end,
				disabled = function() return not MT.db.profile.blizzButtons.addonCompartment.shown end,
			},
			x = {
				type = "range",
				name = "X",
				desc = "Horizontal offset from the anchor point (pixels)",
				order = 3,
				min = -300,
				max = 300,
				step = 1,
				get = function() return MT.db.profile.blizzButtons.addonCompartment.x end,
				set = function(_, v)
					MT.db.profile.blizzButtons.addonCompartment.x = v
					MT.RepositionBlizzButtons()
					local bs = MT.db.profile.blizzButtons.addonCompartment
					refreshPreview("addonCompartment", bs.anchor, bs.x, bs.y)
				end,
				disabled = function() return not MT.db.profile.blizzButtons.addonCompartment.shown end,
			},
			y = {
				type = "range",
				name = "Y",
				desc = "Vertical offset from the anchor point (pixels)",
				order = 4,
				min = -300,
				max = 300,
				step = 1,
				get = function() return MT.db.profile.blizzButtons.addonCompartment.y end,
				set = function(_, v)
					MT.db.profile.blizzButtons.addonCompartment.y = v
					MT.RepositionBlizzButtons()
					local bs = MT.db.profile.blizzButtons.addonCompartment
					refreshPreview("addonCompartment", bs.anchor, bs.x, bs.y)
				end,
				disabled = function() return not MT.db.profile.blizzButtons.addonCompartment.shown end,
			},
			font = {
				type = "select",
				name = "Font",
				order = 5,
				values = MT.GetFontList,
				get = function() return MT.db.profile.compartment.font end,
				set = function(_, v)
					MT.db.profile.compartment.font = v; MT.ApplyCompartmentFont()
				end,
			},
			outline = {
				type = "select",
				name = "Outline",
				order = 6,
				width = 1,
				values = MT.OUTLINE_SELECT,
				get = function() return MT.db.profile.compartment.outline or "NONE" end,
				set = function(_, v)
					MT.db.profile.compartment.outline = v; MT.ApplyCompartmentFont()
				end,
			},
			fontSize = {
				type = "range",
				name = "Font Size",
				order = 7,
				width = 2,
				min = 7,
				max = 24,
				step = 1,
				get = function() return MT.db.profile.compartment.fontSize end,
				set = function(_, v)
					MT.db.profile.compartment.fontSize = v; MT.ApplyCompartmentFont()
				end,
			},
		},
	}
	-- ── Zone Text ─────────────────────────────────────────────────────────────
	widgetEntries[#widgetEntries + 1] = {
		name = "Zone Text",
		key = "zoneText",
		args = {
			preview = makePreviewToggle("zoneText", function()
				local s = MT.db.profile.zoneText
				return s.anchor, s.x, s.y
			end),
			enabled = {
				type = "toggle",
				name = "Show",
				order = 1,
				width = 1,
				get = function() return MT.db.profile.zoneText.enabled end,
				set = function(_, v)
					MT.db.profile.zoneText.enabled = v; MT.ApplyZoneText()
				end,
			},
			anchor = {
				type = "select",
				name = "Anchor",
				order = 2,
				width = 2,
				values = MT.ANCHOR_SELECT,
				get = function() return MT.db.profile.zoneText.anchor end,
				set = function(_, v)
					MT.db.profile.zoneText.anchor = v; MT.ApplyZoneText()
					local s = MT.db.profile.zoneText
					refreshPreview("zoneText", s.anchor, s.x, s.y)
				end,
				disabled = function() return not MT.db.profile.zoneText.enabled end,
			},
			x = {
				type = "range",
				name = "X",
				order = 3,
				min = -300,
				max = 300,
				step = 1,
				get = function() return MT.db.profile.zoneText.x end,
				set = function(_, v)
					MT.db.profile.zoneText.x = v; MT.ApplyZoneText()
					local s = MT.db.profile.zoneText
					refreshPreview("zoneText", s.anchor, s.x, s.y)
				end,
				disabled = function() return not MT.db.profile.zoneText.enabled end,
			},
			y = {
				type = "range",
				name = "Y",
				order = 4,
				min = -300,
				max = 300,
				step = 1,
				get = function() return MT.db.profile.zoneText.y end,
				set = function(_, v)
					MT.db.profile.zoneText.y = v; MT.ApplyZoneText()
					local s = MT.db.profile.zoneText
					refreshPreview("zoneText", s.anchor, s.x, s.y)
				end,
				disabled = function() return not MT.db.profile.zoneText.enabled end,
			},
			font = {
				type = "select",
				name = "Font",
				order = 5,
				width = 0.9,
				values = MT.GetFontList,
				get = function() return MT.db.profile.zoneText.font end,
				set = function(_, v)
					MT.db.profile.zoneText.font = v; MT.ApplyZoneText()
				end,
				disabled = function() return not MT.db.profile.zoneText.enabled end,
			},
			outline = {
				type = "select",
				name = "Outline",
				order = 6,
				width = 0.6,
				values = MT.OUTLINE_SELECT,
				get = function() return MT.db.profile.zoneText.outline or "OUTLINE" end,
				set = function(_, v)
					MT.db.profile.zoneText.outline = v; MT.ApplyZoneText()
				end,
				disabled = function() return not MT.db.profile.zoneText.enabled end,
			},
			justify = {
				type = "select",
				name = "Justify",
				order = 7,
				width = 0.5,
				values = MT.JUSTIFY_SELECT,
				get = function() return MT.db.profile.zoneText.justify end,
				set = function(_, v)
					MT.db.profile.zoneText.justify = v; MT.ApplyZoneText()
				end,
				disabled = function() return not MT.db.profile.zoneText.enabled end,
			},
			fontSize = {
				type = "range",
				name = "Font Size",
				order = 8,
				width = 2,
				min = 6,
				max = 24,
				step = 1,
				get = function() return MT.db.profile.zoneText.fontSize end,
				set = function(_, v)
					MT.db.profile.zoneText.fontSize = v; MT.ApplyZoneText()
				end,
				disabled = function() return not MT.db.profile.zoneText.enabled end,
			},
		},
	}
	-- ── Custom Clock ──────────────────────────────────────────────────────────
	-- Key is "clockWidget" to avoid colliding with the "clock" blizz button key
	-- that comes from BLIZZ_BUTTON_DEFS.
	widgetEntries[#widgetEntries + 1] = {
		name = "Clock (MM|cff00ff00T|r)",
		key = "clockWidget",
		args = {
			preview = makePreviewToggle("clockWidget", function()
				local s = MT.db.profile.clock
				return s.anchor, s.x, s.y
			end),
			enabled = {
				type = "toggle",
				name = "Show",
				desc =
				"Replaces the Blizzard clock with a custom widget. Respects the game's 12/24h and local/realm time settings.",
				order = 1,
				width = 1,
				get = function() return MT.db.profile.clock.enabled end,
				set = function(_, v)
					MT.db.profile.clock.enabled = v; MT.ApplyClockWidget()
				end,
			},
			anchor = {
				type = "select",
				name = "Anchor",
				order = 2,
				width = 2,
				values = MT.ANCHOR_SELECT,
				get = function() return MT.db.profile.clock.anchor end,
				set = function(_, v)
					MT.db.profile.clock.anchor = v; MT.ApplyClockWidget()
					local s = MT.db.profile.clock
					refreshPreview("clockWidget", s.anchor, s.x, s.y)
				end,
				disabled = function() return not MT.db.profile.clock.enabled end,
			},
			x = {
				type = "range",
				name = "X",
				order = 3,
				min = -300,
				max = 300,
				step = 1,
				get = function() return MT.db.profile.clock.x end,
				set = function(_, v)
					MT.db.profile.clock.x = v; MT.ApplyClockWidget()
					local s = MT.db.profile.clock
					refreshPreview("clockWidget", s.anchor, s.x, s.y)
				end,
				disabled = function() return not MT.db.profile.clock.enabled end,
			},
			y = {
				type = "range",
				name = "Y",
				order = 4,
				min = -300,
				max = 300,
				step = 1,
				get = function() return MT.db.profile.clock.y end,
				set = function(_, v)
					MT.db.profile.clock.y = v; MT.ApplyClockWidget()
					local s = MT.db.profile.clock
					refreshPreview("clockWidget", s.anchor, s.x, s.y)
				end,
				disabled = function() return not MT.db.profile.clock.enabled end,
			},
			font = {
				type = "select",
				name = "Font",
				order = 5,
				width = 0.9,
				values = MT.GetFontList,
				get = function() return MT.db.profile.clock.font end,
				set = function(_, v)
					MT.db.profile.clock.font = v; MT.ApplyClockWidget()
				end,
				disabled = function() return not MT.db.profile.clock.enabled end,
			},
			outline = {
				type = "select",
				name = "Outline",
				order = 6,
				width = 0.6,
				values = MT.OUTLINE_SELECT,
				get = function() return MT.db.profile.clock.outline or "OUTLINE" end,
				set = function(_, v)
					MT.db.profile.clock.outline = v; MT.ApplyClockWidget()
				end,
				disabled = function() return not MT.db.profile.clock.enabled end,
			},
			justify = {
				type = "select",
				name = "Justify",
				order = 7,
				width = 0.5,
				values = MT.JUSTIFY_SELECT,
				get = function() return MT.db.profile.clock.justify end,
				set = function(_, v)
					MT.db.profile.clock.justify = v; MT.ApplyClockWidget()
				end,
				disabled = function() return not MT.db.profile.clock.enabled end,
			},
			fontSize = {
				type = "range",
				name = "Font Size",
				order = 8,
				width = 2,
				min = 6,
				max = 24,
				step = 1,
				get = function() return MT.db.profile.clock.fontSize end,
				set = function(_, v)
					MT.db.profile.clock.fontSize = v; MT.ApplyClockWidget()
				end,
				disabled = function() return not MT.db.profile.clock.enabled end,
			},
			width = {
				type = "range",
				name = "Width",
				order = 9,
				min = 20,
				max = 300,
				step = 1,
				get = function() return MT.db.profile.clock.width end,
				set = function(_, v)
					MT.db.profile.clock.width = v; MT.ApplyClockWidget()
				end,
				disabled = function() return not MT.db.profile.clock.enabled end,
			},
			height = {
				type = "range",
				name = "Height",
				order = 10,
				min = 10,
				max = 100,
				step = 1,
				get = function() return MT.db.profile.clock.height end,
				set = function(_, v)
					MT.db.profile.clock.height = v; MT.ApplyClockWidget()
				end,
				disabled = function() return not MT.db.profile.clock.enabled end,
			},
		},
	}
	-- ── Coordinates ───────────────────────────────────────────────────────────
	widgetEntries[#widgetEntries + 1] = {
		name = "Coordinates",
		key = "coords",
		args = {
			preview = makePreviewToggle("coords", function()
				local s = MT.db.profile.coords
				return s.anchor, s.x, s.y
			end),
			enabled = {
				type = "toggle",
				name = "Show",
				order = 1,
				width = 1,
				get = function() return MT.db.profile.coords.enabled end,
				set = function(_, v)
					MT.db.profile.coords.enabled = v; MT.ApplyCoords()
				end,
			},
			anchor = {
				type = "select",
				name = "Anchor",
				order = 2,
				width = 2,
				values = MT.ANCHOR_SELECT,
				get = function() return MT.db.profile.coords.anchor end,
				set = function(_, v)
					MT.db.profile.coords.anchor = v; MT.ApplyCoords()
					local s = MT.db.profile.coords
					refreshPreview("coords", s.anchor, s.x, s.y)
				end,
				disabled = function() return not MT.db.profile.coords.enabled end,
			},
			x = {
				type = "range",
				name = "X",
				order = 3,
				min = -300,
				max = 300,
				step = 1,
				get = function() return MT.db.profile.coords.x end,
				set = function(_, v)
					MT.db.profile.coords.x = v; MT.ApplyCoords()
					local s = MT.db.profile.coords
					refreshPreview("coords", s.anchor, s.x, s.y)
				end,
				disabled = function() return not MT.db.profile.coords.enabled end,
			},
			y = {
				type = "range",
				name = "Y",
				order = 4,
				min = -300,
				max = 300,
				step = 1,
				get = function() return MT.db.profile.coords.y end,
				set = function(_, v)
					MT.db.profile.coords.y = v; MT.ApplyCoords()
					local s = MT.db.profile.coords
					refreshPreview("coords", s.anchor, s.x, s.y)
				end,
				disabled = function() return not MT.db.profile.coords.enabled end,
			},
			font = {
				type = "select",
				name = "Font",
				order = 5,
				width = 0.9,
				values = MT.GetFontList,
				get = function() return MT.db.profile.coords.font end,
				set = function(_, v)
					MT.db.profile.coords.font = v; MT.ApplyCoords()
				end,
				disabled = function() return not MT.db.profile.coords.enabled end,
			},
			outline = {
				type = "select",
				name = "Outline",
				order = 6,
				width = 0.6,
				values = MT.OUTLINE_SELECT,
				get = function() return MT.db.profile.coords.outline or "OUTLINE" end,
				set = function(_, v)
					MT.db.profile.coords.outline = v; MT.ApplyCoords()
				end,
				disabled = function() return not MT.db.profile.coords.enabled end,
			},
			justify = {
				type = "select",
				name = "Justify",
				order = 7,
				width = 0.5,
				values = MT.JUSTIFY_SELECT,
				get = function() return MT.db.profile.coords.justify end,
				set = function(_, v)
					MT.db.profile.coords.justify = v; MT.ApplyCoords()
				end,
				disabled = function() return not MT.db.profile.coords.enabled end,
			},
			fontSize = {
				type = "range",
				name = "Font Size",
				order = 8,
				width = 2,
				min = 6,
				max = 24,
				step = 1,
				get = function() return MT.db.profile.coords.fontSize end,
				set = function(_, v)
					MT.db.profile.coords.fontSize = v; MT.ApplyCoords()
				end,
				disabled = function() return not MT.db.profile.coords.enabled end,
			},
			width = {
				type = "range",
				name = "Width",
				order = 9,
				min = 20,
				max = 300,
				step = 1,
				get = function() return MT.db.profile.coords.width end,
				set = function(_, v)
					MT.db.profile.coords.width = v; MT.ApplyCoords()
				end,
				disabled = function() return not MT.db.profile.coords.enabled end,
			},
			height = {
				type = "range",
				name = "Height",
				order = 10,
				min = 10,
				max = 100,
				step = 1,
				get = function() return MT.db.profile.coords.height end,
				set = function(_, v)
					MT.db.profile.coords.height = v; MT.ApplyCoords()
				end,
				disabled = function() return not MT.db.profile.coords.enabled end,
			},
			decimals = {
				type = "range",
				name = "Decimals",
				order = 11,
				width = 2,
				min = 0,
				max = 3,
				step = 1,
				get = function() return MT.db.profile.coords.decimals end,
				set = function(_, v)
					MT.db.profile.coords.decimals = v; MT.UpdateCoords()
				end,
				disabled = function() return not MT.db.profile.coords.enabled end,
			},
		},
	}
	-- ── Sort alphabetically and build the final widgetArgs table ─────────────
	table.sort(widgetEntries, function(a, b) return a.name < b.name end)
	local widgetArgs = {}
	for i, entry in ipairs(widgetEntries) do
		widgetArgs[entry.key] = {
			type = "group",
			name = entry.name,
			order = i,
			args = entry.args,
		}
	end

	return {
		type = "group",
		name = ADDON_NAME,
		childGroups = "tab",
		args = {
			-- ── Tab: Minimap ──────────────────────────────────────────
			minimap = {
				type = "group",
				name = "Minimap",
				order = 1,
				args = {
					-- ── Inline: Minimap ───────────────────────────────
					minimapGroup = {
						type = "group",
						name = "Minimap",
						inline = true,
						order = 1,
						args = {
							size = {
								type = "range",
								name = "Size",
								desc = "Changes the size of the minimap WITHOUT affecting other elements.",
								order = 1,
								min = 100,
								max = 400,
								step = 1,
								get = get("size"),
								set = set("size"),
							},
							scale = {
								type = "range",
								name = "Scale",
								desc =
								"Changes the size of the minimap AND all its elements: player and enemy icon, gatherable icons, zone text, calendar, clock etc.",
								order = 2,
								min = 0.5,
								max = 2.0,
								step = 0.05,
								get = get("scale"),
								set = set("scale"),
							},
							buttonOffset = {
								type = "range",
								name = "Addon Buttons Offset",
								desc = "Gap between the minimap edge and LibDBIcon addon buttons (pixels)",
								order = 3,
								min = 0,
								max = 20,
								step = 1,
								get = get("buttonOffset"),
								set = set("buttonOffset", MT.SyncButtonRadius),
							},
							mapOffsetX = {
								type = "range",
								name = "Map X Offset",
								desc = "Horizontal offset of the minimap within its cluster frame (Blizzard default was +10)",
								order = 4,
								min = -50,
								max = 50,
								step = 1,
								get = get("mapOffsetX"),
								set = set("mapOffsetX", MT.HideBlizzHeader),
							},
							mapOffsetY = {
								type = "range",
								name = "Map Y Offset",
								desc = "Vertical offset of the minimap within its cluster frame (Blizzard default was -30)",
								order = 5,
								min = -50,
								max = 0,
								step = 1,
								get = get("mapOffsetY"),
								set = set("mapOffsetY", MT.HideBlizzHeader),
							},
						},
					},
					-- ── Inline: Border ────────────────────────────────
					borderGroup = {
						type = "group",
						name = "Minimap Border",
						inline = true,
						order = 2,
						args = {
							borderEnabled = {
								type = "toggle",
								name = "Show Border",
								order = 1,
								width = 1,
								get = getb("border", "enabled"),
								set = setb("border", "enabled", MT.ApplyBorder),
							},
							borderSize = {
								type = "range",
								name = "Border Size",
								desc = "Size of each texture tile (edgeSize). Controls how large the border artwork is rendered.",
								order = 2,
								width = 1,
								min = 1,
								max = 64,
								step = 1,
								get = getb("border", "size"),
								set = setb("border", "size", MT.ApplyBorder),
								disabled = function() return not MT.db.profile.border.enabled end,
							},
							borderOffset = {
								type = "range",
								name = "Border Offset",
								desc =
								"How far the border frame extends beyond the minimap edge on each side. 0 = flush with the map edge.",
								order = 3,
								width = 1,
								min = -32,
								max = 64,
								step = 1,
								get = getb("border", "offset"),
								set = setb("border", "offset", MT.ApplyBorder),
								disabled = function() return not MT.db.profile.border.enabled end,
							},
							borderColor = {
								type = "color",
								name = "Border Color",
								order = 4,
								width = 0.99,
								hasAlpha = true,
								get = function()
									local b = MT.db.profile.border
									return b.r, b.g, b.b, b.a
								end,
								set = function(_, r, g, b, a)
									local border = MT.db.profile.border
									border.r = r; border.g = g
									border.b = b; border.a = a
									MT.ApplyBorder()
								end,
								disabled = function() return not MT.db.profile.border.enabled end,
							},
							borderTexture = {
								type = "select",
								name = "Border Style",
								desc = "Border texture. Populated from LibSharedMedia if installed, otherwise shows built-in options.",
								order = 5,
								width = 2,
								values = MT.GetBorderList,
								get = getb("border", "texture"),
								set = setb("border", "texture", MT.ApplyBorder),
								disabled = function() return not MT.db.profile.border.enabled end,
							},
						},
					},
					-- ── Inline: Zoom ──────────────────────────────────
					zoomGroup = {
						type = "group",
						name = "Zoom",
						inline = true,
						order = 3,
						args = {
							zoomResetEnabled = {
								type = "toggle",
								name = "Auto reset zoom",
								desc = "Automatically return to a fixed zoom level after scrolling",
								order = 1,
								get = get("zoomResetEnabled"),
								set = set("zoomResetEnabled"),
							},
							zoomResetDelay = {
								type = "range",
								name = "Reset Delay",
								desc = "Seconds to wait after the last scroll before resetting zoom",
								order = 2,
								min = 1,
								max = 60,
								step = 1,
								get = get("zoomResetDelay"),
								set = set("zoomResetDelay"),
								disabled = function() return not MT.db.profile.zoomResetEnabled end,
							},
							zoomResetLevel = {
								type = "range",
								name = "Reset to Zoom Level",
								desc = "0 = fully zoomed out, 5 = fully zoomed in",
								order = 3,
								min = 0,
								max = 5,
								step = 1,
								get = get("zoomResetLevel"),
								set = set("zoomResetLevel"),
								disabled = function() return not MT.db.profile.zoomResetEnabled end,
							},
						},
					},
				},
			},

			-- ── Tab: Widgets (tree layout) ────────────────────────────────────
			buttons = {
				type = "group",
				name = "Widgets",
				order = 2,
				childGroups = "tree",
				args = widgetArgs,
			},

			-- ── Tab: Mouse Bindings ───────────────────────────────────────────
			clicks = {
				type = "group",
				name = "Mouse Bindings",
				order = 3,
				args = {
					clickGroup = {
						type = "group",
						name = "Minimap",
						inline = true,
						order = 1,
						args = {
							left = {
								type = "select",
								name = "Left Click",
								order = 1,
								values = MT.CLICK_ACTION_VALUES,
								get = function() return MT.db.profile.clicks.left end,
								set = function(_, v)
									MT.db.profile.clicks.left = v; MT.ApplyClickActions()
								end,
							},
							middle = {
								type = "select",
								name = "Middle Click",
								order = 2,
								values = MT.CLICK_ACTION_VALUES,
								get = function() return MT.db.profile.clicks.middle end,
								set = function(_, v)
									MT.db.profile.clicks.middle = v; MT.ApplyClickActions()
								end,
							},
							right = {
								type = "select",
								name = "Right Click",
								order = 3,
								values = MT.CLICK_ACTION_VALUES,
								get = function() return MT.db.profile.clicks.right end,
								set = function(_, v)
									MT.db.profile.clicks.right = v; MT.ApplyClickActions()
								end,
							},
						},
					},
					clockClickGroup = {
						type = "group",
						name = "Custom Clock",
						inline = true,
						order = 2,
						args = {
							left = {
								type = "select",
								name = "Left Click",
								order = 1,
								values = MT.OVERLAY_CLICK_ACTION_VALUES,
								get = function() return MT.db.profile.clockClicks.left end,
								set = function(_, v)
									MT.db.profile.clockClicks.left = v
									MT.RebuildPassThrough(MT.clockFrame, MT.db.profile.clockClicks)
								end,
							},
							middle = {
								type = "select",
								name = "Middle Click",
								order = 2,
								values = MT.OVERLAY_CLICK_ACTION_VALUES,
								get = function() return MT.db.profile.clockClicks.middle end,
								set = function(_, v)
									MT.db.profile.clockClicks.middle = v
									MT.RebuildPassThrough(MT.clockFrame, MT.db.profile.clockClicks)
								end,
							},
							right = {
								type = "select",
								name = "Right Click",
								order = 3,
								values = MT.OVERLAY_CLICK_ACTION_VALUES,
								get = function() return MT.db.profile.clockClicks.right end,
								set = function(_, v)
									MT.db.profile.clockClicks.right = v
									MT.RebuildPassThrough(MT.clockFrame, MT.db.profile.clockClicks)
								end,
							},
						},
					},
					coordsClickGroup = {
						type = "group",
						name = "Coordinates",
						inline = true,
						order = 3,
						args = {
							left = {
								type = "select",
								name = "Left Click",
								order = 1,
								values = MT.OVERLAY_CLICK_ACTION_VALUES,
								get = function() return MT.db.profile.coordsClicks.left end,
								set = function(_, v)
									MT.db.profile.coordsClicks.left = v
									MT.RebuildPassThrough(MT.coordsFrame, MT.db.profile.coordsClicks)
								end,
							},
							middle = {
								type = "select",
								name = "Middle Click",
								order = 2,
								values = MT.OVERLAY_CLICK_ACTION_VALUES,
								get = function() return MT.db.profile.coordsClicks.middle end,
								set = function(_, v)
									MT.db.profile.coordsClicks.middle = v
									MT.RebuildPassThrough(MT.coordsFrame, MT.db.profile.coordsClicks)
								end,
							},
							right = {
								type = "select",
								name = "Right Click",
								order = 3,
								values = MT.OVERLAY_CLICK_ACTION_VALUES,
								get = function() return MT.db.profile.coordsClicks.right end,
								set = function(_, v)
									MT.db.profile.coordsClicks.right = v
									MT.RebuildPassThrough(MT.coordsFrame, MT.db.profile.coordsClicks)
								end,
							},
						},
					},
				},
			},
		},
	}
end

-- ============================================================
-- Settings setup
-- ============================================================
local function SetupSettings()
	local AceConfig = LibStub("AceConfig-3.0")
	AceConfig:RegisterOptionsTable(ADDON_NAME, BuildOptionsTable())
	LibStub("AceConfigDialog-3.0"):SetDefaultSize(ADDON_NAME, 620, 500)
	-- Register a native Settings panel rather than using AceConfigDialog:AddToBlizOptions.
	-- AddToBlizOptions internally hooks OnHide → AceConfigDialog:Close(), which pulls the
	-- floating window down whenever game settings close.  A plain canvas panel has no such
	-- linkage, so the floating window is completely unaffected by game settings open/close.
	local panel = CreateFrame("Frame")
	local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btn:SetText("Open " .. ADDON_NAME .. " Settings")
	btn:SetPoint("TOPLEFT", 16, -16)
	btn:SetWidth(220)
	btn:SetScript("OnClick", MT.OpenSettings)
	local category = Settings.RegisterCanvasLayoutCategory(panel, ADDON_NAME)
	Settings.RegisterAddOnCategory(category)
end

-- ============================================================
-- Export to shared namespace
-- ============================================================
MT.SetupSettings = SetupSettings
