--[[
	Player Module
	Manages player teams using Roblox's TeamService
]]

local Player = {
	Name = "Player"
}

local Teams = game:GetService("Teams")
local TeamColors = require(game.ReplicatedStorage.Shared.TeamColors)

-- Team references (built dynamically)
local TeamInstances = {}

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

function Player.ClearTeam(player)
	player.Team = nil
end

function Player.IsOnTeam(player, teamName)
	return Player.GetTeam(player) == teamName
end

--[[
	LIFECYCLE
]]

local function CreateTeam(name, brickColorName)
	local team = Teams:FindFirstChild(name)
	if not team then
		team = Instance.new("Team")
		team.Name = name
		team.TeamColor = BrickColor.new(brickColorName)
		team.AutoAssignable = false
		team.Parent = Teams
	end
	return team
end

function Player.Init()
	-- Create all teams from TeamColors
	for _, name in ipairs(TeamColors.GetTeamNames()) do
		TeamInstances[name] = CreateTeam(name, TeamColors.GetBrickColor(name))
	end
end

function Player.Start()
end

return Player
