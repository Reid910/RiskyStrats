--[[
	AIController
	Manages AI-controlled teams (skeleton for future AI logic)

	When fewer than 4 human players are in a game, remaining team slots
	are filled with AI. Currently AI teams do nothing — their nodes sit idle.
]]

local AIController = {
	Name = "AIController"
}

-- Set of team names controlled by AI: { [teamName] = true }
local AITeams = {}

--[[
	Register teams as AI-controlled
	@param teamNames - Array of team name strings
]]
function AIController.AssignTeams(teamNames)
	for _, name in ipairs(teamNames) do
		AITeams[name] = true
	end
	if #teamNames > 0 then
		print(`[AIController] Assigned AI teams: {table.concat(teamNames, ", ")}`)
	end
end

--[[
	Check if a team is AI-controlled
]]
function AIController.IsAITeam(teamName)
	return AITeams[teamName] == true
end

--[[
	Clear all AI team assignments (called on game end)
]]
function AIController.ClearTeams()
	table.clear(AITeams)
end

function AIController.Init()
end

function AIController.Start()
	-- Future: Heartbeat loop for AI decision-making
	-- Will call Troops.SendTroopsForTeam(), Buildings.PlaceBuildingForTeam(), etc.
end

return AIController
