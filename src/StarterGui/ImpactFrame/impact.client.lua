local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local gui = script.Parent
local clean = gui:WaitForChild("Clean")
local feral = gui:WaitForChild("Feral")

local function waitFrame()
	RunService.RenderStepped:Wait()
end

local function playImpactFrames()
	clean.ImageTransparency = 0
	task.wait(0.05)

	clean.ImageTransparency = 1
	feral.ImageTransparency = 0
	task.wait(0.05)

	feral.ImageTransparency = 1
end

-- test
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.P then
		playImpactFrames()
	end
end)
