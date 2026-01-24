-- StarterPlayerScripts/EncounterBridge.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local plr = Players.LocalPlayer
local pg = plr:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EncounterCommandRE = Remotes:WaitForChild("EncounterCommandRE")
local EncounterStatusRE = Remotes:WaitForChild("EncounterStatusRE")
local BattleRE = Remotes:WaitForChild("BattleRE")

local function inBattle()
	return tostring(plr:GetAttribute("__BattlePhase") or "None") ~= "None"
end

local POP_GUI = "__EncounterPop"
local popGui = pg:FindFirstChild(POP_GUI)
if popGui then popGui:Destroy() end

local function showPop()
	if pg:FindFirstChild(POP_GUI) then
		pg[POP_GUI]:Destroy()
	end

	popGui = Instance.new("ScreenGui")
	popGui.Name = POP_GUI
	popGui.ResetOnSpawn = false
	popGui.IgnoreGuiInset = true
	popGui.DisplayOrder = 2499997
	popGui.Parent = pg

	local lab = Instance.new("TextLabel")
	lab.BackgroundTransparency = 1
	lab.Size = UDim2.new(0, 120, 0, 120)
	lab.AnchorPoint = Vector2.new(0.5, 0.5)
	lab.Position = UDim2.fromScale(0.5, 0.4)
	lab.Text = "!"
	lab.TextScaled = true
	lab.Font = Enum.Font.Arcade
	lab.TextColor3 = Color3.fromRGB(255, 255, 255)
	lab.Parent = popGui

	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://110566528613660"
	s.Volume = 0.7
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 2)

	task.delay(0.45, function()
		if popGui then popGui:Destroy() end
	end)
end

EncounterCommandRE.OnClientEvent:Connect(function(kind, payload)
	payload = payload or {}

	if kind == "BeginEncounter" then
		if inBattle() then return end

		local enemyId = tostring(payload.enemyId or "Froggit")
		showPop()

		task.delay(0.35, function()
			if inBattle() then return end
			BattleRE:FireServer("StartTest", { enemyId = enemyId })
			EncounterStatusRE:FireServer("EncounterStarted", { enemyId = enemyId })
		end)

		return
	end
end)

BattleRE.OnClientEvent:Connect(function(kind, payload)
	if kind == "End" then
		-- ✅ correct message that RegionEncounterDirector listens for
		EncounterStatusRE:FireServer("EncounterEnded", { reason = payload and payload.reason })
	end
end)
