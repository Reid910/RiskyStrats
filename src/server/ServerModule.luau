local Packager = require(game.ReplicatedStorage.Packager)

--[[
	ServerModule / Game Loop
	Manages the game state and loop

	Win condition: Last team with their Capitol (Spawn building) wins
	Triggered by Team.SetNodeOwner when a team loses their Capitol
]]

local ServerModule = {
	Name = "ServerModule"
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Game state
local GameState = "Waiting" -- "Waiting", "Voting_GameMode", "Voting_Map", "Playing", "Ended"
local NetworkConnection = nil
local CombatConnection = nil
local DisconnectConnection = nil
local WinnerTeam = nil

-- Track player-to-team mapping for disconnect handling
local PlayerTeamMap = {} -- [player] = teamName

-- Voting configuration
local VOTE_DURATION = 4 -- Seconds for each vote
local GameModeOptions = {
	{id = 1, name = "Classic", description = "Standard gameplay"},
	{id = 2, name = "Fast", description = "Double production speed"},
	{id = 3, name = "Large", description = "Bigger map"},
	{id = 4, name = "Chaos", description = "More teams, faster combat"},
}
local MapOptions = {} -- Generated during voting
local CurrentVotes = {} -- [player] = optionId
local SelectedGameMode = nil
local SelectedMapSeed = nil

-- Combat configuration
local COMBAT_DAMAGE_RATE = 0.1 -- Troops lost per second per enemy troop present

-- Module references (set in Start)
local MapGeneration = nil
local NetworkBatch = nil
local Team = nil
local Player = nil
local Troops = nil
local Buildings = nil
local PlayerData = nil

-- Remote references (set in Start)
local VoteRemote = nil
local VotingOptionsRemote = nil
local GameStartedRemote = nil
local VoteCountsRemote = nil
local MapOwnershipRemote = nil
local VoteResultRemote = nil
local ClientReadyResponseRemote = nil
local PlayerSettingsRemote = nil

-- Public function for modules to mark changes (kept for compatibility)
function ServerModule.MarkNodeChanged(_nodeId)
	-- No-op: we send full state every frame now
end

function ServerModule.MarkTroopMoving(_troopId, _troopData)
	-- No-op: we send full state every frame now
end

--[[
	Count votes and return winning option id
	If tied, picks randomly among tied options
]]
local function TallyVotes()
	local voteCounts = {}
	for _, optionId in pairs(CurrentVotes) do
		voteCounts[optionId] = (voteCounts[optionId] or 0) + 1
	end

	-- Find highest vote count
	local highestCount = 0
	for _, count in pairs(voteCounts) do
		if count > highestCount then
			highestCount = count
		end
	end

	-- Collect all options with the highest count (handles ties)
	local tiedOptions = {}
	if highestCount > 0 then
		for optionId, count in pairs(voteCounts) do
			if count == highestCount then
				table.insert(tiedOptions, optionId)
			end
		end
	end

	-- If no votes or tie, pick randomly
	if #tiedOptions == 0 then
		return math.random(1, 4)
	elseif #tiedOptions == 1 then
		return tiedOptions[1]
	else
		return tiedOptions[math.random(1, #tiedOptions)]
	end
end

--[[
	Send voting options to a player (includes duration for countdown timer)
]]
local function SendVotingOptions(player, voteType, options)
	if VotingOptionsRemote then
		VotingOptionsRemote:FireClient(player, voteType, options, VOTE_DURATION)
	end
end

--[[
	Broadcast current vote counts to all clients
]]
local function BroadcastVoteCounts()
	local voteCounts = {0, 0, 0, 0} -- [optionId] = count
	for _, optionId in pairs(CurrentVotes) do
		voteCounts[optionId] = voteCounts[optionId] + 1
	end
	if VoteCountsRemote then
		VoteCountsRemote:FireAllClients(voteCounts)
	end
end

--[[
	Run a vote phase
	@param voteType - "GameMode" or "Map"
	@param options - Array of {id, name, description} or {id, name, seed} for maps
	@return winning option id
]]
local function RunVotePhase(voteType, options)
	-- Clear previous votes
	CurrentVotes = {}

	-- Send options to all players
	for _, player in ipairs(Players:GetPlayers()) do
		SendVotingOptions(player, voteType, options)
	end

	-- Wait full duration
	task.wait(VOTE_DURATION)

	-- Tally and return winner
	local winnerId = TallyVotes()

	-- Send result to all clients
	local winningOption = options[winnerId]
	if VoteResultRemote and winningOption then
		VoteResultRemote:FireAllClients(voteType, winningOption)
	end

	-- Brief pause so clients can see the result
	task.wait(3)

	return winnerId
end

--[[
	Generate map options for voting
]]
local function GenerateMapOptions()
	local maps = {}
	for i = 1, 4 do
		local seed = math.random(1, 999999)
		table.insert(maps, {
			id = i,
			name = "Map " .. i,
			seed = seed,
		})
	end
	return maps
end

function ServerModule.Init()
end

--[[
	Send map data to a player
]]
local function SendMapToPlayer(player)
	local playerTeam = Player.GetTeam(player)
	local visibleMapData = MapGeneration.SerializeForPlayer(player, playerTeam)
	NetworkBatch.SendImmediate(NetworkBatch.EventType.MapUpdate, visibleMapData, player)
end

--[[
	Combat update - resolves battles on contested nodes
	Called every frame via Heartbeat
]]
local function UpdateCombat(deltaTime)
	local allNodes = MapGeneration.GetAllNodes()

	for _, node in ipairs(allNodes) do
		local nodeId = node.id
		local allTroops = Team.GetAllNodeTroops(nodeId)

		-- Count teams with troops
		local teamsPresent = {}
		for teamName, count in pairs(allTroops) do
			if count > 0 then
				table.insert(teamsPresent, {name = teamName, count = count})
			end
		end

		-- If 2+ teams, they fight
		if #teamsPresent >= 2 then
			-- Calculate total enemy troops for each team
			local totalTroops = 0
			for _, teamData in ipairs(teamsPresent) do
				totalTroops = totalTroops + teamData.count
			end

			-- Each team takes damage based on enemy troops present
			for _, teamData in ipairs(teamsPresent) do
				local enemyTroops = totalTroops - teamData.count
				local damage = enemyTroops * COMBAT_DAMAGE_RATE * deltaTime

				-- Apply damage
				local newCount = math.max(0, teamData.count - damage)
				Team.SetNodeTroops(nodeId, newCount, teamData.name)
			end
		end
	end
end

--[[
	Called when a team is eliminated (loses their Capitol)
	Only checks win condition - cleanup is done by ForceEliminateTeam
]]
local function OnTeamEliminated(_eliminatedTeam)
	if GameState ~= "Playing" then return end

	-- Check if only one team remains
	local activeTeams = Team.GetActiveTeams()

	if #activeTeams == 1 then
		WinnerTeam = activeTeams[1]
		GameState = "Ended"
		print(`{WinnerTeam} wins!`)
	elseif #activeTeams == 0 then
		WinnerTeam = "Draw"
		GameState = "Ended"
		print("Draw - no teams remaining!")
	end
end

--[[
	Count how many players are currently on a given team
]]
local function CountPlayersOnTeam(teamName)
	local count = 0
	for _, name in pairs(PlayerTeamMap) do
		if name == teamName then
			count = count + 1
		end
	end
	return count
end

--[[
	Force eliminate a team: clear troops, reset nodes to neutral, trigger elimination
]]
local function ForceEliminateTeam(teamName)
	if GameState ~= "Playing" then return end
	if Team.IsTeamEliminated(teamName) then return end

	print(`Eliminating team {teamName}`)

	-- Clear moving troops
	Troops.ClearTeamTroops(teamName)

	-- Clear troops from all nodes
	local allNodes = MapGeneration.GetAllNodes()
	for _, node in ipairs(allNodes) do
		Team.SetNodeTroops(node.id, 0, teamName)
	end

	-- Reset all owned nodes to neutral (including spawn, which triggers elimination)
	Team.ClearTeamOwnership(teamName)
end

--[[
	Remove a player from their team. If they were the last player, eliminate the team.
	Used by forfeit and disconnect.
]]
local function RemovePlayerFromTeam(player)
	local teamName = PlayerTeamMap[player]
	if not teamName then return end

	PlayerTeamMap[player] = nil
	Player.ClearTeam(player)

	-- If no players left on that team, eliminate it
	if CountPlayersOnTeam(teamName) == 0 then
		ForceEliminateTeam(teamName)
	end
end

function ServerModule.Start()
	-- Get required modules from Packager
	MapGeneration = Packager.Get("MapGeneration")
	NetworkBatch = Packager.Get("NetworkBatch")
	Team = Packager.Get("Team")
	Player = Packager.Get("Player")
	Troops = Packager.Get("Troops")
	Buildings = Packager.Get("Buildings")
	PlayerData = Packager.Get("PlayerData")

	-- Register for team elimination events
	Team.SetOnTeamEliminated(OnTeamEliminated)

	-- Setup remote event handlers (once, outside game loop)
	local Remotes = game.ReplicatedStorage:WaitForChild("Remotes")
	local clientReadyRemote = Remotes:WaitForChild("ClientReady")
	local sendTroopsRemote = Remotes:WaitForChild("SendTroops")
	local placeBuildingRemote = Remotes:WaitForChild("PlaceBuilding")
	local retreatTroopsRemote = Remotes:WaitForChild("RetreatTroops")

	-- Create voting remotes if they don't exist
	VoteRemote = Remotes:FindFirstChild("Vote")
	if not VoteRemote then
		VoteRemote = Instance.new("RemoteEvent")
		VoteRemote.Name = "Vote"
		VoteRemote.Parent = Remotes
	end

	VotingOptionsRemote = Remotes:FindFirstChild("VotingOptions")
	if not VotingOptionsRemote then
		VotingOptionsRemote = Instance.new("RemoteEvent")
		VotingOptionsRemote.Name = "VotingOptions"
		VotingOptionsRemote.Parent = Remotes
	end

	GameStartedRemote = Remotes:FindFirstChild("GameStarted")
	if not GameStartedRemote then
		GameStartedRemote = Instance.new("RemoteEvent")
		GameStartedRemote.Name = "GameStarted"
		GameStartedRemote.Parent = Remotes
	end

	VoteCountsRemote = Remotes:FindFirstChild("VoteCounts")
	if not VoteCountsRemote then
		VoteCountsRemote = Instance.new("RemoteEvent")
		VoteCountsRemote.Name = "VoteCounts"
		VoteCountsRemote.Parent = Remotes
	end

	MapOwnershipRemote = Remotes:FindFirstChild("MapOwnership")
	if not MapOwnershipRemote then
		MapOwnershipRemote = Instance.new("RemoteEvent")
		MapOwnershipRemote.Name = "MapOwnership"
		MapOwnershipRemote.Parent = Remotes
	end

	VoteResultRemote = Remotes:FindFirstChild("VoteResult")
	if not VoteResultRemote then
		VoteResultRemote = Instance.new("RemoteEvent")
		VoteResultRemote.Name = "VoteResult"
		VoteResultRemote.Parent = Remotes
	end

	ClientReadyResponseRemote = Remotes:FindFirstChild("ClientReadyResponse")
	if not ClientReadyResponseRemote then
		ClientReadyResponseRemote = Instance.new("RemoteEvent")
		ClientReadyResponseRemote.Name = "ClientReadyResponse"
		ClientReadyResponseRemote.Parent = Remotes
	end

	PlayerSettingsRemote = Remotes:FindFirstChild("PlayerSettings")
	if not PlayerSettingsRemote then
		PlayerSettingsRemote = Instance.new("RemoteEvent")
		PlayerSettingsRemote.Name = "PlayerSettings"
		PlayerSettingsRemote.Parent = Remotes
	end

	local ForfeitRemote = Remotes:FindFirstChild("Forfeit")
	if not ForfeitRemote then
		ForfeitRemote = Instance.new("RemoteEvent")
		ForfeitRemote.Name = "Forfeit"
		ForfeitRemote.Parent = Remotes
	end

	-- Register for ownership change events
	Team.SetOnOwnershipChanged(function(ownershipData)
		MapOwnershipRemote:FireAllClients(ownershipData)
	end)

	sendTroopsRemote.OnServerEvent:Connect(function(player, fromNodeIds, toNodeId, amount)
		if GameState ~= "Playing" then return end
		Troops.SendTroops(player, fromNodeIds, toNodeId, amount)
	end)

	placeBuildingRemote.OnServerEvent:Connect(function(player, nodeId, buildingType)
		if GameState ~= "Playing" then return end
		Buildings.PlaceBuilding(player, nodeId, buildingType)
	end)

	retreatTroopsRemote.OnServerEvent:Connect(function(player, centerX, centerZ, radius)
		if GameState ~= "Playing" then return end
		Troops.RetreatTroops(player, centerX, centerZ, radius)
	end)

	-- Handle votes from clients
	VoteRemote.OnServerEvent:Connect(function(player, optionId)
		if GameState ~= "Voting_GameMode" and GameState ~= "Voting_Map" then return end
		if type(optionId) == "number" and optionId >= 1 and optionId <= 4 then
			CurrentVotes[player] = optionId
			print(`{player.Name} voted for option {optionId}`)
			BroadcastVoteCounts()
		end
	end)

	clientReadyRemote.OnServerEvent:Connect(function(player)
		-- Wait for PlayerData to load if needed
		local settings = PlayerData.GetSettings(player)
		if not settings then
			local retries = 0
			while not settings and retries < 10 do
				task.wait(0.5)
				settings = PlayerData.GetSettings(player)
				retries += 1
			end
		end

		-- Build init payload
		local initData = {
			gameState = GameState,
			settings = settings,
		}

		if GameState == "Voting_GameMode" then
			initData.voteType = "GameMode"
			initData.voteOptions = GameModeOptions
			initData.voteDuration = VOTE_DURATION
		elseif GameState == "Voting_Map" then
			initData.voteType = "Map"
			initData.voteOptions = MapOptions
			initData.voteDuration = VOTE_DURATION
		end

		if GameState == "Ended" and WinnerTeam then
			initData.winnerTeam = WinnerTeam
		end

		ClientReadyResponseRemote:FireClient(player, initData)

		if GameState == "Playing" or GameState == "Ended" then
			SendMapToPlayer(player)
		end
	end)

	-- Handle settings updates from clients
	PlayerSettingsRemote.OnServerEvent:Connect(function(player, settingName, value)
		PlayerData.UpdateSetting(player, settingName, value)
	end)

	-- Handle forfeit (player gives up)
	ForfeitRemote.OnServerEvent:Connect(function(player)
		if GameState ~= "Playing" then return end
		if not PlayerTeamMap[player] then return end

		print(`{player.Name} forfeited`)
		RemovePlayerFromTeam(player)
	end)

	-- Count players who want to play (not spectate)
	local function CountActivePlayers()
		local count = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local s = PlayerData.GetSettings(player)
			if s and s.playing then
				count = count + 1
			end
		end
		return count
	end

	-- Main game loop
	task.spawn(function()
		-- Wait a moment for everything to initialize
		task.wait(1)
		print("Server ready - waiting for players...")

		while true do
			-- 1. Wait for at least 1 active player
			GameState = "Waiting"
			WinnerTeam = nil
			PlayerTeamMap = {}

			while CountActivePlayers() < 1 do
				task.wait(1)
			end

			print("Players joined - starting voting...")

			-- 2. Vote for game mode
			GameState = "Voting_GameMode"
			local winningGameModeId = RunVotePhase("GameMode", GameModeOptions)
			SelectedGameMode = GameModeOptions[winningGameModeId]
			print(`Game mode selected: {SelectedGameMode.name}`)

			-- 3. Generate and vote for map
			GameState = "Voting_Map"
			MapOptions = GenerateMapOptions()
			local winningMapId = RunVotePhase("Map", MapOptions)
			SelectedMapSeed = MapOptions[winningMapId].seed
			print(`Map selected: {MapOptions[winningMapId].name} (seed: {SelectedMapSeed})`)

			-- 4. Assign teams to players BEFORE map generation
			local teamNames = {"Red", "Blue", "Green", "Yellow"}
			local playerList = Players:GetPlayers()
			local activeTeams = {}

			-- Only assign teams to players who want to play
			local playingPlayers = {}
			for _, player in ipairs(playerList) do
				local s = PlayerData.GetSettings(player)
				if s and s.playing then
					table.insert(playingPlayers, player)
				end
			end

			for i, player in ipairs(playingPlayers) do
				local teamIndex = ((i - 1) % #teamNames) + 1
				local teamName = teamNames[teamIndex]
				Player.SetTeam(player, teamName)
				PlayerTeamMap[player] = teamName
				table.insert(activeTeams, teamName)
				print(`Assigned {player.Name} to {teamName} team`)
			end

			-- 5. Setup new game with only active teams
			GameState = "Playing"
			Team.ResetAllTeams()
			Buildings.ClearAllBuildings()
			Troops.ClearAllTroops()
			MapGeneration.Generate(1, activeTeams)
			Buildings.PlaceSpawnBuildings()

			-- 6. Notify clients that game has started (so they can hide voting UI)
			GameStartedRemote:FireAllClients(SelectedGameMode, SelectedMapSeed)

			-- Send initial map ownership percentages
			MapOwnershipRemote:FireAllClients(Team.GetMapOwnership())

			-- 7. Send initial map to all players
			for _, player in ipairs(playerList) do
				SendMapToPlayer(player)
			end

			print("Game started!")

			-- 8. Handle player disconnects - eliminate their team
			DisconnectConnection = Players.PlayerRemoving:Connect(function(player)
				if GameState ~= "Playing" then return end
				if not PlayerTeamMap[player] then return end

				print(`{player.Name} disconnected`)
				RemovePlayerFromTeam(player)
			end)

			-- 9. Start combat loop (every frame)
			CombatConnection = RunService.Heartbeat:Connect(UpdateCombat)

			-- 10. Start network sync (every frame)
			NetworkConnection = RunService.Heartbeat:Connect(function()
				for _, player in ipairs(Players:GetPlayers()) do
					SendMapToPlayer(player)
				end
			end)

			-- 11. Wait for game to end (win condition checked via OnTeamEliminated callback)
			while GameState == "Playing" do
				task.wait(1)

				-- End if no players
				if #Players:GetPlayers() == 0 then
					GameState = "Ended"
					print("All players left - ending game")
				end
			end

			-- 12. Cleanup
			if CombatConnection then
				CombatConnection:Disconnect()
				CombatConnection = nil
			end
			if NetworkConnection then
				NetworkConnection:Disconnect()
				NetworkConnection = nil
			end
			if DisconnectConnection then
				DisconnectConnection:Disconnect()
				DisconnectConnection = nil
			end
			PlayerTeamMap = {}

			-- 13. Show winner and restart
			if WinnerTeam then
				print(`Game Over - {WinnerTeam} is victorious!`)
				task.wait(5) -- Show winner for 5 seconds
			else
				print("Game ended")
				task.wait(3)
			end

			print("Restarting...")
		end
	end)
end

return ServerModule
