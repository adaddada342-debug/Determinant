-- StarterPlayerScripts/AsrielBodyAuraStars.client.lua
-- HYPERDEATH AURA (NO FLASHING / NO HEARTBEAT)
-- ✅ Insane rainbow, layered, body-hugging aura
-- ✅ Animated hue shift (so it stays alive)
-- ✅ Beam lattice detail (god silhouette)
-- ✅ NO pulse bursts + NO bloom breathing (prevents strobe/heartbeat)
-- ✅ Smooth distance falloff (no enable/disable blinking)
-- ✅ Avoids stacking post FX if Cataclysm post pack exists

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local AsrielEvent = Remotes and Remotes:FindFirstChild("AsrielEvent")

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[AsrielAura]", ...) end
end

-- ============================================================
-- CONFIG
-- ============================================================
local CFG = {
	-- Distance fade (smooth, not blinking)
	FadeStart = 650,
	FadeEnd = 900,
	DistanceCheckHz = 15,

	-- Textures (built-in)
	Tex = {
		Glow  = "rbxasset://textures/particles/flare_main.dds",
		Star  = "rbxasset://textures/particles/sparkles_main.dds",
		Smoke = "rbxasset://textures/particles/smoke_main.dds",
	},

	-- Rainbow intensity
	RainbowS = 1.0,
	RainbowV = 1.0,

	-- Animated hue shift (this is “alive” without flashing)
	HueSpeed = 0.22,
	HueSpeedPhase2 = 0.36,
	SequenceUpdateHz = 18,

	-- “Insane” rates (but stable)
	Rate = {
		Rim       = 260,
		Flames    = 220,
		Ribbons   = 150,
		Streaks   = 120,
		Micro     = 220,
		Stars     = 150,
		Haze      = 22,
	},

	Phase2Mul = 1.8,

	Speed = {
		Rim     = NumberRange.new(0.10, 0.55),
		Flames  = NumberRange.new(0.60, 2.60),
		Ribbons = NumberRange.new(0.18, 0.95),
		Streaks = NumberRange.new(4.0, 10.0),
		Micro   = NumberRange.new(1.2, 5.2),
		Stars   = NumberRange.new(0.9, 4.2),
		Haze    = NumberRange.new(0.10, 0.55),
	},

	Drag = {
		Rim     = 3.2,
		Flames  = 2.1,
		Ribbons = 1.4,
		Streaks = 0.25,
		Micro   = 1.0,
		Stars   = 1.1,
		Haze    = 4.3,
	},

	-- Post FX (steady, no breathing)
	LocalPostFX = true,
	BloomIntensity = 0.26, -- keep modest (Cataclysm + aura stacking is how you get "milk world")
	BloomSize = 52,
	BloomThreshold = 0.86,

	CC_Saturation = 0.18,
	CC_Contrast   = 0.10,
	CC_Brightness = -0.02,

	UseSunRays = false, -- sun rays can feel like brightness pulsing in motion-heavy scenes

	-- Beam motion: animate texture movement only (no brightness pulsing)
	BeamTextureSpeed1 = 1.8,
	BeamTextureSpeed2 = 2.6,
	BeamSpeedWobble = 0.15, -- tiny wobble for life, not flashing
}

local function clamp01(x) return math.clamp(x, 0, 1) end
local function hsv(h, s, v)
	return Color3.fromHSV((h % 1), math.clamp(s, 0, 1), math.clamp(v, 0, 1))
