--[[
	ClientController
	Handles node selection and sending troop commands to server
]]

local ClientController = {
	Name = "ClientController"
}

local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

-- Selection state
local SelectionList = {} -- [Node] = SelectionVisual
local MouseDown = false
local MouseDownAt = nil
local SingleTargetModel = nil
local CircleSelectParts = {}

-- Map data cache (for ownership/troop validation)
local CurrentMapData = {
	nodeOwnership = {}, -- [nodeIdStr] = teamName
	nodeTroops = {}, -- [nodeIdStr] = troopCount
	playerTeam = nil
}

-- Spectator mode (set by ClientModule when player has no team)
local IsSpectator = false

-- Constants
local SINGLE_SELECT_RANGE = 2.5
local MAX_CIRCLE_SIZE = 35

-- Helpers
local Camera = game.Workspace.CurrentCamera
local Player = game.Players.LocalPlayer
local Mouse = Player:GetMouse()
local SelectionsFolder = nil

local RaycastParams = RaycastParams.new()
RaycastParams.FilterType = Enum.RaycastFilterType.Include
RaycastParams.FilterDescendantsInstances = {game.Workspace:WaitForChild("Baseplate"), game.Workspace.Nodes}

local function ZeroY(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function SquaredMagnitude(v)
	return v.X * v.X + v.Y * v.Y + v.Z * v.Z
end

local function RayToMouse()
	local origin = Camera.CFrame.Position
	return game.Workspace:Raycast(origin, (Mouse.Hit.Position - origin) * 10, RaycastParams)
end

local function GetMousePosition()
	local rayResult = RayToMouse()
	return rayResult and rayResult.Position or Mouse.Hit.Position
end

local function FindClosestNode(range)
	local ray = RayToMouse()
	if not ray then return nil end

	-- Direct hit on node
	if ray.Instance.Parent == game.Workspace.Nodes then
		return ray.Instance
	end

	-- Find closest node to ray position
	local closestNode = nil
	local closestDistSq = math.huge

	for _, node in pairs(game.Workspace.Nodes:GetChildren()) do
		local distSq = SquaredMagnitude(node.Position - ray.Position)
		if distSq < closestDistSq then
			closestDistSq = distSq
			closestNode = node
		end
	end

	return closestDistSq <= (range * range) and closestNode or nil
end

local function GetNodesInRange(center, radiusSq)
	local nodes = {}
	for _, node in pairs(game.Workspace.Nodes:GetChildren()) do
		if SquaredMagnitude(node.Position - center) <= radiusSq then
			table.insert(nodes, node)
		end
	end
	return nodes
end

local function CreateSelectionVisual()
	local cyl = Instance.new("Part")
	cyl.Shape = Enum.PartType.Cylinder
	cyl.Color = Color3.fromHSV(0, 0, 0.8)
	cyl.Size = Vector3.new(0.1, 2.5, 2.5)
	cyl.Orientation = Vector3.new(0, 0, 90)
	cyl.Anchored = true
	cyl.CanCollide = false
	cyl.CanTouch = false
	cyl.CanQuery = false
	cyl.Material = Enum.Material.Wood
	return cyl
end

local function CreateTargetIndicator()
	local model = Instance.new("Model")

	local function CreatePart()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Size = Vector3.new(0.25, 0.25, 1)
		return p
	end

	-- Create 4 corner indicators
	for i = 1, 2 do
		local p = CreatePart()
		p.Position = Vector3.new(0, 0, -1.5 + (i - 1) * 3)
		p.Parent = model
		if i == 1 then model.PrimaryPart = p end
	end

	for i = 1, 2 do
		local p = CreatePart()
		local pos = Vector3.new(-1.5 + (i - 1) * 3, 0, 0)
		p.CFrame = CFrame.new(pos, pos + Vector3.new(1, 0, 0))
		p.Parent = model
	end

	return model
end

local function CreateCirclePart()
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Size = Vector3.new(1, 0.25, 0.25)
	return p
end

-- Selection functions
local function SelectNode(node)
	if SelectionList[node] then return end

	-- Check if player owns this node OR has troops there (for contested nodes)
	local nodeId = tonumber(string.match(node.Name, "Node_(%d+)"))
	if nodeId then
		local nodeIdStr = tostring(nodeId)
		local owner = CurrentMapData.nodeOwnership[nodeIdStr]
		local troops = CurrentMapData.nodeTroops[nodeIdStr]

		-- Allow selecting if player owns the node
		local canSelect = (owner == CurrentMapData.playerTeam)

		-- Also allow selecting if player has troops on this node (contested battles)
		if not canSelect and troops and type(troops) == "table" then
			local playerTroops = troops[CurrentMapData.playerTeam]
			if playerTroops and playerTroops > 0 then
				canSelect = true
			end
		end

		if not canSelect then
			return
		end
	end

	local visual = CreateSelectionVisual()
	visual.Position = node.Position
	visual.Parent = SelectionsFolder
	SelectionList[node] = visual
end

local function DeselectNode(node)
	if SelectionList[node] then
		local visual = SelectionList[node]
		-- Defensive check: ensure visual still exists before destroying
		if visual and visual.Parent then
			visual:Destroy()
		end
		SelectionList[node] = nil
	end
end

local function DeselectAll()
	for _, visual in pairs(SelectionList) do
		-- Defensive check: ensure visual still exists before destroying
		if visual and visual.Parent then
			visual:Destroy()
		end
	end
	SelectionList = {}
end

local function PerformSelection()
	local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
	if not shift then
		DeselectAll()
	end

	local MousePos = GetMousePosition()
	if not MousePos or not MouseDownAt then return end
	local dragDist = ZeroY(MousePos) - ZeroY(MouseDownAt)
	local dragDistSq = SquaredMagnitude(dragDist)

	-- Single select
	if dragDistSq < (SINGLE_SELECT_RANGE * SINGLE_SELECT_RANGE) then
		local node = FindClosestNode(SINGLE_SELECT_RANGE)
		if node then
			if SelectionList[node] and shift then
				DeselectNode(node)
			else
				SelectNode(node)
			end
		end
	else
		-- Circle select
		local radiusSq = math.min(dragDistSq, MAX_CIRCLE_SIZE * MAX_CIRCLE_SIZE)
		local nodes = GetNodesInRange(MouseDownAt, radiusSq)
		for _, node in pairs(nodes) do
			SelectNode(node)
		end
	end
end

-- Visual updates
local function UpdateTargetVisual()
	if not MouseDown then
		-- Show single target indicator
		local node = FindClosestNode(SINGLE_SELECT_RANGE)
		if node then
			if not SingleTargetModel then
				SingleTargetModel = CreateTargetIndicator()
				SingleTargetModel.Parent = game.Workspace
			end
			SingleTargetModel:PivotTo(CFrame.new(node.Position - Vector3.new(0, 0, 1.5)))
		else
			if SingleTargetModel then
				SingleTargetModel:Destroy()
				SingleTargetModel = nil
			end
		end

		-- Clear circle parts
		for _, part in pairs(CircleSelectParts) do
			part:Destroy()
		end
		CircleSelectParts = {}
	else
		-- Hide single target
		if SingleTargetModel then
			SingleTargetModel:Destroy()
			SingleTargetModel = nil
		end

		-- Show circle select
		local magnitude = (ZeroY(GetMousePosition()) - ZeroY(MouseDownAt)).Magnitude
		magnitude = math.min(magnitude, MAX_CIRCLE_SIZE)

		if magnitude >= SINGLE_SELECT_RANGE then
			local partCount = 3 + math.floor(magnitude * 2)

			-- Adjust part count
			while #CircleSelectParts > partCount do
				CircleSelectParts[#CircleSelectParts]:Destroy()
				table.remove(CircleSelectParts)
			end
			while #CircleSelectParts < partCount do
				local part = CreateCirclePart()
				part.Parent = SelectionsFolder
				table.insert(CircleSelectParts, part)
			end

			-- Position parts in circle
			local center = ZeroY(MouseDownAt)
			for i, part in ipairs(CircleSelectParts) do
				local angle = math.rad(360 / #CircleSelectParts * i)
				local offset = CFrame.Angles(0, angle, 0).LookVector * magnitude
				part.CFrame = CFrame.new(center + offset, center)
			end

			-- Color based on state
			local altHeld = UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt)
			local color
			if altHeld then
				color = Color3.new(0.1, 0.1, 0.1) -- Black for retreat
			elseif magnitude == MAX_CIRCLE_SIZE then
				color = Color3.new(1, 0, 0) -- Red at max
			else
				color = Color3.new(0.5, 0.5, 1) -- Default blue
			end
			for _, part in ipairs(CircleSelectParts) do
				part.Color = color
			end
		else
			-- Clear circle if too small
			for _, part in pairs(CircleSelectParts) do
				part:Destroy()
			end
			CircleSelectParts = {}
		end
	end
end

-- Public API for input handling
function ClientController.GetMousePosition()
	return GetMousePosition()
end

function ClientController.SetSpectator(spectating)
	IsSpectator = spectating
	if spectating then
		DeselectAll()
	end
end

function ClientController.OnMouseDown()
	if IsSpectator then return end
	MouseDown = true
	MouseDownAt = GetMousePosition()
end

function ClientController.OnMouseUp()
	if IsSpectator then return end
	MouseDown = false
	PerformSelection()
end

function ClientController.SendTroops(amount)
	-- Get selected nodes and validate ownership or troop presence
	local selectedNodeIds = {}
	local invalidNodes = {} -- Track invalid/destroyed node references

	for node, _ in pairs(SelectionList) do
		-- Defensive check: ensure node still exists
		if not node or not node.Parent then
			table.insert(invalidNodes, node)
			continue
		end

		local nodeId = tonumber(string.match(node.Name, "Node_(%d+)"))
		if nodeId then
			local nodeIdStr = tostring(nodeId)
			local owner = CurrentMapData.nodeOwnership[nodeIdStr]
			local troops = CurrentMapData.nodeTroops[nodeIdStr]

			-- Allow sending from owned nodes
			local canSend = (owner == CurrentMapData.playerTeam)

			-- Also allow sending from contested nodes where player has troops
			if not canSend and troops and type(troops) == "table" then
				local playerTroops = troops[CurrentMapData.playerTeam]
				if playerTroops and playerTroops > 0 then
					canSend = true
				end
			end

			if canSend then
				table.insert(selectedNodeIds, nodeId)
			else
				warn(`Cannot send from node {nodeId}: no troops there`)
			end
		end
	end

	-- Clean up invalid node references
	for _, invalidNode in ipairs(invalidNodes) do
		SelectionList[invalidNode] = nil
	end

	if #selectedNodeIds == 0 then
		warn("No owned nodes selected")
		return
	end

	-- Get target node
	local targetNode = FindClosestNode(SINGLE_SELECT_RANGE)
	if not targetNode then return end

	local targetNodeId = tonumber(string.match(targetNode.Name, "Node_(%d+)"))
	if not targetNodeId then return end

	-- Check if any nodes can send troops (>1 troop)
	-- local canSendFromAny = false
	-- for _, troopCount in pairs(validNodes) do
	-- 	if troopCount > 1 then
	-- 		canSendFromAny = true
	-- 		break
	-- 	end
	-- end

	-- if not canSendFromAny then
	-- 	warn("No nodes have troops to send (all nodes have ≤1 troop)")
	-- 	return
	-- end

	-- Send to server (server will handle sending what's available from each node)
	local Remotes = game.ReplicatedStorage:WaitForChild("Remotes")
	local sendTroopsRemote = Remotes:FindFirstChild("SendTroops")
	if sendTroopsRemote then
		sendTroopsRemote:FireServer(selectedNodeIds, targetNodeId, amount or 999999)
	end
end

-- Build a building on the node under the mouse cursor
function ClientController.BuildOnTarget(buildingType)
	-- Find the node under the mouse cursor
	local targetNode = FindClosestNode(SINGLE_SELECT_RANGE)
	if not targetNode then
		print("[ClientController] No node under cursor")
		return
	end

	local nodeId = tonumber(string.match(targetNode.Name, "Node_(%d+)"))
	if not nodeId then
		print("[ClientController] Invalid node name format")
		return
	end

	-- Check if player owns this node
	local nodeIdStr = tostring(nodeId)
	local owner = CurrentMapData.nodeOwnership[nodeIdStr]
	if owner ~= CurrentMapData.playerTeam then
		print(`[ClientController] You don't own node {nodeId}`)
		return
	end

	print(`[ClientController] Building {buildingType} on node {nodeId}`)

	-- Send to server
	local Remotes = game.ReplicatedStorage:WaitForChild("Remotes")
	local buildRemote = Remotes:FindFirstChild("PlaceBuilding")
	if buildRemote then
		print(`[ClientController] Sending PlaceBuilding request for node {nodeId}`)
		buildRemote:FireServer(nodeId, buildingType)
	else
		warn("[ClientController] PlaceBuilding RemoteEvent not found! Create it in ReplicatedStorage.Remotes")
	end
end

-- Retreat troops (called when Alt+click or Alt+drag is released)
function ClientController.RetreatTroops()
	-- Reset MouseDown state
	MouseDown = false

	local dragDist = ZeroY(GetMousePosition()) - ZeroY(MouseDownAt)
	local dragDistSq = SquaredMagnitude(dragDist)

	-- Use MouseDownAt as center (consistent with circle selection)
	local centerPos = MouseDownAt
	local radius = 0

	-- Single point retreat
	if dragDistSq < (SINGLE_SELECT_RANGE * SINGLE_SELECT_RANGE) then
		radius = SINGLE_SELECT_RANGE -- Small radius around cursor
	else
		-- Circle retreat
		radius = math.min(math.sqrt(dragDistSq), MAX_CIRCLE_SIZE)
	end

	-- Get expansion multiplier from MapRenderer
	local MapRenderer = require(game.ReplicatedStorage.Packager).Get("MapRenderer")
	local multiplier = MapRenderer and MapRenderer.GetExpansionMultiplier() or 5

	-- Convert world position to map coordinates
	local centerX = centerPos.X / multiplier
	local centerZ = centerPos.Z / multiplier
	local mapRadius = radius / multiplier

	-- Send retreat command to server
	local Remotes = game.ReplicatedStorage:WaitForChild("Remotes")
	local retreatRemote = Remotes:FindFirstChild("RetreatTroops")
	if retreatRemote then
		retreatRemote:FireServer(centerX, centerZ, mapRadius)
		print(`[Retreat] Recalling troops at radius {string.format("%.1f", mapRadius)}`)
	else
		warn("[ClientController] RetreatTroops RemoteEvent not found!")
	end
end

function ClientController.Init()
	-- Create Selections folder
	SelectionsFolder = game.Workspace:FindFirstChild("Selections")
	if not SelectionsFolder then
		SelectionsFolder = Instance.new("Folder")
		SelectionsFolder.Name = "Selections"
		SelectionsFolder.Parent = game.Workspace
	end
end

function ClientController.Start()
	-- Get player's team
	CurrentMapData.playerTeam = Player.Team and Player.Team.Name or nil

	-- Listen for team changes
	Player:GetPropertyChangedSignal("Team"):Connect(function()
		CurrentMapData.playerTeam = Player.Team and Player.Team.Name or nil
		-- Deselect all nodes when team changes
		DeselectAll()
	end)

	-- Update visuals every frame
	RunService.RenderStepped:Connect(UpdateTargetVisual)
end

-- Update map data cache and sync troops (called by MapRenderer or ClientModule)
function ClientController.UpdateMapData(mapData)
	if mapData and mapData.teamData then
		-- Sync moving troops with TroopRenderer
		if mapData.movingTroops then
			local TroopRenderer = require(game.ReplicatedStorage.Packager).Get("TroopRenderer")
			TroopRenderer.SyncTroops(mapData.movingTroops)
		end

		-- Sync buildings with BuildingRenderer
		if mapData.buildings then
			local BuildingRenderer = require(game.ReplicatedStorage.Packager).Get("BuildingRenderer")
			BuildingRenderer.SyncBuildings(mapData.buildings)
		end

		-- Track nodes that lost ownership to deselect them
		local nodesToDeselect = {}

		-- Create set of all visible node IDs
		local visibleNodeIds = {}
		for _, nodeData in ipairs(mapData.nodes or {}) do
			visibleNodeIds[tostring(nodeData.id)] = true
		end

		-- Update ownership and troops for all visible nodes
		for nodeIdStr, _ in pairs(visibleNodeIds) do
			local oldOwner = CurrentMapData.nodeOwnership[nodeIdStr]
			local newOwner = mapData.teamData.nodeOwnership[nodeIdStr]
			local oldTroops = CurrentMapData.nodeTroops[nodeIdStr]
			local newTroops = mapData.teamData.nodeTroops[nodeIdStr]

			-- Update ownership
			CurrentMapData.nodeOwnership[nodeIdStr] = newOwner

			-- Update troops
			CurrentMapData.nodeTroops[nodeIdStr] = newTroops

			-- Check if player can still select this node
			local couldSelectBefore = (oldOwner == CurrentMapData.playerTeam)
			local canSelectNow = (newOwner == CurrentMapData.playerTeam)

			-- Also check troop presence for contested nodes
			if not couldSelectBefore and oldTroops and type(oldTroops) == "table" then
				local oldPlayerTroops = oldTroops[CurrentMapData.playerTeam]
				if oldPlayerTroops and oldPlayerTroops > 0 then
					couldSelectBefore = true
				end
			end
			if not canSelectNow and newTroops and type(newTroops) == "table" then
				local newPlayerTroops = newTroops[CurrentMapData.playerTeam]
				if newPlayerTroops and newPlayerTroops > 0 then
					canSelectNow = true
				end
			end

			-- If player lost ability to select this node, mark for deselection
			if couldSelectBefore and not canSelectNow then
				table.insert(nodesToDeselect, nodeIdStr)
			end
		end

		-- Clean up data for nodes that are no longer visible (fog of war changes)
		for nodeIdStr, _ in pairs(CurrentMapData.nodeOwnership) do
			if not visibleNodeIds[nodeIdStr] then
				CurrentMapData.nodeOwnership[nodeIdStr] = nil
				-- Also mark for deselection if it was selected
				table.insert(nodesToDeselect, nodeIdStr)
			end
		end

		for nodeIdStr, _ in pairs(CurrentMapData.nodeTroops) do
			if not visibleNodeIds[nodeIdStr] then
				CurrentMapData.nodeTroops[nodeIdStr] = nil
			end
		end

		-- Deselect nodes that player no longer owns or that disappeared
		for _, nodeIdStr in ipairs(nodesToDeselect) do
			for node, _ in pairs(SelectionList) do
				-- Check if this node matches the nodeId exactly (with defensive check)
				if node and node.Parent and node.Name == "Node_" .. nodeIdStr then
					DeselectNode(node)
				end
			end
		end
	end
end

-- Get cached team data for rendering
function ClientController.GetCachedTeamData()
	return {
		nodeOwnership = CurrentMapData.nodeOwnership,
		nodeTroops = CurrentMapData.nodeTroops,
		playerTeam = CurrentMapData.playerTeam
	}
end

--[[
	Reset all client state (called when a new game starts)
]]
function ClientController.Reset()
	-- Clear all selections
	DeselectAll()

	-- Reset mouse state
	MouseDown = false
	MouseDownAt = nil

	-- Clear target indicator
	if SingleTargetModel then
		SingleTargetModel:Destroy()
		SingleTargetModel = nil
	end

	-- Clear circle selection parts
	for _, part in pairs(CircleSelectParts) do
		if part and part.Parent then
			part:Destroy()
		end
	end
	CircleSelectParts = {}

	-- Clear cached map data
	CurrentMapData.nodeOwnership = {}
	CurrentMapData.nodeTroops = {}
	-- Keep playerTeam as it will be updated by team assignment

	print("[ClientController] Reset complete")
end

return ClientController
