-- AsrielClient.client.lua
-- Client rendering:
-- - Boss bar UI (shows Asriel owner's DISPLAY NAME only)
-- - Per-letter floating text that FITS the bar + afterimages
-- - Overhead typed bubbles for ALL chat
-- - Maxed-out VFX for Asriel abilities (client side, but server-broadcast so everyone sees)
--
-- AMENDED:
-- ✅ PostFX pooling (no spam-creating Bloom/Blur every cast)
-- ✅ Camera shake + impact frame flashes (client-only feel boost)
-- ✅ "PresenceTick" visuals for the passive aura
-- ✅ "HitConfirm" local feedback when YOU get hit

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local TextService = game:GetService("TextService")

local localPlayer = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AsrielEvent = Remotes:WaitForChild("AsrielEvent")

-- ========= Tiny helpers =========
local function rng(seed: number) return Random.new(seed) end
local function tween(obj, ti, props)
	local tw = TweenService:Create(obj, ti, props)
	tw:Play()
	return tw
end

-- ========= Camera Shake (lightweight, client-only) =========
local cam = workspace.CurrentCamera
local shakeAmp = 0
local shakeTime = 0

local function addShake(intensity: number, duration: number)
	shakeAmp = math.max(shakeAmp, intensity)
	shakeTime = math.max(shakeTime, duration)
end

RunService.RenderStepped:Connect(function(dt)
	if shakeTime <= 0 or shakeAmp <= 0 then return end
	shakeTime -= dt

	local a = shakeAmp * math.clamp(shakeTime / 0.35, 0, 1)
	local ox = (math.random() - 0.5) * 2 * a
	local oy = (math.random() - 0.5) * 2 * a
	local oz = (math.random() - 0.5) * 2 * (a * 0.25)

	-- Subtle, doesn’t break aiming
	cam.CFrame = cam.CFrame * CFrame.new(ox, oy, oz)

	if shakeTime <= 0 then
		shakeAmp = 0
	end
end)

-- ========= Impact Frame (1-2 frames flash) =========
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "__AsrielImpactFrames"
flashGui.IgnoreGuiInset = true
flashGui.ResetOnSpawn = false
flashGui.Parent = localPlayer:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.Size = UDim2.fromScale(1, 1)
flash.Parent = flashGui

local function impactFlash(power: number)
	power = math.clamp(power, 0, 1)
	flash.BackgroundTransparency = 1
	flash.Visible = true

	-- two quick pops
	tween(flash, TweenInfo.new(0.03, Enum.EasingStyle.Linear), {BackgroundTransparency = 1 - 0.55 * power})
	task.delay(0.04, function()
		tween(flash, TweenInfo.new(0.05, Enum.EasingStyle.Linear), {BackgroundTransparency = 1})
	end)
	task.delay(0.12, function()
		flash.Visible = false
	end)
end

-- ========= PostFX Pool (Bloom + Blur + ColorCorrection) =========
local FX = {}
FX.bloom = Instance.new("BloomEffect")
FX.bloom.Intensity = 0
FX.bloom.Size = 56
FX.bloom.Threshold = 0.85
FX.bloom.Parent = Lighting

FX.blur = Instance.new("BlurEffect")
FX.blur.Size = 0
FX.blur.Parent = Lighting

FX.cc = Instance.new("ColorCorrectionEffect")
FX.cc.Brightness = 0
FX.cc.Contrast = 0
FX.cc.Saturation = 0
FX.cc.TintColor = Color3.new(1, 1, 1)
FX.cc.Parent = Lighting

local function punchPostFX(intensity: number, duration: number, tint: Color3?)
	intensity = math.clamp(intensity, 0, 3)

	if tint then FX.cc.TintColor = tint end

	tween(FX.bloom, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Intensity = intensity})
	tween(FX.blur, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = math.clamp(intensity * 8, 0, 28)})
	tween(FX.cc, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Contrast = math.clamp(0.15 + intensity * 0.12, 0, 0.55),
		Saturation = math.clamp(-0.05 + intensity * 0.08, -0.1, 0.25),
	})

	task.delay(duration, function()
		tween(FX.bloom, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Intensity = 0})
		tween(FX.blur, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = 0})
		tween(FX.cc, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Contrast = 0, Saturation = 0})
	end)
