-- ExplosionDirector.lua (CINEMATIC BUILD - CLIENT VFX)
-- Uses template particle parts from ReplicatedStorage/Assets/VFX/CataclysmExplosionFX
-- Templates: Energy, Explosion, Impact, Smoke, Star, Swirl
--
-- FIXES INCLUDED:
--  ✅ Client-only guard (server must not run visuals)
--  ✅ WaitForChild for templates (replication-safe)
--  ✅ Supports templates as BasePart (Part + Attachment + ParticleEmitter)
--  ✅ Pooling fixed: pooled parts are NOT Debris:AddItem()'d (no self-destruction)
--  ✅ Still cleans up folder at end

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
	Scale = 1.0,

	-- Timeline (total ~7s)
	Phase = {
		Charge = 0.35,
		PillarRise = 0.65,
		RingFlow = 1.25,
		Convert = 0.22,
		DetonationBurst = 0.65,
		Aftershock = 4.2,
		FadeModel = 1.25,
	},
	TotalLifetime = 7.25,

	-- Palette
	CoreColor  = Color3.fromRGB(255, 95, 70),
	HotWhite   = Color3.fromRGB(255, 255, 255),
	ShockColor = Color3.fromRGB(255, 235, 225),
	PinkEdge   = Color3.fromRGB(255, 120, 190),
	SmokeColor = Color3.fromRGB(255, 120, 105),

	-- Safety
	ForceVisibleAndAnchored = true,
	WarnMissing = true,

	-- Pool sizes
	Pool = {
		Rings = 220,
		ShockRings = 90,
		Streaks = 220,
		Debris = 120,
		Rays = 120,
	},

	-- =========================================
	-- TEMPLATE PARTICLES (ReplicatedStorage parts)
	-- =========================================
	TemplateParticles = {
		Enabled = true,

		Path = {"Assets", "VFX", "CataclysmExplosionFX"},
		Names = {"Energy", "Explosion", "Impact", "Smoke", "Star", "Swirl"},

		-- Script-side scaling (multiplies ParticleEmitter.Size and Speed)
		Scale = {
			GlobalSize = 1.0,
			GlobalSpeed = 1.0,

			EnergySize = 1.0,   EnergySpeed = 1.0,
			SwirlSize  = 1.0,   SwirlSpeed  = 1.0,
			StarSize   = 1.8,   StarSpeed   = 0.75,
			ImpactSize = 1.25,  ImpactSpeed = 1.05,
			ExplosionSize = 1.45, ExplosionSpeed = 1.15,
			SmokeSize  = 1.55,  SmokeSpeed  = 0.85,
		},

		-- Enable windows (continuous emitters)
		EnableBuildEnergy = true,
		EnableBuildSwirl = true,
		EnableSmokeOnDetonation = true,
		SmokeEnableTime = 2.0,

		-- Burst timings
		Burst = {
			BuildStars = {0.15, 0.55, 0.95},
			DetonateImpact = {0.00, 0.18},
			DetonateExplosion = {0.02, 0.35, 0.75},
			DetonateStars = {0.00, 0.22, 0.55},
		},

		-- Burst strengths
		BurstStrength = {
			BuildStar = 0.8,
			Impact1 = 1.0,
			Impact2 = 0.7,
			Explosion1 = 1.0,
			Explosion2 = 0.75,
			Explosion3 = 0.55,
			Stars1 = 1.0,
			Stars2 = 0.8,
			Stars3 = 0.65,
		},
	},

	-- Pillar beam
	PillarBeam = {
		Enabled = true,
		HeightStart = 18,
		HeightEnd = 260,
		Width = 14,
		GrowTime = 0.55,
		Color = Color3.fromRGB(255, 170, 120),
		TransparencyStart = 0.55,
		TransparencyBright = 0.18,
		TransparencyEnd = 0.85,
		Material = Enum.Material.Neon,

		RayCount = 46,
		RayLength = {80, 240},
		RayThickness = {0.8, 2.4},
		RaySpreadRadius = 24,
		RayLife = 1.2,
	},

	-- RingFlow
	RingFlow = {
		Enabled = true,
		RingsPerSecond = 18,
		Heights = {10, 22, 40, 66, 92, 120, 150},
		StartRadius = 10,
		EndRadius = 240,
		StartThickness = 1.4,
		EndThickness = 5.4,
		GrowTime = 0.38,
		FadeTime = 0.44,
		StartTransparency = 0.22,
		WobbleDeg = 10,
		Color = nil,
	},

	-- Ribbons
	Ribbons = {
		Enabled = true,
		Count = 10,
		Radius = 140,
		Height = 110,
		Width = {2.5, 6.5},
		Life = 1.6,
		Speed = 2.6,
		Color = nil,
	},

	-- Sphere
	Sphere = {
		Enabled = true,
		CoreStart = 6,
		CoreEnd = 190,
		GrowTime = 0.20,
		HoldTime = 0.38,
		FadeTime = 0.72,
		StartTransparency = 0.05,

		ShellStart = 14,
		ShellEnd = 280,
		ShellGrowTime = 0.68,
		ShellStartTransparency = 0.86,
	},

	-- Shockwaves
	Shockwaves = {
		Enabled = true,
		Count = 10,
		Stagger = 0.045,
		StartRadius = 18,
		EndRadius = {280, 250, 220, 195, 170, 150, 132, 120, 110, 105},
		StartThickness = 1.8,
		EndThickness = 5.0,
		GrowTime = 0.35,
		FadeTime = 0.48,
		StartTransparency = 0.18,
		WobbleDeg = 10,
		Color = nil,
	},

	PressureDome = {
		Enabled = true,
		Start = 30,
		End = 340,
		GrowTime = 0.55,
		StartTransparency = 0.82,
		Color = nil,
	},

	Streaks = {
		Enabled = true,
		Count = 90,
		Length = {80, 260},
		Thickness = {0.2, 0.85},
		OutRadius = 240,
		Time = 0.22,
		FadeTime = 0.22,
		Color = nil,
	},

	Debris = {
		Enabled = true,
		Count = 70,
		Radius = 74,
		Size = Vector3.new(0.7, 0.7, 0.7),
		SizeJitter = Vector3.new(2.0, 1.5, 2.0),

		Absorb = true,
		AbsorbDelay = 0.75,
		AbsorbTime = 0.85,
		AbsorbTargetName = "HumanoidRootPart",
	},

	Camera = {
		Enabled = true,
		ZoomOut = true,
		ZoomBack = 360,
		ZoomUp = 82,
		ZoomInTime = 0.22,
		Hold = 1.10,
		ZoomOutTime = 0.30,
		FovPunch = 18,

		TraumaKick = 1.0,
		TraumaDecay = 1.4,
		MaxOffset = Vector3.new(3.8, 3.2, 1.1),
		MaxRotDeg = Vector3.new(3.2, 2.8, 2.2),

		AfterTraumaKick = 0.55,
	},

	PostFX = {
		Enabled = true,
		CC = {
			Tint = Color3.fromRGB(255, 80, 80),
			Contrast = 0.72,
			Saturation = 0.22,
			Brightness = 0.12,
			RecoverTime = 1.4,
		},
		Bloom = {
			Intensity = 4.6,
			Size = 96,
			Threshold = 0.50,
			RecoverIntensity = 0.85,
			RecoverSize = 30,
			RecoverThreshold = 0.84,
			RecoverTime = 1.2,
		},
		Blur = {
			Size = 14,
			RecoverTime = 0.65,
		},

		ImpactOverlay = true,
		ImpactFrameTime = 0.06,
		ImpactFrameCount = 4,
		ImpactFrameGap = 0.06,
	},
}

