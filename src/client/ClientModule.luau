local ClientModule = {
	Name = "ClientModule"
}

function ClientModule.Init()
end

function ClientModule.Start()
	-- Get required modules from Packager (already loaded)
	local Packager = require(game.ReplicatedStorage.Packager)
	local MapRenderer = Packager.Get("MapRenderer")
	local NetworkBatch = Packager.Get("NetworkBatch")
	local ClientController = Packager.Get("ClientController")

	-- Register callback for map updates
	NetworkBatch.RegisterCallback(NetworkBatch.EventType.MapUpdate, function(mapData)
		-- Update ClientController's map data cache for ownership/troop validation
		-- This also handles deselecting nodes that lost ownership
		ClientController.UpdateMapData(mapData)

		-- Render the map directly with server's data
		-- RenderMap handles updating/removing nodes as needed
		MapRenderer.RenderMap(mapData)
	end)

	-- Notify server that client is ready
	NetworkBatch.NotifyServerReady()
end

return ClientModule