end

-- ========= UI: Boss Bar =========
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "__AsrielUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

local bossFrame = Instance.new("Frame")
bossFrame.AnchorPoint = Vector2.new(0.5, 0)
bossFrame.Position = UDim2.fromScale(0.5, 0.03)
bossFrame.Size = UDim2.fromScale(0.72, 0.075)
bossFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
bossFrame.BackgroundTransparency = 0.18
bossFrame.BorderSizePixel = 0
bossFrame.Visible = false
bossFrame.Parent = screenGui

local bossCorner = Instance.new("UICorner")
bossCorner.CornerRadius = UDim.new(0, 8)
bossCorner.Parent = bossFrame

local bossStroke = Instance.new("UIStroke")
bossStroke.Thickness = 2
bossStroke.Color = Color3.fromRGB(255, 255, 255)
bossStroke.Transparency = 0.18
bossStroke.Parent = bossFrame

local inner = Instance.new("Frame")
inner.BackgroundTransparency = 1
inner.Size = UDim2.fromScale(1, 1)
inner.Parent = bossFrame
local innerStroke = Instance.new("UIStroke")
innerStroke.Thickness = 1
innerStroke.Color = Color3.fromRGB(255, 255, 255)
innerStroke.Transparency = 0.70
innerStroke.Parent = inner

-- rainbow overlay
local rainbowLayer = Instance.new("Frame")
rainbowLayer.Name = "Rainbow"
rainbowLayer.Size = UDim2.fromScale(1, 1)
rainbowLayer.BackgroundTransparency = 1
rainbowLayer.Parent = bossFrame

local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
	ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 160, 0)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 255, 0)),
	ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 120)),
	ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 160, 255)),
	ColorSequenceKeypoint.new(0.83, Color3.fromRGB(170, 0, 255)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 120)),
})
grad.Offset = Vector2.new(0, 0)
grad.Rotation = 0
grad.Parent = rainbowLayer

-- scanlines
local scan = Instance.new("Frame")
scan.Name = "Scanlines"
scan.Size = UDim2.fromScale(1, 1)
scan.BackgroundTransparency = 1
scan.Parent = bossFrame
for i = 1, 20 do
	local line = Instance.new("Frame")
	line.BorderSizePixel = 0
	line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	line.BackgroundTransparency = 0.93
	line.Size = UDim2.new(1, 0, 0, 1)
	line.Position = UDim2.new(0, 0, (i - 1) / 20, 0)
	line.Parent = scan
end

-- sparkles
local sparkLayer = Instance.new("Frame")
sparkLayer.Name = "Sparks"
sparkLayer.Size = UDim2.fromScale(1, 1)
sparkLayer.BackgroundTransparency = 1
sparkLayer.ClipsDescendants = true
sparkLayer.Parent = bossFrame

local function spawnSpark()
	local s = Instance.new("Frame")
	s.BorderSizePixel = 0
	s.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	s.BackgroundTransparency = 0.25
	s.Size = UDim2.fromOffset(2, 2)
	s.Position = UDim2.fromScale(math.random(), math.random())
	s.Parent = sparkLayer

	local life = 0.14 + math.random() * 0.22
	tween(s, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
		Position = s.Position + UDim2.fromScale((math.random() - 0.5) * 0.04, (math.random() - 0.5) * 0.07),
	})

	task.delay(life, function()
		if s then s:Destroy() end
	end)
end

-- ========= Boss Name: floating letters that FIT =========
local textLayer = Instance.new("Frame")
textLayer.Name = "TextLayer"
textLayer.BackgroundTransparency = 1
textLayer.Size = UDim2.fromScale(1, 1)
textLayer.ClipsDescendants = true
textLayer.Parent = bossFrame

local letters = {} -- { label, baseX, baseY, vx, vy, seed, ghostTimer }

local function clearLetters()
	for _, L in ipairs(letters) do
		if L.label then L.label:Destroy() end
	end
	letters = {}
end

