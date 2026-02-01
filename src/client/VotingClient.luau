--[[
	VotingClient
	Handles voting UI interactions on the client

	RemoteEvents:
	- Vote: Client -> Server (optionId: 1-4)
	- VotingOptions: Server -> Client (voteType, options)
	- VoteCounts: Server -> Client (voteCounts: {count1, count2, count3, count4})
	- GameStarted: Server -> Client (gameMode, mapSeed)
]]

local VotingClient = {
	Name = "VotingClient"
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Callbacks (set by UI code)
local OnVotingOptionsReceived = nil -- function(voteType, options)
local OnVoteCountsUpdated = nil -- function(voteCounts: {number, number, number, number})
local OnGameStarted = nil -- function(gameMode, mapSeed)

-- Remote references
local VoteRemote = nil
local VotingOptionsRemote = nil
local VoteCountsRemote = nil
local GameStartedRemote = nil

--[[
	Set callback for when voting options are received
	@param callback - function(voteType: string, options: {{id, name, description/seed}})
	voteType is "GameMode" or "Map"
]]
function VotingClient.SetOnVotingOptions(callback)
	OnVotingOptionsReceived = callback
end

--[[
	Set callback for when vote counts are updated
	@param callback - function(voteCounts: {number, number, number, number})
	voteCounts[1] = votes for option 1, etc.
]]
function VotingClient.SetOnVoteCountsUpdated(callback)
	OnVoteCountsUpdated = callback
end

--[[
	Set callback for when game starts (to hide voting UI)
	@param callback - function(gameMode: {id, name, description}, mapSeed: number)
]]
function VotingClient.SetOnGameStarted(callback)
	OnGameStarted = callback
end

--[[
	Send a vote to the server
	@param optionId - 1, 2, 3, or 4
]]
function VotingClient.Vote(optionId)
	if VoteRemote and type(optionId) == "number" and optionId >= 1 and optionId <= 4 then
		VoteRemote:FireServer(optionId)
	end
end

function VotingClient.Init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	VoteRemote = Remotes:WaitForChild("Vote")
	VotingOptionsRemote = Remotes:WaitForChild("VotingOptions")
	VoteCountsRemote = Remotes:WaitForChild("VoteCounts")
	GameStartedRemote = Remotes:WaitForChild("GameStarted")
end

function VotingClient.Start()
	-- Listen for voting options from server
	VotingOptionsRemote.OnClientEvent:Connect(function(voteType, options)
		print(`[VotingClient] Received {voteType} options:`, options)
		if OnVotingOptionsReceived then
			OnVotingOptionsReceived(voteType, options)
		end
	end)

	-- Listen for vote count updates
	VoteCountsRemote.OnClientEvent:Connect(function(voteCounts)
		if OnVoteCountsUpdated then
			OnVoteCountsUpdated(voteCounts)
		end
	end)

	-- Listen for game start
	GameStartedRemote.OnClientEvent:Connect(function(gameMode, mapSeed)
		print(`[VotingClient] Game started - Mode: {gameMode.name}, Seed: {mapSeed}`)
		if OnGameStarted then
			OnGameStarted(gameMode, mapSeed)
		end
	end)
end

return VotingClient
