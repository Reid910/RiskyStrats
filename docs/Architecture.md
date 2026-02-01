# Architecture Overview

## Module System (Packager)

All modules are loaded through `Packager.luau` which provides:
- `Packager.Add(Module)` - Register a single module
- `Packager.AddDeep(Object)` - Register a module and all descendants
- `Packager.Get(ModuleName)` - Retrieve a registered module
- `Packager.Start()` - Initialize all modules (calls Init then Start on each)

### Lifecycle
1. Modules are registered via `Add` or `AddDeep`
2. `Packager.Start()` freezes the module table
3. All `Init()` functions are called (for setting up references)
4. All `Start()` functions are called (for starting loops/connections)

---

## Module Relationship Map

```
                                    ENTRY POINTS
                    ┌────────────────────┬────────────────────┐
                    │  Server.server     │  Client.client     │
                    │  (loads Shared +   │  (loads Shared +   │
                    │   Server modules)  │   Client modules)  │
                    └─────────┬──────────┴──────────┬─────────┘
                              │                     │
                    ┌─────────▼──────────┐ ┌───────▼─────────┐
                    │     PACKAGER       │ │    PACKAGER     │
                    │  (ReplicatedStorage)│ │                 │
                    └─────────┬──────────┘ └───────┬─────────┘
                              │                     │
        ┌─────────────────────┼─────────────────────┼─────────────────────┐
        │                     │     SHARED          │                     │
        │    ┌────────────────┼────────────────┐    │                     │
        │    │  BuildingConfig│  TroopConfig   │    │                     │
        │    │  NetworkBatch  │                │    │                     │
        │    └────────────────┴────────────────┘    │                     │
        │                     │                     │                     │
┌───────┼─────────────────────┼─────────────────────┼─────────────────────┼───────┐
│       │         SERVER      │                     │        CLIENT       │       │
│       │                     │                     │                     │       │
│  ┌────▼────┐          ┌─────▼─────┐         ┌─────▼─────┐         ┌─────▼─────┐ │
│  │ Server  │◄────────►│   Team    │         │  Client   │◄───────►│  Client   │ │
│  │ Module  │          │           │         │  Module   │         │ Controller│ │
│  │(game    │          │(ownership,│         │(network   │         │(selection,│ │
│  │ loop)   │          │ troops)   │         │ receive)  │         │ commands) │ │
│  └────┬────┘          └─────┬─────┘         └─────┬─────┘         └─────┬─────┘ │
│       │                     │                     │                     │       │
│       │    ┌────────────────┼────────────────┐    │    ┌────────────────┼─────┐ │
│       │    │                │                │    │    │                │     │ │
│  ┌────▼────▼───┐      ┌─────▼─────┐    ┌─────▼────▼───┐         ┌───────▼───┐ │ │
│  │    Map      │◄────►│ Buildings │    │    Map       │◄───────►│  Troop    │ │ │
│  │ Generation  │      │           │    │   Renderer   │         │  Renderer │ │ │
│  │(nodes,      │      │(factories,│    │(visual nodes,│         │(moving    │ │ │
│  │ paths)      │      │ spawns)   │    │ roads)       │         │ troops)   │ │ │
│  └──────┬──────┘      └───────────┘    └──────────────┘         └───────────┘ │ │
│         │                                                                     │ │
│    ┌────▼────┐        ┌───────────┐                             ┌───────────┐ │ │
│    │  Troops │◄──────►│   AStar   │                             │ Building  │ │ │
│    │         │        │(pathfind) │                             │ Renderer  │ │ │
│    │(movement│        └───────────┘                             └───────────┘ │ │
│    │ logic)  │                                                                │ │
│    └────┬────┘        ┌───────────┐                             ┌───────────┐ │ │
│         │             │  Player   │                             │UserInput  │◄┘ │
│         └────────────►│(team mgmt)│                             │ Service   │   │
│                       └───────────┘                             └───────────┘   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

                              NETWORK FLOW
                    ┌─────────────────────────────┐
                    │                             │
                    │    RemoteEvents (Remotes)   │
                    │                             │
                    │  ┌───────────────────────┐  │
                    │  │ BatchUpdate           │  │  Server ──► Client (map data)
                    │  │ ClientReady           │  │  Client ──► Server (ready signal)
                    │  │ SendTroops            │  │  Client ──► Server (troop commands)
                    │  │ PlaceBuilding         │  │  Client ──► Server (building requests)
                    │  │ RetreatTroops         │  │  Client ──► Server (retreat commands)
                    │  └───────────────────────┘  │
                    │                             │
                    └─────────────────────────────┘
```

---

## Data Flow

### Server → Client (Per-Player Fog of War)
```
MapGeneration.SerializeForPlayer(player, team)
    │
    ├── Calculates visible nodes (owned + FogOfWarDistance hops)
    ├── Filters ownership/troops to info-visible nodes (owned + 1 hop)
    │
    ▼
NetworkBatch.SendImmediate(EventType.MapUpdate, data, player)
    │
    ▼
Client receives via BatchUpdate RemoteEvent
    │
    ▼
ClientModule processes → MapRenderer.RenderMap() + ClientController.UpdateMapData()
```

### Client → Server (Commands)
```
UserInputService (key press / mouse click)
    │
    ▼
ClientController.SendTroops() / BuildOnTarget() / RetreatTroops()
    │
    ▼
RemoteEvent:FireServer(...)
    │
    ▼
ServerModule receives → Troops.SendTroops() / Buildings.PlaceBuilding() / Troops.RetreatTroops()
```

---

## Module Dependencies

| Module | Depends On |
|--------|------------|
| ServerModule | MapGeneration, NetworkBatch, Team, Player, Troops, Buildings |
| MapGeneration | Team, Troops, Buildings |
| Buildings | Team, BuildingConfig, ServerModule, MapGeneration |
| Troops | MapGeneration, Team, AStar, NetworkBatch, Player, TroopConfig |
| Team | ServerModule (for MarkNodeChanged) |
| ClientController | MapRenderer, TroopRenderer, BuildingRenderer |
| MapRenderer | (none - standalone rendering) |
| TroopRenderer | TroopConfig |
| UserInputService | ClientController |

---

## Game Loop (ServerModule)

```
while true do
    1. Wait for players (GameState = "Waiting")

    2. Setup new game:
       - Reset teams, buildings, troops
       - Generate map
       - Place spawn buildings
       - Assign players to teams

    3. Start loops:
       - CombatConnection (Heartbeat → UpdateCombat)
       - NetworkConnection (Heartbeat → SendMapToPlayer for all)
       - Buildings.UpdateProduction (Heartbeat, 1-second intervals)
       - Troops.UpdateMovingTroops (Heartbeat)

    4. Wait for game end:
       - OnTeamEliminated callback triggers when Capitol is captured
       - Last team standing wins

    5. Cleanup and restart
end
```
