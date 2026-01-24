-- StarterPlayerScripts/CooldownUIClient
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local AbilityCooldown = remotes:WaitForChild("AbilityCooldown")

-- Build simple UI
local gui = Instance.new("ScreenGui")
gui.Name = "CooldownGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.AnchorPoint = Vector2.new(0.5, 1)
holder.Position = UDim2.fromScale(0.5, 0.96)
holder.Size = UDim2.fromOffset(260, 46)
holder.BackgroundTransparency = 0.25
holder.BorderSizePixel = 0
holder.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = holder

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 20)
title.Position = UDim2.fromOffset(0, 2)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = "Ground Slam"
title.Parent = holder

local barBg = Instance.new("Frame")
barBg.BackgroundTransparency = 0.55
barBg.BorderSizePixel = 0
barBg.Position = UDim2.fromOffset(10, 26)
barBg.Size = UDim2.fromOffset(240, 14)
barBg.Parent = holder

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 8)
barCorner.Parent = barBg

local bar = Instance.new("Frame")
bar.BorderSizePixel = 0
bar.Size = UDim2.fromScale(1, 1)
bar.Parent = barBg

local barCorner2 = Instance.new("UICorner")
barCorner2.CornerRadius = UDim.new(0, 8)
barCorner2.Parent = bar

local timeLabel = Instance.new("TextLabel")
timeLabel.BackgroundTransparency = 1
timeLabel.Size = UDim2.fromOffset(60, 20)
timeLabel.AnchorPoint = Vector2.new(1, 0)
timeLabel.Position = UDim2.new(1, -6, 0, 2)
timeLabel.Font = Enum.Font.Gotham
timeLabel.TextSize = 14
timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timeLabel.Text = ""
timeLabel.Parent = holder

holder.Visible = false

-- cooldown state
local active = false
local endT = 0
local dur = 0

local function startCooldown(abilityName: string, duration: number)
	dur = math.max(0.05, tonumber(duration) or 0)
	endT = os.clock() + dur
	active = true
	holder.Visible = true
	title.Text = abilityName
end

AbilityCooldown.OnClientEvent:Connect(function(abilityName, duration)
	startCooldown(tostring(abilityName), duration)
end)

RunService.RenderStepped:Connect(function()
	if not active then return end
	local remain = endT - os.clock()
	if remain <= 0 then
		active = false
		holder.Visible = false
		return
	end

	local pct = math.clamp(remain / dur, 0, 1)
	bar.Size = UDim2.fromScale(pct, 1)
	timeLabel.Text = string.format("%.1fs", remain)
end)
