# Data Structures

## Core Data Types

### Node (MapGeneration)
```lua
Node = {
    id: number,           -- Unique identifier (1-indexed)
    x: number,            -- Map X coordinate
    z: number,            -- Map Z coordinate
    color: Color3?,       -- Optional color
    connections: {number},-- Array of connected node IDs
    deleted: boolean?,    -- True if node was removed
}
```

### TeamData (Team)
```lua
TeamData = {
    name: string,             -- "Red", "Blue", "Green", "Yellow", "Neutral"
    color: Color3,            -- Team color for rendering
    ownedNodes: {number},     -- Array of owned node IDs
    spawnNodeId: number?,     -- Capitol/spawn node ID
}
```

### MovingTroop (Troops)
```lua
MovingTroop = {
    id: string,               -- Unique ID: "{team}_{fromId}_{toId}_{timestamp}"
    team: string,             -- Owning team name
    troopCount: number,       -- Number of troops
    fromNode: Node,           -- Current segment start
    toNode: Node,             -- Current segment end
    progress: number,         -- 0-1 along current segment
    remainingPath: {Node},    -- Nodes after toNode
    originNodeId: number,     -- Where troops started (for retreat)
    finalDestId: number,      -- Ultimate destination
    speed: number,            -- Units per second
}
```

### Building (Buildings)
```lua
Building = {
    type: string,             -- "Spawn", "Factory", "Powerplant"
    owner: string,            -- Current owning team
    nodeId: number,           -- Node this building is on
}
```

### BuildingType (BuildingConfig)
```lua
BuildingType = {
    name: string,
    productionRate: number,   -- Troops per second
    productionBoost: number?, -- Additive bonus to connected factories
    cost: number,             -- Troops required to build
    color: Color3,
    size: Vector3,
}
```

---

## Storage Tables

### Team Module
```lua
-- Node ownership: nodeId (as string) → team name
NodeOwnership: {[string]: string}
-- Example: { ["1"] = "Red", ["5"] = "Blue" }

-- Per-team troops on each node
NodeTroops: {[string]: {[string]: number}}
-- Example: { ["3"] = { Red = 50, Blue = 30 }, ["7"] = { Neutral = 25 } }

-- Eliminated teams
EliminatedTeams: {[string]: boolean}
-- Example: { Blue = true }
```

### Buildings Module
```lua
-- Buildings by node
NodeBuildings: {[string]: Building}
-- Example: { ["1"] = { type = "Spawn", owner = "Red", nodeId = 1 } }
```

### MapGeneration Module
```lua
State = {
    Seed: number,
    Random: Random,
    IsGenerated: boolean,
    NodeCount: number,
    Nodes: {Node},            -- Array indexed by node ID
    NodesByChunk: {[string]: {Node}}, -- Spatial partitioning
}
```

### MapRenderer (Client)
```lua
-- Tracked nodes for updates
CreatedNodes: {[number]: {part: Part, label: TextLabel}}

-- Roads (recreated each frame)
CreatedRoads: {Frame}
```

---

## Network Data Formats

### MapData (Server → Client)
```lua
MapData = {
    nodes: {{id, x, z, color?}},
    roads: {{from: {x, z}, to: {x, z}}},
    teamData: {
        nodeOwnership: {[nodeIdStr]: teamName},
        nodeTroops: {[nodeIdStr]: {[teamName]: count}},
        spawns: {Red: nodeId?, Blue: nodeId?, ...}
    },
    movingTroops: {SerializedTroop},
    buildings: {[nodeIdStr]: {type, owner}}
}
```

### SerializedTroop
```lua
SerializedTroop = {
    id: string,
    team: string,
    troopCount: number,       -- Floored for display
    fromNode: {x, z},         -- Coordinates, not full node
    toNode: {x, z},
    remainingPath: {{x, z}},
    progress: number,
    finalDestId: number,
}
```

### BatchUpdate (RemoteEvent)
```lua
BatchData = {
    [EventType]: {data, data, ...}
}
-- Example: { MapUpdate = {mapData1}, TroopMovement = {troop1, troop2} }
```