local function spawnGhost(original: TextLabel)
	local g = original:Clone()
	g.Name = "Ghost"
	g.ZIndex = original.ZIndex - 1
	g.TextTransparency = 0.45
	g.TextStrokeTransparency = 0.55
	g.Parent = textLayer

	g.Position = original.Position + UDim2.fromScale((math.random() - 0.5) * 0.008, (math.random() - 0.5) * 0.02)

	local life = 0.16 + math.random() * 0.14
	tween(g, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Position = g.Position + UDim2.fromScale((math.random() - 0.5) * 0.01, (math.random() - 0.5) * 0.02),
	})

	task.delay(life, function()
		if g then g:Destroy() end
	end)
end

local function newLetter(ch: string, xScale: number, yScale: number, wScale: number, hScale: number)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Size = UDim2.fromScale(wScale, hScale)
	lbl.Position = UDim2.fromScale(xScale, yScale)
	lbl.Font = Enum.Font.Arcade
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lbl.TextStrokeTransparency = 0.18
	lbl.Text = ch
	lbl.ZIndex = 30
	lbl.Parent = textLayer
	return lbl
end

local function setFloatingName(nameText: string)
	clearLetters()
	if not nameText or nameText == "" then return end

	if #nameText > 28 then
		nameText = nameText:sub(1, 27) .. "…"
	end

	local absSize = bossFrame.AbsoluteSize
	local barW = math.max(1, absSize.X)
	local barH = math.max(1, absSize.Y)

	local targetFontPx = math.floor(barH * 0.78)
	targetFontPx = math.clamp(targetFontPx, 18, 64)

	local spacingPx = math.floor(targetFontPx * 0.10)

	local fullSize = TextService:GetTextSize(nameText, targetFontPx, Enum.Font.Arcade, Vector2.new(9999, 9999))
	local totalW = math.max(1, fullSize.X) + spacingPx * (#nameText - 1)

	local maxW = barW * 0.90
	if totalW > maxW then
		local scale = maxW / totalW
		targetFontPx = math.floor(targetFontPx * scale)
		targetFontPx = math.clamp(targetFontPx, 14, 64)
		spacingPx = math.floor(targetFontPx * 0.10)
		fullSize = TextService:GetTextSize(nameText, targetFontPx, Enum.Font.Arcade, Vector2.new(9999, 9999))
		totalW = math.max(1, fullSize.X) + spacingPx * (#nameText - 1)
	end

	local letterHScale = (targetFontPx * 1.18) / barH
	letterHScale = math.clamp(letterHScale, 0.60, 0.92)

	local startXPx = (barW - totalW) * 0.5
	local cursorPx = startXPx
	local yScale = 0.52

	for i = 1, #nameText do
		local ch = nameText:sub(i, i)
		local chSize = TextService:GetTextSize(ch, targetFontPx, Enum.Font.Arcade, Vector2.new(9999, 9999))
		local chW = math.max(1, chSize.X)

		local centerXPx = cursorPx + chW * 0.5
		local xScale = centerXPx / barW

		local letterWScale = (chW + 2) / barW
		letterWScale = math.clamp(letterWScale, 0.018, 0.10)

		local lbl = newLetter(ch, xScale, yScale, letterWScale, letterHScale)
		if ch == " " then
			lbl.TextTransparency = 1
			lbl.TextStrokeTransparency = 1
		end

		table.insert(letters, {
			label = lbl,
			baseX = xScale,
			baseY = yScale,
			vx = (math.random() - 0.5) * 0.018,
			vy = (math.random() - 0.5) * 0.013,
			seed = math.random() * 1000,
			ghostTimer = 0,
		})

		cursorPx += chW + spacingPx
	end
end

local activeBossUserId: number? = nil

local function resolveDisplayName(userId: number?, fallback: string?)
	if userId then
		local p = Players:GetPlayerByUserId(userId)
		if p then return p.DisplayName end
	end
	return fallback or "???"
end

local function setBossBar(userId: number?, fallbackName: string?)
	activeBossUserId = userId
	if userId then
		bossFrame.Visible = true
		setFloatingName(resolveDisplayName(userId, fallbackName))
	else
		bossFrame.Visible = false
		clearLetters()
	end
end

-- ========= Boss bar animation loop =========
local activeUI = false
local t = 0
local jitterSeed = math.random() * 1000
local basePos = bossFrame.Position

local function setBossUIVisible(on: boolean)
	activeUI = on
	bossFrame.Visible = on
	if not on then
		bossFrame.Position = basePos
		grad.Offset = Vector2.new(0, 0)
		grad.Rotation = 0
		clearLetters()
	end
end

RunService.RenderStepped:Connect(function(dt)
	if not activeUI then return end
	t += dt

	grad.Offset = Vector2.new((t * 0.65) % 1, 0)
	grad.Rotation = 9 * math.sin(t * 1.6)

	if math.random() < 0.42 then
		spawnSpark()
	end

	-- slightly more “alive”
	local jx = math.floor((math.noise(jitterSeed, t * 12) - 0.5) * 8)
	local jy = math.floor((math.noise(jitterSeed + 99, t * 10) - 0.5) * 6)
	bossFrame.Position = basePos + UDim2.fromOffset(jx, jy)

	scan.Rotation = math.sin(t * 2.0) * 0.8

	for _, L in ipairs(letters) do
		local lbl = L.label
		if lbl and lbl.Parent then
			local wobX = math.sin(t * 2.1 + L.seed) * 0.010
			local wobY = math.cos(t * 2.6 + L.seed) * 0.024

			L.vx = (L.vx * 0.92) + (L.baseX - lbl.Position.X.Scale) * 0.08
			L.vy = (L.vy * 0.92) + (L.baseY - lbl.Position.Y.Scale) * 0.10

			local nx = L.baseX + wobX + L.vx * 0.03
			local ny = L.baseY + wobY + L.vy * 0.04

			lbl.Position = UDim2.fromScale(nx, ny)
			lbl.Rotation = math.sin(t * 3.2 + L.seed) * 4

			L.ghostTimer += dt
			if L.ghostTimer > 0.050 then
				L.ghostTimer = 0
				if lbl.TextTransparency < 1 then
					spawnGhost(lbl)
				end
			end
		end
	end
end)

-- ========= Overhead typed bubble system (unchanged from your version) =========
local bubbleByUserId: {[number]: BillboardGui} = {}
local typingJobs: {[number]: number} = {}

local function getCharByUserId(userId: number): Model?
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == userId then
			return p.Character
		end
	end
	return nil
end

local function destroyBubble(userId: number)
	local b = bubbleByUserId[userId]
	if b then
		b:Destroy()
		bubbleByUserId[userId] = nil
	end
end

local function makeBubble(userId: number, style: string): BillboardGui?
	local char = getCharByUserId(userId)
	if not char then return nil end
	local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	if not head then return nil end

	destroyBubble(userId)

	local gui = Instance.new("BillboardGui")
	gui.Name = "__TypedBubble"
	gui.Size = UDim2.fromOffset(420, 110)
	gui.StudsOffset = Vector3.new(0, 3.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
	gui.Adornee = head
	gui.Parent = char

	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = frame

	local txt = Instance.new("TextLabel")
	txt.Name = "Text"
	txt.BackgroundTransparency = 1
	txt.Position = UDim2.fromScale(0.04, 0.12)
	txt.Size = UDim2.fromScale(0.92, 0.76)
	txt.TextXAlignment = Enum.TextXAlignment.Left
	txt.TextYAlignment = Enum.TextYAlignment.Top
	txt.Font = Enum.Font.Arcade
	txt.TextScaled = true
	txt.TextWrapped = true
	txt.Text = ""
	txt.Parent = frame

	if style == "asriel" then
		stroke.Color = Color3.fromRGB(255, 255, 255)
		txt.TextColor3 = Color3.fromRGB(255, 255, 255)
		txt.TextStrokeTransparency = 0.70
	else
		stroke.Color = Color3.fromRGB(255, 255, 255)
		txt.TextColor3 = Color3.fromRGB(255, 255, 255)
		txt.TextStrokeTransparency = 0.85
	end

	bubbleByUserId[userId] = gui
	return gui
end

local function typeText(userId: number, text: string, style: string)
	local gui = makeBubble(userId, style)
	if not gui then return end
	local frame = gui:FindFirstChild("Frame")
	local lbl = frame and frame:FindFirstChild("Text")
	lbl = lbl :: TextLabel
	if not lbl then return end

	local token = (typingJobs[userId] or 0) + 1
	typingJobs[userId] = token

	task.spawn(function()
		lbl.Text = ""
		local speed = (style == "asriel") and 0.018 or 0.012
		for i = 1, #text do
			if typingJobs[userId] ~= token then return end
			lbl.Text = string.sub(text, 1, i)
			task.wait(speed)
		end

		task.delay(2.2, function()
			if typingJobs[userId] == token and bubbleByUserId[userId] == gui then
				destroyBubble(userId)
			end
		end)
	end)
end

-- ========= VFX helpers (your existing ones) =========
local function makeFXFolder(tag: string)
	local f = Instance.new("Folder")
	f.Name = "__AsrielFX_" .. tag
	f.Parent = workspace
	Debris:AddItem(f, 4)
	return f
end

local function neonPart(parent, size, cframe, color, transparency)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0.2
	p.Size = size
	p.CFrame = cframe
	p.Parent = parent
	return p
end

local function ring(parent, pos, radius, thickness, color, alpha)
	local p = neonPart(parent, Vector3.new(1,1,1), CFrame.new(pos) * CFrame.Angles(math.rad(90),0,0), color, alpha or 0.25)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Scale = Vector3.new(radius*2, thickness, radius*2)
	mesh.Parent = p
	return p, mesh
end

local function star(parent, pos, size, color, alpha)
	local p = neonPart(parent, Vector3.new(size,size,size), CFrame.new(pos), color, alpha or 0.1)
	p.Shape = Enum.PartType.Ball
	return p
end

-- ========= Ability VFX (your existing, but “punched”) =========
local function vfxStarBlazing(payload)
	local origin = payload.origin
	local seed = payload.seed
	local R = rng(seed)

	local fx = makeFXFolder("StarBlazing")
	punchPostFX(1.35, 0.60, Color3.fromRGB(255, 255, 255))
	addShake(0.7, 0.28)
	impactFlash(0.35)

	for i = 1, 26 do
		local tt = i / 26
		local spawnPos = origin + Vector3.new(R:NextNumber(30, 70), R:NextNumber(45, 78), R:NextNumber(-28, 28))
		local hitPos = origin + Vector3.new(R:NextNumber(-48, 48), R:NextNumber(2, 8), R:NextNumber(-48, 48))

		local s = star(fx, spawnPos, R:NextNumber(1.0, 2.3), Color3.fromHSV(tt, 1, 1), 0.08)
		tween(s, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {CFrame = CFrame.new(hitPos), Transparency = 0.02})

		task.delay(0.32, function()
			addShake(0.9, 0.20)
			impactFlash(0.25)
			for rI = 1, 4 do
				local part, mesh = ring(fx, hitPos, 2 + rI*2, 0.18, Color3.fromHSV(tt, 1, 1), 0.28)
				tween(mesh, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = Vector3.new((22+rI*10), 0.18, (22+rI*10))})
				tween(part, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1})
				Debris:AddItem(part, 1)
			end
			s:Destroy()
		end)

		task.wait(0.025)
	end
end

local function vfxShockerBreaker(payload)
	local origin = payload.origin
	local seed = payload.seed
	local R = rng(seed)
	local fx = makeFXFolder("ShockerBreaker")
	punchPostFX(1.15, 0.55, Color3.fromRGB(200, 235, 255))
	addShake(0.55, 0.25)

	for i = 1, 10 do
		local p0 = origin + Vector3.new(R:NextNumber(-42, 42), 0.5, R:NextNumber(-42, 42))
		local warn = neonPart(fx, Vector3.new(5, 0.2, 5), CFrame.new(p0), Color3.fromRGB(255, 255, 255), 0.35)
		Debris:AddItem(warn, 1)

		task.delay(0.16, function()
			impactFlash(0.18)
			addShake(0.9, 0.22)

			local beam = neonPart(fx, Vector3.new(1.4, 60, 1.4), CFrame.new(p0 + Vector3.new(0, 30, 0)), Color3.fromRGB(120, 190, 255), 0.18)
			tween(beam, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1})
			Debris:AddItem(beam, 1)

			for rI = 1, 3 do
				local part, mesh = ring(fx, p0 + Vector3.new(0, 0.2, 0), 3, 0.18, Color3.fromRGB(120, 190, 255), 0.32)
				tween(mesh, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = Vector3.new(34 + rI*12, 0.18, 34 + rI*12)})
				tween(part, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1})
				Debris:AddItem(part, 1)
			end
		end)

		task.wait(0.055)
	end
