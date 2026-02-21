--[[
	VotingClient
	Handles voting UI interactions on the client

	RemoteEvents:
	- Vote: Client -> Server (optionId: 1-4)
	- VotingOptions: Server -> Client (voteType, options, duration)
	- VoteCounts: Server -> Client (voteCounts: {count1, count2, count3, count4})
	- VoteResult: Server -> Client (voteType, winningOption)
	- GameStarted: Server -> Client (gameMode, mapSeed)
	- MapOwnership: Server -> Client (ownership: { Red = %, Blue = %, Green = %, Yellow = %, Neutral = % })
]]

local VotingClient = {
	Name = "VotingClient"
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeamColors = require(ReplicatedStorage.Shared.TeamColors)

-- Callbacks (set by UI code)
local OnVotingOptionsReceived = nil -- function(voteType, options)
local OnVoteCountsUpdated = nil -- function(voteCounts: {number, number, number, number})
local OnGameStarted = nil -- function(gameMode, mapSeed)
local OnMapOwnershipUpdated = nil -- function(ownership: { Red = %, Blue = %, Green = %, Yellow = %, Neutral = % })

-- Remote references
local VoteRemote = nil
local VotingOptionsRemote = nil
local VoteCountsRemote = nil
local GameStartedRemote = nil
local MapOwnershipRemote = nil
local VoteResultRemote = nil

-- Timer state
local TimerConnection = nil

-- UI references (set in Start)
local MenuUI = nil
local Vote = nil
local ResultLabel = nil
local TimerLabel = nil

--[[
	Set callback for when voting options are received
]]
function VotingClient.SetOnVotingOptions(callback)
	OnVotingOptionsReceived = callback
end

--[[
	Set callback for when vote counts are updated
]]
function VotingClient.SetOnVoteCountsUpdated(callback)
	OnVoteCountsUpdated = callback
end

--[[
	Set callback for when game starts (to hide voting UI)
]]
function VotingClient.SetOnGameStarted(callback)
	OnGameStarted = callback
end

--[[
	Set callback for when map ownership changes
]]
function VotingClient.SetOnMapOwnershipUpdated(callback)
	OnMapOwnershipUpdated = callback
end

--[[
	Send a vote to the server
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
	MapOwnershipRemote = Remotes:WaitForChild("MapOwnership")
	VoteResultRemote = Remotes:WaitForChild("VoteResult")
end

local function StopTimer()
	if TimerConnection then
		TimerConnection:Disconnect()
		TimerConnection = nil
	end
	if TimerLabel then
		TimerLabel.Text = "Waiting For Players..."
	end
end

local function StartTimer(duration)
	StopTimer()
	local endTime = tick() + duration
	if TimerLabel then
		TimerLabel.Visible = true
		TimerLabel.Text = tostring(math.ceil(duration))
	end
	TimerConnection = game:GetService("RunService").Heartbeat:Connect(function()
		local remaining = math.max(0, endTime - tick())
		if TimerLabel then
			TimerLabel.Text = tostring(math.ceil(remaining))
		end
		if remaining <= 0 then
			StopTimer()
		end
	end)
end

--[[
	Show voting options in the UI (reusable by remote handler and HandleGameState)
]]
function VotingClient.ShowVotingOptions(voteType, options, duration)
	if not Vote or not MenuUI then return end

	Vote.Visible = true

	for _, o in pairs(options) do
		local frame = Vote:FindFirstChild(tostring(o.id))
		if frame then
			frame.Display.Text = o.name
		end
	end

	-- Reset vote count display
	for i = 1, 4 do
		local frame = Vote:FindFirstChild(tostring(i))
		if frame then
			frame.Count.Text = "0"
		end
	end

	-- Hide result from previous phase
	if ResultLabel then
		ResultLabel.Visible = false
	end

	if duration then
		StartTimer(duration)
	end

	MenuUI.Enabled = true
	print(`[VotingClient] Showing {voteType} options`)
	if OnVotingOptionsReceived then
		OnVotingOptionsReceived(voteType, options)
	end
end

--[[
	Handle initial game state from server (called on ClientReady response)
	@param initData - { gameState, settings, voteType?, voteOptions?, voteDuration?, winnerTeam? }
]]
function VotingClient.HandleGameState(initData)
	if not MenuUI then return end

	if initData.gameState == "Waiting" then
		MenuUI.Enabled = true
		if TimerLabel then
			TimerLabel.Text = "Waiting For Players..."
			TimerLabel.Visible = true
		end
		if Vote then Vote.Visible = false end

	elseif initData.gameState == "Voting_GameMode" or initData.gameState == "Voting_Map" then
		if initData.voteOptions and initData.voteType then
			VotingClient.ShowVotingOptions(initData.voteType, initData.voteOptions, initData.voteDuration)
		end

	elseif initData.gameState == "Playing" then
		MenuUI.Enabled = false

	elseif initData.gameState == "Ended" then
		MenuUI.Enabled = true
		if TimerLabel then
			if initData.winnerTeam then
				TimerLabel.Text = initData.winnerTeam .. " Wins!"
			else
				TimerLabel.Text = "Game Over"
			end
			TimerLabel.Visible = true
		end
		if Vote then Vote.Visible = false end
	end
end

function VotingClient.Start()
	local UI = ReplicatedStorage:WaitForChild("UI")
	local PlayerGui = game.Players.LocalPlayer.PlayerGui

	-- Set module-level UI references
	MenuUI = PlayerGui:WaitForChild("MenuUI")
	TimerLabel = MenuUI.Background:WaitForChild("Status")
	Vote = MenuUI.Background.Vote
	ResultLabel = MenuUI.Background:FindFirstChild("Result")

	-- Connect vote button clicks
	for i = 1, 4 do
		local frame = Vote:WaitForChild(tostring(i))
		frame.TextButton.MouseButton1Click:Connect(function()
			VotingClient.Vote(i)
		end)
	end

	-- Listen for voting options from server
	VotingOptionsRemote.OnClientEvent:Connect(function(voteType, options, duration)
		VotingClient.ShowVotingOptions(voteType, options, duration)
	end)

	-- Listen for vote count updates
	VoteCountsRemote.OnClientEvent:Connect(function(voteCounts)
		for id, v in pairs(voteCounts) do
			local frame = Vote:FindFirstChild(tostring(id))
			if frame then
				frame.Count.Text = v
			end
		end
		if OnVoteCountsUpdated then
			OnVoteCountsUpdated(voteCounts)
		end
	end)

	-- Listen for vote result (winning option after each phase)
	VoteResultRemote.OnClientEvent:Connect(function(voteType, winningOption)
		StopTimer()
		if TimerLabel then
			TimerLabel.Visible = false
		end
		if ResultLabel then
			ResultLabel.Text = winningOption.name .. " wins!"
			ResultLabel.Visible = true
		end
		print(`[VotingClient] {voteType} result: {winningOption.name}`)
	end)

	-- Listen for game start
	GameStartedRemote.OnClientEvent:Connect(function(gameMode, mapSeed)
		MenuUI.Enabled = false
		print(`[VotingClient] Game started - Mode: {gameMode.name}, Seed: {mapSeed}`)
		if OnGameStarted then
			OnGameStarted(gameMode, mapSeed)
		end
	end)

	-- Ownership bar UI
	local HUD = PlayerGui:WaitForChild("HUD")
	local Container = HUD.OwnershipDisplay.Container
	local Bar = UI:WaitForChild("PercentBar")

	local Bars = {}

	local function MakeBar(teamName)
		local b = {Bar=Bar:Clone(),P=0}
		b.Bar.BackgroundColor3 = TeamColors.GetColor(teamName)
		b.Bar.Visible = true
		b.Bar.Parent = Container
		Bars[teamName] = b
		return b
	end

	-- Listen for map ownership updates
	MapOwnershipRemote.OnClientEvent:Connect(function(ownership)
		local o = {}

		for color, percent in pairs(ownership) do
			local b = Bars[color] or MakeBar(color)

			b.P = percent
			b.Bar.Size = UDim2.new(percent / 100, -3, 1, 0)
			b.Bar.Display.Text = string.format("%d%%", math.ceil(percent))

			table.insert(o, b)
		end

		table.sort(o, function(a, b)
			return a.P > b.P
		end)

		local nextScale = 0
		local nextOffset = 0

		for _, v in ipairs(o) do
			v.Bar.Position = UDim2.new(nextScale, nextOffset, 0, 0)
			nextScale += (v.P / 100)
			nextOffset += -3
		end
	end)
end

return VotingClient
