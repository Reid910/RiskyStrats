local MapRenderer = {}

local TeamColors = require(game.ReplicatedStorage.Shared.TeamColors)

local Nodes_folder = nil
local Baseplate_ui = nil
local ExpndMulti = 5

-- Track all created objects for guaranteed cleanup (now dictionary by nodeId)
local CreatedNodes = {} -- [nodeId] = {part, label}
local CreatedRoads = {} -- Still array since roads don't have IDs

function MapRenderer.Init()
	-- Wait for workspace objects to be available
	Nodes_folder = game.Workspace:WaitForChild("Nodes")
	Baseplate_ui = game.Workspace:WaitForChild("Baseplate"):WaitForChild("SurfaceGui")
end

function MapRenderer.GetExpansionMultiplier()
	return ExpndMulti
end

function MapRenderer.CreateNode(x, z, color, troopText, nodeId, isContested, isGhostNode)
	local Node = Instance.new("Part")
	Node.Anchored = true
	Node.Locked = true
	Node.CanCollide = false
	Node.Color = color or Color3.new(1, 1, 1)
	Node.Material = Enum.Material.SmoothPlastic
	Node.Shape = Enum.PartType.Cylinder
	Node.Position = Vector3.new(x * ExpndMulti, 0.1, z * ExpndMulti)
	Node.Size = Vector3.new(0.3, 1.25, 1.25)
	Node.Orientation = Vector3.new(0, 0, 90)
	Node.Name = "Node_" .. (nodeId or "Unknown")

	-- Create BillboardGui for troop count
	local Billboard = Instance.new("BillboardGui")
	Billboard.Size = UDim2.new(5, 5, 0.85, 8) -- Taller for contested nodes
	Billboard.StudsOffset = Vector3.new(0, 1, 0)
	Billboard.AlwaysOnTop = true
	Billboard.Enabled = not isGhostNode -- Hide billboard for ghost nodes

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, 0, 1, 0)
	Label.BackgroundTransparency = 1
	Label.TextColor3 = isContested and Color3.new(1, 1, 1) or (color or Color3.new(1, 1, 1))
	Label.TextScaled = true
	Label.Font = Enum.Font.GothamBold
	Label.Text = troopText or "0"

	-- Add black stroke
	local Stroke = Instance.new("UIStroke")
	Stroke.Color = Color3.new(0, 0, 0)
	Stroke.Thickness = 1

	Stroke.Parent = Label
	Label.Parent = Billboard
	Billboard.Parent = Node
	Node.Parent = Nodes_folder

	-- Track for cleanup (now as dictionary)
	CreatedNodes[nodeId] = {part = Node, label = Label}

	return Node
end

function MapRenderer.UpdateNode(nodeId, color, troopText, isContested, isGhostNode)
	-- Update existing node instead of recreating
	local nodeData = CreatedNodes[nodeId]
	if not nodeData then
		return false -- Node doesn't exist
	end

	-- Update color
	if nodeData.part then
		nodeData.part.Color = color
	end

	-- Update troop count label, color, and visibility
	if nodeData.label then
		nodeData.label.Text = troopText or "0"
		nodeData.label.TextColor3 = isContested and Color3.new(1, 1, 1) or color
		-- Hide billboard for ghost nodes
		if nodeData.label.Parent then
			nodeData.label.Parent.Enabled = not isGhostNode
		end
	end

	return true
end

function MapRenderer.CreateRoad(from, to)
	-- from and to should be tables with x and z properties
	local Road = Instance.new("Frame")
	Road.Name = "Road"
	Road.BackgroundColor3 = Color3.new(0.3, 0.3, 0.3)
	Road.BorderSizePixel = 0
	Road.AnchorPoint = Vector2.new(0.5, 0.5)
	Road.ZIndex = 2

	local mul = ExpndMulti * 15

	local D = Vector3.new(to.x - from.x, 0, to.z - from.z)

	Road.Size = UDim2.new(0, D.Magnitude * mul - 15, 0, 3)
	Road.Position = UDim2.new(0.5, (from.x + D.X / 2) * mul, 0.5, (from.z + D.Z / 2) * mul)
	Road.Rotation = math.deg(math.atan2(D.Z, D.X))

	-- Create background road (slightly wider)
	local Roadbg = Instance.new("Frame")
	Roadbg.Name = "RoadBG"
	Roadbg.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
	Roadbg.BackgroundTransparency = 0.5
	Roadbg.BorderSizePixel = 0
	Roadbg.AnchorPoint = Vector2.new(0.5, 0.5)
	Roadbg.ZIndex = 1
	Roadbg.Size = UDim2.new(0, D.Magnitude * mul - 15, 0, 7) -- 1 pixel wider
	Roadbg.Position = Road.Position
	Roadbg.Rotation = Road.Rotation
	Roadbg.Parent = Baseplate_ui

	Road.Parent = Baseplate_ui

	-- Track background for cleanup too
	table.insert(CreatedRoads, Roadbg)

	-- Track for cleanup
	table.insert(CreatedRoads, Road)

	return Road