end

local function vfxChaosSabers(payload)
	local origin = payload.origin
	local seed = payload.seed
	local R = rng(seed)
	local fx = makeFXFolder("ChaosSabers")
	punchPostFX(1.25, 0.55, Color3.fromRGB(255, 255, 255))
	addShake(0.75, 0.22)
	impactFlash(0.22)

	for swipe = 1, 6 do
		local side = (swipe % 2 == 1) and 1 or -1
		local start = origin + Vector3.new(side * 38, 10 + swipe*2, R:NextNumber(-10, 10))
		local finish = origin + Vector3.new(-side * 38, 6 + swipe*1.5, R:NextNumber(-10, 10))

		local blade = neonPart(fx, Vector3.new(1.6, 26, 1.6), CFrame.new(start, finish), Color3.fromRGB(255, 255, 255), 0.10)
		blade.CFrame = blade.CFrame * CFrame.Angles(0, 0, math.rad(45))
		tween(blade, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = CFrame.new(finish, start), Transparency = 1})
		Debris:AddItem(blade, 1)

		task.delay(0.10, function()
			addShake(0.55, 0.16)
			for i = 1, 14 do
				local sp = origin + Vector3.new(R:NextNumber(-14, 14), R:NextNumber(3, 12), R:NextNumber(-14, 14))
				local s = star(fx, sp, R:NextNumber(0.25, 0.7), Color3.fromRGB(255, 255, 255), 0.20)
				tween(s, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1, Size = Vector3.new(0.1,0.1,0.1)})
				Debris:AddItem(s, 1)
			end
		end)

		task.wait(0.085)
	end
