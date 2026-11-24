--[[
	TeamColors
	Shared module for consistent team colors across client and server
	Single source of truth for all team definitions
]]

local TeamColors = {
	-- Main team colors
	Red = Color3.fromRGB(255, 85, 85),
	Blue = Color3.fromRGB(85, 170, 255),
	Green = Color3.fromRGB(85, 255, 127),
	Yellow = Color3.fromRGB(255, 255, 127),
	Purple = Color3.fromRGB(170, 85, 255),
	Orange = Color3.fromRGB(255, 170, 85),
	Cyan = Color3.fromRGB(85, 255, 255),
	Pink = Color3.fromRGB(255, 127, 200),
	Lime = Color3.fromRGB(170, 255, 85),
	Teal = Color3.fromRGB(85, 200, 170),
	Maroon = Color3.fromRGB(170, 60, 60),
	Navy = Color3.fromRGB(85, 85, 200),
	Coral = Color3.fromRGB(255, 130, 110),
	Violet = Color3.fromRGB(200, 130, 255),
	Gold = Color3.fromRGB(255, 200, 85),
	White = Color3.fromRGB(230, 230, 230),

	-- Special colors
	Neutral = Color3.fromRGB(180, 180, 180),
	Contested = Color3.fromRGB(128, 128, 128),
	Ghost = Color3.fromRGB(100, 100, 100),
}

-- Ordered list of all playable team names (first N are used based on game config)
local ALL_TEAMS = {
	"Red", "Blue", "Green", "Yellow",
	"Purple", "Orange", "Cyan", "Pink",
	"Lime", "Teal", "Maroon", "Navy",
	"Coral", "Violet", "Gold", "White",
}

-- BrickColor mappings for Roblox Team instances
local BRICK_COLORS = {
	Red = "Bright red",
	Blue = "Bright blue",
	Green = "Bright green",
	Yellow = "Bright yellow",
	Purple = "Bright violet",
	Orange = "Neon orange",
	Cyan = "Cyan",
	Pink = "Pink",
	Lime = "Lime green",
	Teal = "Teal",
	Maroon = "Maroon",
	Navy = "Navy blue",
	Coral = "Salmon",
	Violet = "Lavender",
	Gold = "Gold",
	White = "White",
}

--[[
	Get color for a team name (with fallback to Neutral)
]]
function TeamColors.GetColor(teamName)
	return TeamColors[teamName] or TeamColors.Neutral
end

--[[
	Get ordered list of all playable team names (16 total)
]]
function TeamColors.GetTeamNames()
	return ALL_TEAMS
end

--[[
	Get BrickColor name for a team (for Roblox Team instances)
]]
function TeamColors.GetBrickColor(teamName)
	return BRICK_COLORS[teamName] or "Medium stone grey"
end

return TeamColors
