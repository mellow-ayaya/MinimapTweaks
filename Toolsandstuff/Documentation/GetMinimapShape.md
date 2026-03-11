GetMinimapShape
GetMinimapShape is a function that is declared by the currently running minimap addon to provide information about what shape it is, in case other addons need to deal with the minimap's borders.

It takes no arguments and returns one of the following strings:

"ROUND"
    standard shape, round. This is to be assumed if an unknown string is returned or if no string is returned or if GetMinimapShape does not exist.
"SQUARE"
    square shape.
"CORNER-TOPLEFT"
    square, but with the top-left corner being round. This would normally be put at the bottom-right of the screen.
"CORNER-TOPRIGHT"
    square, but with the top-right corner being round. This would normally be put at the bottom-left of the screen.
"CORNER-BOTTOMLEFT"
    square, but with the bottom-left corner being round. This would normally be put at the top-right of the screen.
"CORNER-BOTTOMRIGHT"
    square, but with the bottom-right corner being round. This would normally be put at the top-left of the screen.
"SIDE-LEFT"
    square on the right side, rounded on the left side. This would normally be put at the right of the screen.
"SIDE-RIGHT"
    square on the left side, rounded on the right side. This would normally be put at the left of the screen.
"SIDE-TOP"
    square on the bottom side, rounded on the top side. This would normally be put at the bottom of the screen.
"SIDE-BOTTOM"
    square on the top side, rounded on the bottom side. This would normally be put at the top of the screen.
"TRICORNER-TOPLEFT"
    round, but with the bottom-right corner being square. This would normally be put at the bottom-right of the screen.
"TRICORNER-TOPRIGHT"
    round, but with the bottom-left corner being square. This would normally be put at the bottom-left of the screen.
"TRICORNER-BOTTOMLEFT"
    round, but with the top-right corner being square. This would normally be put at the top-right of the screen.
"TRICORNER-BOTTOMRIGHT"
    round, but with the top-left corner being square. This would normally be put at the top-left of the screen.

It is possible this function will be called once a frame, so it is recommended not to do anything CPU-intensive in calculating the shape.

This is currently used by FuBarPlugin-2.0 to determine position of minimap buttons.
This is currently used by Cartographer_Notes to determine edge position of notes on the minimap.
This is currently used by MobileMinimapButtons to determine position of draggable minimap buttons.

This is the code currently used by FuBarPlugin-2.0 to determine position on the edge of a minimap:

local angle = math.rad(position) -- determine position on your own
local minimapShape = GetMinimapShape and GetMinimapShape() or "ROUND"
local cos = math.cos(angle)
local sin = math.sin(angle)

local round = true
if minimapShape == "ROUND" then
	-- do nothing
elseif minimapShape == "SQUARE" then
	round = false
elseif minimapShape == "CORNER-TOPRIGHT" then
	if cos < 0 or sin < 0 then
		round = false
	end
elseif minimapShape == "CORNER-TOPLEFT" then
	if cos > 0 or sin < 0 then
		round = false
	end
elseif minimapShape == "CORNER-BOTTOMRIGHT" then
	if cos < 0 or sin > 0 then
		round = false
	end
elseif minimapShape == "CORNER-BOTTOMLEFT" then
	if cos > 0 or sin > 0 then
		round = false
	end
elseif minimapShape == "SIDE-LEFT" then
	if cos > 0 then
		round = false
	end
elseif minimapShape == "SIDE-RIGHT" then
	if cos < 0 then
		round = false
	end
elseif minimapShape == "SIDE-TOP" then
	if sin > 0 then
		round = false
	end
elseif minimapShape == "SIDE-BOTTOM" then
	if sin < 0 then
		round = false
	end
elseif minimapShape == "TRICORNER-TOPRIGHT" then
	if cos < 0 and sin > 0 then
		round = false
	end
elseif minimapShape == "TRICORNER-TOPLEFT" then
	if cos > 0 and sin > 0 then
		round = false
	end
elseif minimapShape == "TRICORNER-BOTTOMRIGHT" then
	if cos < 0 and sin < 0 then
		round = false
	end
elseif minimapShape == "TRICORNER-BOTTOMLEFT" then
	if cos > 0 and sin < 0 then
		round = false
	end
end

local x,y
if round then
	x = cos * 80
	y = sin * 80
else
	x = 110 * cos
	y = 110 * sin
	x = math.max(-82, math.min(x, 84))
	y = math.max(-86, math.min(y, 82))
end
frame:SetPoint("CENTER", Minimap, "CENTER", x, y)

This is the a conversion table used by MobileMinimapButtons to shorten the previous code, add radius functionality and make the square corner rounding more flexible:

local MinimapShapes = {
	-- quadrant booleans (same order as SetTexCoord)
	-- {upper-left, lower-left, upper-right, lower-right}
	-- true = rounded, false = squared
	["ROUND"] 			= {true, true, true, true},
	["SQUARE"] 			= {false, false, false, false},
	["CORNER-TOPLEFT"] 		= {true, false, false, false},
	["CORNER-TOPRIGHT"] 		= {false, false, true, false},
	["CORNER-BOTTOMLEFT"] 		= {false, true, false, false},
	["CORNER-BOTTOMRIGHT"]	 	= {false, false, false, true},
	["SIDE-LEFT"] 			= {true, true, false, false},
	["SIDE-RIGHT"] 			= {false, false, true, true},
	["SIDE-TOP"] 			= {true, false, true, false},
	["SIDE-BOTTOM"] 		= {false, true, false, true},
	["TRICORNER-TOPLEFT"] 		= {true, true, true, false},
	["TRICORNER-TOPRIGHT"] 		= {true, false, true, true},
	["TRICORNER-BOTTOMLEFT"] 	= {true, true, false, true},
	["TRICORNER-BOTTOMRIGHT"] 	= {false, true, true, true},
}

function UpdateButtonPosition(position, radius, rounding)
	if not radius then rounding = 80 end
	if not rounding then rounding = 10 end
	local angle = math.rad(position) -- determine position on your own
	local x = math.sin(angle)
	local y = math.cos(angle)
	local q = 1;
	if x < 0 then
		q = q + 1;	-- lower
	end
	if y > 0 then
		q = q + 2;	-- right
	end
	local minimapShape = GetMinimapShape and GetMinimapShape() or "ROUND"
	local quadTable = MinimapShapes[minimapShape];
	if quadTable[q] then
		x = x*radius;
		y = y*radius;
	else
		local diagRadius = math.sqrt(2*(radius)^2)-rounding
		x = math.max(-radius, math.min(x*diagRadius, radius))
		y = math.max(-radius, math.min(y*diagRadius, radius))
	end
	frame:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