end

local function vfxPurgeHyperGoner(payload)
	local origin = payload.origin
	local seed = payload.seed
	local R = rng(seed)
	local fx = makeFXFolder("Purge")

	-- Phase shift should feel like “gravity got angry”
	punchPostFX(1.9, 1.2, Color3.fromRGB(230, 230, 230))
	addShake(1.2, 0.60)
	impactFlash(0.55)

	for i = 1, 7 do
		local part, mesh = ring(fx, origin + Vector3.new(0, 2 + i*0.2, 0), 6 + i*4, 0.25, Color3.fromRGB(20,20,20), 0.18)
		tween(mesh, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = Vector3.new((86+i*20), 0.25, (86+i*20))})
		tween(part, TweenInfo.new(0.48, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1})
		Debris:AddItem(part, 1)
	end

	for i = 1, 150 do
		local spawnPos = origin + Vector3.new(R:NextNumber(-95, 95), R:NextNumber(8, 60), R:NextNumber(-95, 95))
		local obj = neonPart(fx, Vector3.new(0.8,0.8,0.8), CFrame.new(spawnPos), Color3.fromRGB(255,255,255), 0.4)
		obj.Shape = Enum.PartType.Block
		tween(obj, TweenInfo.new(0.52, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {CFrame = CFrame.new(origin + Vector3.new(0, 10, 0)), Transparency = 1})
		Debris:AddItem(obj, 1)
		task.wait(0.007)
	end
end

local function vfxFinalRainbow(payload)
	local origin = payload.origin
	local seed = payload.seed
	local R = rng(seed)
	local fx = makeFXFolder("Final")

	-- Final should be rude
	punchPostFX(2.4, 1.8, Color3.fromRGB(255, 255, 255))
	addShake(1.8, 0.90)
	impactFlash(0.85)

	local beam = neonPart(fx, Vector3.new(7, 190, 7), CFrame.new(origin + Vector3.new(0, 95, 0)), Color3.fromRGB(255,255,255), 0.22)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = beam
	Debris:AddItem(beam, 2)

	for i = 1, 320 do
		local tt = i / 320
		local ang = tt * math.pi * 2
		local rad = R:NextNumber(4, 28)
		local y = R:NextNumber(6, 130)
		local pos = origin + Vector3.new(math.cos(ang)*rad, y, math.sin(ang)*rad)
		local s = star(fx, pos, R:NextNumber(0.22, 0.9), Color3.fromHSV(tt, 1, 1), 0.10)
		tween(s, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1})
		Debris:AddItem(s, 2)
	end

	for rI = 1, 6 do
		local part, rmesh = ring(fx, origin + Vector3.new(0, 0.25 + rI*0.05, 0), 3, 0.22, Color3.fromRGB(255,255,255), 0.28)
		task.delay((rI-1)*0.055, function()
			tween(rmesh, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = Vector3.new(300, 0.22, 300)})
			tween(part, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1})
			Debris:AddItem(part, 2)
		end)
	end

	tween(beam, TweenInfo.new(1.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1})
