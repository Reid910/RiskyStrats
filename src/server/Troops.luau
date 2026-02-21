--[[
	Troops Module
	Manages moving troops between nodes, pathfinding, and ownership updates

	Troop movement uses a segment-based model:
	- fromNode: The node we just left
	- toNode: The node we're heading to
	- progress: 0-1 how far along the current segment
	- remainingPath: Array of nodes after toNode (if any)
]]

local Troops = {
	Name = "Troops",
	Moving = {} -- Array of moving troop data
}

local Packager = nil
local MapGeneration = nil
local Team = nil
local AStar = nil
local NetworkBatch = nil
local Player = nil
local TroopConfig = nil

function Troops.Init()
	Packager = require(game.ReplicatedStorage.Packager)
	MapGeneration = Packager.Get("MapGeneration")
	Team = Packager.Get("Team")
	AStar = Packager.Get("AStar")
	NetworkBatch = Packager.Get("NetworkBatch")
	Player = Packager.Get("Player")
	TroopConfig = Packager.Get("TroopConfig")
end

function Troops.Start()
	-- Start the movement update loop
	game:GetService("RunService").Heartbeat:Connect(Troops.UpdateMovingTroops)
end

--[[
	Send troops from multiple nodes to a target node
	@param player - The player sending troops
	@param fromNodeIds - Array of node IDs to send from
	@param toNodeId - Target node ID
	@param amount - Flat amount of troops to send from each node (sends as much as possible up to this amount)
]]
function Troops.SendTroops(player, fromNodeIds, toNodeId, amount)
	if not player or not player.Team then
		warn("Player has no team")
		return
	end

	local playerTeam = player.Team.Name
	amount = amount or 999999 -- Default to sending all available

	-- Validate target node
	local targetNode = MapGeneration.GetNodeById(toNodeId)
	if not targetNode then
		warn(`Target node {toNodeId} not found`)
		return
	end

	-- Process each source node
	for _, fromNodeId in ipairs(fromNodeIds) do
		local sourceNode = MapGeneration.GetNodeById(fromNodeId)
		if not sourceNode then
			warn(`Source node {fromNodeId} not found`)
			continue
		end

		-- Check if player owns this node OR has troops there (contested node)
		local owner = Team.GetNodeOwner(fromNodeId)
		local playerTroopsOnNode = Team.GetNodeTroops(fromNodeId, playerTeam)
		if owner ~= playerTeam and playerTroopsOnNode <= 0 then
			warn(`Player {player.Name} has no troops on node {fromNodeId}`)
			continue
		end

		-- Don't send to self
		if fromNodeId == toNodeId then
			continue
		end

		-- Calculate troops to send
		local currentTroops = Team.GetNodeTroops(fromNodeId, playerTeam)
		if currentTroops < 1 then
			continue
		end

		-- On owned nodes, leave at least 1 behind; on contested nodes, can send all
		local minKeep = (owner == playerTeam) and 1 or 0
		local troopsToSend = math.min(amount, currentTroops - minKeep)

		if troopsToSend < 1 then
			continue
		end

		-- Find path using A*
		local path = AStar.FindPath(sourceNode, targetNode, MapGeneration)
		if not path or #path < 2 then
			warn(`No path found from node {fromNodeId} to {toNodeId}`)
			continue
		end

		-- Remove troops from source node
		Team.RemoveNodeTroops(fromNodeId, troopsToSend, playerTeam)

		-- Calculate speed based on troop count
		local speed = TroopConfig.GetTroopSpeed(troopsToSend)

		-- Build remaining path (nodes after the second one)
		local remainingPath = {}
		for i = 3, #path do
			table.insert(remainingPath, path[i])
		end

		-- Create moving troop entry with segment-based model
		local movingTroop = {
			fromNode = path[1],        -- Starting node
			toNode = path[2],          -- First destination
			progress = 0,              -- 0 to 1 along current segment
			remainingPath = remainingPath,
			originNodeId = fromNodeId, -- Where we started (for retreat)
			finalDestId = toNodeId,    -- Ultimate destination
			team = playerTeam,
			troopCount = troopsToSend,
			speed = speed,
		}

		-- Generate unique ID for this troop movement
		local troopId = `{playerTeam}_{fromNodeId}_{toNodeId}_{os.clock()}`
		movingTroop.id = troopId

		table.insert(Troops.Moving, movingTroop)
	end

	-- Update fog of war for affected players
	Troops.UpdateFogOfWarForNodes(fromNodeIds)
end