end

function MapRenderer.ClearMap()
	-- Destroy all tracked nodes (now dictionary)
	for nodeId, nodeData in pairs(CreatedNodes) do
		if nodeData.part and nodeData.part.Parent then
			nodeData.part:Destroy()
		end
		CreatedNodes[nodeId] = nil
	end
	table.clear(CreatedNodes)

	-- Destroy all tracked roads (still array)
	for i = #CreatedRoads, 1, -1 do
		local road = CreatedRoads[i]
		if road and road.Parent then
			road:Destroy()
		end
		CreatedRoads[i] = nil
	end
	table.clear(CreatedRoads)

	-- Double-check with ClearAllChildren as backup
	if Nodes_folder then
		Nodes_folder:ClearAllChildren()
	end
	if Baseplate_ui then
		Baseplate_ui:ClearAllChildren()
	end
end

function MapRenderer.RenderMap(mapData)
	-- mapData should be a table with:
	-- { nodes = {{id, x, z, color?}, ...}, roads = {{from = {x, z}, to = {x, z}}, ...}, teamData = {...} }

	local teamData = mapData.teamData or {}

	-- Track which nodes we've seen in this update
	local seenNodes = {}

	-- Update or create nodes
	for _, nodeData in ipairs(mapData.nodes) do
		local nodeId = nodeData.id
		seenNodes[nodeId] = true

		-- nodeId is already a string from server (consistent with RemoteEvent serialization)
		local nodeIdStr = tostring(nodeId)
		local nodeTroops = teamData.nodeTroops and teamData.nodeTroops[nodeIdStr] -- Now a table: {Red = 50, Blue = 30}
		local owner = teamData.nodeOwnership and teamData.nodeOwnership[nodeIdStr]

		-- Process troop data
		local troopText = "0"
		local color = TeamColors.Neutral
		local isContested = false
		local totalTroops = 0
		local isGhostNode = false

		-- Check if this is a ghost node (no troop data from server)
		if not nodeTroops then
			isGhostNode = true
			color = TeamColors.Ghost
		elseif type(nodeTroops) == "table" then
			-- Count teams and total troops
			local teamsWithTroops = {}
			for teamName, count in pairs(nodeTroops) do
				if count > 0 then
					table.insert(teamsWithTroops, {name = teamName, count = count})
					totalTroops = totalTroops + count
				end
			end

			if #teamsWithTroops == 0 then
				-- No troops = neutral node with 0
				troopText = "0"
				color = TeamColors.Neutral
			elseif #teamsWithTroops == 1 then
				-- Single team owns this node
				local team = teamsWithTroops[1]
				troopText = tostring(math.floor(team.count))
				color = TeamColors.GetColor(team.name)
			else
				-- Contested! Multiple teams
				isContested = true
				color = TeamColors.Contested

				-- Build multi-line text: "Red: 50\nBlue: 30"
				local lines = {}
				-- Sort by troop count (highest first)
				table.sort(teamsWithTroops, function(a, b) return a.count > b.count end)
				for _, team in ipairs(teamsWithTroops) do
					table.insert(lines, team.name .. ": " .. tostring(math.floor(team.count)))
				end
				troopText = table.concat(lines, "\n")
			end
		elseif nodeTroops and type(nodeTroops) == "number" then
			-- Legacy support: single number
			troopText = tostring(nodeTroops)
			totalTroops = nodeTroops
			color = TeamColors.GetColor(owner)
		end

		-- If no troops but has owner, still show owner color
		if totalTroops == 0 and owner then
			color = TeamColors.GetColor(owner)
		end

		-- Try to update existing node first
		local updated = MapRenderer.UpdateNode(nodeId, color, troopText, isContested, isGhostNode)

		if not updated then
			-- Node doesn't exist yet, create it
			MapRenderer.CreateNode(nodeData.x, nodeData.z, color, troopText, nodeId, isContested, isGhostNode)
		end
	end

	-- Remove nodes that no longer exist in the map
	for nodeId, nodeData in pairs(CreatedNodes) do
		if not seenNodes[nodeId] then
			if nodeData.part and nodeData.part.Parent then
				nodeData.part:Destroy()
			end
			CreatedNodes[nodeId] = nil
		end
	end

	-- Rebuild roads (roads are cheap to recreate)
	-- Clear old roads
	for i = #CreatedRoads, 1, -1 do
		local road = CreatedRoads[i]
		if road and road.Parent then
			road:Destroy()
		end
		CreatedRoads[i] = nil
	end
	table.clear(CreatedRoads)

	-- Create new roads
	if mapData.roads then
		for _, roadData in ipairs(mapData.roads) do
			MapRenderer.CreateRoad(roadData.from, roadData.to)
		end
	end
end

function MapRenderer.Start()
end

return MapRenderer