end

-- ========= PresenceTick VFX (new) =========
local function vfxPresenceTick(payload)
	local origin = payload.origin
	local intensity = tonumber(payload.intensity) or 0.2
	local phase = tonumber(payload.phase) or 1

	-- Keep it cheap: a couple dark rings + slight post punch
	local fx = makeFXFolder("Presence")
	local dark = (phase == 2) and Color3.fromRGB(35,35,35) or Color3.fromRGB(55,55,55)

	punchPostFX(0.35 + intensity * 0.55, 0.18, Color3.fromRGB(255, 255, 255))

	for i = 1, 2 do
		local part, mesh = ring(fx, origin + Vector3.new(0, 1.2 + i*0.05, 0), 4, 0.18, dark, 0.55)
		tween(mesh, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = Vector3.new(52 + i*18, 0.18, 52 + i*18)})
		tween(part, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1})
		Debris:AddItem(part, 0.8)
	end
end

-- ========= Input (only the Asriel owner should send requests) =========
local abilityKeymap = {
	[Enum.KeyCode.Z] = "STAR_BLAZING",
	[Enum.KeyCode.X] = "SHOCKER_BREAKER",
	[Enum.KeyCode.C] = "CHAOS_SABERS",
	[Enum.KeyCode.V] = "PURGE",
	[Enum.KeyCode.B] = "FINAL",
}