--[[
	Retreat troops within a specific area
	@param player - The player retreating troops
	@param centerX - Center X position of retreat area
	@param centerZ - Center Z position of retreat area
	@param radius - Radius of retreat area (0 for single-point retreat)
]]
function Troops.RetreatTroops(player, centerX, centerZ, radius)
	if not player or not player.Team then
		warn("Player has no team")
		return
	end

	local playerTeam = player.Team.Name
	local retreatedCount = 0

	-- Find all troops owned by this player within the radius
	for _, troop in ipairs(Troops.Moving) do
		-- Only retreat own troops
		if troop.team ~= playerTeam then
			continue
		end

		-- Get current position of the troop (interpolate between fromNode and toNode)
		local currentX = troop.fromNode.x + (troop.toNode.x - troop.fromNode.x) * troop.progress
		local currentZ = troop.fromNode.z + (troop.toNode.z - troop.fromNode.z) * troop.progress

		-- Check if within radius
		local dx = currentX - centerX
		local dz = currentZ - centerZ
		local distSq = dx * dx + dz * dz

		if distSq <= (radius * radius) then
			-- Reverse direction: swap fromNode and toNode, invert progress
			local oldFromNode = troop.fromNode
			local oldToNode = troop.toNode

			troop.fromNode = oldToNode
			troop.toNode = oldFromNode
			troop.progress = 1 - troop.progress

			-- Just go to the node we came from, no pathfinding
			troop.remainingPath = {}
			troop.finalDestId = oldFromNode.id
			troop.originNodeId = oldToNode.id

			retreatedCount = retreatedCount + 1
		end
	end
end

