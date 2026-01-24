-- StarterPlayerScripts/DeterminantCombat/HitFeedback.client.lua
-- Placeholder: brief slowdown + tiny camera FOV punch (no assets).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local plr = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("DeterminantCombat"):WaitForChild("Remotes")
local CombatRE = remotes:WaitForChild("CombatRE")

local function getHum()
	local ch = plr.Character
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function punchFOV()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local base = cam.FieldOfView
	cam.FieldOfView = base - 6
	TweenService:Create(cam, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base }):Play()
end

local function slowBrief()
	local hum = getHum()
	if not hum then return end
	local base = hum.WalkSpeed
	hum.WalkSpeed = math.max(6, base * 0.65)
	task.delay(0.22, function()
		if hum.Parent then hum.WalkSpeed = base end
	end)
end

CombatRE.OnClientEvent:Connect(function(msg, data)
	if msg == "HitFeedback" then
		punchFOV()
		slowBrief()
	end
end)
