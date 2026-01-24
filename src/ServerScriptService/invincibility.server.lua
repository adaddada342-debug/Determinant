-- ServerScriptService/DeathIntercept.server.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StartDeathSequenceRE = Remotes:WaitForChild("StartDeathSequenceRE")

local function fireDeathSequence(player)
	-- Mark so we don't spam-fire while Humanoid keeps reporting 0
	player:SetAttribute("InDeathSequence", true)

	-- Send whatever payload your client expects. If your client gate expects flags,
	-- include them. (This matches your "phase3/refusal" checks.)
	StartDeathSequenceRE:FireClient(player, {
		refusal = true,
		phase3 = true,
		mode = "refusal",
		sequence = "phase3",
	})

	-- Safety: clear the attribute after a short time in case the client fails
	task.delay(10, function()
		if player and player.Parent then
			player:SetAttribute("InDeathSequence", false)
		end
	end)
end

local function hookCharacter(player, char)
	local hum = char:WaitForChild("Humanoid", 5)
	if not hum then return end

	local fired = false
	hum.HealthChanged:Connect(function(hp)
		if fired then return end
		if hp > 0 then return end
		if player:GetAttribute("InDeathSequence") then return end

		fired = true
		fireDeathSequence(player)
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		hookCharacter(player, char)
	end)
end)
