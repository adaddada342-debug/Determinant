-- StarterPlayerScripts/AwakeningClient.client.lua
-- Client-only cinematic + visuals for Awakening.
-- Debug: press J (Studio only) to force Awakening.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local plr = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE: RemoteEvent = remotes:WaitForChild("AwakeningEvent")

local gui: ScreenGui? = nil
local overlay: Frame? = nil
local titleLabel: TextLabel? = nil

local fx = {
	cc = nil :: ColorCorrectionEffect?,
	bloom = nil :: BloomEffect?,
	blur = nil :: BlurEffect?,
}

local active = false
local highlight: Highlight? = nil
local cleanupConn: RBXScriptConnection? = nil

local function ensureGui()
	if gui and gui.Parent then return end

	gui = Instance.new("ScreenGui")
	gui.Name = "AwakeningGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 9999
	gui.Parent = plr:WaitForChild("PlayerGui")

	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundColor3 = Color3.new(0,0,0)
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1,1)
	overlay.Parent = gui

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.5, 0.0),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	grad.Parent = overlay

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	titleLabel.Position = UDim2.fromScale(0.5, 0.18)
	titleLabel.Size = UDim2.fromScale(0.9, 0.18)
	titleLabel.Font = Enum.Font.Arcade
	titleLabel.TextScaled = true
	titleLabel.TextTransparency = 1
	titleLabel.TextStrokeTransparency = 0.25
	titleLabel.Parent = gui

	-- cheap glitch bars
	for i = 1, 16 do
		local bar = Instance.new("Frame")
		bar.Name = "GlitchBar"..i
		bar.BackgroundColor3 = Color3.new(1,1,1)
		bar.BackgroundTransparency = 1
		bar.BorderSizePixel = 0
		bar.Size = UDim2.new(1, 0, 0, math.random(2, 6))
		bar.Position = UDim2.new(0, 0, math.random(), 0)
		bar.Parent = gui
	end
end

local function ensureFx()
	if fx.cc and fx.cc.Parent then return end

	local cc = Lighting:FindFirstChild("__AWAKEN_CC") :: ColorCorrectionEffect?
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "__AWAKEN_CC"
		cc.Parent = Lighting
	end
	cc.Enabled = false
	cc.Brightness = 0
	cc.Contrast = 0
	cc.Saturation = 0
	cc.TintColor = Color3.new(1,1,1)

	local bloom = Lighting:FindFirstChild("__AWAKEN_BLOOM") :: BloomEffect?
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "__AWAKEN_BLOOM"
		bloom.Parent = Lighting
	end
	bloom.Enabled = false
	bloom.Intensity = 0
	bloom.Size = 24
	bloom.Threshold = 1

	local blur = Lighting:FindFirstChild("__AWAKEN_BLUR") :: BlurEffect?
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = "__AWAKEN_BLUR"
		blur.Parent = Lighting
	end
	blur.Enabled = false
	blur.Size = 0

	fx.cc = cc
	fx.bloom = bloom
	fx.blur = blur
end

local function themeColors(theme: string)
	if theme == "RAGE" then
		return Color3.fromRGB(255, 70, 110), Color3.fromRGB(255, 155, 190)
	elseif theme == "CALM" then
		return Color3.fromRGB(80, 220, 255), Color3.fromRGB(255, 240, 180)
	else
		return Color3.fromRGB(200, 120, 255), Color3.fromRGB(255, 160, 120)
	end
end

local function applyHighlight(theme: string, intensity: number)
	local char = plr.Character
	if not char then return end
	if highlight and highlight.Parent then highlight:Destroy() end

	local c1, c2 = themeColors(theme)
	highlight = Instance.new("Highlight")
	highlight.Name = "__AwakenHighlight"
	highlight.Adornee = char
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = c1
	highlight.OutlineColor = c2
	highlight.FillTransparency = 0.35
	highlight.OutlineTransparency = 0.2
	highlight.Parent = char

	-- pulse
	local t = TweenService:Create(highlight, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		FillTransparency = math.clamp(0.20 + (0.25 * (1 - intensity)), 0.15, 0.45),
		OutlineTransparency = 0.05,
	})
	t:Play()
end

local function setGlitchBars(alpha: number, theme: string)
	if not gui then return end
	local c1, _ = themeColors(theme)
	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("Frame") and child.Name:match("^GlitchBar") then
			child.BackgroundColor3 = c1
			child.BackgroundTransparency = 1 - alpha
			child.Position = UDim2.new(0, 0, math.random(), 0)
			child.Size = UDim2.new(1, 0, 0, math.random(2, 8))
		end
	end
