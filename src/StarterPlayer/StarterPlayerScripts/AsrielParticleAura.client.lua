-- StarterPlayerScripts/AsrielParticleAura.client.lua
-- Particle-based rainbow "merged" aura (like your screenshots)
-- FULL AMENDED (NO TYPE ANNOTATIONS):
-- ✅ Built-in textures (reliable)
-- ✅ Rainbow is forced (RainbowSkin layer)
-- ✅ Local post-FX does NOT desaturate (positive saturation)
-- ✅ Phase scaling
-- ✅ Proper cleanup + disconnect RenderStepped

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AsrielEvent = Remotes:WaitForChild("AsrielEvent")

-- =========================
-- CONFIG
-- =========================
local CFG = {
	MaxDistance = 260,

	-- Built-in textures (always exist)
	Tex = {
		Glow  = "rbxasset://textures/particles/flare_main.dds",
		Smoke = "rbxasset://textures/particles/smoke_main.dds",
		Spark = "rbxasset://textures/particles/sparkles_main.dds",
	},

	-- Rainbow
	RainbowS = 1.0,
	RainbowV = 1.0,

	-- Phase 1 rates
	Base = {
		RainbowSkinRate = 140, -- guaranteed rainbow layer
		CoreGlowRate    = 55,
		StarRate        = 70,
		GlitchRate      = 95,
		StreakRate      = 28,
		SmokeRate       = 14,
	},

	Phase2Mul = 1.65,

	-- Hug the body (low speed + high drag + locked)
	HugDrag = 9.0,
	HugSpeedMin = 0.05,
	HugSpeedMax = 1.25,

	-- Local post FX (DO NOT desaturate)
	LocalPostFX = true,
	BloomIntensity = 0.28,
	BloomPulseAdd = 0.28,
	CC_Saturation = 0.22, -- IMPORTANT: positive
	CC_Contrast = 0.11,
	CC_Brightness = -0.02,
}

-- =========================
-- HELPERS
-- =========================
local function hsv(h, s, v)
	return Color3.fromHSV((h % 1), math.clamp(s, 0, 1), math.clamp(v, 0, 1))
end

