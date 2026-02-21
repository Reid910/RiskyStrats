--[[
	BuildingRenderer
	Renders buildings on nodes
]]

local BuildingRenderer = {
	Name = "BuildingRenderer"
}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeamColors = require(ReplicatedStorage.Shared.TeamColors)

local Packager = nil
local BuildingConfig = nil

-- Track created building visuals: [nodeId] = { visual = Model or Part, type = string, owner = string }
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
function BuildingRenderer.CreateBuilding(nodeId, buildingType, x, z, owner)
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
	building.Transparency = 0.5
	building.Position = Vector3.new(x * multiplier, 0, z * multiplier)
	building.Anchored = true
	building.CanCollide = false
	building.Parent = BuildingsFolder

	-- Apply team color
	BuildingRenderer.ApplyTeamColor(building, owner)

	-- Store reference with metadata
	CreatedBuildings[tostring(nodeId)] = {
		visual = building,
		type = buildingType,
		owner = owner,
	}
end

--[[
	Remove a building visual
]]
function BuildingRenderer.RemoveBuilding(nodeId)
	local nodeIdStr = tostring(nodeId)
	local buildingEntry = CreatedBuildings[nodeIdStr]
	if buildingEntry then
		if buildingEntry.visual then
			buildingEntry.visual:Destroy()
		end
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
	for nodeIdStr, buildingEntry in pairs(CreatedBuildings) do
		if not serverBuildingIds[nodeIdStr] then
			if buildingEntry.visual then
				buildingEntry.visual:Destroy()
			end
			CreatedBuildings[nodeIdStr] = nil
		end
	end

	-- Add or update buildings
	for nodeIdStr, buildingData in pairs(buildingsData) do
		local existingEntry = CreatedBuildings[nodeIdStr]
		local needsRecreate = false

		if not existingEntry then
			-- New building
			needsRecreate = true
		elseif existingEntry.type ~= buildingData.type then
			-- Building type changed (swapped)
			if existingEntry.visual then
				existingEntry.visual:Destroy()
			end
			CreatedBuildings[nodeIdStr] = nil
			needsRecreate = true
		elseif existingEntry.owner ~= buildingData.owner then
			-- Owner changed, update color
			BuildingRenderer.ApplyTeamColor(existingEntry.visual, buildingData.owner)
			existingEntry.owner = buildingData.owner
		end

		if needsRecreate then
			local nodeId = tonumber(nodeIdStr)
			if nodeId then
				local nodePart = Workspace.Nodes:FindFirstChild("Node_" .. nodeId)
				if nodePart then
					local x = nodePart.Position.X
					local z = nodePart.Position.Z
					BuildingRenderer.CreateBuildingAtWorldPos(nodeId, buildingData.type, x, z, buildingData.owner)
				end
			end
		end
	end
end

--[[
	Apply team color to a building visual
]]
function BuildingRenderer.ApplyTeamColor(visual, owner)
	if not visual or not owner then return end

	local color = TeamColors[owner]
	if not color then return end

	-- Apply color to all parts in the model/part
	if visual:IsA("Model") then
		for _, descendant in ipairs(visual:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Color = color
			end
		end
	elseif visual:IsA("BasePart") then
		visual.Color = color
	end
end

--[[
	Create a building visual at world position (no multiplier needed)
]]
function BuildingRenderer.CreateBuildingAtWorldPos(nodeId, buildingType, worldX, worldZ, owner)
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
		building.Transparency = 0.5
		building.Position = position
		building.Anchored = true
		building.CanCollide = false
		building.Parent = BuildingsFolder
	end

	-- Apply team color
	BuildingRenderer.ApplyTeamColor(building, owner)

	-- Store reference with metadata
	CreatedBuildings[tostring(nodeId)] = {
		visual = building,
		type = buildingType,
		owner = owner,
	}
end

--[[
	Clear all buildings
]]
function BuildingRenderer.ClearAllBuildings()
	for _, buildingEntry in pairs(CreatedBuildings) do
		if buildingEntry.visual then
			buildingEntry.visual:Destroy()
		end
	end
	table.clear(CreatedBuildings)
end

return BuildingRenderer
