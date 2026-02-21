local ClientModule = {
	Name = "ClientModule"
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Settings cache (updated from server on init and by client toggles)
local PlayerSettings = {
	birdsEyeView = false,
	gameStartNotification = true,
	playing = true,
}

-- Remote for sending setting updates to server
local PlayerSettingsRemote = nil

function ClientModule.GetSettings()
	return PlayerSettings
end

function ClientModule.UpdateSetting(settingName, value)
	PlayerSettings[settingName] = value
	if PlayerSettingsRemote then
		PlayerSettingsRemote:FireServer(settingName, value)
	end
end

function ClientModule.Init()
end

function ClientModule.Start()
	-- Get required modules from Packager (already loaded)
	local Packager = require(ReplicatedStorage.Packager)
	local MapRenderer = Packager.Get("MapRenderer")
	local NetworkBatch = Packager.Get("NetworkBatch")
	local ClientController = Packager.Get("ClientController")
	local TroopRenderer = Packager.Get("TroopRenderer")
	local BuildingRenderer = Packager.Get("BuildingRenderer")
	local VotingClient = Packager.Get("VotingClient")

	-- Get remotes
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ClientReadyResponseRemote = Remotes:WaitForChild("ClientReadyResponse")
	PlayerSettingsRemote = Remotes:WaitForChild("PlayerSettings")

	-- Handle server's response to our ClientReady signal
	ClientReadyResponseRemote.OnClientEvent:Connect(function(initData)
		print("[ClientModule] Received init data, gameState:", initData.gameState)

		-- Cache settings from server
		if initData.settings then
			PlayerSettings = initData.settings
		end

		-- Show correct UI based on game state
		VotingClient.HandleGameState(initData)
	end)

	-- Register callback for when a new game starts (reset all client state)
	VotingClient.SetOnGameStarted(function()
		print("[ClientModule] New game started - resetting client state")

		-- Check if we are spectating (no team = spectator)
		local isSpectating = (game.Players.LocalPlayer.Team == nil)
		ClientController.SetSpectator(isSpectating)

		-- Reset all client modules
		MapRenderer.ClearMap()
		TroopRenderer.ClearAllTroops()
		BuildingRenderer.ClearAllBuildings()
		ClientController.Reset()

		print("[ClientModule] Client reset complete, spectating:", isSpectating)
	end)

	-- Register callback for map updates
	NetworkBatch.RegisterCallback(NetworkBatch.EventType.MapUpdate, function(mapData)
		ClientController.UpdateMapData(mapData)
		MapRenderer.RenderMap(mapData)
	end)

	-- Notify server that client is ready
	NetworkBatch.NotifyServerReady()
end

return ClientModule