local function rainbowSequence(offset)
	local keys = {}
	for i = 0, 6 do
		local t = i / 6
		keys[#keys + 1] = ColorSequenceKeypoint.new(t, hsv(t + offset, CFG.RainbowS, CFG.RainbowV))
	end
	return ColorSequence.new(keys)
end

local function numRange(a, b)
	return NumberRange.new(a, b)
end

local function numSeq(points)
	local k = {}
	for _, p in ipairs(points) do
		k[#k + 1] = NumberSequenceKeypoint.new(p[1], p[2])
	end
	return NumberSequence.new(k)
end

local function getCharByUserId(uid)
	local p = Players:GetPlayerByUserId(uid)
	return p and p.Character or nil
end

local function getRigParts(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	return hrp, torso, head
end

local function makeAttachment(parent, name, pos)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = pos
	a.Parent = parent
	return a
end

local function makeEmitter(parent, props)
	local pe = Instance.new("ParticleEmitter")
	for k, v in pairs(props) do
		pe[k] = v
	end
	pe.Parent = parent
	return pe
end

-- =========================
-- STATE
-- =========================
local activeUid = nil
local phase = 1

local fxFolder = nil
local highlight = nil
local pointLight = nil

local bloom = nil
local cc = nil

local emitters = {}
local attachments = {}
local pulseConn = nil
local pulseT = 0

local function ensureLocalPostFX(on)
	if not CFG.LocalPostFX then return end

	if on then
		if not bloom then
			bloom = Instance.new("BloomEffect")
			bloom.Intensity = CFG.BloomIntensity
			bloom.Size = 42
			bloom.Threshold = 0.9
			bloom.Parent = Lighting
		end
		if not cc then
			cc = Instance.new("ColorCorrectionEffect")
			cc.Brightness = CFG.CC_Brightness
			cc.Contrast = CFG.CC_Contrast
			cc.Saturation = CFG.CC_Saturation
			cc.Parent = Lighting
		end
	else
		if bloom then bloom:Destroy() bloom = nil end
		if cc then cc:Destroy() cc = nil end
	end
end

local function clearFX()
	if pulseConn then
		pulseConn:Disconnect()
		pulseConn = nil
	end
	pulseT = 0

	for _, pe in ipairs(emitters) do
		if pe then pe:Destroy() end
	end
	emitters = {}

	for _, a in ipairs(attachments) do
		if a then a:Destroy() end
	end
	attachments = {}

	if highlight then highlight:Destroy() highlight = nil end
	if pointLight then pointLight:Destroy() pointLight = nil end
	if fxFolder then fxFolder:Destroy() fxFolder = nil end

	activeUid = nil
	phase = 1
end

local function applyPhaseIntensity()
	local mul = (phase == 2) and CFG.Phase2Mul or 1.0

	for _, pe in ipairs(emitters) do
		if pe and pe.Parent then
			local baseRate = tonumber(pe:GetAttribute("__BaseRate")) or pe.Rate
			pe.Rate = baseRate * mul

			local baseMin = tonumber(pe:GetAttribute("__BaseSpeedMin")) or 0
			local baseMax = tonumber(pe:GetAttribute("__BaseSpeedMax")) or 0
			if baseMax > 0 then
				local sMul = 1.0 + (mul - 1) * 0.35
				pe.Speed = NumberRange.new(math.max(0.01, baseMin * sMul), baseMax * (sMul + 0.10))
			end
		end
	end

	if pointLight then
		pointLight.Brightness = (phase == 2) and 6.2 or 4.4
		pointLight.Range = (phase == 2) and 24 or 18
	end
	if highlight then
		highlight.OutlineTransparency = (phase == 2) and 0.05 or 0.11
		highlight.FillTransparency = (phase == 2) and 0.92 or 0.96
	end
	if cc then
		cc.Contrast = (phase == 2) and (CFG.CC_Contrast + 0.06) or CFG.CC_Contrast
		cc.Saturation = (phase == 2) and (CFG.CC_Saturation + 0.10) or CFG.CC_Saturation
	end
end

local function buildAuraForCharacter(char)
	clearFX()

	local hrp, torso, head = getRigParts(char)
	if not hrp or not torso or not head then return end

	fxFolder = Instance.new("Folder")
	fxFolder.Name = "__AsrielAuraParticles"
	fxFolder.Parent = char

	highlight = Instance.new("Highlight")
	highlight.Name = "__AsrielHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.96
	highlight.OutlineTransparency = 0.11
	highlight.Adornee = char
	highlight.Parent = fxFolder

	local aRoot  = makeAttachment(hrp,  "__AuraRoot",  Vector3.new(0, 0.0, 0))
	local aTorso = makeAttachment(torso,"__AuraTorso", Vector3.new(0, 0.2, 0))
	local aHead  = makeAttachment(head, "__AuraHead",  Vector3.new(0, 0.1, 0))
	attachments[#attachments+1] = aRoot
	attachments[#attachments+1] = aTorso
	attachments[#attachments+1] = aHead

	pointLight = Instance.new("PointLight")
	pointLight.Name = "__AsrielLight"
	pointLight.Color = Color3.new(1, 1, 1)
	pointLight.Brightness = 4.4
	pointLight.Range = 18
	pointLight.Shadows = false
	pointLight.Parent = hrp

	local function applyHug(pe)
		pe.LockedToPart = true
		pe.LightInfluence = 0
		pe.LightEmission = 1
		pe.Drag = CFG.HugDrag
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Shape = Enum.ParticleEmitterShape.Sphere
		pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		pe.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	end

	-- 0) RAINBOW SKIN (guaranteed rainbow)
	do
		local pe = makeEmitter(aTorso, {
			Texture = CFG.Tex.Glow,
			Rate = CFG.Base.RainbowSkinRate,
			Lifetime = numRange(0.12, 0.22),
			Speed = numRange(0.05, 0.55),
			Size = numSeq({{0.00, 0.50},{0.40, 0.90},{1.00, 0.00}}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0.00, 0.06),
				NumberSequenceKeypoint.new(0.35, 0.10),
				NumberSequenceKeypoint.new(1.00, 1.00),
			}),
			Color = rainbowSequence(0.00),
			Rotation = numRange(0, 360),
			RotSpeed = numRange(-180, 180),
			Acceleration = Vector3.new(0, 0.35, 0),
		})
		applyHug(pe)
		pe:SetAttribute("__BaseRate", CFG.Base.RainbowSkinRate)
		pe:SetAttribute("__BaseSpeedMin", 0.05)
		pe:SetAttribute("__BaseSpeedMax", 0.55)
		emitters[#emitters+1] = pe
	end

	-- 1) CORE GLOW
	do
		local pe = makeEmitter(aTorso, {
			Texture = CFG.Tex.Glow,
			Rate = CFG.Base.CoreGlowRate,
			Lifetime = numRange(0.35, 0.70),
			Speed = numRange(CFG.HugSpeedMin, CFG.HugSpeedMax),
			Size = numSeq({{0.00, 1.1},{0.25, 2.3},{1.00, 0.00}}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0.00, 0.10),
				NumberSequenceKeypoint.new(0.30, 0.08),
				NumberSequenceKeypoint.new(1.00, 1.00),
			}),
			Color = rainbowSequence(0.12),
			Rotation = numRange(0, 360),
			RotSpeed = numRange(-120, 120),
			Acceleration = Vector3.new(0, 1.2, 0),
		})
		applyHug(pe)
		pe:SetAttribute("__BaseRate", CFG.Base.CoreGlowRate)
		pe:SetAttribute("__BaseSpeedMin", CFG.HugSpeedMin)
		pe:SetAttribute("__BaseSpeedMax", CFG.HugSpeedMax)
		emitters[#emitters+1] = pe
	end

	-- 2) STARS
	do
		local pe = makeEmitter(aRoot, {
			Texture = CFG.Tex.Spark,
			Rate = CFG.Base.StarRate,
			Lifetime = numRange(0.55, 1.10),
			Speed = numRange(0.4, 2.8),
			Size = numSeq({{0.00, 0.35},{0.22, 0.60},{1.00, 0.05}}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0.00, 0.05),
				NumberSequenceKeypoint.new(0.70, 0.18),
				NumberSequenceKeypoint.new(1.00, 1.00),
			}),
			Color = rainbowSequence(0.25),
			Rotation = numRange(0, 360),
			RotSpeed = numRange(-260, 260),
			Acceleration = Vector3.new(0, 2.1, 0),
		})
		applyHug(pe)
		pe:SetAttribute("__BaseRate", CFG.Base.StarRate)
		pe:SetAttribute("__BaseSpeedMin", 0.4)
		pe:SetAttribute("__BaseSpeedMax", 2.8)
		emitters[#emitters+1] = pe
	end

	-- 3) GLITCH PIXELS
	do
		local pe = makeEmitter(aTorso, {
			Texture = CFG.Tex.Glow,
			Rate = CFG.Base.GlitchRate,
			Lifetime = numRange(0.08, 0.22),
			Speed = numRange(0.15, 1.3),
			Size = numSeq({{0.00, 0.18},{0.18, 0.42},{0.85, 0.22},{1.00, 0.00}}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0.00, 0.03),
				NumberSequenceKeypoint.new(0.25, 0.08),
				NumberSequenceKeypoint.new(1.00, 1.00),
			}),
			Color = rainbowSequence(0.45),
			Rotation = numRange(0, 360),
			RotSpeed = numRange(-200, 200),
			Acceleration = Vector3.new(0, 0.8, 0),
		})
		applyHug(pe)
		pe:SetAttribute("__BaseRate", CFG.Base.GlitchRate)
		pe:SetAttribute("__BaseSpeedMin", 0.15)
		pe:SetAttribute("__BaseSpeedMax", 1.3)
		emitters[#emitters+1] = pe
	end

	-- 4) HEAD STREAKS
	do
		local pe = makeEmitter(aHead, {
			Texture = CFG.Tex.Glow,
			Rate = CFG.Base.StreakRate,
			Lifetime = numRange(0.10, 0.28),
			Speed = numRange(0.6, 3.4),
			Size = numSeq({{0.00, 0.40},{0.30, 0.70},{1.00, 0.00}}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0.00, 0.06),
				NumberSequenceKeypoint.new(0.40, 0.16),
				NumberSequenceKeypoint.new(1.00, 1.00),
			}),
			Color = rainbowSequence(0.62),
			Rotation = numRange(-180, 180),
			RotSpeed = numRange(-260, 260),
			Acceleration = Vector3.new(0, 3.0, 0),
		})
		applyHug(pe)
		pe:SetAttribute("__BaseRate", CFG.Base.StreakRate)
		pe:SetAttribute("__BaseSpeedMin", 0.6)
		pe:SetAttribute("__BaseSpeedMax", 3.4)
		emitters[#emitters+1] = pe
	end

	-- 5) SMOKE / HAZE (white haze)
	do
		local pe = makeEmitter(aTorso, {
			Texture = CFG.Tex.Smoke,
			Rate = CFG.Base.SmokeRate,
			Lifetime = numRange(0.70, 1.30),
			Speed = numRange(0.05, 0.40),
			Size = numSeq({{0.00, 1.1},{0.40, 2.0},{1.00, 2.8}}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0.00, 0.70),
				NumberSequenceKeypoint.new(0.55, 0.80),
				NumberSequenceKeypoint.new(1.00, 1.00),
			}),
			Color = ColorSequence.new(Color3.fromRGB(255,255,255)),
			Rotation = numRange(0, 360),
			RotSpeed = numRange(-25, 25),
			Acceleration = Vector3.new(0, 0.25, 0),
		})
		applyHug(pe)
		pe.LightEmission = 0.25
		pe:SetAttribute("__BaseRate", CFG.Base.SmokeRate)
		pe:SetAttribute("__BaseSpeedMin", 0.05)
		pe:SetAttribute("__BaseSpeedMax", 0.40)
		emitters[#emitters+1] = pe
	end

	-- Burst so it’s immediately visible
	for _, pe in ipairs(emitters) do
		if pe and pe.Parent then
			pe:Emit(80)
		end
	end

	ensureLocalPostFX(true)
	applyPhaseIntensity()

	pulseConn = RunService.RenderStepped:Connect(function(dt)
		if not activeUid or not fxFolder or not fxFolder.Parent then return end
		pulseT += dt

		local p = 0.5 + 0.5 * math.sin(pulseT * (phase == 2 and 9 or 6))

		if bloom then
			bloom.Intensity = CFG.BloomIntensity + p * (phase == 2 and (CFG.BloomPulseAdd + 0.10) or CFG.BloomPulseAdd)
		end
		if highlight then
			highlight.OutlineTransparency = (phase == 2)
				and (0.04 + 0.10 * (1 - p))
				or  (0.10 + 0.12 * (1 - p))
		end
	end)
end

-- =========================
-- EVENTS
-- =========================
AsrielEvent.OnClientEvent:Connect(function(kind, payload)
	if kind == "AsrielStart" then
		activeUid = payload and payload.ownerUserId or nil
		phase = 1

		local char = activeUid and getCharByUserId(activeUid) or nil
		if char then
			buildAuraForCharacter(char)
		end

	elseif kind == "AsrielPhase" then
		if payload and activeUid and payload.ownerUserId == activeUid then
			phase = tonumber(payload.phase) or phase
			applyPhaseIntensity()
		end

	elseif kind == "AsrielEnd" then
		if payload and activeUid and payload.ownerUserId == activeUid then
			ensureLocalPostFX(false)
			clearFX()
		end
	end
end)

-- Rebuild on respawn for owner
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(char)
		if activeUid and p.UserId == activeUid then
			buildAuraForCharacter(char)
			applyPhaseIntensity()
		end
	end)
end)

Players.PlayerRemoving:Connect(function(p)
	if activeUid and p.UserId == activeUid then
		ensureLocalPostFX(false)
		clearFX()
	end
end)
