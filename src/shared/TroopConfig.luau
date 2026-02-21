--[[
	TroopConfig
	Shared configuration for troop movement between server and client
]]

local TroopConfig = {
	Name = "TroopConfig"
}

-- Base speed settings
local BASE_SPEED = 0.42 -- Base units per second (small armies)
local MIN_SPEED = 0.2 -- Minimum speed for large armies
local SPEED_SCALE_FACTOR = 0.1 -- How much troop count affects speed

--[[
	Calculate movement speed based on troop count
	Larger armies move slower
	@param troopCount - Number of troops
	@return speed - Units per second
]]
function TroopConfig.GetTroopSpeed(troopCount)
	-- Logarithmic scaling - larger armies move slower
	local speedReduction = math.log(troopCount + 1) * SPEED_SCALE_FACTOR
	local speed = math.max(MIN_SPEED, BASE_SPEED - speedReduction)
	return speed
end

function TroopConfig.GetTroopSize(amt)
	return math.sqrt(amt/(math.pi*200)) / 2 + 0.1
end

function TroopConfig.Init()
end

function TroopConfig.Start()
end

return TroopConfig
