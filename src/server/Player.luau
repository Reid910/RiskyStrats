--[[
	Player Module
	Manages player teams using Roblox's TeamService
]]

local Player = {
	Name = "Player"
}

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

-- Team references
local TeamInstances = {
	Red = nil,
	Blue = nil,
	Green = nil,
	Yellow = nil,
}

--[[
	TEAM MANAGEMENT
]]

function Player.SetTeam(player, teamName)
	local teamInstance = TeamInstances[teamName]
	if teamInstance then
		player.Team = teamInstance
		return true
	end
	return false
end

function Player.GetTeam(player)
	for teamName, teamInstance in pairs(TeamInstances) do
		if player.Team == teamInstance then
			return teamName
		end
	end
	return nil
end

function Player.IsOnTeam(player, teamName)
	return Player.GetTeam(player) == teamName
end

--[[
	LIFECYCLE
]]

local function CreateTeam(name, color)
	local team = Teams:FindFirstChild(name)
	if not team then
		team = Instance.new("Team")
		team.Name = name
		team.TeamColor = BrickColor.new(color)
		team.AutoAssignable = false
		team.Parent = Teams
	end
	return team
end

function Player.Init()
	-- Create all teams
	TeamInstances.Red = CreateTeam("Red", "Bright red")
	TeamInstances.Blue = CreateTeam("Blue", "Bright blue")
	TeamInstances.Green = CreateTeam("Green", "Bright green")
	TeamInstances.Yellow = CreateTeam("Yellow", "Bright yellow")

	-- print("Teams created: Red, Blue, Green, Yellow")
end

function Player.Start()
end

return Player