--[[
	Combine friendly troops going to the same destination when within range
	Merges smaller troop into larger troop (keeps bigger troop's ID)
]]
local function CombineTroops()
	-- Distance in map units (multiply by expansion for world studs)
	-- 0.2 map units = ~1 world stud with expansion of 5
	local COMBINE_DISTANCE_SQ = 0.2 * 0.2

	-- Build list of troops to remove after combining
	local troopsToRemove = {}

	for i, troopA in ipairs(Troops.Moving) do
		if troopsToRemove[i] then continue end

		for j, troopB in ipairs(Troops.Moving) do
			if i >= j then continue end
			if troopsToRemove[j] then continue end

			-- Must be same team and same destination
			if troopA.team ~= troopB.team then continue end
			if troopA.finalDestId ~= troopB.finalDestId then continue end

			-- Calculate current positions
			local posAX = troopA.fromNode.x + (troopA.toNode.x - troopA.fromNode.x) * troopA.progress
			local posAZ = troopA.fromNode.z + (troopA.toNode.z - troopA.fromNode.z) * troopA.progress
			local posBX = troopB.fromNode.x + (troopB.toNode.x - troopB.fromNode.x) * troopB.progress
			local posBZ = troopB.fromNode.z + (troopB.toNode.z - troopB.fromNode.z) * troopB.progress

			local dx = posAX - posBX
			local dz = posAZ - posBZ
			local distSq = dx * dx + dz * dz

			if distSq <= COMBINE_DISTANCE_SQ then
				-- Merge smaller into larger (keep larger troop's ID and position)
				local larger, smaller, smallerIdx
				if troopA.troopCount >= troopB.troopCount then
					larger, smaller, smallerIdx = troopA, troopB, j
				else
					larger, smaller, smallerIdx = troopB, troopA, i
				end

				-- Combine into larger troop
				larger.troopCount = larger.troopCount + smaller.troopCount
				-- Recalculate speed based on new troop count (larger armies move slower)
				larger.speed = TroopConfig.GetTroopSpeed(larger.troopCount)
				troopsToRemove[smallerIdx] = true
			end
		end
	end

	-- Remove combined troops (iterate backwards to preserve indices)
	for i = #Troops.Moving, 1, -1 do
		if troopsToRemove[i] then
			table.remove(Troops.Moving, i)
		end
	end
end

--[[
	Check for collisions between opposing troops on the same road
	Smaller army gets pushed back to where it came from
]]
local function CheckTroopCollisions()
	local troopsToRetreat = {}

	for i, troopA in ipairs(Troops.Moving) do
		for j, troopB in ipairs(Troops.Moving) do
			if i >= j then continue end -- Skip self and already-checked pairs

			-- Skip friendly troops
			if troopA.team == troopB.team then continue end

			-- Check if on same road segment going opposite directions
			local sameRoad = (troopA.fromNode.id == troopB.toNode.id and troopA.toNode.id == troopB.fromNode.id)
			if not sameRoad then continue end

			-- Calculate positions on the road (0 to 1)
			-- troopA goes from 0 to 1, troopB goes from 1 to 0 (opposite direction)
			local posA = troopA.progress
			local posB = 1 - troopB.progress -- Flip since they're going opposite ways

			-- Only collide if approaching (posA < posB) and close enough
			local approaching = posA < posB
			local distance = math.abs(posA - posB)
			if distance < 0.1 and approaching then
				-- Collision! Smaller army retreats back to where it came from
				if troopA.troopCount < troopB.troopCount then
					troopsToRetreat[troopA] = troopA.fromNode -- Retreat to where it came from
				elseif troopB.troopCount < troopA.troopCount then
					troopsToRetreat[troopB] = troopB.fromNode
				else
					-- Equal size - both retreat to where they came from
					troopsToRetreat[troopA] = troopA.fromNode
					troopsToRetreat[troopB] = troopB.fromNode
				end
			end
		end
	end

	-- Apply retreats - each troop goes back to where it came from
	for troop in pairs(troopsToRetreat) do
		-- Reverse direction
		local oldFromNode = troop.fromNode
		local oldToNode = troop.toNode

		troop.fromNode = oldToNode
		troop.toNode = oldFromNode
		troop.progress = 1 - troop.progress

		-- Goal is to return to where we originally came from (the node we were leaving)
		troop.remainingPath = {}
		troop.finalDestId = oldFromNode.id
		troop.originNodeId = oldToNode.id
	end
end

--[[
	Update all moving troops
]]
function Troops.UpdateMovingTroops(deltaTime)
	-- Combine nearby friendly troops going to same destination
	CombineTroops()

	-- Check for collisions with enemy troops
	CheckTroopCollisions()

	for i = #Troops.Moving, 1, -1 do
		local troop = Troops.Moving[i]

		if not troop.fromNode or not troop.toNode then
			-- Invalid state, remove
			table.remove(Troops.Moving, i)
			continue
		end

		-- Calculate distance between nodes
		local distance = math.sqrt(
			(troop.toNode.x - troop.fromNode.x) ^ 2 +
			(troop.toNode.z - troop.fromNode.z) ^ 2
		)

		-- Update progress
		if distance > 0 then
			troop.progress += (troop.speed * deltaTime) / distance
		else
			troop.progress = 1 -- Same position, instantly arrive
		end

		if troop.progress >= 1 then
			-- Reached toNode
			local arrivedNodeId = troop.toNode.id

			-- Check if there are more nodes in the path
			if #troop.remainingPath > 0 then
				-- Check if we can continue (must own intermediate nodes or be at destination)
				local intermediateOwner = Team.GetNodeOwner(arrivedNodeId)

				if arrivedNodeId == troop.finalDestId or intermediateOwner == troop.team then
					-- Continue to next node
					troop.fromNode = troop.toNode
					troop.toNode = table.remove(troop.remainingPath, 1)
					troop.progress = 0
				else
					-- Can't continue through unowned/enemy territory, stop here
					Troops.HandleTroopArrival(troop, arrivedNodeId)
					table.remove(Troops.Moving, i)
					Troops.UpdateFogOfWarForNodes({arrivedNodeId})
				end
			else
				-- No more nodes, arrived at final destination
				Troops.HandleTroopArrival(troop, arrivedNodeId)
				table.remove(Troops.Moving, i)
			end
		end
	end
end

--[[
	Handle troops arriving at a node
	Now adds troops to the node - combat is resolved gradually in ServerModule
	@param troop - The troop data
	@param nodeId - The node ID where troops arrived
]]
function Troops.HandleTroopArrival(troop, nodeId)
	local currentOwner = Team.GetNodeOwner(nodeId)

	-- Simply add troops for this team to the node
	-- Combat between teams is handled by the combat loop in ServerModule
	Team.AddNodeTroops(nodeId, troop.troopCount, troop.team)

	-- If node was neutral (no owner), claim it
	if not currentOwner then
		Team.SetNodeOwner(nodeId, troop.team)
	end

	-- Update fog of war for all players who can see this node
	Troops.UpdateFogOfWarForNodes({nodeId})
end

--[[
	Update fog of war for all players that can see the affected nodes
]]
function Troops.UpdateFogOfWarForNodes(nodeIds)
	local Players = game:GetService("Players")

	for _, player in ipairs(Players:GetPlayers()) do
		local playerTeam = Player.GetTeam(player)
		if not playerTeam then continue end

		-- Check if any of these nodes are visible to this player
		local ownedNodes = Team.GetOwnedNodes(playerTeam)
		local visibleNodeIds = {}

		for _, ownedNodeId in ipairs(ownedNodes) do
			visibleNodeIds[ownedNodeId] = true
			local node = MapGeneration.GetNodeById(ownedNodeId)
			if node then
				for _, connectedId in ipairs(node.connections) do
					visibleNodeIds[connectedId] = true
				end
			end
		end

		-- Check if any affected node is visible
		local shouldUpdate = false
		for _, nodeId in ipairs(nodeIds) do
			if visibleNodeIds[nodeId] then
				shouldUpdate = true
				break
			end
		end

		if shouldUpdate then
			-- Send updated map data
			local visibleMapData = MapGeneration.SerializeForPlayer(player, playerTeam)
			NetworkBatch.SendImmediate(NetworkBatch.EventType.MapUpdate, visibleMapData, player)
		end
	end
end

--[[
	Clear all moving troops (for game reset)
]]
function Troops.ClearAllTroops()
	table.clear(Troops.Moving)
end

--[[
	Clear all troops belonging to a specific team (when team is eliminated)
]]
function Troops.ClearTeamTroops(teamName)
	for i = #Troops.Moving, 1, -1 do
		if Troops.Moving[i].team == teamName then
			table.remove(Troops.Moving, i)
		end
	end
end

return Troops
