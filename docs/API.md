# API Reference

## Packager (src/Packager.luau)

| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `Add(Module)` | `ModuleScript` | `void` | Registers a module |
| `AddDeep(Object)` | `Instance` | `void` | Registers module and all descendants |
| `Get(ModuleName)` | `string` | `table \| nil` | Retrieves a registered module |
| `Start()` | `void` | `void` | Calls Init() then Start() on all modules |

---

## Team (src/server/Team.luau)

### Team Management
| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `GetTeamData(teamName)` | `string` | `TeamData \| nil` | Get team data table |
| `GetAllTeams()` | `void` | `{"Red", "Blue", "Green", "Yellow"}` | All playable teams |
| `GetAllTeamsIncludingNeutral()` | `void` | `{...teams, "Neutral"}` | All teams including Neutral |
| `ResetAllTeams()` | `void` | `void` | Clears all team data |
| `SetOnTeamEliminated(callback)` | `(teamName: string) -> void` | `void` | Set elimination callback |
| `IsTeamEliminated(teamName)` | `string` | `boolean` | Check if team is eliminated |
| `GetActiveTeams()` | `void` | `{string}` | Teams with spawn nodes, not eliminated |

### Node Ownership
| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `SetNodeOwner(nodeId, teamName)` | `number, string \| nil` | `void` | Set node ownership |
| `GetNodeOwner(nodeId)` | `number` | `string \| nil` | Get owning team |
| `IsNodeOwnedBy(nodeId, teamName)` | `number, string` | `boolean` | Check ownership |
| `GetOwnedNodes(teamName)` | `string` | `{number}` | Array of owned node IDs |

### Troop Management
| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `SetNodeTroops(nodeId, count, teamName?)` | `number, number, string?` | `void` | Set troop count |
| `GetNodeTroops(nodeId, teamName?)` | `number, string?` | `number` | Get troop count |
| `GetAllNodeTroops(nodeId)` | `number` | `{[teamName]: count}` | All teams' troops on node |
| `AddNodeTroops(nodeId, count, teamName)` | `number, number, string` | `void` | Add troops |
| `RemoveNodeTroops(nodeId, count, teamName)` | `number, number, string` | `number` | Remove troops, returns new count |
| `IsNodeContested(nodeId)` | `number` | `boolean` | Multiple teams have troops |
| `UpdateNodeOwnership(nodeId)` | `number` | `void` | Recalculates ownership based on troops |

### Spawn Management
| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `SetSpawnNode(teamName, nodeId)` | `string, number` | `boolean` | Set team's spawn (clears neutral troops) |
| `GetSpawnNode(teamName)` | `string` | `number \| nil` | Get team's spawn node ID |

### Serialization
| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `SerializeForClient()` | `void` | `{nodeOwnership, nodeTroops, spawns}` | Full state for clients |

---

## MapGeneration (src/server/MapGeneration.luau)

| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `Generate(size?)` | `number? (default 10)` | `boolean` | Generate new map |
| `ClearMap()` | `void` | `void` | Clear all nodes |
| `GetNodeById(id)` | `number` | `Node \| nil` | Get node by ID |
| `GetAllNodes()` | `void` | `{Node}` | All non-deleted nodes |
| `GetConfig()` | `void` | `Config` | Map generation config |
| `SerializeForClient()` | `void` | `MapData` | Full map (spectator view) |
| `SerializeForPlayer(player, playerTeam)` | `Player, string?` | `MapData` | Fog-of-war filtered map |
| `SetFogOfWarDistance(distance)` | `number` | `void` | Set visibility hops |
| `GetFogOfWarDistance()` | `void` | `number` | Current fog distance |

---

## Buildings (src/server/Buildings.luau)

| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `PlaceBuilding(player, nodeId, buildingType)` | `Player, number, string` | `boolean` | Build on owned node |
| `RemoveBuilding(nodeId)` | `number` | `void` | Remove building from node |
| `GetBuilding(nodeId)` | `number` | `Building \| nil` | Get building data |
| `UpdateProduction(deltaTime)` | `number` | `void` | Called every Heartbeat |
| `SerializeForClient()` | `void` | `{[nodeIdStr]: Building}` | All buildings |
| `ClearAllBuildings()` | `void` | `void` | Reset for new game |
| `PlaceSpawnBuildings()` | `void` | `void` | Auto-place spawns for all teams |

---

## Troops (src/server/Troops.luau)

| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `SendTroops(player, fromNodeIds, toNodeId, amount?)` | `Player, {number}, number, number?` | `void` | Send troops along path |
| `RetreatTroops(player, centerX, centerZ, radius)` | `Player, number, number, number` | `void` | Reverse troop direction in area |
| `UpdateMovingTroops(deltaTime)` | `number` | `void` | Move all troops (Heartbeat) |
| `HandleTroopArrival(troop, nodeId)` | `MovingTroop, number` | `void` | Process arrival |
| `UpdateFogOfWarForNodes(nodeIds)` | `{number}` | `void` | Notify clients of changes |
| `ClearAllTroops()` | `void` | `void` | Clear for new game |
| `ClearTeamTroops(teamName)` | `string` | `void` | Clear eliminated team's troops |

---

## Player (src/server/Player.luau)

| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `SetTeam(player, teamName)` | `Player, string` | `boolean` | Assign player to team |
| `GetTeam(player)` | `Player` | `string \| nil` | Get player's team name |
| `IsOnTeam(player, teamName)` | `Player, string` | `boolean` | Check team membership |

---

## AStar (src/server/AStar.luau)

| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `FindPath(startNode, endNode, MapGeneration)` | `Node, Node, MapGeneration` | `{Node} \| nil` | A* pathfinding |

---

## NetworkBatch (src/shared/NetworkBatch.luau)

### Server Functions
| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `QueueUpdate(eventType, data)` | `EventType, any` | `void` | Queue for batch send |
| `SendBatch(player?)` | `Player?` | `void` | Send queued updates |
| `SendImmediate(eventType, data, player?)` | `EventType, any, Player?` | `void` | Send immediately |

### Client Functions
| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `RegisterCallback(eventType, callback)` | `EventType, function` | `void` | Register update handler |
| `NotifyServerReady()` | `void` | `void` | Tell server client is ready |
| `ProcessBatch(batch)` | `BatchData` | `void` | Process received batch |

### Event Types
- `MapUpdate` - Map/node/troop data
- `GameState` - Game state changes
- `PlayerUpdate` - Player data
- `EntityUpdate` - Entity data
- `TroopMovement` - Troop positions

---

## BuildingConfig (src/shared/BuildingConfig.luau)

| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `GetBuildingType(typeName)` | `string` | `BuildingType \| nil` | Get building config |

### Building Types
| Type | productionRate | productionBoost | cost |
|------|---------------|-----------------|------|
| Spawn | 10/sec | - | 0 |
| Factory | 5/sec | - | 50 |
| Powerplant | 0/sec | +20 | 200 |

---

## TroopConfig (src/shared/TroopConfig.luau)

| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `GetTroopSpeed(troopCount)` | `number` | `number` | Speed in units/second (larger armies slower) |

---

## ClientController (src/client/ClientController.luau)

| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `GetMousePosition()` | `void` | `Vector3` | World position under mouse |
| `OnMouseDown()` | `void` | `void` | Start selection |
| `OnMouseUp()` | `void` | `void` | Complete selection |
| `SendTroops(amount?)` | `number?` | `void` | Send troops to target |
| `BuildOnTarget(buildingType)` | `string` | `void` | Build on hovered node |
| `RetreatTroops()` | `void` | `void` | Retreat troops in selection area |
| `UpdateMapData(mapData)` | `MapData` | `void` | Sync with server state |
| `GetCachedTeamData()` | `void` | `{nodeOwnership, nodeTroops, playerTeam}` | Cached state |

---

## MapRenderer (src/client/MapRenderer.luau)

| Function | Input | Output | Description |
|----------|-------|--------|-------------|
| `GetExpansionMultiplier()` | `void` | `number` | World scale factor (5) |
| `CreateNode(x, z, color, troopText, nodeId, isContested, isGhostNode)` | `...` | `Part` | Create visual node |
| `UpdateNode(nodeId, color, troopText, isContested, isGhostNode)` | `...` | `boolean` | Update existing node |
| `CreateRoad(from, to)` | `{x,z}, {x,z}` | `Frame` | Create road visual |
| `ClearMap()` | `void` | `void` | Clear all visuals |
| `RenderMap(mapData)` | `MapData` | `void` | Full render from server data |

---

## UserInputService (src/client/UserInputService.luau)

### Key Bindings
| Key | Action |
|-----|--------|
| Left Click | Select nodes (drag for circle select) |
| Shift+Click | Add to selection |
| Alt+Click | Retreat troops |
| Q | Send 10 troops |
| E | Send 50 troops |
| R | Send 100 troops |
| F | Send all troops |
| 1 | Build Factory |
| 3 | Build Powerplant |
