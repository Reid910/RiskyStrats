--[[
	Team Module
	Manages team data for the RTS game (nodes owned, troop counts, etc.)
]]

local Team = {
	Name = "Team"
}

-- Reference to ServerModule (set during Init)
local ServerModule = nil

-- Callback for when a team is eliminated (loses their Capitol)
local OnTeamEliminatedCallback = nil

-- Track eliminated teams
local EliminatedTeams = {}

-- Team data structure
local Teams = {
	Red = {
		name = "Red",
		color = Color3.fromRGB(255, 85, 85),
		ownedNodes = {}, -- Array of node IDs owned by this team
		spawnNodeId = nil,
	},
	Blue = {
		name = "Blue",
		color = Color3.fromRGB(85, 170, 255),
		ownedNodes = {},
		spawnNodeId = nil,
	},
	Green = {
		name = "Green",
		color = Color3.fromRGB(85, 255, 127),
		ownedNodes = {},
		spawnNodeId = nil,
	},
	Yellow = {
		name = "Yellow",
		color = Color3.fromRGB(255, 255, 127),
		ownedNodes = {},
		spawnNodeId = nil,
	},
	Neutral = {
		name = "Neutral",
		color = Color3.fromRGB(180, 180, 180),
		ownedNodes = {},
		spawnNodeId = nil,
	},
}

-- Node ownership data (maps nodeId -> teamName)
local NodeOwnership = {}

-- Node troop counts (maps nodeId -> { teamName = count, ... })
local NodeTroops = {}

--[[
	TEAM MANAGEMENT
]]

function Team.GetTeamData(teamName)
	return Teams[teamName]
end

function Team.GetAllTeams()
	return {"Red", "Blue", "Green", "Yellow"}
end

function Team.GetAllTeamsIncludingNeutral()
	return {"Red", "Blue", "Green", "Yellow", "Neutral"}
end

function Team.ResetAllTeams()
	for _, teamName in ipairs(Team.GetAllTeams()) do
		local teamData = Teams[teamName]
		table.clear(teamData.ownedNodes)
		teamData.spawnNodeId = nil
	end
	-- Clear ownership, troop data, and eliminated teams
	NodeOwnership = {}
	NodeTroops = {}
	table.clear(EliminatedTeams)
end

--[[
	Set callback for when a team is eliminated
]]
function Team.SetOnTeamEliminated(callback)
	OnTeamEliminatedCallback = callback
end

--[[
	Check if a team is eliminated
]]
function Team.IsTeamEliminated(teamName)
	return EliminatedTeams[teamName] == true
end

--[[
	Get list of active (non-eliminated) teams
]]
function Team.GetActiveTeams()
	local active = {}
	for _, teamName in ipairs(Team.GetAllTeams()) do
		if not EliminatedTeams[teamName] then
			local spawnNodeId = Teams[teamName].spawnNodeId
			if spawnNodeId then
				table.insert(active, teamName)
			end
		end
	end
	return active
end

--[[
	NODE OWNERSHIP
]]

function Team.SetNodeOwner(nodeId, teamName)
	-- Convert nodeId to string for consistency with RemoteEvent serialization
	local nodeIdStr = tostring(nodeId)

	-- Remove from previous owner
	local previousOwner = NodeOwnership[nodeIdStr]
	if previousOwner then
		local teamData = Teams[previousOwner]
		if teamData then
			local index = table.find(teamData.ownedNodes, nodeId)
			if index then
				table.remove(teamData.ownedNodes, index)
			end
		end
	end

	-- Set new owner
	if teamName then
		NodeOwnership[nodeIdStr] = teamName
		local teamData = Teams[teamName]
		if teamData then
			table.insert(teamData.ownedNodes, nodeId)
		end
	else
		NodeOwnership[nodeIdStr] = nil
	end

	-- Mark node as changed for network updates
	if ServerModule then
		ServerModule.MarkNodeChanged(nodeId)
	end

	-- Check if previous owner lost their Capitol (spawn node)
	if previousOwner and previousOwner ~= teamName then
		local prevTeamData = Teams[previousOwner]
		if prevTeamData and prevTeamData.spawnNodeId == nodeId then
			-- Team lost their Capitol - they are eliminated
			if not EliminatedTeams[previousOwner] then
				EliminatedTeams[previousOwner] = true
				print(`{previousOwner} has been eliminated!`)

				if OnTeamEliminatedCallback then
					OnTeamEliminatedCallback(previousOwner)
				end
			end
		end
	end
end

function Team.GetNodeOwner(nodeId)
	-- Convert nodeId to string for consistency with RemoteEvent serialization
	local nodeIdStr = tostring(nodeId)
	return NodeOwnership[nodeIdStr]
end

function Team.IsNodeOwnedBy(nodeId, teamName)
	-- Convert nodeId to string for consistency with RemoteEvent serialization
	local nodeIdStr = tostring(nodeId)
	return NodeOwnership[nodeIdStr] == teamName
end

function Team.GetOwnedNodes(teamName)
	local teamData = Teams[teamName]
	if teamData then
		return teamData.ownedNodes
	end
	return {}
end

--[[
	TROOP MANAGEMENT
	Troops are now stored per-team: NodeTroops[nodeId] = { Red = 50, Blue = 30 }
]]