end

local function beginCinematic(payload)
	active = true
	ensureGui()
	ensureFx()

	local theme = tostring(payload.theme or "RAGE")
	local intensity = tonumber(payload.intensity) or 0.6
	local duration = tonumber(payload.duration) or 18

	local c1, c2 = themeColors(theme)

	fx.cc.Enabled = true
	fx.bloom.Enabled = true
	fx.blur.Enabled = true

	fx.cc.TintColor = c1:Lerp(Color3.new(1,1,1), 0.35)
	fx.cc.Saturation = 0
	fx.cc.Contrast = 0
	fx.cc.Brightness = 0

	fx.bloom.Intensity = 0
	fx.blur.Size = 0

	overlay.BackgroundColor3 = c2
	overlay.BackgroundTransparency = 1

	titleLabel.Text = (theme == "CALM" and "AWAKENING: FOCUS") or (theme == "DUAL" and "AWAKENING: DUALITY") or "AWAKENING: RAGE"
	titleLabel.TextColor3 = c2

	applyHighlight(theme, intensity)

	-- fade in
	TweenService:Create(overlay, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.70}):Play()
	TweenService:Create(titleLabel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0}):Play()

	TweenService:Create(fx.cc, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Saturation = 0.35 + intensity * 0.55,
		Contrast = 0.18 + intensity * 0.55,
		Brightness = 0.06 + intensity * 0.10,
	}):Play()
	TweenService:Create(fx.bloom, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Intensity = 0.6 + intensity * 1.2,
		Threshold = 0.9,
	}):Play()
	TweenService:Create(fx.blur, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = 4 + intensity * 10,
	}):Play()

	-- cheap animated glitch
	if cleanupConn then cleanupConn:Disconnect() end
	cleanupConn = RunService.RenderStepped:Connect(function()
		if not active then return end
		setGlitchBars(0.08 + intensity * 0.10, theme)
	end)

	-- auto-fade title
	task.delay(1.3, function()
		if not active then return end
		TweenService:Create(titleLabel, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0.65}):Play()
	end)

	-- hard stop if server forgets to end
	task.delay(duration + 0.25, function()
		-- no spam: just let it time out server-side
	end)
end

local function pulse(payload)
	if not active then return end
	local intensity = tonumber(payload.intensity) or 0.6
	local theme = tostring(payload.theme or "RAGE")

	local _, c2 = themeColors(theme)
	overlay.BackgroundColor3 = c2

	local flashIn = TweenService:Create(overlay, TweenInfo.new(0.08, Enum.EasingStyle.Linear), {BackgroundTransparency = 0.55})
	local flashOut = TweenService:Create(overlay, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.72})
	flashIn:Play()
	flashIn.Completed:Once(function()
		if active then flashOut:Play() end
	end)

	if fx.bloom then
		TweenService:Create(fx.bloom, TweenInfo.new(0.10, Enum.EasingStyle.Linear), {Intensity = 1.2 + intensity * 1.4}):Play()
		task.delay(0.18, function()
			if active and fx.bloom then
				TweenService:Create(fx.bloom, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Intensity = 0.6 + intensity * 1.2}):Play()
			end
		end)
	end

	setGlitchBars(0.10 + intensity * 0.18, theme)
end

local function endCinematic()
	active = false

	if cleanupConn then
		cleanupConn:Disconnect()
		cleanupConn = nil
	end

	if highlight and highlight.Parent then
		highlight:Destroy()
		highlight = nil
	end

	if overlay then
		TweenService:Create(overlay, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	end
	if titleLabel then
		TweenService:Create(titleLabel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 1}):Play()
	end

	task.delay(0.4, function()
		if fx.cc then fx.cc.Enabled = false end
		if fx.bloom then fx.bloom.Enabled = false end
		if fx.blur then fx.blur.Enabled = false end
	end)

	-- hide glitch bars
	if gui then
		for _, child in ipairs(gui:GetChildren()) do
			if child:IsA("Frame") and child.Name:match("^GlitchBar") then
				child.BackgroundTransparency = 1
			end
		end
	end
end

RE.OnClientEvent:Connect(function(kind, payload)
	if kind == "Begin" then
		beginCinematic(payload or {})
	elseif kind == "Pulse" then
		pulse(payload or {})
	elseif kind == "End" then
		endCinematic()
	end
end)

-- Debug: J key in Studio
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.J then
		if RunService:IsStudio() then
			RE:FireServer("DebugAwaken")
		end
	end
end)
