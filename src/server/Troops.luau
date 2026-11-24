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
local TroopConfig = nil

-- Event buffer: troop state changes queued each frame, flushed by ServerModule
local TroopEventBuffer = {} -- Array of {type, data}

--[[
	Serialize a moving troop into event data (snapshot at queue time)
]]
local function SerializeTroopForEvent(troop)
	local remainingCoords = {}
	for _, node in ipairs(troop.remainingPath) do
		table.insert(remainingCoords, {x = node.x, z = node.z})
	end
	return {
		id = troop.id,
		team = troop.team,
		troopCount = math.floor(troop.troopCount),
		fromNodeId = troop.fromNode.id,
		toNodeId = troop.toNode.id,
		fromNode = {x = troop.fromNode.x, z = troop.fromNode.z},
		toNode = {x = troop.toNode.x, z = troop.toNode.z},
		remainingPath = remainingCoords,
		progress = troop.progress,
		speed = troop.speed,
	}
end

local function QueueTroopUpdate(troop)
	table.insert(TroopEventBuffer, {
		type = "update",
		data = SerializeTroopForEvent(troop),
	})
end

local function QueueTroopRemove(troopId)
	table.insert(TroopEventBuffer, {
		type = "remove",
		data = {id = troopId},
	})
end

--[[
	Flush all queued troop events (called by ServerModule each frame)
]]
function Troops.FlushTroopEvents()
	local events = TroopEventBuffer
	TroopEventBuffer = {}
	return events
end

function Troops.Init()
	Packager = require(game.ReplicatedStorage.Packager)
	MapGeneration = Packager.Get("MapGeneration")
	Team = Packager.Get("Team")
	AStar = Packager.Get("AStar")
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
--[[
	Core troop sending logic shared by player and AI
]]
local function SendTroopsInternal(teamName, fromNodeIds, toNodeId, amount)
	amount = amount or 999999

	local targetNode = MapGeneration.GetNodeById(toNodeId)
	if not targetNode then
		warn(`Target node {toNodeId} not found`)
		return
	end

	for _, fromNodeId in ipairs(fromNodeIds) do
		local sourceNode = MapGeneration.GetNodeById(fromNodeId)
		if not sourceNode then
			warn(`Source node {fromNodeId} not found`)
			continue
		end

		local owner = Team.GetNodeOwner(fromNodeId)
		local troopsOnNode = Team.GetNodeTroops(fromNodeId, teamName)
		if owner ~= teamName and troopsOnNode <= 0 then
			continue
		end

		if fromNodeId == toNodeId then
			continue
		end

		local currentTroops = Team.GetNodeTroops(fromNodeId, teamName)
		if currentTroops < 1 then
			continue
		end

		local minKeep = (owner == teamName) and 1 or 0
		local troopsToSend = math.min(amount, currentTroops - minKeep)

		if troopsToSend < 1 then
			continue
		end

		local path = AStar.FindPath(sourceNode, targetNode, MapGeneration, function(nodeId)
			return Team.GetNodeOwner(nodeId) == teamName
		end)
		if not path or #path < 2 then
			continue
		end

		if #path == 2 and owner ~= teamName then
			local targetOwner = Team.GetNodeOwner(toNodeId)
			local ourTroopsOnTarget = Team.GetNodeTroops(toNodeId, teamName)
			if targetOwner ~= teamName and ourTroopsOnTarget <= 0 then
				continue
			end
		end

		Team.RemoveNodeTroops(fromNodeId, troopsToSend, teamName)

		local speed = TroopConfig.GetTroopSpeed(troopsToSend)

		local remainingPath = {}
		for i = 3, #path do
			table.insert(remainingPath, path[i])
		end

		local movingTroop = {
			fromNode = path[1],
			toNode = path[2],
			progress = 0,
			remainingPath = remainingPath,
			originNodeId = fromNodeId,
			finalDestId = toNodeId,
			team = teamName,
			troopCount = troopsToSend,
			speed = speed,
		}

		local troopId = `{teamName}_{fromNodeId}_{toNodeId}_{os.clock()}`
		movingTroop.id = troopId

		table.insert(Troops.Moving, movingTroop)
		QueueTroopUpdate(movingTroop)
	end
end

function Troops.SendTroops(player, fromNodeIds, toNodeId, amount)
	if not player or not player.Team then
		warn("Player has no team")
		return
	end
	SendTroopsInternal(player.Team.Name, fromNodeIds, toNodeId, amount)
end

--[[
	Send troops for an AI-controlled team (no player object needed)
]]
function Troops.SendTroopsForTeam(teamName, fromNodeIds, toNodeId, amount)
	SendTroopsInternal(teamName, fromNodeIds, toNodeId, amount)
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

			QueueTroopUpdate(troop)
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

				QueueTroopRemove(smaller.id)
				QueueTroopUpdate(larger)
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

		QueueTroopUpdate(troop)
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
			QueueTroopRemove(troop.id)
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
					QueueTroopUpdate(troop)
				else
					-- Can't continue through unowned/enemy territory, stop here
					Troops.HandleTroopArrival(troop, arrivedNodeId)
					QueueTroopRemove(troop.id)
					table.remove(Troops.Moving, i)
				end
			else
				-- No more nodes, arrived at final destination
				Troops.HandleTroopArrival(troop, arrivedNodeId)
				QueueTroopRemove(troop.id)
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
end

--[[
	Clear all moving troops (for game reset)
]]
function Troops.ClearAllTroops()
	table.insert(TroopEventBuffer, {type = "clear_all"})
	table.clear(Troops.Moving)
end

--[[
	Clear all troops belonging to a specific team (when team is eliminated)
]]
function Troops.ClearTeamTroops(teamName)
	for i = #Troops.Moving, 1, -1 do
		if Troops.Moving[i].team == teamName then
			QueueTroopRemove(Troops.Moving[i].id)
			table.remove(Troops.Moving, i)
		end
	end
end

return Troops
