-- ServerScriptService/CannotDie_DeathRefusal.server.lua
-- Prevents real death by clamping Health above 0, freezes player, triggers client cinematic,
-- then restores control only after client says it's done (or a timeout).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Ensure remotes exist
local StartDeathRefusalRE = Remotes:FindFirstChild("StartDeathRefusalRE")
if not StartDeathRefusalRE then
	StartDeathRefusalRE = Instance.new("RemoteEvent")
	StartDeathRefusalRE.Name = "StartDeathRefusalRE"
	StartDeathRefusalRE.Parent = Remotes
end

local DeathRefusalFinishedRE = Remotes:FindFirstChild("DeathRefusalFinishedRE")
if not DeathRefusalFinishedRE then
	DeathRefusalFinishedRE = Instance.new("RemoteEvent")
	DeathRefusalFinishedRE.Name = "DeathRefusalFinishedRE"
	DeathRefusalFinishedRE.Parent = Remotes
end

local CFG = {
	ClientTimeoutSeconds = 14,
	MinHealth = 1,
	HealToMax = true,
	HealAmountFallback = 100,
}

local waiting = {} -- [player] = true while waiting

local function freezeCharacter(char, freeze)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	hum.PlatformStand = freeze
	hum.AutoRotate = not freeze

	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = freeze
	end
end

DeathRefusalFinishedRE.OnServerEvent:Connect(function(player)
	if waiting[player] then
		waiting[player] = false
	end
end)

local function hookCharacter(player, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end

	-- Make actual death less likely to fire
	hum.BreakJointsOnDeath = false
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end)

	local tripped = false

	hum.HealthChanged:Connect(function(hp)
		-- Default: immortal ON, unless you set Attribute CannotDie=false
		local cannotDie = player:GetAttribute("CannotDie")
		if cannotDie == nil then cannotDie = true end
		if not cannotDie then return end

		if tripped then return end
		if hp > 0 then return end

		tripped = true

		-- Clamp back to life
		hum.Health = CFG.MinHealth

		-- Freeze character so cinematic is stable/visible
		freezeCharacter(char, true)

		-- Fire client cinematic
		waiting[player] = true
		StartDeathRefusalRE:FireClient(player, { tag = "DeathRefusal" })

		-- Wait for client finish OR timeout
		local t0 = os.clock()
		while waiting[player] and (os.clock() - t0) < CFG.ClientTimeoutSeconds do
			task.wait(0.05)
		end
		waiting[player] = nil

		-- Heal + unfreeze
		if hum and hum.Parent then
			if CFG.HealToMax then
				hum.Health = hum.MaxHealth
			else
				hum.Health = math.max(hum.Health, CFG.HealAmountFallback)
			end
		end

		if char and char.Parent then
			freezeCharacter(char, false)
		end

		tripped = false
	end)
end

Players.PlayerAdded:Connect(function(player)
	if player:GetAttribute("CannotDie") == nil then
		player:SetAttribute("CannotDie", true)
	end

	player.CharacterAdded:Connect(function(char)
		hookCharacter(player, char)
	end)
end)
