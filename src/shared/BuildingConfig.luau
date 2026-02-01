--[[
	BuildingConfig
	Configuration for building types and their properties
]]

local BuildingConfig = {
	Name = "BuildingConfig"
}

-- Building type definitions
-- Note: productionRate is troops per SECOND (multiplied by deltaTime)
-- Model names reference models in ReplicatedStorage.Models
BuildingConfig.Types = {
	Spawn = {
		name = "Spawn",
		productionRate = 2, -- 2 troops
		cost = 0, -- Free (auto-placed)
		size = Vector3.new(2, 2, 2),
		model = "SpawnModel", -- Model name in ReplicatedStorage.Models
	},
	Factory = {
		name = "Factory",
		productionRate = 1, -- 1 troop
		cost = 50, -- Troops required to build
		size = Vector3.new(1, 1, 1),
		model = "FactoryModel", -- Model name in ReplicatedStorage.Models
	},
	Powerplant = {
		name = "Powerplant",
		productionRate = 0, -- No direct production
		productionBoost = 2, -- Adds +2 to connected factories
		cost = 200, -- Troops required to build
		size = Vector3.new(3, 1.5, 3),
		model = "Powerplant", -- Model name in ReplicatedStorage.Models
	},
}

function BuildingConfig.GetBuildingType(typeName)
	return BuildingConfig.Types[typeName]
end

return BuildingConfig