end
local function nr(a,b) return NumberRange.new(a,b) end
local function ns(points)
	local k = {}
	for _, p in ipairs(points) do
		k[#k+1] = NumberSequenceKeypoint.new(p[1], p[2])
	end
	return NumberSequence.new(k)
end

local function rainbowSequenceAnimated(offset, baseHue)
	local keys = {}
	for i = 0, 8 do
		local t = i / 8
		keys[#keys+1] = ColorSequenceKeypoint.new(t, hsv(baseHue + t + offset, CFG.RainbowS, CFG.RainbowV))
	end
	return ColorSequence.new(keys)
end

local function getCharByUserId(uid)
	local p = Players:GetPlayerByUserId(uid)
	return p and p.Character or nil
end

local function getRigParts(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head") or hrp
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or hrp
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

local function makeBeam(a0, a1)
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Width0 = 0.20
	b.Width1 = 0.08
	b.Transparency = NumberSequence.new{
		NumberSequenceKeypoint.new(0.0, 0.25),
		NumberSequenceKeypoint.new(0.4, 0.08),
		NumberSequenceKeypoint.new(1.0, 0.35),
	}
	b.Texture = CFG.Tex.Glow
	b.TextureMode = Enum.TextureMode.Stretch
	b.TextureSpeed = CFG.BeamTextureSpeed1
	b.Parent = a0.Parent
	return b
end

-- ============================================================
-- STATE
-- ============================================================
local activeUid = nil
local phase = 1

local fxFolder = nil
local attachments = {}
local emitters = {}
local beams = {}
local highlight = nil
local light = nil

local bloom, cc, rays
local conn
local hueT = 0
local seqAccum = 0
local distAccum = 0

-- ============================================================
-- POST FX (steady, and avoids Cataclysm stacking)
-- ============================================================
local function ensurePostFX(on)
	if not CFG.LocalPostFX then return end

	-- If Cataclysm pack exists, do NOT add more global effects.
	if Lighting:FindFirstChild("__CataclysmPost") then
		return
	end

	if on then
		if not bloom then
			bloom = Instance.new("BloomEffect")
			bloom.Intensity = CFG.BloomIntensity
			bloom.Size = CFG.BloomSize
			bloom.Threshold = CFG.BloomThreshold
			bloom.Parent = Lighting
		else
			-- force steady
			bloom.Intensity = CFG.BloomIntensity
			bloom.Size = CFG.BloomSize
			bloom.Threshold = CFG.BloomThreshold
		end

		if not cc then
			cc = Instance.new("ColorCorrectionEffect")
			cc.Brightness = CFG.CC_Brightness
			cc.Contrast   = CFG.CC_Contrast
			cc.Saturation = CFG.CC_Saturation
			cc.Parent = Lighting
		else
			cc.Brightness = CFG.CC_Brightness
			cc.Contrast   = CFG.CC_Contrast
			cc.Saturation = CFG.CC_Saturation
			cc.TintColor  = Color3.new(1,1,1)
		end

		if CFG.UseSunRays and not rays then
			rays = Instance.new("SunRaysEffect")
			rays.Intensity = 0
			rays.Spread = 0.9
			rays.Parent = Lighting
		end
	else
		if bloom then bloom:Destroy() bloom = nil end
		if cc then cc:Destroy() cc = nil end
		if rays then rays:Destroy() rays = nil end
	end
end

-- ============================================================
-- CLEANUP
-- ============================================================
local function clearFX()
	if conn then conn:Disconnect() conn = nil end
	hueT, seqAccum, distAccum = 0, 0, 0

	for _, b in ipairs(beams) do
		if b then b:Destroy() end
	end
	beams = {}

	for _, pe in ipairs(emitters) do
		if pe then pe:Destroy() end
	end
	emitters = {}

	for _, a in ipairs(attachments) do
		if a then a:Destroy() end
	end
	attachments = {}

	if highlight then highlight:Destroy() highlight = nil end
	if light then light:Destroy() light = nil end
	if fxFolder then fxFolder:Destroy() fxFolder = nil end

	activeUid = nil
	phase = 1
end

-- ============================================================
-- EMITTER DEFAULTS
-- ============================================================
local function baseEmitter(pe)
	pe.Enabled = true
	pe.LockedToPart = true
	pe.LightInfluence = 0
	pe.LightEmission = 1
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.ZOffset = 3
	pe.Orientation = Enum.ParticleOrientation.FacingCamera
end

-- ============================================================
-- PHASE APPLY
-- ============================================================
local function applyPhase()
	local mul = (phase == 2) and CFG.Phase2Mul or 1.0
	for _, pe in ipairs(emitters) do
		if pe and pe.Parent then
			local base = tonumber(pe:GetAttribute("__BaseRate")) or pe.Rate
			pe:SetAttribute("__PhaseMul", mul)
			pe.Rate = base * mul
		end
	end

	if light then
		light.Brightness = (phase == 2) and 7.2 or 5.0
		light.Range      = (phase == 2) and 28  or 20
	end
	if highlight then
		highlight.OutlineTransparency = (phase == 2) and 0.03 or 0.08
		highlight.FillTransparency    = (phase == 2) and 0.90 or 0.955
	end

	-- Beam texture speed changes with phase (motion only)
	local baseSpeed = (phase == 2) and CFG.BeamTextureSpeed2 or CFG.BeamTextureSpeed1
	for _, b in ipairs(beams) do
		if b and b.Parent then
			b.TextureSpeed = baseSpeed
		end
	end

	-- Force steady post FX values if we own them
	if bloom then
		bloom.Intensity = CFG.BloomIntensity
		bloom.Size = CFG.BloomSize
		bloom.Threshold = CFG.BloomThreshold
	end
	if cc then
		cc.Brightness = CFG.CC_Brightness
		cc.Contrast   = CFG.CC_Contrast
		cc.Saturation = CFG.CC_Saturation
	end
end

-- ============================================================
-- DISTANCE ALPHA (smooth)
-- ============================================================
local function computeDistanceAlpha(hrp)
	if not Camera or not hrp then return 1 end
	local dist = (Camera.CFrame.Position - hrp.Position).Magnitude
	if dist <= CFG.FadeStart then return 1 end
	if dist >= CFG.FadeEnd then return 0 end
	local t = (dist - CFG.FadeStart) / (CFG.FadeEnd - CFG.FadeStart)
	t = t * t * (3 - 2 * t) -- smoothstep
	return 1 - t
end

local function applyDistanceAlpha(alpha)
	for _, pe in ipairs(emitters) do
		if pe and pe.Parent then
			local base = tonumber(pe:GetAttribute("__BaseRate")) or pe.Rate
			local pmul = tonumber(pe:GetAttribute("__PhaseMul")) or 1.0
			pe.Rate = base * pmul * alpha
		end
	end

	-- beams fade smoothly too
	local bAlpha = alpha ^ 0.65
	for _, b in ipairs(beams) do
		if b and b.Parent then
			local baseT0 = tonumber(b:GetAttribute("__T0")) or 0.25
			local baseT1 = tonumber(b:GetAttribute("__T1")) or 0.08
			local baseT2 = tonumber(b:GetAttribute("__T2")) or 0.35
			local inv = 1 - bAlpha

			b.Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0.0, math.clamp(baseT0 + inv * 0.70, 0, 1)),
				NumberSequenceKeypoint.new(0.4, math.clamp(baseT1 + inv * 0.75, 0, 1)),
				NumberSequenceKeypoint.new(1.0, math.clamp(baseT2 + inv * 0.70, 0, 1)),
			}
		end
	end

	if highlight then highlight.Enabled = alpha > 0.02 end
	if light then
		light.Enabled = alpha > 0.02
		local baseB = (phase == 2) and 7.2 or 5.0
		light.Brightness = baseB * alpha
	end
end

-- ============================================================
-- BUILD
-- ============================================================
local function buildForCharacter(char)
	clearFX()

	local hrp, torso, head = getRigParts(char)
	if not hrp then
		hrp = char:WaitForChild("HumanoidRootPart", 5)
		if not hrp then return end
		torso, head = hrp, hrp
	end

	fxFolder = Instance.new("Folder")
	fxFolder.Name = "__AuraStarsFX"
	fxFolder.Parent = char

	highlight = Instance.new("Highlight")
	highlight.Name = "__AuraOutline"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.new(1,1,1)
	highlight.OutlineColor = Color3.new(1,1,1)
	highlight.FillTransparency = 0.955
	highlight.OutlineTransparency = 0.08
	highlight.Adornee = char
	highlight.Parent = fxFolder

	light = Instance.new("PointLight")
	light.Color = Color3.new(1,1,1)
	light.Brightness = 5.0
	light.Range = 20
	light.Parent = hrp

	local aRoot  = makeAttachment(hrp, "__AuraRoot",  Vector3.new(0, 0.05, 0))
	local aTorso = makeAttachment(torso, "__AuraTorso", Vector3.new(0, 0.20, 0))
	local aHead  = makeAttachment(head, "__AuraHead",  Vector3.new(0, 0.15, 0))
	attachments[#attachments+1] = aRoot
	attachments[#attachments+1] = aTorso
	attachments[#attachments+1] = aHead

	-- Torso wrap ring (hugging aura)
	local ring = {}
	do
		local r = 1.10
		local y = 0.15
		local points = 12
		for i = 1, points do
			local ang = (i / points) * math.pi * 2
			local x = math.cos(ang) * r
			local z = math.sin(ang) * r
			local att = makeAttachment(torso, ("__AuraRing_%02d"):format(i), Vector3.new(x, y, z))
			attachments[#attachments+1] = att
			ring[#ring+1] = att
		end
	end

	local function addEmitter(pe, baseRate)
		baseEmitter(pe)
		pe:SetAttribute("__BaseRate", baseRate)
		pe:SetAttribute("__PhaseMul", 1.0)
		emitters[#emitters+1] = pe
		return pe
	end

	-- Rim (tight glow)
	for _, att in ipairs(ring) do
		local pe = makeEmitter(att, {
			Texture = CFG.Tex.Glow,
			Rate = CFG.Rate.Rim,
			Lifetime = nr(0.07, 0.14),
			Speed = CFG.Speed.Rim,
			Drag = CFG.Drag.Rim,
			Size = ns({{0.00, 0.60},{0.35, 1.05},{1.00, 0.00}}),
			Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0.00, 0.02),
				NumberSequenceKeypoint.new(0.35, 0.08),
				NumberSequenceKeypoint.new(1.00, 1.00),
			},
			Rotation = nr(0, 360),
			RotSpeed = nr(-280, 280),
			Acceleration = Vector3.new(0, 0.10, 0),
		})
		pe.SpreadAngle = Vector2.new(105, 105)
		addEmitter(pe, CFG.Rate.Rim)
	end

	-- Flames (outer licks)
	for _, att in ipairs(ring) do
		local pe = makeEmitter(att, {
			Texture = CFG.Tex.Glow,
			Rate = CFG.Rate.Flames,
			Lifetime = nr(0.16, 0.30),
			Speed = CFG.Speed.Flames,
			Drag = CFG.Drag.Flames,
			Size = ns({{0.00, 0.65},{0.20, 1.40},{0.65, 0.55},{1.00, 0.00}}),
			Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0.00, 0.06),
				NumberSequenceKeypoint.new(0.30, 0.14),
				NumberSequenceKeypoint.new(1.00, 1.00),
			},
			Rotation = nr(0, 360),
			RotSpeed = nr(-420, 420),
			Acceleration = Vector3.new(0, 2.8, 0),
		})
		pe.SpreadAngle = Vector2.new(150, 150)
		addEmitter(pe, CFG.Rate.Flames)
	end

	-- Ribbons (fat aura sheets)
	do
		local pe = makeEmitter(aTorso, {
			Texture = CFG.Tex.Glow,
			Rate = CFG.Rate.Ribbons,
			Lifetime = nr(0.22, 0.45),
			Speed = CFG.Speed.Ribbons,
			Drag = CFG.Drag.Ribbons,
			Size = ns({{0.00, 1.10},{0.25, 2.40},{0.60, 1.40},{1.00, 0.00}}),
			Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0.00, 0.08),
				NumberSequenceKeypoint.new(0.35, 0.12),
				NumberSequenceKeypoint.new(1.00, 1.00),
			},
			Rotation = nr(0, 360),
			RotSpeed = nr(-160, 160),
			Acceleration = Vector3.new(0, 1.2, 0),
		})
		addEmitter(pe, CFG.Rate.Ribbons)
	end

	-- Streaks (anime detail)
	do
		local pe = makeEmitter(aTorso, {
			Texture = CFG.Tex.Glow,
			Rate = CFG.Rate.Streaks,
			Lifetime = nr(0.05, 0.11),
			Speed = CFG.Speed.Streaks,
			Drag = CFG.Drag.Streaks,
			Size = ns({{0.00, 0.20},{0.25, 0.55},{1.00, 0.00}}),
			Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0.00, 0.05),
				NumberSequenceKeypoint.new(0.20, 0.10),
				NumberSequenceKeypoint.new(1.00, 1.00),
			},
			Rotation = nr(0, 360),
			RotSpeed = nr(-900, 900),
			Acceleration = Vector3.new(0, 2.0, 0),
		})
		pe.ZOffset = 5
		addEmitter(pe, CFG.Rate.Streaks)
	end

	-- Micro glitter
	do
		local pe = makeEmitter(aTorso, {
			Texture = CFG.Tex.Star,
			Rate = CFG.Rate.Micro,
			Lifetime = nr(0.18, 0.42),
			Speed = CFG.Speed.Micro,
			Drag = CFG.Drag.Micro,
			Size = ns({{0.00, 0.08},{0.20, 0.16},{1.00, 0.00}}),
			Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0.00, 0.05),
				NumberSequenceKeypoint.new(0.40, 0.22),
				NumberSequenceKeypoint.new(1.00, 1.00),
			},
			Rotation = nr(0, 360),
			RotSpeed = nr(-1200, 1200),
			Acceleration = Vector3.new(0, 3.2, 0),
		})
		pe.ZOffset = 6
		addEmitter(pe, CFG.Rate.Micro)
	end

	-- Drifting stars
	do
		local pe = makeEmitter(aRoot, {
			Texture = CFG.Tex.Star,
			Rate = CFG.Rate.Stars,
			Lifetime = nr(0.70, 1.50),
			Speed = CFG.Speed.Stars,
			Drag = CFG.Drag.Stars,
			Size = ns({{0.00, 0.22},{0.15, 0.48},{0.55, 0.36},{1.00, 0.00}}),
			Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0.00, 0.06),
				NumberSequenceKeypoint.new(0.65, 0.18),
				NumberSequenceKeypoint.new(1.00, 1.00),
			},
			Rotation = nr(0, 360),
			RotSpeed = nr(-520, 520),
			Acceleration = Vector3.new(0, 3.5, 0),
		})
		pe.ZOffset = 7
		pe.SpreadAngle = Vector2.new(125, 125)
		addEmitter(pe, CFG.Rate.Stars)
	end

	-- Haze glue
	do
		local pe = makeEmitter(aTorso, {
			Texture = CFG.Tex.Smoke,
			Rate = CFG.Rate.Haze,
			Lifetime = nr(0.9, 1.6),
			Speed = CFG.Speed.Haze,
			Drag = CFG.Drag.Haze,
			Size = ns({{0.00, 1.10},{0.45, 2.10},{1.00, 2.90}}),
			Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0.00, 0.80),
				NumberSequenceKeypoint.new(0.55, 0.88),
				NumberSequenceKeypoint.new(1.00, 1.00),
			},
			Rotation = nr(0, 360),
			RotSpeed = nr(-22, 22),
			Acceleration = Vector3.new(0, 0.10, 0),
		})
		baseEmitter(pe)
		pe.LightEmission = 0.12
		pe:SetAttribute("__BaseRate", CFG.Rate.Haze)
		pe:SetAttribute("__PhaseMul", 1.0)
		emitters[#emitters+1] = pe
	end

	-- Beam lattice (god silhouette)
	do
		for i = 1, #ring do
			local a0 = ring[i]
			local a1 = ring[(i % #ring) + 1]
			local b = makeBeam(a0, a1)
			b:SetAttribute("__T0", 0.25)
			b:SetAttribute("__T1", 0.08)
			b:SetAttribute("__T2", 0.35)
			beams[#beams+1] = b
		end
		for i = 1, #ring do
			local a0 = ring[i]
			local a1 = ring[((i + 4 - 1) % #ring) + 1]
			local b = makeBeam(a0, a1)
			b.Width0 = 0.14
			b.Width1 = 0.06
			b.TextureSpeed = CFG.BeamTextureSpeed1
			b:SetAttribute("__T0", 0.25)
			b:SetAttribute("__T1", 0.08)
			b:SetAttribute("__T2", 0.35)
			beams[#beams+1] = b
		end
	end

	-- Kickstart so it doesn’t “warm up”
	for _, pe in ipairs(emitters) do
		pe:Emit(60)
	end

	ensurePostFX(true)
	applyPhase()

	local seqStep = 1 / CFG.SequenceUpdateHz
	local distStep = 1 / CFG.DistanceCheckHz

	conn = RunService.RenderStepped:Connect(function(dt)
		-- Hue shift
		local hs = (phase == 2) and CFG.HueSpeedPhase2 or CFG.HueSpeed
		hueT += dt * hs

		-- Update rainbow sequences at a controlled rate
		seqAccum += dt
		if seqAccum >= seqStep then
			seqAccum -= seqStep

			for idx, pe in ipairs(emitters) do
				if pe and pe.Parent then
					local off = (idx * 0.07) % 1
					pe.Color = rainbowSequenceAnimated(off, hueT)
				end
			end

			for idx, b in ipairs(beams) do
				if b and b.Parent then
					local off = (idx * 0.09) % 1
					b.Color = ColorSequence.new(
						hsv(hueT + off, CFG.RainbowS, CFG.RainbowV),
						hsv(hueT + off + 0.35, CFG.RainbowS, CFG.RainbowV)
					)

					-- motion only, no brightness pulsing
					local baseSpeed = (phase == 2) and CFG.BeamTextureSpeed2 or CFG.BeamTextureSpeed1
					local wobble = CFG.BeamSpeedWobble * math.sin(os.clock() * 2.5 + idx * 0.4)
					b.TextureSpeed = baseSpeed + wobble
				end
			end

			if light then
				light.Color = hsv(hueT, 0.35, 1.0)
			end
		end

		-- Smooth distance falloff (no blinking)
		distAccum += dt
		if distAccum >= distStep then
			distAccum -= distStep
			local alpha = computeDistanceAlpha(hrp)
			applyDistanceAlpha(alpha)
		end
	end)
end

-- ============================================================
-- SELF TEST: K toggles on yourself
-- ============================================================
local selfOn = false
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.K then
		selfOn = not selfOn
		if selfOn then
			activeUid = localPlayer.UserId
			phase = 1
			buildForCharacter(localPlayer.Character or localPlayer.CharacterAdded:Wait())
		else
			ensurePostFX(false)
			clearFX()
		end
	end
end)

localPlayer.CharacterAdded:Connect(function(char)
	if selfOn then
		task.defer(function()
			buildForCharacter(char)
		end)
	end
end)

-- ============================================================
-- REMOTES
-- ============================================================
if AsrielEvent then
	AsrielEvent.OnClientEvent:Connect(function(kind, payload)
		if kind == "AsrielStart" then
			activeUid = payload and payload.ownerUserId or nil
			phase = 1
			if activeUid then
				local char = getCharByUserId(activeUid)
				if char then buildForCharacter(char) end
			end

		elseif kind == "AsrielPhase" then
			if payload and activeUid and payload.ownerUserId == activeUid then
				phase = tonumber(payload.phase) or phase
				applyPhase()
			end

		elseif kind == "AsrielEnd" then
			if payload and activeUid and payload.ownerUserId == activeUid then
				ensurePostFX(false)
				clearFX()
			end
		end
	end)
end