-- ============================================================
-- UTIL
-- ============================================================
local function warnf(...)
	if CONFIG.WarnMissing then warn("[ExplosionDirector]", ...) end
end

local function isAlive(obj) return obj and obj.Parent end

local function tw(obj, t, props, style, dir)
	if not isAlive(obj) then return nil end
	style = style or Enum.EasingStyle.Exponential
	dir = dir or Enum.EasingDirection.Out
	local tween = TweenService:Create(obj, TweenInfo.new(t, style, dir), props)
	tween:Play()
	return tween
end

local function safeWaitChild(parent, name)
	local ok, child = pcall(function() return parent:WaitForChild(name, 5) end)
	if ok and child then return child end
	warnf("Missing required child:", name, "under", parent:GetFullName())
	return nil
end

local function randf(a, b) return a + (b - a) * math.random() end

local function getDescParts(root)
	local parts = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	return parts
end

local function stabilizeModel(fxModel)
	for _, p in ipairs(getDescParts(fxModel)) do
		if CONFIG.ForceVisibleAndAnchored then
			p.LocalTransparencyModifier = 0
			if p.Transparency >= 1 then p.Transparency = 0 end
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			if p.Size.Magnitude < 0.05 then p.Size = Vector3.new(0.2, 0.2, 0.2) end
		end
	end
end

-- ============================================================
-- SPAWN FOLDER + POOLS
-- ============================================================
local function makeFolder(tag)
	local f = Instance.new("Folder")
	f.Name = "__ExplosionFX_" .. tag
	f.Parent = workspace
	return f
end

local function makePool(folder, count, createFn)
	local pool = {items = {}, idx = 1}
	for i = 1, count do
		local it = createFn(i)
		it.Parent = folder
		pool.items[i] = it
	end
	function pool:next()
		local it = self.items[self.idx]
		self.idx += 1
		if self.idx > #self.items then self.idx = 1 end
		return it
	end
	return pool
end

local function releaseLater(inst, t)
	task.delay(t, function()
		if isAlive(inst) then
			if inst:IsA("BasePart") then
				inst.Transparency = 1
			end
		end
	end)
end

-- ============================================================
-- FX PRIMITIVES
-- ============================================================
local function makeRingPart()
	local p = Instance.new("Part")
	p.Name = "__Ring"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	return p
end

local function makeStreakPart()
	local p = Instance.new("Part")
	p.Name = "__Streak"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 8)
	return p
end

local function makeDebrisPart()
	local p = Instance.new("Part")
	p.Name = "__Debris"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 1
	p.Size = Vector3.new(1,1,1)
	return p
end

local function makeRayPart()
	local p = Instance.new("WedgePart")
	p.Name = "__Ray"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	return p
end

-- ============================================================
-- TEMPLATE PARTICLES DRIVER (FIXED)
-- ============================================================
local function getTemplateRoot()
	local node = ReplicatedStorage
	for _, name in ipairs(CONFIG.TemplateParticles.Path) do
		node = node:WaitForChild(name, 10)
		if not node then return nil end
	end

	-- replication guard
	local t0 = os.clock()
	while #node:GetChildren() == 0 and (os.clock() - t0) < 5 do
		task.wait()
	end

	return node
end


local function getEmitters(container)
	local out = {}
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("ParticleEmitter") then table.insert(out, d) end
	end
	return out
end

local function scaleNumberRange(nr, mult)
	return NumberRange.new(nr.Min * mult, nr.Max * mult)
end

