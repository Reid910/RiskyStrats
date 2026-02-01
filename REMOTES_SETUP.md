# Remote Events Setup

You need to create the following RemoteEvents in ReplicatedStorage.

## Folder Structure

Create a folder called `Remotes` in ReplicatedStorage:

```
ReplicatedStorage
└── Remotes (Folder)
    ├── BatchUpdate (RemoteEvent)
    └── ClientReady (RemoteEvent)
```

## Required RemoteEvents

### BatchUpdate
- **Type:** RemoteEvent
- **Location:** ReplicatedStorage.Remotes.BatchUpdate
- **Purpose:** Sends batched network updates from server to clients
- **Used For:**
  - Map updates
  - Game state updates
  - Player updates
  - Entity updates

### ClientReady
- **Type:** RemoteEvent
- **Location:** ReplicatedStorage.Remotes.ClientReady
- **Purpose:** Client signals to server when it's fully loaded and ready to receive data
- **Flow:** Client fires to server → Server sends map data to that specific client

## How It Works

### Client Ready Handshake

1. **Client loads** and initializes all modules
2. **Client registers callbacks** for different event types
3. **Client signals server** it's ready via `ClientReady` RemoteEvent
4. **Server receives signal** and sends map data to that specific client
5. **Client receives map** and renders it

This ensures the client is fully initialized before receiving any data, preventing race conditions.

### Event Types Supported:
- `MapUpdate` - Sends map data to clients
- `GameState` - Sends game state updates
- `PlayerUpdate` - Sends player-specific updates
- `EntityUpdate` - Sends entity/game object updates

### Usage Example:

**Server:**
```lua
local NetworkBatch = Packager.Get("NetworkBatch")

-- Listen for client ready signals
local clientReadyRemote = Remotes:WaitForChild("ClientReady")
clientReadyRemote.OnServerEvent:Connect(function(player)
    -- Send map to specific player when they're ready
    NetworkBatch.SendImmediate(NetworkBatch.EventType.MapUpdate, mapData, player)
end)

-- For other updates during gameplay
NetworkBatch.QueueUpdate(NetworkBatch.EventType.GameState, data)
NetworkBatch.SendBatch() -- Send to all connected clients
```

**Client:**
```lua
local NetworkBatch = Packager.Get("NetworkBatch")

-- Register callback for specific event type
NetworkBatch.RegisterCallback(NetworkBatch.EventType.MapUpdate, function(data)
    -- Handle map data
end)

-- Notify server we're ready
NetworkBatch.NotifyServerReady()
```

## Quick Setup Steps

**These RemoteEvents are already configured in the project and will auto-create when you sync!**

If you need to create them manually:

1. Open Roblox Studio
2. In Explorer, navigate to ReplicatedStorage
3. Right-click ReplicatedStorage → Insert Object → Folder
4. Name it `Remotes`
5. Right-click Remotes → Insert Object → RemoteEvent
6. Name it `BatchUpdate`
7. Right-click Remotes → Insert Object → RemoteEvent
8. Name it `ClientReady`
9. Done!
