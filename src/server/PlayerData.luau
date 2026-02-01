--[[
	PlayerData Module
	Handles loading and saving persistent player data using DataStoreService
]]

local PlayerData = {
	Name = "PlayerData"
}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

-- DataStore configuration
local DATASTORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 300 -- 5 minutes

-- In-memory cache of player data
local PlayerDataCache = {}

-- Default player data structure
local DEFAULT_DATA = {
	wins = 0,
	losses = 0,
	points = 0,
	skins = {}, -- Array of owned skin IDs
	selectedSkin = nil,
	gamesPlayed = 0,
	lastPlayed = 0
}

-- DataStore reference
local PlayerDataStore = nil

--[[
	UTILITY FUNCTIONS
]]

local function DeepCopy(original)
	local copy = {}
	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = DeepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

local function GetDataKey(player)
	return "Player_" .. player.UserId
end

--[[
	DATA MANAGEMENT
]]

function PlayerData.LoadData(player)
	local key = GetDataKey(player)
	local data = DeepCopy(DEFAULT_DATA)

	-- Try to load from DataStore
	local success, result = pcall(function()
		if PlayerDataStore then
			return PlayerDataStore:GetAsync(key)
		end
		return nil
	end)

	if success and result then
		-- Merge loaded data with defaults (in case new fields were added)
		for k, v in pairs(result) do
			data[k] = v
		end
	elseif not success then
		warn(`Failed to load data for {player.Name}: {result}`)
	end

	-- Update last played timestamp
	data.lastPlayed = os.time()

	-- Cache the data
	PlayerDataCache[player.UserId] = data

	return data
end

function PlayerData.SaveData(player)
	local data = PlayerDataCache[player.UserId]
	if not data then
		warn(`No data to save for {player.Name}`)
		return false
	end

	local key = GetDataKey(player)

	-- Update timestamp
	data.lastPlayed = os.time()

	-- Save to DataStore
	local success, errorMsg = pcall(function()
		if PlayerDataStore then
			PlayerDataStore:SetAsync(key, data)
		end
	end)

	if not success then
		warn(`Failed to save data for {player.Name}: {errorMsg}`)
		return false
	end

	return true
end

function PlayerData.GetData(player)
	return PlayerDataCache[player.UserId]
end

function PlayerData.SetData(player, key, value)
	local data = PlayerDataCache[player.UserId]
	if data then
		data[key] = value
		return true
	end
	return false
end

--[[
	GAME STAT FUNCTIONS
]]

function PlayerData.AddWin(player)
	local data = PlayerData.GetData(player)
	if data then
		data.wins += 1
		data.gamesPlayed += 1
		return true
	end
	return false
end

function PlayerData.AddLoss(player)
	local data = PlayerData.GetData(player)
	if data then
		data.losses += 1
		data.gamesPlayed += 1
		return true
	end
	return false
end

function PlayerData.AddPoints(player, amount)
	local data = PlayerData.GetData(player)
	if data then
		data.points += amount
		return true
	end
	return false
end

function PlayerData.RemovePoints(player, amount)
	local data = PlayerData.GetData(player)
	if data then
		data.points = math.max(0, data.points - amount)
		return true
	end
	return false
end

--[[
	SKIN FUNCTIONS
]]

function PlayerData.UnlockSkin(player, skinId)
	local data = PlayerData.GetData(player)
	if data then
		if not table.find(data.skins, skinId) then
			table.insert(data.skins, skinId)
			return true
		end
	end
	return false
end

function PlayerData.HasSkin(player, skinId)
	local data = PlayerData.GetData(player)
	if data then
		return table.find(data.skins, skinId) ~= nil
	end
	return false
end

function PlayerData.SetSelectedSkin(player, skinId)
	local data = PlayerData.GetData(player)
	if data then
		if skinId == nil or table.find(data.skins, skinId) then
			data.selectedSkin = skinId
			return true
		end
	end
	return false
end

function PlayerData.GetSelectedSkin(player)
	local data = PlayerData.GetData(player)
	if data then
		return data.selectedSkin
	end
	return nil
end

--[[
	LIFECYCLE
]]

local function OnPlayerAdded(player)
	PlayerData.LoadData(player)
end

local function OnPlayerRemoving(player)
	PlayerData.SaveData(player)
	PlayerDataCache[player.UserId] = nil
end

local function StartAutoSave()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)

			for _, player in ipairs(Players:GetPlayers()) do
				PlayerData.SaveData(player)
			end
		end
	end)
end

function PlayerData.Init()
	-- Initialize DataStore
	local success, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)

	if success then
		PlayerDataStore = result
	else
		warn(`Failed to initialize DataStore: {result}`)
		warn("Data will not be saved!")
	end

	-- Set up player connection handlers
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	-- Load data for existing players (in case this loads late)
	for _, player in ipairs(Players:GetPlayers()) do
		OnPlayerAdded(player)
	end
end

function PlayerData.Start()
	-- Start autosave loop
	StartAutoSave()
end

return PlayerData
