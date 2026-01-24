local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local function onChar(char)
	local hum = char:WaitForChild("Humanoid")

	-- store defaults once (you can replace with your sprint system later)
	local defaultWalkSpeed = hum.WalkSpeed
	local defaultJumpPower = hum.JumpPower

	RunService.RenderStepped:Connect(function()
		if not hum or not hum.Parent then return end

		local untilT = hum:GetAttribute("StunnedUntil")
		local stunned = (type(untilT) == "number") and (os.clock() < untilT)

		if stunned then
			-- lock movement without changing physics ownership or teleporting
			if hum.WalkSpeed ~= 0 then hum.WalkSpeed = 0 end
			if hum.JumpPower ~= 0 then hum.JumpPower = 0 end
		else
			-- restore
			if hum.WalkSpeed == 0 then hum.WalkSpeed = defaultWalkSpeed end
			if hum.JumpPower == 0 then hum.JumpPower = defaultJumpPower end
		end
	end)
end

if player.Character then
	onChar(player.Character)
end
player.CharacterAdded:Connect(onChar)