---

## Fog of War Visibility

### Node Categories
1. **Owned Nodes** (distance 0)
   - Full info: ownership, troops, buildings
   - Can select and command from

2. **Info-Visible Nodes** (distance 1)
   - Full info: ownership, troops, buildings
   - See structure and troop counts

3. **Ghost Nodes** (distance 2-4)
   - Structure only: position, roads
   - No troop/ownership data
   - Darker grey color, hidden billboard

4. **Hidden Nodes** (distance 5+)
   - Not sent to client at all

### Visibility Calculation
```lua
-- In SerializeForPlayer:
visibleNodeIds = {}     -- All nodes player can see (structure)
infoVisibleNodeIds = {} -- Nodes with full info (owned + 1 hop)

-- BFS from owned nodes:
for nodeId in ownedNodes:
    distance[nodeId] = 0
    visibleNodeIds[nodeId] = true
    infoVisibleNodeIds[nodeId] = true

while queue not empty:
    if current.distance < FogOfWarDistance:
        for neighbor in node.connections:
            visibleNodeIds[neighbor] = true
            if current.distance == 0:
                infoVisibleNodeIds[neighbor] = true
```

---

## Combat System

### Gradual Combat
```lua
COMBAT_DAMAGE_RATE = 0.1  -- Damage per second per enemy troop

-- Each frame on contested nodes:
for each team:
    enemyTroops = totalTroops - team.count
    damage = enemyTroops * COMBAT_DAMAGE_RATE * deltaTime
    team.count = max(0, team.count - damage)
```

### Troop Collisions (on roads)
```lua
-- Troops moving opposite directions on same road:
if troopA.fromNode == troopB.toNode and troopA.toNode == troopB.fromNode:
    if close enough and approaching:
        -- Smaller army retreats to origin
        if troopA.count < troopB.count:
            reverse(troopA)
        elif troopB.count < troopA.count:
            reverse(troopB)
        else:
            reverse(both)
```

---

## Production System

### Timing
```lua
PRODUCTION_INTERVAL = 1.0  -- Seconds between production ticks
ProductionTimer = 0

function UpdateProduction(deltaTime):
    ProductionTimer += deltaTime
    if ProductionTimer < PRODUCTION_INTERVAL:
        return
    ProductionTimer -= PRODUCTION_INTERVAL
    -- Process all buildings...
```

### Powerplant Boost
```lua
function GetPowerplantBoost(nodeId):
    boost = 0
    for connectedId in node.connections:
        if NodeBuildings[connectedId].type == "Powerplant":
            boost += 20
    return boost

-- Applied to Factory and Spawn production:
productionRate = baseRate + GetPowerplantBoost(nodeId)
```

---

## Key Constants

| Constant | Value | Location |
|----------|-------|----------|
| `COMBAT_DAMAGE_RATE` | 0.1 | ServerModule |
| `PRODUCTION_INTERVAL` | 1.0 sec | Buildings |
| `FogOfWarDistance` | 4 hops | MapGeneration |
| `BASE_SPEED` | 0.5 units/sec | TroopConfig |
| `MIN_SPEED` | 0.2 units/sec | TroopConfig |
| `ExpansionMultiplier` | 5 | MapRenderer |
| `MinDistance` (nodes) | 0.65 | MapGeneration |
| `MaxDistance` (nodes) | 2 | MapGeneration |

---

## Team Colors

| Team | RGB | Usage |
|------|-----|-------|
| Red | (255, 85, 85) | Nodes, troops, text |
| Blue | (85, 170, 255) | Nodes, troops, text |
| Green | (85, 255, 127) | Nodes, troops, text |
| Yellow | (255, 255, 127) | Nodes, troops, text |
| Neutral | (180, 180, 180) | Unowned nodes |
| Contested | (128, 128, 128) | Multi-team nodes |
| Ghost | (100, 100, 100) | Fog of war nodes |