function Team.SetNodeTroops(nodeId, count, teamName)
	local nodeIdStr = tostring(nodeId)
	local newCount = math.max(0, count)

	-- Ensure node has a troop table
	if not NodeTroops[nodeIdStr] then
		NodeTroops[nodeIdStr] = {}
	end

	-- If teamName provided, set troops for that team
	if teamName then
		if newCount > 0 then
			NodeTroops[nodeIdStr][teamName] = newCount
		else
			NodeTroops[nodeIdStr][teamName] = nil
		end
	else
		-- Legacy: if no teamName, set for the owner
		local owner = NodeOwnership[nodeIdStr]
		if owner then
			if newCount > 0 then
				NodeTroops[nodeIdStr][owner] = newCount
			else
				NodeTroops[nodeIdStr][owner] = nil
			end
		end
	end

	-- Update ownership based on troop presence
	Team.UpdateNodeOwnership(nodeId)

	-- Mark node as changed for network updates
	if ServerModule then
		ServerModule.MarkNodeChanged(nodeId)
	end
end

function Team.GetNodeTroops(nodeId, teamName)
	local nodeIdStr = tostring(nodeId)
	local troops = NodeTroops[nodeIdStr]

	if not troops then
		return 0
	end

	-- If teamName provided, return that team's troops
	if teamName then
		return troops[teamName] or 0
	end

	-- Legacy: return owner's troops (or total if contested)
	local owner = NodeOwnership[nodeIdStr]
	if owner then
		return troops[owner] or 0
	end

	-- Return total if no owner
	local total = 0
	for _, count in pairs(troops) do
		total = total + count
	end
	return total
end

function Team.GetAllNodeTroops(nodeId)
	-- Returns the full troop table for a node: { Red = 50, Blue = 30 }
	local nodeIdStr = tostring(nodeId)
	return NodeTroops[nodeIdStr] or {}
end

function Team.AddNodeTroops(nodeId, count, teamName)
	local current = Team.GetNodeTroops(nodeId, teamName)
	Team.SetNodeTroops(nodeId, current + count, teamName)
end

function Team.RemoveNodeTroops(nodeId, count, teamName)
	local current = Team.GetNodeTroops(nodeId, teamName)
	local newCount = math.max(0, current - count)
	Team.SetNodeTroops(nodeId, newCount, teamName)
	return newCount
end

function Team.IsNodeContested(nodeId)
	-- Returns true if multiple teams have troops on this node
	local nodeIdStr = tostring(nodeId)
	local troops = NodeTroops[nodeIdStr]
	if not troops then return false end

	local teamCount = 0
	for _, count in pairs(troops) do
		if count > 0 then
			teamCount = teamCount + 1
		end
	end
	return teamCount > 1
end

function Team.UpdateNodeOwnership(nodeId)
	-- Called after troop changes to update who owns the node
	local nodeIdStr = tostring(nodeId)
	local troops = NodeTroops[nodeIdStr]

	if not troops then
		-- No troops = neutral (unless spawn node)
		local isSpawnNode = false
		for _, teamData in pairs(Teams) do
			if teamData.spawnNodeId == nodeId then
				isSpawnNode = true
				break
			end
		end
		if not isSpawnNode then
			Team.SetNodeOwner(nodeId, nil)
		end
		return
	end

	-- Count teams with troops
	local teamsWithTroops = {}
	for teamName, count in pairs(troops) do
		if count > 0 then
			table.insert(teamsWithTroops, teamName)
		end
	end

	if #teamsWithTroops == 0 then
		-- No troops = neutral (unless spawn node)
		local isSpawnNode = false
		for _, teamData in pairs(Teams) do
			if teamData.spawnNodeId == nodeId then
				isSpawnNode = true
				break
			end
		end
		if not isSpawnNode then
			Team.SetNodeOwner(nodeId, nil)
		end
	elseif #teamsWithTroops == 1 then
		-- Only one team = they own it
		Team.SetNodeOwner(nodeId, teamsWithTroops[1])
	end
	-- If multiple teams, ownership stays with whoever had it (contested)
end

--[[
	SPAWN MANAGEMENT
]]

function Team.SetSpawnNode(teamName, nodeId)
	local teamData = Teams[teamName]
	if teamData then
		teamData.spawnNodeId = nodeId
		-- Remove neutral troops from spawn node
		Team.SetNodeTroops(nodeId, 0, "Neutral")
		Team.SetNodeOwner(nodeId, teamName)
		return true
	end
	return false
end

function Team.GetSpawnNode(teamName)
	local teamData = Teams[teamName]
	if teamData then
		return teamData.spawnNodeId
	end
	return nil
end

--[[
	SERIALIZATION
]]

function Team.SerializeForClient()
	-- Floor troop counts for client display (server keeps decimals for production)
	-- Now returns per-team troops: nodeTroops[nodeId] = { Red = 50, Blue = 30 }
	local flooredTroops = {}
	for nodeIdStr, teamTroops in pairs(NodeTroops) do
		flooredTroops[nodeIdStr] = {}
		for teamName, count in pairs(teamTroops) do
			if count > 0 then
				flooredTroops[nodeIdStr][teamName] = math.floor(count)
			end
		end
	end

	-- Returns node ownership and troop data for clients
	return {
		nodeOwnership = NodeOwnership,
		nodeTroops = flooredTroops,
		spawns = {
			Red = Teams.Red.spawnNodeId,
			Blue = Teams.Blue.spawnNodeId,
			Green = Teams.Green.spawnNodeId,
			Yellow = Teams.Yellow.spawnNodeId,
		}
	}
end

--[[
	LIFECYCLE
]]

function Team.Init()
	-- Get reference to ServerModule from Packager
	local Packager = require(game.ReplicatedStorage.Packager)
	ServerModule = Packager.Get("ServerModule")
end

function Team.Start()
end

return Team
