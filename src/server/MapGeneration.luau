--[[
	Map Generation Module
	Generates a procedural network of connected nodes using noise-based placement
]]

local MapGeneration = {
	Name = "MapGeneration"
}

-- Configuration
local Config = {
	ExpansionMultiplier = 5,
	MinDistance = 0.65,
	MaxDistance = 2,
	MinConnections = 3,
	MaxConnections = 8,
	ChunkSize = 5,
	FogOfWarDistance = 4, -- How many hops away from owned nodes players can see (ghost nodes)
}

-- State
local State = {
	Seed = nil,
	Random = Random.new(),
	IsGenerated = false,
	NodeCount = 0,
	Nodes = {}, -- Array of all nodes
	NodesByChunk = {}, -- Spatial partitioning for optimization
}

-- Node structure: { id, x, z, color, connections = {} }

--[[
	UTILITY FUNCTIONS
]]

local function GetChunkKey(x, z)
	return math.floor(x / Config.ChunkSize) .. "_" .. math.floor(z / Config.ChunkSize)
end

local function GetChunk(x, z)
	local key = GetChunkKey(x, z)
	if not State.NodesByChunk[key] then
		State.NodesByChunk[key] = {}
	end
	return State.NodesByChunk[key]
end

local function GetSurroundingChunks(x, z)
	local chunks = {}
	for offsetX = -1, 1 do
		for offsetZ = -1, 1 do
			local chunkX = x + (offsetX * Config.ChunkSize)
			local chunkZ = z + (offsetZ * Config.ChunkSize)
			table.insert(chunks, GetChunk(chunkX, chunkZ))
		end
	end
	return chunks
end

local function GetDistance(x1, z1, x2, z2)
	local dx = x2 - x1
	local dz = z2 - z1
	return math.sqrt(dx * dx + dz * dz)
end

local function IsInCircle(x, z, radius)
	return GetDistance(x, z, 0, 0) <= radius
end

--[[
	NODE MANAGEMENT
]]

local function CreateNode(x, z, color)
	State.NodeCount += 1
	local node = {
		id = State.NodeCount,
		x = x,
		z = z,
		color = color,
		connections = {}, -- Array of connected node IDs
	}

	table.insert(State.Nodes, node)

	local chunk = GetChunk(x, z)
	table.insert(chunk, node)

	-- Set default 25 neutral troops (will be overridden for spawn nodes)
	local Packager = require(game.ReplicatedStorage.Packager)
	local Team = Packager.Get("Team")
	Team.SetNodeTroops(node.id, 25, "Neutral")

	return node
end

local function IsPositionTooClose(x, z, minDistance)
	minDistance = minDistance or Config.MinDistance
	local chunks = GetSurroundingChunks(x, z)

	for _, chunk in ipairs(chunks) do
		for _, node in ipairs(chunk) do
			if GetDistance(x, z, node.x, node.z) < minDistance then
				return true
			end
		end
	end

	return false
end

local function GetNodesInRange(x, z, maxDistance)
	maxDistance = maxDistance or Config.MaxDistance
	local nearbyNodes = {}
	local chunks = GetSurroundingChunks(x, z)

	for _, chunk in ipairs(chunks) do
		for _, node in ipairs(chunk) do
			local distance = GetDistance(x, z, node.x, node.z)
			if distance <= maxDistance then
				table.insert(nearbyNodes, {
					node = node,
					distance = distance
				})
			end
		end
	end

	-- Sort by distance (closest first)
	table.sort(nearbyNodes, function(a, b)
		return a.distance < b.distance
	end)

	return nearbyNodes
end

local function ConnectNodes(nodeA, nodeB)
	-- Avoid duplicate connections
	if table.find(nodeA.connections, nodeB.id) then
		return
	end

	table.insert(nodeA.connections, nodeB.id)
	table.insert(nodeB.connections, nodeA.id)
end

