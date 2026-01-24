-- StarterPlayerScripts/OrbitalStrikeInput.client.lua
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE = Remotes:WaitForChild("OrbitalStrikeRequest")

local KEY = Enum.KeyCode.E
local LOCAL_COOLDOWN = 1.25

local last = 0

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode ~= KEY then return end

	local now = os.clock()
	if now - last < LOCAL_COOLDOWN then return end
	last = now

	RE:FireServer()
end)