local function scaleNumberSequence(seq, mult)
	local kps = seq.Keypoints
	local out = table.create(#kps)
	for i, kp in ipairs(kps) do
		out[i] = NumberSequenceKeypoint.new(kp.Time, kp.Value * mult, kp.Envelope * mult)
	end
	return NumberSequence.new(out)
end

local function applyEmitterScale(pe, sizeMult, speedMult)
	pcall(function() pe.Size = scaleNumberSequence(pe.Size, sizeMult) end)
	pcall(function() pe.Speed = scaleNumberRange(pe.Speed, speedMult) end)
end

local function cloneTemplateParts(intoFolder)
	if not CONFIG.TemplateParticles.Enabled then return nil end
	local root = getTemplateRoot()
	if not root then
		warnf("TemplateParticles root missing at ReplicatedStorage/" .. table.concat(CONFIG.TemplateParticles.Path, "/"))
		return nil
	end

	local parts = {}

	for _, n in ipairs(CONFIG.TemplateParticles.Names) do
		local src = root:WaitForChild(n, 10)
		if not src then
			warnf("Missing template:", n, "under", root:GetFullName())
		else
			local ok, c = pcall(function() return src:Clone() end)
			if not ok or not c then
				warnf("FAILED to clone template:", n, "(Archivable false?)")
			else
				c.Name = "__TP_" .. n
				c.Parent = intoFolder

				-- Make carrier invisible + noninteractive without changing attachments/emitter layout
				if c:IsA("BasePart") then
					c.Anchored = true
					c.CanCollide = false
					c.CanTouch = false
					c.CanQuery = false
					c.CastShadow = false
					c.Transparency = 1
				end
				for _, bp in ipairs(c:GetDescendants()) do
					if bp:IsA("BasePart") then
						bp.Anchored = true
						bp.CanCollide = false
						bp.CanTouch = false
						bp.CanQuery = false
						bp.CastShadow = false
						bp.Transparency = 1
					end
				end

				parts[n] = c
			end
		end
	end

	-- Disable everything initially
	for _, part in pairs(parts) do
		for _, pe in ipairs(getEmitters(part)) do
			pe.Enabled = false
		end
	end

	-- Apply scaling
	local S = CONFIG.TemplateParticles.Scale
	local function scaleGroup(name, sizeMul, speedMul)
		local part = parts[name]
		if not part then return end
		for _, pe in ipairs(getEmitters(part)) do
			applyEmitterScale(pe, S.GlobalSize * sizeMul, S.GlobalSpeed * speedMul)
		end
	end

	scaleGroup("Energy",    S.EnergySize,    S.EnergySpeed)
	scaleGroup("Swirl",     S.SwirlSize,     S.SwirlSpeed)
	scaleGroup("Star",      S.StarSize,      S.StarSpeed)
	scaleGroup("Impact",    S.ImpactSize,    S.ImpactSpeed)
	scaleGroup("Explosion", S.ExplosionSize, S.ExplosionSpeed)
	scaleGroup("Smoke",     S.SmokeSize,     S.SmokeSpeed)

	return parts
end

local function setGroupCFrame(parts, name, cf)
	local p = parts and parts[name]
	if p and p:IsA("BasePart") then
		p.CFrame = cf
	end
end

local function setGroupEnabled(parts, name, enabled)
	local p = parts and parts[name]
	if not p then return end
	for _, pe in ipairs(getEmitters(p)) do
		pe.Enabled = enabled
	end
end

local function burstGroup(parts, name, mult)
	local p = parts and parts[name]
	if not p then return end
	mult = mult or 1
	for _, pe in ipairs(getEmitters(p)) do
		local base = math.max(20, math.floor(pe.Rate))
		local amt = math.floor(base * mult)
		pcall(function() pe:Emit(amt) end)
	end
end

-- ============================================================
-- POSTFX + IMPACT FRAMES
-- ============================================================
local function doPostFX()
	if not (RunService:IsClient() and CONFIG.PostFX.Enabled) then return end

	local cc = Lighting:FindFirstChild("__ExplosionCC") or Instance.new("ColorCorrectionEffect")
	cc.Name = "__ExplosionCC"
	cc.Parent = Lighting

	local bloom = Lighting:FindFirstChild("__ExplosionBloom") or Instance.new("BloomEffect")
	bloom.Name = "__ExplosionBloom"
	bloom.Parent = Lighting

	local blur = Lighting:FindFirstChild("__ExplosionBlur") or Instance.new("BlurEffect")
	blur.Name = "__ExplosionBlur"
	blur.Parent = Lighting

	local PCC = CONFIG.PostFX.CC
	local PB = CONFIG.PostFX.Bloom
	local PL = CONFIG.PostFX.Blur

	cc.TintColor = PCC.Tint
	cc.Contrast = PCC.Contrast
	cc.Saturation = PCC.Saturation
	cc.Brightness = PCC.Brightness

	bloom.Intensity = PB.Intensity
	bloom.Size = PB.Size
	bloom.Threshold = PB.Threshold

	blur.Size = PL.Size

	task.delay(0.14, function()
		if isAlive(cc) then
			tw(cc, PCC.RecoverTime, {Contrast = 0, Saturation = 0, Brightness = 0, TintColor = Color3.fromRGB(255,255,255)}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
		if isAlive(bloom) then
			tw(bloom, PB.RecoverTime, {Intensity = PB.RecoverIntensity, Size = PB.RecoverSize, Threshold = PB.RecoverThreshold}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
		if isAlive(blur) then
			tw(blur, PL.RecoverTime, {Size = 0}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
	end)
end

local function doImpactOverlay()
	if not (RunService:IsClient() and CONFIG.PostFX.Enabled and CONFIG.PostFX.ImpactOverlay) then return end
	local lp = Players.LocalPlayer
	if not lp then return end
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	if not pg then return end

	local gui = pg:FindFirstChild("__ExplosionImpactGUI")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "__ExplosionImpactGUI"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = pg
	end

	local frame = gui:FindFirstChild("__ImpactFrame")
	if not frame then
		frame = Instance.new("Frame")
		frame.Name = "__ImpactFrame"
		frame.BorderSizePixel = 0
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.ZIndex = 1000
		frame.Parent = gui
	end

	local function flash(color, t)
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 0
		tw(frame, t, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end

	for i = 1, CONFIG.PostFX.ImpactFrameCount do
		task.delay((i - 1) * CONFIG.PostFX.ImpactFrameGap, function()
			if not isAlive(frame) then return end
			flash(Color3.new(1, 1, 1), CONFIG.PostFX.ImpactFrameTime)
			task.delay(CONFIG.PostFX.ImpactFrameTime * 0.55, function()
				if isAlive(frame) then
					flash(Color3.new(0, 0, 0), CONFIG.PostFX.ImpactFrameTime * 0.75)
				end
			end)
		end)
	end
end

-- ============================================================
-- CAMERA
-- ============================================================
local function cameraController(originPos, tag)
	if not (RunService:IsClient() and CONFIG.Camera.Enabled) then return nil end
	local cam = workspace.CurrentCamera
	if not cam then return nil end

	local oldType = cam.CameraType
	local oldSubject = cam.CameraSubject
	local oldCF = cam.CFrame
	local oldFov = cam.FieldOfView

	local function zoomCF()
		local back = CONFIG.Camera.ZoomBack * CONFIG.Scale
		local up = CONFIG.Camera.ZoomUp * CONFIG.Scale
		local camPos = originPos + Vector3.new(0, up, 0) - (Vector3.new(0, 0, 1) * back)
		return CFrame.lookAt(camPos, originPos + Vector3.new(0, 18 * CONFIG.Scale, 0))
	end

	local t0 = time()
	local inEnd = t0 + CONFIG.Camera.ZoomInTime
	local holdEnd = inEnd + CONFIG.Camera.Hold
	local outEnd = holdEnd + CONFIG.Camera.ZoomOutTime

	local targetCF = zoomCF()
	local targetFov = math.clamp(oldFov - CONFIG.Camera.FovPunch, 35, 90)

	local key = "__ExplosionCam_" .. tag
	pcall(function() RunService:UnbindFromRenderStep(key) end)

	cam.CameraType = Enum.CameraType.Scriptable

	local trauma = 0
	local seed = math.random(1, 999999)

	local function addTrauma(x)
		trauma = math.clamp(trauma + x, 0, 1)
	end

	RunService:BindToRenderStep(key, Enum.RenderPriority.Camera.Value + 10, function()
		if not isAlive(cam) then
			RunService:UnbindFromRenderStep(key)
			return
		end

		local now = time()
		local base

		if CONFIG.Camera.ZoomOut then
			if now <= inEnd then
				local a = math.clamp((now - t0) / CONFIG.Camera.ZoomInTime, 0, 1)
				base = oldCF:Lerp(targetCF, a)
				cam.FieldOfView = oldFov + (targetFov - oldFov) * a
			elseif now <= holdEnd then
				base = targetCF
				cam.FieldOfView = targetFov
			elseif now <= outEnd then
				local a = math.clamp((now - holdEnd) / CONFIG.Camera.ZoomOutTime, 0, 1)
				base = targetCF:Lerp(oldCF, a)
				cam.FieldOfView = targetFov + (oldFov - targetFov) * a
			else
				RunService:UnbindFromRenderStep(key)
				cam.FieldOfView = oldFov
				cam.CameraSubject = oldSubject
				cam.CameraType = oldType
				cam.CFrame = oldCF
				return
			end
		else
			base = cam.CFrame
		end

		cam.CFrame = base
	end)

	local hbConn
	hbConn = RunService.Heartbeat:Connect(function(dt)
		if not isAlive(cam) then
			if hbConn then hbConn:Disconnect() end
			return
		end

		trauma = math.max(0, trauma - CONFIG.Camera.TraumaDecay * dt)
		local t = os.clock()

		local tx = math.noise(t * 18, seed, 0)
		local ty = math.noise(t * 18, seed, 1)
		local tz = math.noise(t * 18, seed, 2)

		local rx = math.noise(t * 14, seed, 3)
		local ry = math.noise(t * 14, seed, 4)
		local rz = math.noise(t * 14, seed, 5)

		local k = trauma * trauma
		local off = Vector3.new(
			tx * CONFIG.Camera.MaxOffset.X,
			ty * CONFIG.Camera.MaxOffset.Y,
			tz * CONFIG.Camera.MaxOffset.Z
		) * k

		local rot = Vector3.new(
			rx * math.rad(CONFIG.Camera.MaxRotDeg.X),
			ry * math.rad(CONFIG.Camera.MaxRotDeg.Y),
			rz * math.rad(CONFIG.Camera.MaxRotDeg.Z)
		) * k

		cam.CFrame = cam.CFrame * CFrame.new(off) * CFrame.Angles(rot.X, rot.Y, rot.Z)
	end)

	return {
		addTrauma = addTrauma,
		stop = function()
			pcall(function() RunService:UnbindFromRenderStep(key) end)
			if hbConn then hbConn:Disconnect() end
		end
	}
end

-- ============================================================
-- PROCEDURAL SYSTEMS
-- ============================================================
local function activateRing(ring, cf, radius0, radius1, thick0, thick1, growT, fadeT, wobbleDeg, color, startAlpha)
	ring.Color = color
	ring.Transparency = startAlpha
	ring.Size = Vector3.new(thick0, radius0 * 2, radius0 * 2) * CONFIG.Scale
	ring.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))

	local tiltX = math.rad((math.random() - 0.5) * 2 * wobbleDeg)
	local tiltZ = math.rad((math.random() - 0.5) * 2 * wobbleDeg)
	ring.CFrame = ring.CFrame * CFrame.Angles(tiltX, 0, tiltZ)

	tw(ring, growT, {Size = Vector3.new(thick1, radius1 * 2, radius1 * 2) * CONFIG.Scale}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	tw(ring, fadeT, {Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- pooled: do NOT Debris:AddItem
	releaseLater(ring, math.max(growT, fadeT) + 0.6)
end

local function spawnStreaks(originCF, streakPool)
	if not CONFIG.Streaks.Enabled then return end
	local cfg = CONFIG.Streaks
	local color = cfg.Color or CONFIG.HotWhite

	for _ = 1, cfg.Count do
		local ang = randf(0, math.pi * 2)
		local elev = randf(-0.45, 0.65)
		local dir = Vector3.new(math.cos(ang), elev, math.sin(ang)).Unit

		local len = randf(cfg.Length[1], cfg.Length[2]) * CONFIG.Scale
		local thick = randf(cfg.Thickness[1], cfg.Thickness[2]) * CONFIG.Scale
		local out = cfg.OutRadius * CONFIG.Scale

		local startPos = originCF.Position
		local endPos = originCF.Position + dir * out

		local p = streakPool:next()
		p.Color = color
		p.Transparency = 0.16
		p.Size = Vector3.new(thick, thick, len)

		p.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -len * 0.5)
		tw(p, cfg.Time, {CFrame = CFrame.lookAt(endPos, endPos + dir) * CFrame.new(0, 0, -len * 0.5), Transparency = 0.06}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
		tw(p, cfg.FadeTime, {Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		-- pooled: do NOT Debris:AddItem
		releaseLater(p, math.max(cfg.Time, cfg.FadeTime) + 0.7)
	end
end

local function findAbsorbTarget()
	local lp = Players.LocalPlayer
	if not lp then return nil end
	local char = lp.Character
	if not char then return nil end
	local t = char:FindFirstChild(CONFIG.Debris.AbsorbTargetName)
	if t and t:IsA("BasePart") then return t end
	return char:FindFirstChild("HumanoidRootPart")
end

local function spawnDebris(originCF, debrisPool)
	if not CONFIG.Debris.Enabled then return end
	local cfg = CONFIG.Debris
	local pieces = {}

	for i = 1, cfg.Count do
		local a = (i / cfg.Count) * math.pi * 2
		local r = (cfg.Radius * CONFIG.Scale) * (0.55 + math.random() * 0.8)
		local y = (math.random() * 18 - 4) * CONFIG.Scale

		local p = debrisPool:next()
		p.Color = CONFIG.CoreColor
		p.Transparency = 0.12

		local s = cfg.Size * CONFIG.Scale
		local j = cfg.SizeJitter or Vector3.new(1,1,1)
		p.Size = Vector3.new(
			s.X * randf(0.7, j.X),
			s.Y * randf(0.7, j.Y),
			s.Z * randf(0.7, j.Z)
		)

		p.CFrame = originCF * CFrame.new(math.cos(a)*r, y, math.sin(a)*r) * CFrame.Angles(math.random()*math.pi, math.random()*math.pi, math.random()*math.pi)
		table.insert(pieces, p)

		local out = (p.Position - originCF.Position).Unit
		local midPos = p.Position + out * (32 * CONFIG.Scale) + Vector3.new(0, 22 * CONFIG.Scale, 0)
		tw(p, 0.24, {CFrame = CFrame.new(midPos) * p.CFrame.Rotation, Transparency = 0.03}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

		-- pooled safety release
		releaseLater(p, 3.0)
	end

	if cfg.Absorb then
		task.delay(cfg.AbsorbDelay, function()
			local target = findAbsorbTarget()
			for _, p in ipairs(pieces) do
				if isAlive(p) then
					if target then
						local tpos = target.Position
						local jitter = Vector3.new((math.random()-0.5)*4, (math.random()-0.5)*4, (math.random()-0.5)*4) * CONFIG.Scale
						tw(p, cfg.AbsorbTime, {CFrame = CFrame.new(tpos + jitter), Transparency = 1}, Enum.EasingStyle.Exponential, Enum.EasingDirection.In)
						releaseLater(p, cfg.AbsorbTime + 0.5)
					else
						tw(p, 0.35, {Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
						releaseLater(p, 0.6)
					end
				end
			end
		end)
	end
end

local function spawnPillarBeam(originCF, folder, rayPool)
	if not CONFIG.PillarBeam.Enabled then return nil end
	local cfg = CONFIG.PillarBeam

	local beam = Instance.new("Part")
	beam.Name = "__PillarBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = cfg.Material
	beam.Color = cfg.Color
	beam.Transparency = cfg.TransparencyStart
	beam.Size = Vector3.new(cfg.Width, cfg.HeightStart, cfg.Width) * CONFIG.Scale

	local y0 = (cfg.HeightStart * 0.5) * CONFIG.Scale
	beam.CFrame = originCF * CFrame.new(0, y0, 0)
	beam.Parent = folder

	local y1 = (cfg.HeightEnd * 0.5) * CONFIG.Scale
	tw(beam, cfg.GrowTime, {
		Size = Vector3.new(cfg.Width, cfg.HeightEnd, cfg.Width) * CONFIG.Scale,
		CFrame = originCF * CFrame.new(0, y1, 0),
		Transparency = cfg.TransparencyBright
	}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

	for i = 1, cfg.RayCount do
		local r = rayPool:next()
		r.Color = (i % 7 == 0) and CONFIG.PinkEdge or CONFIG.ShockColor
		r.Transparency = 0.85

		local ang = randf(0, math.pi * 2)
		local rad = randf(cfg.RaySpreadRadius * 0.4, cfg.RaySpreadRadius) * CONFIG.Scale
		local len = randf(cfg.RayLength[1], cfg.RayLength[2]) * CONFIG.Scale
		local thick = randf(cfg.RayThickness[1], cfg.RayThickness[2]) * CONFIG.Scale

		r.Size = Vector3.new(thick, len, thick)
		local base = originCF.Position + Vector3.new(math.cos(ang)*rad, randf(8, cfg.HeightEnd*0.55)*CONFIG.Scale, math.sin(ang)*rad)
		r.CFrame = CFrame.lookAt(base, base + Vector3.new(0, 1, 0)) * CFrame.Angles(math.rad(-90), 0, 0)

		tw(r, 0.18, {Transparency = 0.55}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tw(r, cfg.RayLife, {Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		-- pooled: do NOT Debris:AddItem
		releaseLater(r, cfg.RayLife + 0.5)
	end

	-- one-off: fine to Debris
	Debris:AddItem(beam, CONFIG.TotalLifetime + 0.5)
	return beam
end

local function startRingFlow(originCF, ringPool, duration)
	if not CONFIG.RingFlow.Enabled then return end
	local cfg = CONFIG.RingFlow
	local color = cfg.Color or CONFIG.ShockColor

	local interval = 1 / math.max(1, cfg.RingsPerSecond)
	local acc = 0
	local tEnd = os.clock() + duration

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if os.clock() >= tEnd then
			if conn then conn:Disconnect() end
			return
		end

		acc += dt
		while acc >= interval do
			acc -= interval
			local h = cfg.Heights[math.random(1, #cfg.Heights)]
			local ring = ringPool:next()
			activateRing(
				ring,
				originCF * CFrame.new(0, h * CONFIG.Scale, 0),
				cfg.StartRadius, cfg.EndRadius,
				cfg.StartThickness, cfg.EndThickness,
				cfg.GrowTime, cfg.FadeTime,
				cfg.WobbleDeg,
				color,
				cfg.StartTransparency
			)
		end
	end)
end

local function spawnRibbons(originCF, folder, duration)
	if not CONFIG.Ribbons.Enabled then return end
	local cfg = CONFIG.Ribbons
	local color = cfg.Color or CONFIG.HotWhite

	local holder = Instance.new("Part")
	holder.Name = "__RibbonHolder"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1,1,1)
	holder.CFrame = originCF
	holder.Parent = folder

	local beams = {}
	for i = 1, cfg.Count do
		local a0 = Instance.new("Attachment")
		local a1 = Instance.new("Attachment")
		a0.Parent = holder
		a1.Parent = holder

		local b = Instance.new("Beam")
		b.Name = "__Ribbon"
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.FaceCamera = true
		b.LightEmission = 1
		b.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		b.TextureSpeed = 0.6 + math.random() * 2.0

		local w0 = randf(cfg.Width[1], cfg.Width[2]) * CONFIG.Scale
		local w1 = randf(cfg.Width[1] * 0.4, cfg.Width[2] * 0.55) * CONFIG.Scale
		b.Width0 = w0
		b.Width1 = w1
		b.Color = ColorSequence.new(color)
		b.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.10),
			NumberSequenceKeypoint.new(0.2, 0.05),
			NumberSequenceKeypoint.new(1, 1),
		})
		b.CurveSize0 = randf(40, 120) * CONFIG.Scale
		b.CurveSize1 = -randf(40, 120) * CONFIG.Scale
		b.Parent = holder

		beams[i] = {
			a0 = a0, a1 = a1,
			ang = randf(0, math.pi * 2),
			speed = cfg.Speed * (0.65 + math.random() * 0.8),
			r = cfg.Radius * (0.7 + math.random() * 0.55) * CONFIG.Scale,
			h0 = randf(10, cfg.Height) * CONFIG.Scale,
			h1 = randf(10, cfg.Height) * CONFIG.Scale,
		}
	end

	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not isAlive(holder) then
			if conn then conn:Disconnect() end
			return
		end
		local t = os.clock() - t0
		if t >= duration then
			if conn then conn:Disconnect() end
			holder:Destroy()
			return
		end

		for _, r in ipairs(beams) do
			r.ang += r.speed * dt
			local x0 = math.cos(r.ang) * r.r
			local z0 = math.sin(r.ang) * r.r
			local x1 = math.cos(r.ang + 1.2) * (r.r * 0.85)
			local z1 = math.sin(r.ang + 1.2) * (r.r * 0.85)

			r.a0.Position = Vector3.new(x0, r.h0 + math.sin(r.ang * 1.4) * (6 * CONFIG.Scale), z0)
			r.a1.Position = Vector3.new(x1, r.h1 + math.cos(r.ang * 1.1) * (6 * CONFIG.Scale), z1)
		end
	end)

	Debris:AddItem(holder, duration + 0.6)
end

local function spawnShockwaves(originCF, shockPool)
	if not CONFIG.Shockwaves.Enabled then return end
	local cfg = CONFIG.Shockwaves
	local color = cfg.Color or CONFIG.ShockColor

	for i = 1, cfg.Count do
		task.delay((i - 1) * cfg.Stagger, function()
			local ring = shockPool:next()
			activateRing(
				ring,
				originCF,
				cfg.StartRadius,
				cfg.EndRadius[i] or cfg.EndRadius[#cfg.EndRadius],
				cfg.StartThickness,
				cfg.EndThickness,
				cfg.GrowTime,
				cfg.FadeTime,
				cfg.WobbleDeg,
				color,
				cfg.StartTransparency
			)
		end)
	end
end

local function spawnPressureDome(originCF, folder)
	if not CONFIG.PressureDome.Enabled then return end
	local cfg = CONFIG.PressureDome

	local dome = Instance.new("Part")
	dome.Name = "__PressureDome"
	dome.Anchored = true
	dome.CanCollide = false
	dome.CanQuery = false
	dome.CanTouch = false
	dome.CastShadow = false
	dome.Shape = Enum.PartType.Ball
	dome.Material = Enum.Material.Neon
	dome.Color = cfg.Color or CONFIG.ShockColor
	dome.Transparency = cfg.StartTransparency
	dome.Size = Vector3.new(cfg.Start, cfg.Start, cfg.Start) * CONFIG.Scale
	dome.CFrame = originCF
	dome.Parent = folder

	tw(dome, cfg.GrowTime, {
		Size = Vector3.new(cfg.End, cfg.End, cfg.End) * CONFIG.Scale,
		Transparency = 1
	}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

	Debris:AddItem(dome, cfg.GrowTime + 0.75)
end

-- ============================================================
-- MAIN
-- ============================================================
local function Start(fxModel)
	-- CLIENT ONLY.
	if not RunService:IsClient() then
		warn("[ExplosionDirector] Client VFX only. Do not run this on the server.")
		return
	end

	if not fxModel or not fxModel.Parent then
		warnf("Start called with nil/invalid model.")
		return
	end

	-- Optional per-instance scale:
	local s = fxModel:GetAttribute("FXScale")
	if typeof(s) == "number" then
		CONFIG.Scale = s
	end

	local core = safeWaitChild(fxModel, "PillarCore")
	local glow = safeWaitChild(fxModel, "PillarGlow")
	local base = safeWaitChild(fxModel, "BaseFlare")
	local sphereCore = safeWaitChild(fxModel, "SphereCore")
	local sphereShell = safeWaitChild(fxModel, "SphereShell")

	if not (core and glow and base and sphereCore and sphereShell) then
		warnf("Missing required parts; aborting.")
		return
	end

	stabilizeModel(fxModel)

	local tag = tostring(math.random(100000, 999999))
	local folder = makeFolder(tag)

	-- Pools
	local ringPool = makePool(folder, CONFIG.Pool.Rings, makeRingPart)
	local shockPool = makePool(folder, CONFIG.Pool.ShockRings, makeRingPart)
	local streakPool = makePool(folder, CONFIG.Pool.Streaks, makeStreakPart)
	local debrisPool = makePool(folder, CONFIG.Pool.Debris, makeDebrisPart)
	local rayPool = makePool(folder, CONFIG.Pool.Rays, makeRayPart)

	-- Template particle clones
	local tpl
	if CONFIG.TemplateParticles.Enabled then
		tpl = cloneTemplateParts(folder)
		-- FORCE BURST TEST (remove later)
		if tpl then
			warn("[ExplosionDirector] Template burst test firing")
			for _, n in ipairs({"Impact","Explosion","Star"}) do
				burstGroup(tpl, n, 3.0)
			end
			setGroupEnabled(tpl, "Smoke", true)
			task.delay(1.5, function()
				if tpl and tpl.Smoke and tpl.Smoke.Parent then
					setGroupEnabled(tpl, "Smoke", false)
				end
			end)
		end

	end

	local function pillarBottomCF()
		return core.CFrame * CFrame.new(0, -(core.Size.Y * 0.5), 0)
	end

	-- Glow flicker
	local flickerConn
	flickerConn = RunService.Heartbeat:Connect(function(dt)
		if not isAlive(glow) then
			if flickerConn then flickerConn:Disconnect() end
			return
		end
		local t = os.clock()
		local f = (math.noise(t * 9, 0, 0) + 1) * 0.5
		local targetT = math.clamp(0.16 - f * 0.12, 0.03, 0.65)
		glow.Transparency += (targetT - glow.Transparency) * math.clamp(dt * 10, 0, 1)
	end)

	-- Camera/PostFX
	doPostFX()
	local camCtrl = cameraController(core.Position, tag)

	-- ========================================================
	-- PHASE 1: Charge
	-- ========================================================
	tw(base, CONFIG.Phase.Charge, {Transparency = math.max(0.04, base.Transparency - 0.18), Size = base.Size * 1.35}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	tw(core, CONFIG.Phase.Charge, {Transparency = math.max(0.02, core.Transparency - 0.16)}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	tw(glow, CONFIG.Phase.Charge, {Transparency = math.max(0.02, glow.Transparency - 0.22)}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

	-- Template positioning at pillar
	if tpl then
		setGroupCFrame(tpl, "Energy", core.CFrame)
		setGroupCFrame(tpl, "Swirl", core.CFrame)
		setGroupCFrame(tpl, "Star", core.CFrame)
	end

	task.wait(CONFIG.Phase.Charge)

	-- ========================================================
	-- PHASE 2: Pillar rises + rings flow + ribbons + TEMPLATE BUILD
	-- ========================================================
	local originCF = core.CFrame
	local pillarBeam = spawnPillarBeam(originCF, folder, rayPool)

	startRingFlow(originCF, ringPool, CONFIG.Phase.RingFlow)
	spawnRibbons(originCF, folder, CONFIG.Phase.RingFlow + 0.55)

	-- Turn on build templates
	if tpl then
		if CONFIG.TemplateParticles.EnableBuildEnergy then setGroupEnabled(tpl, "Energy", true) end
		if CONFIG.TemplateParticles.EnableBuildSwirl then setGroupEnabled(tpl, "Swirl", true) end

		for _, tmark in ipairs(CONFIG.TemplateParticles.Burst.BuildStars) do
			task.delay(tmark, function()
				if tpl and tpl.Star and isAlive(tpl.Star) then
					burstGroup(tpl, "Star", CONFIG.TemplateParticles.BurstStrength.BuildStar)
				end
			end)
		end
	end

	task.wait(CONFIG.Phase.PillarRise + CONFIG.Phase.RingFlow)

	-- ========================================================
	-- PHASE 3: Convert (bottom collapses into sphere)
	-- ========================================================
	local bottomCF = pillarBottomCF()
	sphereCore.CFrame = bottomCF
	sphereShell.CFrame = bottomCF

	tw(core, CONFIG.Phase.Convert, {Transparency = 0.28}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tw(glow, CONFIG.Phase.Convert, {Transparency = 0.38}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if pillarBeam then tw(pillarBeam, CONFIG.Phase.Convert, {Transparency = 0.55}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) end

	if tpl then
		for _, n in ipairs(CONFIG.TemplateParticles.Names) do
			setGroupCFrame(tpl, n, bottomCF)
		end
	end

	task.wait(CONFIG.Phase.Convert)

	if tpl then
		setGroupEnabled(tpl, "Energy", false)
		setGroupEnabled(tpl, "Swirl", false)
	end

	-- ========================================================
	-- PHASE 4: Detonation
	-- ========================================================
	doPostFX()
	doImpactOverlay()
	if camCtrl then camCtrl.addTrauma(CONFIG.Camera.TraumaKick) end

	-- Sphere
	if CONFIG.Sphere.Enabled then
		sphereCore.Transparency = CONFIG.Sphere.StartTransparency
		sphereCore.Size = Vector3.new(CONFIG.Sphere.CoreStart, CONFIG.Sphere.CoreStart, CONFIG.Sphere.CoreStart) * CONFIG.Scale
		tw(sphereCore, CONFIG.Sphere.GrowTime, {Size = Vector3.new(CONFIG.Sphere.CoreEnd, CONFIG.Sphere.CoreEnd, CONFIG.Sphere.CoreEnd) * CONFIG.Scale}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

		task.delay(CONFIG.Sphere.HoldTime, function()
			if isAlive(sphereCore) then
				tw(sphereCore, CONFIG.Sphere.FadeTime, {Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end
		end)

		sphereShell.Transparency = CONFIG.Sphere.ShellStartTransparency
		sphereShell.Size = Vector3.new(CONFIG.Sphere.ShellStart, CONFIG.Sphere.ShellStart, CONFIG.Sphere.ShellStart) * CONFIG.Scale
		tw(sphereShell, CONFIG.Sphere.ShellGrowTime, {
			Size = Vector3.new(CONFIG.Sphere.ShellEnd, CONFIG.Sphere.ShellEnd, CONFIG.Sphere.ShellEnd) * CONFIG.Scale,
			Transparency = 1
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end

	-- Procedural blast layers
	spawnShockwaves(bottomCF, shockPool)
	spawnPressureDome(bottomCF, folder)
	spawnStreaks(bottomCF, streakPool)
	spawnDebris(bottomCF, debrisPool)

	-- TEMPLATE detonation behavior
	if tpl then
		if CONFIG.TemplateParticles.EnableSmokeOnDetonation then
			setGroupEnabled(tpl, "Smoke", true)
			task.delay(CONFIG.TemplateParticles.SmokeEnableTime, function()
				if tpl and tpl.Smoke and isAlive(tpl.Smoke) then
					setGroupEnabled(tpl, "Smoke", false)
				end
			end)
		end

		task.delay(CONFIG.TemplateParticles.Burst.DetonateImpact[1], function()
			burstGroup(tpl, "Impact", CONFIG.TemplateParticles.BurstStrength.Impact1)
		end)
		task.delay(CONFIG.TemplateParticles.Burst.DetonateImpact[2], function()
			burstGroup(tpl, "Impact", CONFIG.TemplateParticles.BurstStrength.Impact2)
		end)

		task.delay(CONFIG.TemplateParticles.Burst.DetonateExplosion[1], function()
			burstGroup(tpl, "Explosion", CONFIG.TemplateParticles.BurstStrength.Explosion1)
		end)
		task.delay(CONFIG.TemplateParticles.Burst.DetonateExplosion[2], function()
			burstGroup(tpl, "Explosion", CONFIG.TemplateParticles.BurstStrength.Explosion2)
		end)
		task.delay(CONFIG.TemplateParticles.Burst.DetonateExplosion[3], function()
			burstGroup(tpl, "Explosion", CONFIG.TemplateParticles.BurstStrength.Explosion3)
		end)

		task.delay(CONFIG.TemplateParticles.Burst.DetonateStars[1], function()
			burstGroup(tpl, "Star", CONFIG.TemplateParticles.BurstStrength.Stars1)
		end)
		task.delay(CONFIG.TemplateParticles.Burst.DetonateStars[2], function()
			burstGroup(tpl, "Star", CONFIG.TemplateParticles.BurstStrength.Stars2)
		end)
		task.delay(CONFIG.TemplateParticles.Burst.DetonateStars[3], function()
			burstGroup(tpl, "Star", CONFIG.TemplateParticles.BurstStrength.Stars3)
		end)
	end

	task.delay(0.18, function()
		doPostFX()
		doImpactOverlay()
		if camCtrl then camCtrl.addTrauma(0.55) end
		spawnStreaks(bottomCF, streakPool)
	end)

	task.delay(0.42, function()
		doPostFX()
		if camCtrl then camCtrl.addTrauma(0.35) end
		spawnShockwaves(bottomCF, shockPool)
	end)

	-- ========================================================
	-- PHASE 5: Aftershock
	-- ========================================================
	local afterEnd = os.clock() + CONFIG.Phase.Aftershock
	local afterConn
	afterConn = RunService.Heartbeat:Connect(function()
		if os.clock() >= afterEnd then
			if afterConn then afterConn:Disconnect() end
			return
		end

		if math.random() < 0.05 then
			local ring = shockPool:next()
			activateRing(ring, bottomCF, 24, randf(120, 220), 1.8, randf(4.0, 6.0), 0.35, 0.55, 10, CONFIG.ShockColor, 0.35)
		end

		if math.random() < 0.035 then
			spawnStreaks(bottomCF, streakPool)
		end

		if camCtrl and math.random() < 0.025 then
			camCtrl.addTrauma(CONFIG.Camera.AfterTraumaKick * (0.6 + math.random() * 0.6))
		end

		if tpl and math.random() < 0.02 then
			burstGroup(tpl, "Star", 0.45)
		end
	end)

	-- Fade model parts
	task.delay(CONFIG.Phase.DetonationBurst, function()
		if flickerConn and flickerConn.Connected then flickerConn:Disconnect() end
		tw(core, CONFIG.Phase.FadeModel, {Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tw(glow, CONFIG.Phase.FadeModel, {Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tw(base, CONFIG.Phase.FadeModel, {Transparency = 1, Size = base.Size * 0.9}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)

	-- Cleanup
	task.delay(CONFIG.TotalLifetime, function()
		if camCtrl then camCtrl.stop() end
		if flickerConn and flickerConn.Connected then flickerConn:Disconnect() end
		if isAlive(folder) then folder:Destroy() end
	end)
end

return Start
