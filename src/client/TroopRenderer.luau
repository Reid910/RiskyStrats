--[[
	TroopRenderer
	Handles visual representation of moving troops on the client

	Since server sends state every frame, client just displays server position
	without local simulation. Server is authoritative for movement.
]]

local TroopRenderer = {
	Name = "TroopRenderer"
}

-- Track all active troop visuals
local ActiveTroops = {} -- [troopId] = {visual, data}
local TroopsFolder = nil
local MapRenderer = nil

-- Team colors
local TeamColors = {
	Red = Color3.fromRGB(255, 85, 85),
	Blue = Color3.fromRGB(85, 170, 255),
	Green = Color3.fromRGB(85, 255, 127),
	Yellow = Color3.fromRGB(255, 255, 127),
}

local function GetExpansionMultiplier()
	return MapRenderer and MapRenderer.GetExpansionMultiplier() or 5
end

local function Logistic(x, maxValue, steepness, midpoint)
	return maxValue / (1 + math.exp(-steepness * (x - midpoint)))
end

local function CreateTroopVisual(team, troopCount)
	-- Create cylinder to represent moving troops
	local troop = Instance.new("Part")
	troop.Position = Vector3.new(0, -100, 0)
	troop.Shape = Enum.PartType.Cylinder
	troop.Orientation = Vector3.new(0, 90, 90)
	troop.Anchored = true
	troop.CanCollide = false
	troop.CanTouch = false
	troop.CanQuery = false
	troop.Material = Enum.Material.SmoothPlastic
	troop.Color = TeamColors[team] or Color3.new(1, 1, 1)

	-- Size based on troop count (logarithmic scale)
	-- local size = Logistic(troopCount, 100_000, 0.08, 50_000)
	local size = math.log(troopCount * troopCount + 1) * 0.05
	local y = size / 3
	troop.Size = Vector3.new(y, size, size)

	-- Add label showing troop count
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(5, 20, 0.45, 10)
	billboard.StudsOffset = Vector3.new(0, size / 2 + 0.5, 0)
	billboard.AlwaysOnTop = true

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = TeamColors[team] or Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = tostring(troopCount)

	-- Add black stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1

	stroke.Parent = label
	label.Parent = billboard
	billboard.Parent = troop

	return troop, y
end

function TroopRenderer.Init()
	-- Create Troops folder
	TroopsFolder = game.Workspace:FindFirstChild("Troops")
	if not TroopsFolder then
		TroopsFolder = Instance.new("Folder")
		TroopsFolder.Name = "Troops"
		TroopsFolder.Parent = game.Workspace
	end
end

function TroopRenderer.Start()
	-- Get required modules
	local Packager = require(game.ReplicatedStorage.Packager)
	MapRenderer = Packager.Get("MapRenderer")
end

--[[
	Sync troops with server state (called from MapUpdate every frame)
	Server is authoritative - client just displays server position
]]
function TroopRenderer.SyncTroops(serverTroops)
	local multiplier = GetExpansionMultiplier()

	-- Build a set of server troop IDs
	local serverTroopIds = {}
	for _, troopData in ipairs(serverTroops) do
		serverTroopIds[troopData.id] = troopData
	end

	-- Remove troops that no longer exist on server
	for troopId, troop in pairs(ActiveTroops) do
		if not serverTroopIds[troopId] then
			if troop.visual then
				troop.visual:Destroy()
			end
			ActiveTroops[troopId] = nil
		end
	end

	-- Add or update troops from server
	for _, troopData in ipairs(serverTroops) do
		local troop = ActiveTroops[troopData.id]

		if not troop then
			-- New troop, create visual
			local visual, y = CreateTroopVisual(troopData.team, troopData.troopCount)
			visual.Parent = TroopsFolder

			troop = {
				visual = visual,
				height = y/2,
			}
			ActiveTroops[troopData.id] = troop
		end

		-- Update position from server state
		if troop.visual and troopData.fromNode and troopData.toNode then
			local y = troop.height
			local progress = troopData.progress or 0

			local fromX = troopData.fromNode.x * multiplier
			local fromZ = troopData.fromNode.z * multiplier
			local toX = troopData.toNode.x * multiplier
			local toZ = troopData.toNode.z * multiplier

			-- Interpolate position based on server progress
			local x = fromX + (toX - fromX) * progress
			local z = fromZ + (toZ - fromZ) * progress

			troop.visual.Position = Vector3.new(x, y, z)
		end
	end
end

return TroopRenderer