local function DeleteNode(node)
	-- Remove connections to this node from other nodes
	for _, connectedId in ipairs(node.connections) do
		local connectedNode = State.Nodes[connectedId]
		if connectedNode then
			local index = table.find(connectedNode.connections, node.id)
			if index then
				table.remove(connectedNode.connections, index)
			end
		end
	end

	-- Remove from chunk
	local chunk = GetChunk(node.x, node.z)
	local index = table.find(chunk, node)
	if index then
		table.remove(chunk, index)
	end

	-- Mark as deleted (don't remove from Nodes array to preserve IDs)
	node.deleted = true
	-- State.NodeCount -= 1
end

local function GetConnectionCount(node)
	return #node.connections
end

--[[
	MAP GENERATION
]]

local function GenerateBaseNodes(size)
	for x = -size, size do
		for z = -size, size do
			-- Only generate within circular area
			if not IsInCircle(x, z, size) then
				continue
			end

			-- Use noise to determine if a node should be placed here
			local noiseY = z == 0 and State.Seed or (State.Seed + x * z)
			local noise = math.noise(x * 100, noiseY, z * 100)

			if noise > 0.3 then
				-- Add some random offset
				local offsetX = math.noise(x * 10, State.Seed + 5, z * 10) / 2
				local offsetZ = math.noise(x * 10, State.Seed - 5, z * 10) / 2

				local finalX = x + offsetX
				local finalZ = z - offsetZ

				if not IsPositionTooClose(finalX, finalZ) then
					CreateNode(finalX, finalZ)
				end
			end
		end
	end
end

local function ExpandNodes(nodesToExpand, iterations)
	local currentSet = nodesToExpand

	for iteration = 1, iterations do
		local newNodes = {}

		for _, node in ipairs(currentSet) do
			if node.deleted then continue end

			-- Get rotation from noise
			local noise = math.noise(node.x * 1000, State.Seed + 1, node.z * 1000) + 0.5
			local angle = math.rad(360 * noise)

			-- Get distance from noise
			local noise2 = math.noise(node.x * 100, State.Seed - 1, node.z * 100) + 0.5
			local distance = (Config.MaxDistance - Config.MinDistance) * noise2 / 2 + Config.MinDistance

			-- Calculate new position
			local newX = node.x + math.cos(angle) * distance
			local newZ = node.z + math.sin(angle) * distance

			if not IsPositionTooClose(newX, newZ) then
				local newNode = CreateNode(newX, newZ)
				table.insert(newNodes, newNode)
			end
		end

		currentSet = newNodes
		State.Seed += 100
	end
end

local function CreateConnections()
	for _, node in ipairs(State.Nodes) do
		if node.deleted then continue end

		local nearbyNodes = GetNodesInRange(node.x, node.z)

		-- Determine target connection count using noise
		local noise = math.clamp(
			math.noise(node.x * 1000, State.Seed, node.z * 1000) + 0.5,
			0,
			1
		)
		local targetConnections = math.floor(
			(Config.MaxConnections - Config.MinConnections) * noise
		) + Config.MinConnections

		-- Connect to nearby nodes
		for _, nearby in ipairs(nearbyNodes) do
			if nearby.node.deleted then continue end
			if nearby.node == node then continue end

			local currentConnections = GetConnectionCount(node)
			if currentConnections >= targetConnections then
				break
			end

			local otherConnections = GetConnectionCount(nearby.node)
			if otherConnections >= targetConnections then
				continue
			end

			ConnectNodes(node, nearby.node)
		end
	end
end

local function RemoveIsolatedNodes()
	for _, node in ipairs(State.Nodes) do
		if node.deleted then continue end

		local connectionCount = GetConnectionCount(node)
		if connectionCount < Config.MinConnections - 1 then
			DeleteNode(node)
		end
	end
end

local function GetConnectedArea(startNode)
	local area = {}
	local queue = {startNode}
	area[startNode.id] = true

	while #queue > 0 do
		local current = table.remove(queue, 1)

		for _, connectedId in ipairs(current.connections) do
			if not area[connectedId] then
				area[connectedId] = true
				local connectedNode = State.Nodes[connectedId]
				if connectedNode and not connectedNode.deleted then
					table.insert(queue, connectedNode)
				end
			end
		end
	end

	return area
end

local function VerifyConnectivity()
	-- Find the largest connected component
	local mainArea = nil
	local otherAreas = {}

	for _, node in ipairs(State.Nodes) do
		if node.deleted then continue end

		-- Check if this node is already in an area
		local inArea = false
		if mainArea and mainArea[node.id] then
			inArea = true
		end
		for _, area in ipairs(otherAreas) do
			if area[node.id] then
				inArea = true
				break
			end
		end

		if not inArea then
			local area = GetConnectedArea(node)
			if not mainArea then
				mainArea = area
			else
				table.insert(otherAreas, area)
			end
		end
	end

	return mainArea, otherAreas
end

local function AssignTeamSpawns()
	-- Find nodes that are far apart to use as spawns
	local allNodes = MapGeneration.GetAllNodes()
	if #allNodes < 2 then
		warn("Not enough nodes to assign spawns")
		return
	end

	-- Find the center of the map
	local centerX, centerZ = 0, 0
	for _, node in ipairs(allNodes) do
		centerX += node.x
		centerZ += node.z
	end
	centerX = centerX / #allNodes
	centerZ = centerZ / #allNodes

	-- Find nodes in different quadrants relative to center
	local quadrants = {
		topRight = {},    -- Red spawn (positive X, positive Z)
		bottomLeft = {},  -- Blue spawn (negative X, negative Z)
		topLeft = {},     -- Green spawn (negative X, positive Z)
		bottomRight = {}, -- Yellow spawn (positive X, negative Z)
	}

	for _, node in ipairs(allNodes) do
		local relX = node.x - centerX
		local relZ = node.z - centerZ

		if relX >= 0 and relZ >= 0 then
			table.insert(quadrants.topRight, node)
		elseif relX < 0 and relZ < 0 then
			table.insert(quadrants.bottomLeft, node)
		elseif relX < 0 and relZ >= 0 then
			table.insert(quadrants.topLeft, node)
		else
			table.insert(quadrants.bottomRight, node)
		end
	end

	-- Get Team module to assign spawns
	local Packager = require(game.ReplicatedStorage.Packager)
	local Team = Packager.Get("Team")

	-- Find the node furthest from center in each quadrant
	local function GetFurthestNode(nodeList)
		local furthest = nil
		local maxDist = 0
		for _, node in ipairs(nodeList) do
			local dist = GetDistance(node.x, node.z, centerX, centerZ)
			if dist > maxDist then
				maxDist = dist
				furthest = node
			end
		end
		return furthest
	end

	-- Note: Neutral nodes start with no troops (they're neutral)
	-- Teams will need to capture them

	-- Assign spawn nodes
	local redSpawn = GetFurthestNode(quadrants.topRight)
	local blueSpawn = GetFurthestNode(quadrants.bottomLeft)
	local greenSpawn = GetFurthestNode(quadrants.topLeft)
	local yellowSpawn = GetFurthestNode(quadrants.bottomRight)

	if redSpawn then
		Team.SetSpawnNode("Red", redSpawn.id)
		Team.SetNodeTroops(redSpawn.id, 100, "Red")
	end
	if blueSpawn then
		Team.SetSpawnNode("Blue", blueSpawn.id)
		Team.SetNodeTroops(blueSpawn.id, 100, "Blue")
	end
	if greenSpawn then
		Team.SetSpawnNode("Green", greenSpawn.id)
		Team.SetNodeTroops(greenSpawn.id, 100, "Green")
	end
	if yellowSpawn then
		Team.SetSpawnNode("Yellow", yellowSpawn.id)
		Team.SetNodeTroops(yellowSpawn.id, 100, "Yellow")
	end

	-- Debug output
	-- print(`[DEBUG] Assigned spawns: Red={redSpawn and redSpawn.id or "none"}, Blue={blueSpawn and blueSpawn.id or "none"}, Green={greenSpawn and greenSpawn.id or "none"}, Yellow={yellowSpawn and yellowSpawn.id or "none"}`)
end

--[[
	PUBLIC API
]]

function MapGeneration.Init()
end

function MapGeneration.Start()
end

function MapGeneration.ClearMap()
	State.IsGenerated = false
	State.NodeCount = 0
	State.Nodes = {}
	table.clear(State.NodesByChunk)
end

function MapGeneration.Generate(size)
	size = size or 10

	MapGeneration.ClearMap()

	-- Generate seed
	State.Seed = math.log(State.Random:NextNumber(11111, 99999), 2) * 100

	-- Generate base layer
	GenerateBaseNodes(size)

	-- Check if we generated any nodes
	if State.NodeCount == 0 then
		task.wait(0.1)
		return MapGeneration.Generate(size)
	end

	-- Expand nodes in chunks
	for x = -size, size, Config.ChunkSize do
		for z = -size, size, Config.ChunkSize do
			local chunk = GetChunk(x, z)
			if #chunk > 0 then
				ExpandNodes(chunk, 5)
			end
		end
	end

	-- Additional expansion passes
	for _ = 1, 6 do
		ExpandNodes(State.Nodes, 1)
		State.Seed += 250
	end

	-- Create connections FIRST
	CreateConnections()

	-- THEN remove poorly connected nodes
	RemoveIsolatedNodes()

	-- Final cleanup
	for _, node in ipairs(State.Nodes) do
		if node.deleted then continue end

		if GetConnectionCount(node) == 0 then
			DeleteNode(node)
		end
	end

	-- Verify connectivity
	VerifyConnectivity()

	-- Assign spawn nodes for teams
	AssignTeamSpawns()

	State.IsGenerated = true

	return true
end

function MapGeneration.SerializeForClient()
	local nodes = {}
	local roads = {}

	-- Get Team module for team data
	local Packager = require(game.ReplicatedStorage.Packager)
	local Team = Packager.Get("Team")

	-- Collect nodes
	for _, node in ipairs(State.Nodes) do
		if node.deleted then continue end

		table.insert(nodes, {
			id = node.id,
			x = node.x,
			z = node.z,
			color = node.color
		})
	end

	-- Collect connections (roads)
	local processedPairs = {}
	for _, node in ipairs(State.Nodes) do
		if node.deleted then continue end

		for _, connectedId in ipairs(node.connections) do
			-- Avoid duplicates by checking both directions
			local pairKey = math.min(node.id, connectedId) .. "_" .. math.max(node.id, connectedId)
			if not processedPairs[pairKey] then
				processedPairs[pairKey] = true

				local connectedNode = State.Nodes[connectedId]
				if connectedNode and not connectedNode.deleted then
					table.insert(roads, {
						from = { x = node.x, z = node.z },
						to = { x = connectedNode.x, z = connectedNode.z }
					})
				end
			end
		end
	end

	-- Get team data
	local teamData = Team.SerializeForClient()

	-- Get all moving troops (spectators see everything)
	local Troops = Packager.Get("Troops")
	local allTroops = {}
	for _, troop in ipairs(Troops.Moving) do
		-- Serialize remaining path to coordinates
		local remainingCoords = {}
		for _, node in ipairs(troop.remainingPath) do
			table.insert(remainingCoords, {x = node.x, z = node.z})
		end

		table.insert(allTroops, {
			id = troop.id,
			team = troop.team,
			troopCount = math.floor(troop.troopCount),
			fromNode = {x = troop.fromNode.x, z = troop.fromNode.z},
			toNode = {x = troop.toNode.x, z = troop.toNode.z},
			remainingPath = remainingCoords,
			progress = troop.progress,
			finalDestId = troop.finalDestId,
		})
	end

	-- Get buildings data
	local Buildings = Packager.Get("Buildings")
	local buildings = Buildings.SerializeForClient()

	return {
		nodes = nodes,
		roads = roads,
		teamData = teamData,
		movingTroops = allTroops,
		buildings = buildings
	}
end

function MapGeneration.GetNodeById(id)
	return State.Nodes[id]
end

function MapGeneration.GetAllNodes()
	local nodes = {}
	for _, node in ipairs(State.Nodes) do
		if not node.deleted then
			table.insert(nodes, node)
		end
	end
	return nodes
end

function MapGeneration.GetConfig()
	return Config
end

function MapGeneration.SerializeForPlayer(player, playerTeam)
	-- Returns only nodes visible to this player (fog of war)
	-- Players can see nodes owned by their team + connected neighbors
	-- Spectators (no team) can see everything

	local Packager = require(game.ReplicatedStorage.Packager)
	local Team = Packager.Get("Team")

	-- If no team (spectator), return full map
	if not playerTeam then
		return MapGeneration.SerializeForClient()
	end

	-- Get nodes owned by player's team
	local ownedNodes = Team.GetOwnedNodes(playerTeam)
	local visibleNodeIds = {} -- All nodes player can see (structure)
	local infoVisibleNodeIds = {} -- Nodes where player can see troop counts/ownership

	-- BFS to find all nodes within FogOfWarDistance hops
	local queue = {} -- {nodeId, distance}
	local visited = {}

	-- Start with owned nodes at distance 0
	for _, nodeId in ipairs(ownedNodes) do
		table.insert(queue, {nodeId = nodeId, distance = 0})
		visited[nodeId] = true
		visibleNodeIds[nodeId] = true
		infoVisibleNodeIds[nodeId] = true -- Can see info for owned nodes
	end

	-- Process queue
	while #queue > 0 do
		local current = table.remove(queue, 1)

		-- If we haven't reached max distance, add neighbors
		if current.distance < Config.FogOfWarDistance then
			local node = State.Nodes[current.nodeId]
			if node and not node.deleted then
				for _, connectedId in ipairs(node.connections) do
					if not visited[connectedId] then
						visited[connectedId] = true
						visibleNodeIds[connectedId] = true

						-- Only show info for nodes 1 hop away from owned nodes
						if current.distance == 0 then
							infoVisibleNodeIds[connectedId] = true
						end

						table.insert(queue, {nodeId = connectedId, distance = current.distance + 1})
					end
				end
			end
		end
	end

	-- Collect only visible nodes
	local nodes = {}
	for _, node in ipairs(State.Nodes) do
		if node.deleted then continue end
		if not visibleNodeIds[node.id] then continue end

		table.insert(nodes, {
			id = node.id,
			x = node.x,
			z = node.z,
			color = node.color
		})
	end

	-- Collect only roads between visible nodes
	local roads = {}
	local processedPairs = {}
	for _, node in ipairs(State.Nodes) do
		if node.deleted then continue end
		if not visibleNodeIds[node.id] then continue end

		for _, connectedId in ipairs(node.connections) do
			if not visibleNodeIds[connectedId] then continue end

			-- Avoid duplicates
			local pairKey = math.min(node.id, connectedId) .. "_" .. math.max(node.id, connectedId)
			if not processedPairs[pairKey] then
				processedPairs[pairKey] = true

				local connectedNode = State.Nodes[connectedId]
				if connectedNode and not connectedNode.deleted then
					table.insert(roads, {
						from = { x = node.x, z = node.z },
						to = { x = connectedNode.x, z = connectedNode.z }
					})
				end
			end
		end
	end

	-- Get team data (but only for nodes where info is visible)
	local teamData = Team.SerializeForClient()
	local visibleTeamData = {
		nodeOwnership = {},
		nodeTroops = {},
		spawns = teamData.spawns
	}

	-- Filter team data to only nodes where info is visible (owned + 1 hop neighbors)
	-- Ghost nodes (2-4 hops away) won't have ownership/troop data
	for nodeIdStr, owner in pairs(teamData.nodeOwnership) do
		-- Convert string key to number for visibility check
		local nodeId = tonumber(nodeIdStr)
		if nodeId and infoVisibleNodeIds[nodeId] then
			visibleTeamData.nodeOwnership[nodeIdStr] = owner
		end
	end

	for nodeIdStr, troops in pairs(teamData.nodeTroops) do
		-- Convert string key to number for visibility check
		local nodeId = tonumber(nodeIdStr)
		if nodeId and infoVisibleNodeIds[nodeId] then
			visibleTeamData.nodeTroops[nodeIdStr] = troops
		end
	end

	-- Get visible moving troops
	-- Troops are visible if the player owns a node within 1 hop of fromNode, toNode, or remainingPath nodes
	local Troops = Packager.Get("Troops")
	local visibleTroops = {}

	for _, troop in ipairs(Troops.Moving) do
		-- Check if troop is within info visibility (owned + 1 hop)
		local isVisible = false

		-- Check fromNode and toNode
		if infoVisibleNodeIds[troop.fromNode.id] or infoVisibleNodeIds[troop.toNode.id] then
			isVisible = true
		end

		-- Check remaining path nodes
		if not isVisible then
			for _, pathNode in ipairs(troop.remainingPath) do
				if infoVisibleNodeIds[pathNode.id] then
					isVisible = true
					break
				end
			end
		end

		if isVisible then
			-- Serialize remaining path to coordinates
			local remainingCoords = {}
			for _, node in ipairs(troop.remainingPath) do
				table.insert(remainingCoords, {x = node.x, z = node.z})
			end

			table.insert(visibleTroops, {
				id = troop.id,
				team = troop.team,
				troopCount = math.floor(troop.troopCount),
				fromNode = {x = troop.fromNode.x, z = troop.fromNode.z},
				toNode = {x = troop.toNode.x, z = troop.toNode.z},
				remainingPath = remainingCoords,
				progress = troop.progress,
				finalDestId = troop.finalDestId,
			})
		end
	end

	-- Get visible buildings (only nodes where info is visible)
	local Buildings = Packager.Get("Buildings")
	local allBuildings = Buildings.SerializeForClient()
	local visibleBuildings = {}
	for nodeIdStr, building in pairs(allBuildings) do
		local nodeId = tonumber(nodeIdStr)
		if nodeId and infoVisibleNodeIds[nodeId] then
			visibleBuildings[nodeIdStr] = building
		end
	end

	return {
		nodes = nodes,
		roads = roads,
		teamData = visibleTeamData,
		movingTroops = visibleTroops,
		buildings = visibleBuildings
	}
end

--[[
	Configuration helpers
]]
function MapGeneration.SetFogOfWarDistance(distance)
	Config.FogOfWarDistance = math.max(1, math.floor(distance))
	print(`Fog of war distance set to {Config.FogOfWarDistance} hops`)
end

function MapGeneration.GetFogOfWarDistance()
	return Config.FogOfWarDistance
end

return MapGeneration
