--[[
	Test Map Cycle
	Tests generating, sending, and clearing maps in a loop
]]

local TestMapCycle = {
	Name = "TestMapCycle"
}

local IsRunning = false

function TestMapCycle.Init()
	-- print("TestMapCycle initialized!")
end

function TestMapCycle.Start()
	-- print("TestMapCycle started!")
end

function TestMapCycle.StartTest(intervalSeconds)
	if IsRunning then
		warn("Test already running!")
		return
	end

	intervalSeconds = intervalSeconds or 10

	local Packager = require(game.ReplicatedStorage.Packager)
	local MapGeneration = Packager.Get("MapGeneration")
	local NetworkBatch = Packager.Get("NetworkBatch")

	IsRunning = true

	task.spawn(function()
		local cycle = 0

		while IsRunning do
			cycle += 1

			-- Clear previous map first
			if cycle > 1 then
				MapGeneration.ClearMap()
			end

			-- Generate new map
			local startTime = os.clock()
			MapGeneration.Generate(30)
			local genTime = os.clock() - startTime

			-- Serialize and send
			local mapData = MapGeneration.SerializeForClient()
			NetworkBatch.SendImmediate(NetworkBatch.EventType.MapUpdate, mapData)

			-- Single print with generation time
			print(`Map cycle {cycle}: {genTime}s ({#mapData.nodes} nodes, {#mapData.roads} roads)`)

			-- Wait before next cycle
			task.wait(intervalSeconds)
		end
	end)
end

function TestMapCycle.StopTest()
	IsRunning = false
	print("Stopping test after current cycle...")
end

return TestMapCycle
