-- StarterPlayerScripts/DialogueGuiAutoSetup.client.lua
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = playerGui:FindFirstChild("DialogueGui")
if not gui then
	gui = Instance.new("ScreenGui")
	gui.Name = "DialogueGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
end

gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Build Main container if missing
local main = gui:FindFirstChild("Main")
if not main then
	main = Instance.new("Frame")
	main.Name = "Main"
	main.AnchorPoint = Vector2.new(0.5, 1)
	main.Position = UDim2.fromScale(0.5, 0.92)
	main.Size = UDim2.fromScale(0.72, 0.26)
	main.BackgroundTransparency = 1
	main.Visible = false
	main.ZIndex = 50
	main.Parent = gui
else
	main.ZIndex = 50
end

-- Base panel
local panel = main:FindFirstChild("Panel") or Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.fromScale(0.5, 1)
panel.Size = UDim2.fromScale(1, 1)
panel.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
panel.BackgroundTransparency = 0.05
panel.ZIndex = 50
panel.Parent = main

local corner = panel:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 18)
corner.Parent = panel

local stroke = panel:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Transparency = 0.15
stroke.Color = Color3.fromRGB(150, 180, 255)
stroke.Parent = panel

local grad = panel:FindFirstChild("Gradient") or Instance.new("UIGradient")
grad.Name = "Gradient"
grad.Rotation = 90
grad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 10, 18)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(6, 6, 10)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 12, 20)),
})
grad.Parent = panel

-- Glow layer (fake bloom)
local glow = panel:FindFirstChild("Glow") or Instance.new("ImageLabel")
glow.Name = "Glow"
glow.BackgroundTransparency = 1
glow.Image = "rbxassetid://5028857084"
glow.ImageTransparency = 0.65
glow.ScaleType = Enum.ScaleType.Slice
glow.SliceCenter = Rect.new(24,24,276,276)
glow.AnchorPoint = Vector2.new(0.5, 0.5)
glow.Position = UDim2.fromScale(0.5, 0.5)
glow.Size = UDim2.fromScale(1.1, 1.3)
glow.ZIndex = 49
glow.Parent = panel

-- Scanlines overlay
local scan = panel:FindFirstChild("Scanlines") or Instance.new("ImageLabel")
scan.Name = "Scanlines"
scan.BackgroundTransparency = 1
scan.Image = "rbxassetid://1095708"
scan.ImageTransparency = 0.82
scan.ScaleType = Enum.ScaleType.Tile
scan.TileSize = UDim2.fromOffset(256, 256)
scan.Size = UDim2.fromScale(1, 1)
scan.ZIndex = 60
scan.Parent = panel

-- Noise overlay
local noise = panel:FindFirstChild("Noise") or Instance.new("ImageLabel")
noise.Name = "Noise"
noise.BackgroundTransparency = 1
noise.Image = "rbxassetid://144982778"
noise.ImageTransparency = 0.88
noise.ScaleType = Enum.ScaleType.Tile
noise.TileSize = UDim2.fromOffset(256, 256)
noise.Size = UDim2.fromScale(1, 1)
noise.ZIndex = 61
noise.Parent = panel

-- Impact flash
local flash = gui:FindFirstChild("ImpactFlash") or Instance.new("Frame")
flash.Name = "ImpactFlash"
flash.BackgroundColor3 = Color3.new(1,1,1)
flash.BackgroundTransparency = 1
flash.Size = UDim2.fromScale(1,1)
flash.ZIndex = 1000
flash.Parent = gui

-- NpcName label
local npcName = main:FindFirstChild("NpcName") or Instance.new("TextLabel")
npcName.Name = "NpcName"
npcName.BackgroundTransparency = 1
npcName.TextXAlignment = Enum.TextXAlignment.Left
npcName.TextYAlignment = Enum.TextYAlignment.Top
npcName.Position = UDim2.fromScale(0.03, 0.08)
npcName.Size = UDim2.fromScale(0.94, 0.18)
npcName.Font = Enum.Font.GothamBlack
npcName.TextSize = 26
npcName.TextColor3 = Color3.fromRGB(210, 230, 255)
npcName.TextStrokeTransparency = 0.6
npcName.Text = "???"
npcName.ZIndex = 70
npcName.Parent = main

