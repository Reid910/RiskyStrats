local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packager = require(ReplicatedStorage.Packager)

-- Add shared modules
Packager.AddDeep(ReplicatedStorage.Shared)

-- Add client modules
Packager.AddDeep(ReplicatedStorage.Client)

-- Start all modules
Packager.Start()

print("Client started with Packager!")
