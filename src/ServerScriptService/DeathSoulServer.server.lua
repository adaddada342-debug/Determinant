local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DeathSoulCinematicRE = Remotes:WaitForChild("DeathSoulCinematicRE")

local function hookCharacter(plr, char)
	local hum = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not hum or not root then return end

	hum.Died:Connect(function()
		-- Fire only to the player who died (cinematic is local).
		DeathSoulCinematicRE:FireClient(plr, root.CFrame)
	end)
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		hookCharacter(plr, char)
	end)
	if plr.Character then
		hookCharacter(plr, plr.Character)
	end
end)
