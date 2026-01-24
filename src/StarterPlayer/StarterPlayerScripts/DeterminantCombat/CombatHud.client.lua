-- StarterPlayerScripts/DeterminantCombat/CombatHud.client.lua
-- Minimal HUD: health + stamina bars (no fancy UI).

local Players = game:GetService("Players")

local plr = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "CombatHUD"
gui.ResetOnSpawn = false
gui.Parent = plr:WaitForChild("PlayerGui")

local function makeBar(yOffset, labelText, barColor)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(260, 22)
	frame.Position = UDim2.new(0, 16, 1, -yOffset)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(70, 22)
	label.Position = UDim2.fromOffset(0, 0)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.new(1,1,1)
	label.Parent = frame

	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, -78, 1, -6)
	back.Position = UDim2.fromOffset(74, 3)
	back.BackgroundTransparency = 0.5
	back.BorderSizePixel = 0
	back.Parent = frame

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = barColor
	fill.BorderSizePixel = 0
	fill.Parent = back

	return fill
end

local hpFill = makeBar(44, "HP", Color3.fromRGB(255, 80, 80))
local stFill = makeBar(18, "STM", Color3.fromRGB(90, 180, 255))

local function safeRatio(a, b)
	if b <= 0 then return 0 end
	return math.clamp(a / b, 0, 1)
end

task.spawn(function()
	while true do
		local hp = plr:GetAttribute("Health") or 0
		local maxHp = plr:GetAttribute("MaxHealth") or 100
		local st = plr:GetAttribute("Stamina") or 0
		local maxSt = plr:GetAttribute("MaxStamina") or 100

		hpFill.Size = UDim2.new(safeRatio(hp, maxHp), 0, 1, 0)
		stFill.Size = UDim2.new(safeRatio(st, maxSt), 0, 1, 0)

		task.wait(0.05)
	end
end)
