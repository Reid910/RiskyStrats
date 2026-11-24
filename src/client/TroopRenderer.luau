local Rep = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Packager = require(Rep.Packager)

--[[
	TroopRenderer
	Handles visual representation of moving troops on the client

	Event-driven: server sends troop events (spawn, segment advance, retreat,
	combine, arrive) and client simulates movement locally between events.
	Client predicts next segment from remainingPath for smooth node transitions.
]]

local TroopRenderer = {
	Name = "TroopRenderer"
}

local TeamColors = require(game.ReplicatedStorage.Shared.TeamColors)

local TroopConfig = Packager.Get("TroopConfig")

-- Track all active troop visuals
-- [troopId] = { visual, height, troopCount, team, fromNode, toNode, progress, speed, segmentDistance, remainingPath }
local ActiveTroops = {}
local TroopsFolder = nil
local MapRenderer = nil

local function GetExpansionMultiplier()
	return MapRenderer and MapRenderer.GetExpansionMultiplier() or 5
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
	local size = TroopConfig.GetTroopSize(troopCount)
	local y = size / 3
	troop.Size = Vector3.new(y, size, size)

	-- Add label showing troop count
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(5, 20, 0.45, 10)
	billboard.StudsOffset = Vector3.new(0, 0.5, 0)
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

--[[
	Calculate segment distance between two coordinate tables
]]
local function CalcSegmentDistance(fromNode, toNode)
	local dx = toNode.x - fromNode.x
	local dz = toNode.z - fromNode.z
	return math.sqrt(dx * dx + dz * dz)
end

--[[
	Update a troop's visual size and label for a new troop count
]]
local function UpdateTroopVisualSize(troop, newCount)
	if troop.troopCount == newCount then return end
	troop.troopCount = newCount

	local size = TroopConfig.GetTroopSize(newCount)
	local y = size / 3
	troop.visual.Size = Vector3.new(y, size, size)
	troop.height = y / 2

	local billboard = troop.visual:FindFirstChildWhichIsA("BillboardGui")
	if billboard then
		-- billboard.StudsOffset = Vector3.new(0, y + 0.5, 0)
		local label = billboard:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.Text = tostring(newCount)
		end
	end
end

--[[
	Apply troop data (from event or reconciliation) to an active troop entry
	Also sets the visual position immediately so it doesn't stay at (0, -100, 0)
]]
local function ApplyTroopData(troop, data)
	troop.fromNode = data.fromNode
	troop.toNode = data.toNode
	troop.progress = data.progress or 0
	troop.speed = data.speed or 0
	troop.segmentDistance = CalcSegmentDistance(data.fromNode, data.toNode)
	troop.remainingPath = data.remainingPath or {}

	UpdateTroopVisualSize(troop, data.troopCount)

	-- Set visual position immediately
	local multiplier = GetExpansionMultiplier()
	local progress = troop.progress
	local fromX = data.fromNode.x * multiplier
	local fromZ = data.fromNode.z * multiplier
	local toX = data.toNode.x * multiplier
	local toZ = data.toNode.z * multiplier

	local x = fromX + (toX - fromX) * progress
	local z = fromZ + (toZ - fromZ) * progress

	troop.visual.Position = Vector3.new(x, troop.height, z)
end

--[[
	Create a new active troop from event/reconciliation data
]]
local function CreateActiveTroop(data)
	local visual, y = CreateTroopVisual(data.team, data.troopCount)
	visual.Parent = TroopsFolder

	local troop = {
		visual = visual,
		height = y / 2,
		troopCount = data.troopCount,
		team = data.team,
	}

	ApplyTroopData(troop, data)
	return troop
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
	MapRenderer = Packager.Get("MapRenderer")

	-- Client-side simulation: move troops locally, predict next segment at nodes
	RunService.RenderStepped:Connect(function(deltaTime)
		local multiplier = GetExpansionMultiplier()

		for _, troop in pairs(ActiveTroops) do
			if not troop.visual or not troop.fromNode or not troop.toNode then continue end
			if not troop.speed or troop.speed <= 0 then continue end
			if not troop.segmentDistance or troop.segmentDistance <= 0 then continue end

			-- Advance progress locally
			troop.progress = troop.progress + (troop.speed * deltaTime) / troop.segmentDistance

			-- Client-side prediction: if we reached the node, advance to next segment
			if troop.progress >= 1 and troop.remainingPath and #troop.remainingPath > 0 then
				troop.fromNode = troop.toNode
				troop.toNode = table.remove(troop.remainingPath, 1)
				troop.segmentDistance = CalcSegmentDistance(troop.fromNode, troop.toNode)
				troop.progress = troop.progress - 1 -- Carry over excess progress
			end

			-- Clamp after prediction (if no more path, stop at node)
			troop.progress = math.min(1, troop.progress)

			-- Update visual position
			local fromX = troop.fromNode.x * multiplier
			local fromZ = troop.fromNode.z * multiplier
			local toX = troop.toNode.x * multiplier
			local toZ = troop.toNode.z * multiplier

			local x = fromX + (toX - fromX) * troop.progress
			local z = fromZ + (toZ - fromZ) * troop.progress

			troop.visual.Position = Vector3.new(x, troop.height, z)
		end
	end)
end

--[[
	Clear all troop visuals (called when game resets)
]]
function TroopRenderer.ClearAllTroops()
	for _, troop in pairs(ActiveTroops) do
		if troop.visual then
			troop.visual:Destroy()
		end
	end
	table.clear(ActiveTroops)
	-- Keep SimulationConnection alive - it runs for the lifetime of the client
	-- and handles any new troops that arrive after clearing
	print("[TroopRenderer] Cleared all troops")
end

--[[
	Handle troop events from server (event-driven updates)
	Events: "update" (create/update troop), "remove" (troop gone), "clear_all"
]]
function TroopRenderer.HandleTroopEvents(events)
	for _, event in ipairs(events) do
		if event.type == "clear_all" then
			TroopRenderer.ClearAllTroops()

		elseif event.type == "remove" then
			local troopId = event.data.id
			local troop = ActiveTroops[troopId]
			if troop then
				if troop.visual then
					troop.visual:Destroy()
				end
				ActiveTroops[troopId] = nil
			end

		elseif event.type == "update" then
			local data = event.data
			local troop = ActiveTroops[data.id]

			if not troop then
				-- New troop
				troop = CreateActiveTroop(data)
				ActiveTroops[data.id] = troop
			else
				-- Existing troop: update state (segment advance, retreat, combine)
				ApplyTroopData(troop, data)
			end
		end
	end
end

--[[
	Reconcile troops with server state (called on full MapUpdate for fog-of-war changes)
	Creates newly visible troops, removes no-longer-visible troops.
	Does NOT snap existing troops (they simulate locally).
]]
function TroopRenderer.SyncTroops(serverTroops)
	-- Build set of server troop IDs
	local serverTroopIds = {}
	for _, troopData in ipairs(serverTroops) do
		serverTroopIds[troopData.id] = troopData
	end

	-- Remove troops not on server (no longer visible due to fog change)
	for troopId, troop in pairs(ActiveTroops) do
		if not serverTroopIds[troopId] then
			if troop.visual then
				troop.visual:Destroy()
			end
			ActiveTroops[troopId] = nil
		end
	end

	-- Add troops that just became visible (don't touch existing ones)
	for _, troopData in ipairs(serverTroops) do
		if not ActiveTroops[troopData.id] then
			local troop = CreateActiveTroop(troopData)
			ActiveTroops[troopData.id] = troop
		end
	end
end

return TroopRenderer
