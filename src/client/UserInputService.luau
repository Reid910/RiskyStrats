local Rep = game:GetService("ReplicatedStorage")
local Packager = require(Rep.Packager)

local UIS = game:GetService("UserInputService")

local InputModule = {
	Name = "UserInputService"
}

local ClientController = nil

function InputModule.Init()
	ClientController = Packager.Get("ClientController")
end

function InputModule.Start()
	-- Mouse input handling
	UIS.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- Left click - start selection or retreat
			ClientController.OnMouseDown()
		end

		-- Q = 10 troops
		if input.KeyCode == Enum.KeyCode.Q then
			ClientController.SendTroops(11)
		-- E = 50 troops
		elseif input.KeyCode == Enum.KeyCode.E then
			ClientController.SendTroops(511)
		-- R = 100 troops
		elseif input.KeyCode == Enum.KeyCode.R then
			ClientController.SendTroops(2511)
		-- F = all troops
		elseif input.KeyCode == Enum.KeyCode.F then
			ClientController.SendTroops(999_999_999_999)
		-- 1 = build factory on node under cursor
		elseif input.KeyCode == Enum.KeyCode.One then
			ClientController.BuildOnTarget("Factory")
		-- 3 = build powerplant on node under cursor
		elseif input.KeyCode == Enum.KeyCode.Three then
			ClientController.BuildOnTarget("Powerplant")
		end
	end)

	UIS.InputEnded:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- Check if Alt key is held
			local altHeld = UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt)

			if altHeld then
				-- Alt+click - retreat troops
				ClientController.RetreatTroops()
			else
				-- Normal click - perform selection
				ClientController.OnMouseUp()
			end
		end
	end)
end

return InputModule