-- Dialogue text label
local text = main:FindFirstChild("Text") or Instance.new("TextLabel")
text.Name = "Text"
text.BackgroundTransparency = 1
text.TextWrapped = true
text.TextXAlignment = Enum.TextXAlignment.Left
text.TextYAlignment = Enum.TextYAlignment.Top
text.Position = UDim2.fromScale(0.03, 0.25)
text.Size = UDim2.fromScale(0.94, 0.42)
text.Font = Enum.Font.Gotham
text.TextSize = 20
text.TextColor3 = Color3.fromRGB(235, 235, 245)
text.TextStrokeTransparency = 0.9
text.Text = ""
text.ZIndex = 70
text.Parent = main

-- Choices frame
local choices = main:FindFirstChild("Choices") or Instance.new("Frame")
choices.Name = "Choices"
choices.BackgroundTransparency = 1
choices.Position = UDim2.fromScale(0.03, 0.70)
choices.Size = UDim2.fromScale(0.94, 0.26)
choices.ZIndex = 70
choices.Parent = main

local list = choices:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 6)
list.Parent = choices

-- Choice template
local template = choices:FindFirstChild("ChoiceTemplate") or Instance.new("TextButton")
template.Name = "ChoiceTemplate"
template.Visible = false
template.AutoButtonColor = false
template.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
template.BackgroundTransparency = 0.25
template.Size = UDim2.new(1, 0, 0, 34)
template.Font = Enum.Font.GothamSemibold
template.TextSize = 18
template.TextColor3 = Color3.fromRGB(230, 230, 240)
template.TextXAlignment = Enum.TextXAlignment.Left
template.Text = "  ..."
template.ZIndex = 70
template.Parent = choices

local tCorner = template:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
tCorner.CornerRadius = UDim.new(0, 10)
tCorner.Parent = template

local tStroke = template:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
tStroke.Thickness = 1
tStroke.Transparency = 0.65
tStroke.Color = Color3.fromRGB(130, 160, 255)
tStroke.Parent = template

local selector = template:FindFirstChild("Selector") or Instance.new("TextLabel")
selector.Name = "Selector"
selector.BackgroundTransparency = 1
selector.Position = UDim2.fromOffset(10, 0)
selector.Size = UDim2.fromOffset(24, 34)
selector.Font = Enum.Font.GothamBlack
selector.TextSize = 18
selector.TextColor3 = Color3.fromRGB(140, 190, 255)
selector.Text = "▶"
selector.Visible = false
selector.ZIndex = 71
selector.Parent = template

-- Tiny “alive” motion: noise wiggle + scanline drift
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	if scan and scan.Parent then
		scan.Position = UDim2.fromOffset(0, math.floor((t * 18) % 6))
	end
	if noise and noise.Parent then
		noise.Position = UDim2.fromOffset(math.floor((t * 12) % 4), math.floor((t * 10) % 4))
	end
end)

-- Expose FX helpers
_G.__DialogueUIFX = _G.__DialogueUIFX or {}

function _G.__DialogueUIFX.ImpactFlash(intensity: number?)
	intensity = intensity or 0.85
	if not (flash and flash.Parent) then return end

	flash.BackgroundTransparency = 1
	local a = TweenService:Create(flash, TweenInfo.new(0.05, Enum.EasingStyle.Linear), {
		BackgroundTransparency = 1 - intensity
	})
	local b = TweenService:Create(flash, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	})
	a:Play()
	a.Completed:Connect(function()
		if b then b:Play() end
	end)
end

function _G.__DialogueUIFX.OpenAnim()
	if not (main and main.Parent) then return end

	main.Visible = true
	main.Position = UDim2.fromScale(0.5, 0.98)
	panel.BackgroundTransparency = 1
	stroke.Transparency = 1

	TweenService:Create(main, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.92)
	}):Play()

	TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.05
	}):Play()

	TweenService:Create(stroke, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 0.15
	}):Play()

	_G.__DialogueUIFX.ImpactFlash(0.35)
end

function _G.__DialogueUIFX.CloseAnim()
	if not (main and main.Parent) then return end

	TweenService:Create(main, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromScale(0.5, 0.98)
	}):Play()

	task.delay(0.14, function()
		if main and main.Parent then
			main.Visible = false
		end
	end)
end
