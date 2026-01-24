-- StarterPlayerScripts/Phase2Combat.client.lua
-- Phase2 window tracker (no damage key)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Phase2Enter  = Remotes:WaitForChild("Phase2Enter")
local Phase2Exit   = Remotes:WaitForChild("Phase2Exit")

Phase2Enter.OnClientEvent:Connect(function()
	player:SetAttribute("__Phase2Active", true)
end)

Phase2Exit.OnClientEvent:Connect(function()
	player:SetAttribute("__Phase2Active", false)
end)
