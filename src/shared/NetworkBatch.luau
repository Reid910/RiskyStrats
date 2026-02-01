--[[
	NetworkBatch Module
	Handles batching and sending network updates to clients
	Supports different event types for map updates, game state, etc.
]]

local NetworkBatch = {
	Name = "NetworkBatch"
}

-- Event types
NetworkBatch.EventType = {
	MapUpdate = "MapUpdate",
	GameState = "GameState",
	PlayerUpdate = "PlayerUpdate",
	EntityUpdate = "EntityUpdate",
	TroopMovement = "TroopMovement",
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = nil
local IsServer = RunService:IsServer()
local IsClient = RunService:IsClient()

-- Server-side batching
local PendingUpdates = {}
local UpdateCallbacks = {}

function NetworkBatch.Init()
	-- Get remotes folder
	if IsServer then
		Remotes = ReplicatedStorage:WaitForChild("Remotes")
	else
		Remotes = ReplicatedStorage:WaitForChild("Remotes")
	end

	-- print("NetworkBatch initialized!")
end

function NetworkBatch.Start()
	if IsClient then
		-- Set up client listeners
		NetworkBatch.SetupClientListeners()
	end

	-- print("NetworkBatch started!")
end

--[[
	SERVER FUNCTIONS
]]

function NetworkBatch.QueueUpdate(eventType, data)
	if not IsServer then
		warn("QueueUpdate can only be called on the server")
		return
	end

	if not PendingUpdates[eventType] then
		PendingUpdates[eventType] = {}
	end

	table.insert(PendingUpdates[eventType], data)
end

function NetworkBatch.SendBatch(player)
	if not IsServer then
		warn("SendBatch can only be called on the server")
		return
	end

	if not Remotes then
		warn("Remotes folder not found")
		return
	end

	local batchRemote = Remotes:FindFirstChild("BatchUpdate")
	if not batchRemote then
		warn("BatchUpdate remote not found")
		return
	end

	-- Prepare batch data
	local batch = {}
	for eventType, updates in pairs(PendingUpdates) do
		if #updates > 0 then
			batch[eventType] = updates
		end
	end

	-- Send if there's data
	if next(batch) then
		if player then
			batchRemote:FireClient(player, batch)
		else
			batchRemote:FireAllClients(batch)
		end

		-- Clear pending updates
		table.clear(PendingUpdates)
	end
end

function NetworkBatch.SendImmediate(eventType, data, player)
	if not IsServer then
		warn("SendImmediate can only be called on the server")
		return
	end

	if not Remotes then
		warn("Remotes folder not found")
		return
	end

	local batchRemote = Remotes:FindFirstChild("BatchUpdate")
	if not batchRemote then
		warn("BatchUpdate remote not found")
		return
	end

	local batch = {
		[eventType] = {data}
	}

	if player then
		batchRemote:FireClient(player, batch)
	else
		batchRemote:FireAllClients(batch)
	end
end

--[[
	CLIENT FUNCTIONS
]]

function NetworkBatch.RegisterCallback(eventType, callback)
	if not IsClient then
		warn("RegisterCallback can only be called on the client")
		return
	end

	UpdateCallbacks[eventType] = callback
end

function NetworkBatch.SetupClientListeners()
	if not Remotes then
		warn("Remotes folder not found")
		return
	end

	local batchRemote = Remotes:FindFirstChild("BatchUpdate")
	if not batchRemote then
		warn("BatchUpdate remote not found")
		return
	end

	batchRemote.OnClientEvent:Connect(function(batch)
		NetworkBatch.ProcessBatch(batch)
	end)
end

function NetworkBatch.NotifyServerReady()
	if not IsClient then
		warn("NotifyServerReady can only be called on the client")
		return
	end

	if not Remotes then
		warn("Remotes folder not found")
		return
	end

	local readyRemote = Remotes:FindFirstChild("ClientReady")
	if not readyRemote then
		warn("ClientReady remote not found")
		return
	end

	readyRemote:FireServer()
	print("Client notified server it's ready!")
end

function NetworkBatch.ProcessBatch(batch)
	for eventType, updates in pairs(batch) do
		local callback = UpdateCallbacks[eventType]
		if callback then
			for _, data in ipairs(updates) do
				local success, err = pcall(function()
					callback(data)
				end)
				if not success then
					warn(`Error processing {eventType} update: {err}`)
				end
			end
		else
			warn(`No callback registered for event type: {eventType}`)
		end
	end
end

return NetworkBatch
