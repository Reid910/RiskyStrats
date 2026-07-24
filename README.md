# RiskyStrats

A real-time strategy game built for Roblox — capture territory, manage economy, and command troops across a procedurally generated map against up to 4 teams. Built with [Rojo](https://github.com/rojo-rbx/rojo) and Luau.

## Engineering Highlights

A few decisions in this codebase worth calling out:

- **Fog of war is computed per-player on the server, not hidden client-side.** [`MapGeneration.SerializeForPlayer()`](src/server/MapGeneration.luau) runs a BFS from each player's owned nodes and buckets the map into three tiers — full info (owned + 1 hop), structure-only "ghost" nodes (2–4 hops), and nodes never sent to the client at all. A client simply cannot know what it hasn't been told, closing off an entire class of cheats that plague client-side fog implementations.
- **Networking is batched and event-typed by design.** [`NetworkBatch.luau`](src/shared/NetworkBatch.luau) is a shared module used by both server and client: the server queues updates by `EventType` (`MapUpdate`, `TroopMovement`, `GameState`, ...) and flushes them in a single `RemoteEvent` firing per player per frame, instead of firing a remote per change. The client registers one callback per event type and stays decoupled from how updates are batched.
- **A dependency-injected module loader instead of a service locator grab-bag.** [`Packager.luau`](src/Packager.luau) registers every module, then runs a strict two-phase boot: every `Init()` runs (wiring references) before any `Start()` runs (starting loops/connections) — so no module can accidentally depend on another module's loop already being live.
- **A* pathfinding runs over a graph, not a grid.** [`AStar.luau`](src/server/AStar.luau) finds shortest paths across the procedurally generated node graph using Euclidean distance plus a 1.1x-weighted heuristic, with an early-exit for directly connected nodes and `debug.profilebegin`/`profileend` instrumentation to keep pathing cheap during large battles.
- **Combat and army speed are simulated continuously, not resolved in discrete ticks.** Contested nodes lose troops proportional to enemy strength every frame (`damage = enemyTroops * COMBAT_DAMAGE_RATE * deltaTime`), and marching armies slow down as they get larger (`TroopConfig.GetTroopSpeed`), so a large army is powerful but slower to project — a tradeoff baked into the simulation rather than a UI rule.
- **Server is the sole authority; the client only renders.** Every mutation — building placement, troop orders, ownership changes — happens in `src/server`, is serialized, and pushed down. `src/client` modules (`MapRenderer`, `TroopRenderer`, `BuildingRenderer`) exist purely to turn that state into parts, GUIs, and animations, which keeps the game resistant to client-side exploiting.

## How It Works

1. **Boot.** [`Server.server.luau`](src/Server.server.luau) and [`Client.client.luau`](src/Client.client.luau) load their respective modules through `Packager`, which wires dependencies (`Init`) and then starts loops/connections (`Start`).
2. **Game loop.** [`ServerModule.luau`](src/server/ServerModule.luau) drives the match: wait for players → generate a fresh map ([`MapGeneration.luau`](src/server/MapGeneration.luau)) → place spawns and assign teams → run per-frame `Heartbeat` loops for combat, production, troop movement, and networking → detect a team's capital falling → declare a winner and restart.
3. **Territory & economy.** [`Team.luau`](src/server/Team.luau) tracks node ownership and per-team troop counts; [`Buildings.luau`](src/server/Buildings.luau) lets players spend troops to build Factories (troop production) and Powerplants (production boost to connected buildings) on owned nodes.
4. **Commands.** [`UserInputService.luau`](src/client/UserInputService.luau) captures drag-select and hotkeys (send 10/50/100/all troops, build, retreat) and forwards them through [`ClientController.luau`](src/client/ClientController.luau) to server-side `RemoteEvent`s, which [`Troops.luau`](src/server/Troops.luau) and `Buildings.luau` validate and apply.
5. **Movement.** Troops sent between non-adjacent nodes get routed by `AStar.FindPath` and then walked segment-by-segment each frame in `Troops.UpdateMovingTroops`, including head-on collision handling where the smaller army is forced to retreat.
6. **Sync.** Every frame, the server serializes each player's fog-of-war-filtered view and pushes it down via `NetworkBatch`; the client's `MapRenderer`/`TroopRenderer`/`BuildingRenderer` reconcile the visuals against that state.

See [docs/Architecture.md](docs/Architecture.md) for the full module dependency graph and network/data flow, [docs/API.md](docs/API.md) for every module's public API, and [docs/DataStructures.md](docs/DataStructures.md) for the exact shape of every data structure and network payload.

## Tech Stack

| Layer | Choice |
|---|---|
| Runtime | [Roblox](https://www.roblox.com/) / Luau |
| Project sync | [Rojo](https://github.com/rojo-rbx/rojo) 7.7.0-rc.1 |
| Toolchain management | [Aftman](https://github.com/LPGhatguy/aftman) |
| Networking | Custom batched `RemoteEvent` layer ([`NetworkBatch.luau`](src/shared/NetworkBatch.luau)) |
| Module system | Custom two-phase loader ([`Packager.luau`](src/Packager.luau)) |
| Pathfinding | Custom A* over a procedural node graph ([`AStar.luau`](src/server/AStar.luau)) |

## Getting Started

Install [Aftman](https://github.com/LPGhatguy/aftman) to pick up the pinned Rojo version, then:

```bash
aftman install
```

To build the place from scratch:

```bash
rojo build -o "RiskyStrats.rbxlx"
```

Then open the built file in Roblox Studio and start the Rojo server so Studio stays in sync with your edits:

```bash
rojo serve
```

For more on the Rojo workflow, see [the Rojo documentation](https://rojo.space/docs).

## Controls

| Input | Action |
|---|---|
| Left Click / Drag | Select nodes (circle select) |
| Shift + Click | Add to selection |
| Alt + Click | Retreat troops |
| Q / E / R | Send 10 / 50 / 100 troops |
| F | Send all troops |
| 1 | Build Factory |
| 3 | Build Powerplant |

## Project Structure

```
src/
  Packager.luau             # Two-phase module loader (Init then Start)
  Server.server.luau         # Server entry point
  Client.client.luau         # Client entry point
  server/
    ServerModule.luau         # Main game loop (waiting -> playing -> cleanup)
    MapGeneration.luau         # Procedural map generation, fog-of-war serialization
    Team.luau                  # Node ownership, per-team troop counts, elimination
    Troops.luau                 # Troop orders, movement, combat resolution
    Buildings.luau                # Building placement + production
    AStar.luau                     # Pathfinding over the node graph
    Player.luau / PlayerData.luau   # Player-to-team assignment, persistence
    TestMapCycle.luau                # Map generation test harness
  client/
    ClientController.luau      # Selection, commands, cached state
    ClientModule.luau           # Client bootstrap, network callback registration
    MapRenderer.luau              # Node/road visuals
    TroopRenderer.luau             # Moving troop visuals
    BuildingRenderer.luau           # Building visuals
    UserInputService.luau            # Mouse/keyboard bindings
    VotingClient.luau                 # Pre-game map/gamemode voting UI
  shared/
    NetworkBatch.luau          # Batched, event-typed RemoteEvent layer
    BuildingConfig.luau         # Building stats (cost, production, boost)
    TroopConfig.luau             # Troop speed-by-size curve
    TeamColors.luau               # Team color palette
docs/
  Architecture.md             # Module relationship map, data/network flow
  API.md                       # Full public API per module
  DataStructures.md             # Exact shape of every data type + network payload
```
