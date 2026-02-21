--[[
	TeamColors
	Shared module for consistent team colors across client and server
]]

local TeamColors = {
	-- Main team colors
	Red = Color3.fromRGB(255, 85, 85),
	Blue = Color3.fromRGB(85, 170, 255),
	Green = Color3.fromRGB(85, 255, 127),
	Yellow = Color3.fromRGB(255, 255, 127),

	-- Special colors
	Neutral = Color3.fromRGB(180, 180, 180),
	Contested = Color3.fromRGB(128, 128, 128),
	Ghost = Color3.fromRGB(100, 100, 100),
}

--[[
	Get color for a team name (with fallback to Neutral)
]]
function TeamColors.GetColor(teamName)
	return TeamColors[teamName] or TeamColors.Neutral
end

--[[ Get all team names (excluding special colors) ]]
local TeamNames = {}

for i,v in pairs(TeamColors) do
	if i == "Neutral" or i == "Contested" or i == "Ghost" then continue end
	table.insert(TeamNames, i)
end

function TeamColors.GetTeamNames()
	return TeamNames
end

return TeamColors