local function isLocalAsrielOwner(): boolean
	return activeBossUserId ~= nil and activeBossUserId == localPlayer.UserId
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not isLocalAsrielOwner() then return end

	local token = abilityKeymap[input.KeyCode]
	if token then
		AsrielEvent:FireServer("Ability", { token = token })
	end
end)

-- ========= Remote events =========
AsrielEvent.OnClientEvent:Connect(function(kind, payload)
	if kind == "AsrielStart" then
		setBossBar(payload.ownerUserId, payload.ownerDisplayName or payload.ownerName)
		setBossUIVisible(true)

	elseif kind == "AsrielEnd" then
		if activeBossUserId == payload.ownerUserId then
			setBossUIVisible(false)
			setBossBar(nil, nil)
		end

	elseif kind == "OverheadTyped" then
		typeText(payload.ownerUserId, tostring(payload.text or ""), tostring(payload.style or "default"))

	elseif kind == "PresenceTick" then
		-- everyone sees it, but keep it subtle
		vfxPresenceTick(payload)

	elseif kind == "HitConfirm" then
		-- If YOU are the target, add extra shake/flash
		if payload.targetUserId == localPlayer.UserId then
			local intensity = tonumber(payload.intensity) or 0.3
			addShake(0.9 + intensity * 1.2, 0.35)
			impactFlash(0.35 + intensity * 0.45)
			punchPostFX(0.45 + intensity * 0.8, 0.22, Color3.fromRGB(255, 255, 255))
		end

	elseif kind == "VFX" then
		local ability = payload.ability
		if ability == "STAR_BLAZING" then
			vfxStarBlazing(payload)
		elseif ability == "SHOCKER_BREAKER" then
			vfxShockerBreaker(payload)
		elseif ability == "CHAOS_SABERS" then
			vfxChaosSabers(payload)
		elseif ability == "PURGE" then
			vfxPurgeHyperGoner(payload)
		elseif ability == "FINAL" then
			vfxFinalRainbow(payload)
		end
	end
end)
