--[[
	BuildingRenderer
	Renders buildings on nodes
]]

local BuildingRenderer = {
	Name = "BuildingRenderer"
}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packager = nil
local BuildingConfig = nil

-- Track created building visuals: [nodeId] = Model or Part
local CreatedBuildings = {}

local BuildingsFolder = nil
local ModelsFolder = nil

function BuildingRenderer.Init()
	-- Create Buildings folder
	BuildingsFolder = Workspace:FindFirstChild("Buildings")
	if not BuildingsFolder then
		BuildingsFolder = Instance.new("Folder")
		BuildingsFolder.Name = "Buildings"
		BuildingsFolder.Parent = Workspace
	end

	-- Get Models folder (create if needed for reference)
	ModelsFolder = ReplicatedStorage:FindFirstChild("Models")
end

function BuildingRenderer.Start()
	Packager = require(game.ReplicatedStorage.Packager)
	BuildingConfig = Packager.Get("BuildingConfig")
end

--[[
	Create a building visual
]]
function BuildingRenderer.CreateBuilding(nodeId, buildingType, x, z)
	-- Get building config
	local buildingData = BuildingConfig.GetBuildingType(buildingType)
	if not buildingData then
		warn(`Unknown building type: {buildingType}`)
		return
	end

	-- Get expansion multiplier from MapRenderer
	local function GetExpansionMultiplier()
		local MapGenerationModule = Packager.Get("MapGeneration")
		if MapGenerationModule then
			local config = MapGenerationModule.GetConfig()
			return config.ExpansionMultiplier
		end
		return 1
	end

	local multiplier = GetExpansionMultiplier()

	-- Create building part
	local building = Instance.new("Part")
	building.Name = `Building_{nodeId}`
	building.Size = buildingData.size
	-- building.Color = buildingData.color
	building.Transparency = 0.5
	building.Position = Vector3.new(x * multiplier, 0, z * multiplier)
	building.Anchored = true
	building.CanCollide = false
	building.Parent = BuildingsFolder

	-- Store reference
	CreatedBuildings[tostring(nodeId)] = building
end

--[[
	Remove a building visual
]]
function BuildingRenderer.RemoveBuilding(nodeId)
	local nodeIdStr = tostring(nodeId)
	local building = CreatedBuildings[nodeIdStr]
	if building then
		building:Destroy()
		CreatedBuildings[nodeIdStr] = nil
	end
end

--[[
	Sync buildings with server data
]]
function BuildingRenderer.SyncBuildings(buildingsData)
	if not buildingsData then return end

	-- Track which buildings exist on server
	local serverBuildingIds = {}
	for nodeIdStr, _ in pairs(buildingsData) do
		serverBuildingIds[nodeIdStr] = true
	end

	-- Remove buildings that no longer exist
	for nodeIdStr, building in pairs(CreatedBuildings) do
		if not serverBuildingIds[nodeIdStr] then
			building:Destroy()
			CreatedBuildings[nodeIdStr] = nil
		end
	end

	-- Add new buildings
	for nodeIdStr, buildingData in pairs(buildingsData) do
		if not CreatedBuildings[nodeIdStr] then
			local nodeId = tonumber(nodeIdStr)
			if nodeId then
				local nodePart = Workspace.Nodes:FindFirstChild("Node_" .. nodeId)
				if nodePart then
					-- Just use the node's world position directly
					local x = nodePart.Position.X
					local z = nodePart.Position.Z
					BuildingRenderer.CreateBuildingAtWorldPos(nodeId, buildingData.type, x, z)
				end
			end
		end
	end
end

--[[
	Create a building visual at world position (no multiplier needed)
]]
function BuildingRenderer.CreateBuildingAtWorldPos(nodeId, buildingType, worldX, worldZ)
	-- Get building config
	local buildingData = BuildingConfig.GetBuildingType(buildingType)
	if not buildingData then
		warn(`Unknown building type: {buildingType}`)
		return
	end

	local building = nil
	local position = Vector3.new(worldX, 0, worldZ)

	-- Try to use model if available
	if buildingData.model and ModelsFolder then
		local modelTemplate = ModelsFolder:FindFirstChild(buildingData.model)
		if modelTemplate then
			building = modelTemplate:Clone()
			building.Name = `Building_{nodeId}`

			building:PivotTo(CFrame.new(position))

			building.Parent = BuildingsFolder
		end
	end

	-- Fallback to simple part if no model
	if not building then
		building = Instance.new("Part")
		building.Name = `Building_{nodeId}`
		building.Size = buildingData.size
		-- building.Color = buildingData.color
		building.Transparency = 0.5
		building.Position = position
		building.Anchored = true
		building.CanCollide = false
		building.Parent = BuildingsFolder
	end

	-- Store reference
	CreatedBuildings[tostring(nodeId)] = building
end

--[[
	Clear all buildings
]]
function BuildingRenderer.ClearAllBuildings()
	for _, building in pairs(CreatedBuildings) do
		building:Destroy()
	end
	table.clear(CreatedBuildings)
end

return BuildingRenderer
