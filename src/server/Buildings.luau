--[[
	Buildings Module
	Manages buildings on nodes (placement, production, etc.)
]]

local Buildings = {
	Name = "Buildings"
}

local Packager = nil
local Team = nil
local BuildingConfig = nil
local ServerModule = nil
local MapGeneration = nil

-- Building data: [nodeId] = { type = "Factory", owner = "Red" }
local NodeBuildings = {}

-- Production timing (synchronized every second)
local PRODUCTION_INTERVAL = 0.2 -- Produce once per second
local ProductionTimer = 0

function Buildings.Init()
	Packager = require(game.ReplicatedStorage.Packager)
	Team = Packager.Get("Team")
	BuildingConfig = Packager.Get("BuildingConfig")
	ServerModule = Packager.Get("ServerModule")
	MapGeneration = Packager.Get("MapGeneration")
end

function Buildings.Start()
	-- Start production loop
	local RunService = game:GetService("RunService")
	RunService.Heartbeat:Connect(Buildings.UpdateProduction)
end

--[[
	Place a building on a node
	@param player - Player placing the building
	@param nodeId - Node to place on
	@param buildingType - Type of building (e.g., "Factory")
]]
function Buildings.PlaceBuilding(player, nodeId, buildingType)
	local playerTeam = player.Team and player.Team.Name
	if not playerTeam then
		warn("Player has no team")
		return false
	end

	-- Check if player owns the node
	local owner = Team.GetNodeOwner(nodeId)
	if owner ~= playerTeam then
		warn(`Player doesn't own node {nodeId}`)
		return false
	end

	-- Check if node already has a building
	local nodeIdStr = tostring(nodeId)
	local existingBuilding = NodeBuildings[nodeIdStr]
	if existingBuilding then
		-- Spawn/Capitol buildings cannot be replaced
		if existingBuilding.type == "Spawn" then
			warn(`Cannot build on Capitol node {nodeId}`)
			return false
		elseif existingBuilding.type == buildingType then
			warn(`Node {nodeId} already has a {buildingType}`)
			return false
		end
		-- Allow replacing existing building (will be overwritten below)
		print(`Replacing {existingBuilding.type} with {buildingType} on node {nodeId}`)
	end

	-- Get building config
	local buildingData = BuildingConfig.GetBuildingType(buildingType)
	if not buildingData then
		warn(`Invalid building type: {buildingType}`)
		return false
	end

	-- Check if player has enough troops (must leave at least 1 behind)
	local currentTroops = Team.GetNodeTroops(nodeId, playerTeam)
	if currentTroops - buildingData.cost < 1 then
		warn(`Not enough troops to build {buildingType} (need {buildingData.cost + 1}, have {currentTroops})`)
		return false
	end

	-- Deduct cost
	Team.RemoveNodeTroops(nodeId, buildingData.cost, playerTeam)

	-- Place building
	NodeBuildings[nodeIdStr] = {
		type = buildingType,
		owner = playerTeam,
		nodeId = nodeId,
	}

	-- Mark node as changed for network updates
	if ServerModule then
		ServerModule.MarkNodeChanged(nodeId)
	end

	print(`{playerTeam} built {buildingType} on node {nodeId}`)
	return true
end

--[[
	Remove a building from a node (e.g., when node changes ownership)
]]
function Buildings.RemoveBuilding(nodeId)
	local nodeIdStr = tostring(nodeId)
	if NodeBuildings[nodeIdStr] then
		NodeBuildings[nodeIdStr] = nil

		-- Mark node as changed for network updates
		if ServerModule then
			ServerModule.MarkNodeChanged(nodeId)
		end
	end
end

--[[
	Get building on a node
]]
function Buildings.GetBuilding(nodeId)
	local nodeIdStr = tostring(nodeId)
	return NodeBuildings[nodeIdStr]
end

--[[
	Get production boost from connected Powerplants
]]
local function GetPowerplantBoost(nodeId)
	local node = MapGeneration.GetNodeById(nodeId)
	if not node then return 0 end

	local totalBoost = 0
	for _, connectedId in ipairs(node.connections) do
		local connectedIdStr = tostring(connectedId)
		local connectedBuilding = NodeBuildings[connectedIdStr]
		if connectedBuilding and connectedBuilding.type == "Powerplant" then
			local powerplantConfig = BuildingConfig.GetBuildingType("Powerplant")
			if powerplantConfig and powerplantConfig.productionBoost then
				totalBoost = totalBoost + powerplantConfig.productionBoost
			end
		end
	end

	return totalBoost
end

--[[
	Production loop - runs every frame, but only produces once per second
]]
function Buildings.UpdateProduction(deltaTime)
	-- Accumulate time
	ProductionTimer += deltaTime

	-- Only produce once per second (synchronized)
	if ProductionTimer < PRODUCTION_INTERVAL then
		return
	else -- Reset timer (keeping any overflow for accuracy)
		ProductionTimer = ProductionTimer - PRODUCTION_INTERVAL
	end

	-- Process all buildings
	for nodeIdStr, building in pairs(NodeBuildings) do
		local nodeId = tonumber(nodeIdStr)
		if not nodeId then continue end

		-- Sync building owner with node owner (buildings stay on nodes)
		local currentOwner = Team.GetNodeOwner(nodeId)
		if currentOwner and currentOwner ~= building.owner then
			-- Node changed hands, update building owner
			building.owner = currentOwner
		end

		-- Only produce if node has an owner
		if not currentOwner then continue end

		-- Get building type config
		local buildingData = BuildingConfig.GetBuildingType(building.type)
		if not buildingData then continue end

		-- Calculate production (base rate + powerplant boost for factories)
		local productionRate = buildingData.productionRate or 0

		-- Factories get boost from connected Powerplants
		if building.type == "Factory" or building.type == "Spawn" then
			productionRate = productionRate + GetPowerplantBoost(nodeId)
		end

		-- Produce troops (1 second worth since we produce once per second)
		if productionRate > 0 then
			Team.AddNodeTroops(nodeId, productionRate, currentOwner)
		end
	end
end

--[[
	Serialize buildings for client
]]
function Buildings.SerializeForClient()
	-- Return a copy of NodeBuildings
	local buildings = {}
	for nodeIdStr, building in pairs(NodeBuildings) do
		buildings[nodeIdStr] = {
			type = building.type,
			owner = building.owner,
		}
	end
	return buildings
end

--[[
	Clear all buildings (for map reset)
]]
function Buildings.ClearAllBuildings()
	table.clear(NodeBuildings)
end

--[[
	Auto-place spawn buildings on team spawn nodes
	Called after map generation
]]
function Buildings.PlaceSpawnBuildings()
	local allTeams = Team.GetAllTeams()
	for _, teamName in ipairs(allTeams) do
		local spawnNodeId = Team.GetSpawnNode(teamName)
		if spawnNodeId then
			local nodeIdStr = tostring(spawnNodeId)
			-- Place spawn building (no cost check needed)
			NodeBuildings[nodeIdStr] = {
				type = "Spawn",
				owner = teamName,
				nodeId = spawnNodeId,
			}

			-- Mark node as changed for network updates
			if ServerModule then
				ServerModule.MarkNodeChanged(spawnNodeId)
			end
		end
	end
end

return Buildings
