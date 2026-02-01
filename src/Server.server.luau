local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Packager = require(ReplicatedStorage.Packager)

-- Add shared modules
Packager.AddDeep(ReplicatedStorage.Shared)

-- Add server modules
Packager.AddDeep(ServerStorage.Server)

-- Start all modules
Packager.Start()

print("Server started with Packager!")
