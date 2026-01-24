-- ReplicatedStorage/CataclysmExplosionFX.lua
-- Cataclysm Explosion FX (client-safe, code-only)
-- AMENDED (v11) "DETAIL + TEAR RINGS + BEAM + REAL ABSORB" edition:
-- ✅ Debris/parts no longer orbit forever: strong inward bias + capture zone into torso
-- ✅ Core is way more detailed (microbursts + hot shards + rotating halo shards)
-- ✅ Shockwave rings that feel like they rip through space (fast razor rings + shear rings)
-- ✅ Primary energy beam (outward) that later coils and gets absorbed too
-- ✅ Liquify+tear still happens at absorb start; everything funnels into humanoid torso

local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local Lighting     = game:GetService("Lighting")
local Debris       = game:GetService("Debris")
local Players      = game:GetService("Players")

local M = {}
M.DEBUG = false
local function dprint(...) if M.DEBUG then print("[CataclysmExplosionFX]", ...) end end

--////////////////////////////////////////////////////////////
-- UTIL
--////////////////////////////////////////////////////////////
local function mk(parent, className, props)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function tween(obj, ti, props)
	local t = TweenService:Create(obj, ti, props)
	t:Play()
	return t
end

local function clamp(x, a, b)
	if x < a then return a end
	if x > b then return b end
	return x
end

if RunService:IsClient() then
	local lp = Players.LocalPlayer
	if lp then
		lp.CharacterAdded:Connect(function()
			local pack = Lighting:FindFirstChild("__CataclysmPost")
			if pack then
				local bloom = pack:FindFirstChild("Bloom")
				local cc    = pack:FindFirstChild("CC")
				local blur  = pack:FindFirstChild("Blur")
				local sun   = pack:FindFirstChild("Sun")
				if bloom then bloom.Intensity = 0; bloom.Threshold = 0.95; bloom.Size = 64 end
				if cc then cc.Brightness = 0; cc.Contrast = 0; cc.Saturation = 0; cc.TintColor = Color3.new(1,1,1) end
				if blur then blur.Size = 0 end
				if sun then sun.Intensity = 0 end
			end
		end)
	end
end


local function lerp(a, b, t) return a + (b - a) * t end

local function c3lerp(a: Color3, b: Color3, t: number)
	return Color3.new(lerp(a.R,b.R,t), lerp(a.G,b.G,t), lerp(a.B,b.B,t))
end

local function hash01(a: number, b: number, c: number)
	local n = math.sin(a*12.9898 + b*78.233 + c*37.719) * 43758.5453
	return n - math.floor(n)
end

local function safeUnit(v: Vector3)
	local m = v.Magnitude
	if m < 1e-6 then return Vector3.new(0,1,0) end
	return v / m
end

local function randDir(i, j, k)
	local u = hash01(i, j, k)
	local v = hash01(i*2.1, j*3.2, k*4.3)
	local theta = u * math.pi * 2
	local z = (v * 2) - 1
	local r = math.sqrt(math.max(0, 1 - z*z))
	return Vector3.new(r * math.cos(theta), z, r * math.sin(theta))
end

--////////////////////////////////////////////////////////////
-- RETURN TARGET (TORSO-FIRST)
--////////////////////////////////////////////////////////////
local function getReturnTarget(opts)
	if opts and typeof(opts.returnTarget) == "Instance" and opts.returnTarget:IsA("BasePart") then
		return opts.returnTarget, opts.returnTarget.Position
	end
	if opts and typeof(opts.returnTo) == "Vector3" then
		return nil, opts.returnTo
	end

	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	if not char then return nil, nil end

	local torso =
		char:FindFirstChild("Torso") -- R6
		or char:FindFirstChild("UpperTorso") -- R15
		or char:FindFirstChild("LowerTorso") -- R15 fallback

	if torso and torso:IsA("BasePart") then
		return torso, torso.Position
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp, hrp.Position
	end

	return nil, nil
end

--////////////////////////////////////////////////////////////
-- PALETTE
--////////////////////////////////////////////////////////////
local DEFAULT_PALETTE = {
	primary     = Color3.fromRGB(255, 60, 60),
	secondary   = Color3.fromRGB(255, 180, 180),
	accent      = Color3.fromRGB(90, 0, 0),
	core        = Color3.fromRGB(255, 245, 245),
	rim         = Color3.fromRGB(255, 120, 120),
	residue     = Color3.fromRGB(255, 120, 120),
	debris      = Color3.fromRGB(35, 35, 35),
}

local SOULTYPE_COLOR = {
	Determination = Color3.fromRGB(255, 60, 60),
	Patience      = Color3.fromRGB(120, 150, 255),
	Bravery       = Color3.fromRGB(255, 170, 60),
	Integrity     = Color3.fromRGB(60, 120, 255),
	Perseverance  = Color3.fromRGB(200, 80, 255),
	Kindness      = Color3.fromRGB(60, 255, 120),
	Justice       = Color3.fromRGB(255, 255, 120),
}

local function paletteFromBase(base: Color3)
	local white = Color3.new(1,1,1)
	local black = Color3.new(0,0,0)
	return {
		primary   = base,
		secondary = c3lerp(base, white, 0.60),
		accent    = c3lerp(base, black, 0.62),
		core      = c3lerp(base, white, 0.82),
		rim       = c3lerp(base, white, 0.40),
		residue   = c3lerp(base, white, 0.26),
		debris    = c3lerp(Color3.fromRGB(25,25,25), base, 0.08),
	}
end

local function resolveSoulColor(opts)
	if opts and opts.soulColor then return opts.soulColor end
	if not (opts and opts.autoSoulColor) then return nil end
	local player = Players.LocalPlayer
	if not player then return nil end
	local c = player:GetAttribute("SoulColor")
	if typeof(c) == "Color3" then return c end
	local soulType = player:GetAttribute("SoulType")
	if type(soulType) == "string" and SOULTYPE_COLOR[soulType] then
		return SOULTYPE_COLOR[soulType]
	end
	return nil
end

--////////////////////////////////////////////////////////////
-- POST + SCREENFX
--////////////////////////////////////////////////////////////
local function resetPostPack(pack)
	local bloom = pack:FindFirstChild("Bloom")
	local cc    = pack:FindFirstChild("CC")
	local blur  = pack:FindFirstChild("Blur")
	local sun   = pack:FindFirstChild("Sun")

	if bloom then
		bloom.Intensity = 0
		bloom.Threshold = 0.95
		bloom.Size = 64
	end
	if cc then
		cc.Brightness = 0
		cc.Contrast = 0
		cc.Saturation = 0
		cc.TintColor = Color3.new(1,1,1)
	end
	if blur then
		blur.Size = 0
	end
	if sun then
		sun.Intensity = 0
		sun.Spread = 0.9
	end
end

local function ensurePostPack()
	local pack = Lighting:FindFirstChild("__CataclysmPost")
	if pack then
		-- ✅ IMPORTANT: force-safe defaults so nothing “sticks” across respawns
		resetPostPack(pack)
		return pack
	end

	pack = Instance.new("Folder")
	pack.Name = "__CataclysmPost"
	pack.Parent = Lighting

	mk(pack, "BloomEffect", { Name="Bloom", Intensity=0, Threshold=0.95, Size=64 })
	mk(pack, "ColorCorrectionEffect", { Name="CC", Brightness=0, Contrast=0, Saturation=0, TintColor=Color3.new(1,1,1) })
	mk(pack, "BlurEffect", { Name="Blur", Size=0 })
	mk(pack, "SunRaysEffect", { Name="Sun", Intensity=0, Spread=0.9 })

	resetPostPack(pack)
	return pack
end


local function postPulse(pack, palette, intensity, cfg)
	cfg = cfg or {}
	local i = intensity
	local tIn = cfg.tIn or 0.03
	local tHold = cfg.tHold or 0.02
	local tOut = cfg.tOut or 0.20
	local bloom = pack:FindFirstChild("Bloom")
	local cc    = pack:FindFirstChild("CC")
	local blur  = pack:FindFirstChild("Blur")
	local sun   = pack:FindFirstChild("Sun")

	tween(bloom, TweenInfo.new(tIn, Enum.EasingStyle.Linear), {
		Intensity = (cfg.bloomI or (8.0*i)),
		Threshold = cfg.bloomTh or 0.55,
		Size = cfg.bloomSize or 150
	})
	tween(blur, TweenInfo.new(tIn, Enum.EasingStyle.Linear), { Size = cfg.blur or 28 })
	tween(cc, TweenInfo.new(tIn, Enum.EasingStyle.Linear), {
		Brightness = cfg.ccB or (0.55*i),
		Contrast = cfg.ccC or (1.35*i),
		Saturation = cfg.ccS or (0.35*i),
		TintColor = cfg.tint or palette.core,
	})
	tween(sun, TweenInfo.new(tIn, Enum.EasingStyle.Linear), { Intensity = cfg.sun or (0.55*i) })

	tween(bloom, TweenInfo.new(tOut, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, tIn + tHold), {
		Intensity = 0, Threshold = 0.95, Size = 64,
	})
	tween(blur, TweenInfo.new(tOut, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, tIn + tHold), { Size = 0 })
	tween(cc, TweenInfo.new(tOut, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, tIn + tHold), {
		Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1,1,1),
	})
	tween(sun, TweenInfo.new(tOut, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, tIn + tHold), { Intensity = 0 })
end

local function ensureScreenFX()
	if not RunService:IsClient() then return nil end
	local lp = Players.LocalPlayer
	if not lp then return nil end
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	if not pg then return nil end

	local gui = pg:FindFirstChild("__CataclysmScreenFX")
	if gui then return gui end

	gui = Instance.new("ScreenGui")
	gui.Name = "__CataclysmScreenFX"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10^6
	gui.Parent = pg

	mk(gui, "Frame", {
		Name="Flash",
		BackgroundColor3 = Color3.new(1,1,1),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1,1),
		Position = UDim2.fromScale(0,0),
		ZIndex = 10,
	})
	return gui
end

local function screenFlash(gui, alpha, timeIn, timeOut)
	if not gui then return end
	local f = gui:FindFirstChild("Flash")
	if not f then return end
	f.BackgroundTransparency = 1
	tween(f, TweenInfo.new(timeIn or 0.02, Enum.EasingStyle.Linear), {
		BackgroundTransparency = clamp(1 - (alpha or 0.85), 0, 1)
	})
	tween(f, TweenInfo.new(timeOut or 0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, timeIn or 0.02), {
		BackgroundTransparency = 1
	})
end

local function cameraShake(intensity, impulse, life)
	if not RunService:IsClient() then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local amp = (impulse or 1.0) * (0.010 + 0.010*intensity)
	local rot = (impulse or 1.0) * (0.008 + 0.010*intensity)
	local t0 = os.clock()
	local base = cam.CFrame
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > (life or 0.30) then conn:Disconnect(); return end
		local s = 1 - (t / (life or 0.30))
		local a = math.sin(t*42) * rot * s
		local b = math.cos(t*37) * rot * s
		local posJ = Vector3.new(
			math.sin(t*55) * amp * s,
			math.cos(t*61) * amp * 0.7 * s,
			math.sin(t*49) * amp * 0.8 * s
		)
		cam.CFrame = base * CFrame.new(posJ) * CFrame.Angles(a, b, -a*0.6)
	end)
end

--////////////////////////////////////////////////////////////
-- RUNTIME
--////////////////////////////////////////////////////////////
local function newRuntime()
	return { vortexItems = {}, beamItems = {}, freezeUntil = 0 }
end

local function rtAddVortexPart(rt, part, vel, angVel, kind, size0, life)
	rt.vortexItems[#rt.vortexItems+1] = {
		part = part,
		vel = vel or Vector3.zero,
		ang = angVel or Vector3.zero,
		kind = kind or "generic",
		size0 = size0 or part.Size,
		age = 0,
		life = life or 10,
	}
end

local function impactFrame(gui, postPack, palette, intensity, freezeFrac)
	screenFlash(gui, 0.92, 0.015, 0.08)
	if postPack then
		postPulse(postPack, palette, intensity, {
			tIn=0.02, tHold=0.015, tOut=0.18,
			bloomI=10.8*intensity, bloomTh=0.48, bloomSize=190,
			blur=34,
			ccB=0.70*intensity, ccC=1.65*intensity, ccS=0.46*intensity,
			tint=palette.core,
			sun=0.75*intensity
		})
	end
	return os.clock() + (freezeFrac or 0.03)
end

--////////////////////////////////////////////////////////////
-- LIQUIFY + TEAR
--////////////////////////////////////////////////////////////
local function LiquifyAtAbsorbStart(folder, rt, palette, intensity, cfg)
	cfg = cfg or {}
	local dropletPerPart = cfg.dropletPerPart or math.floor(lerp(12, 30, clamp(intensity, 0.6, 1.6)))
	local maxDropletsTotal = cfg.maxDropletsTotal or math.floor(1400 * clamp(intensity, 0.8, 1.4))

	local ribbonChance = cfg.ribbonChance or 0.28
	local dropletSizeMin = cfg.dropletSizeMin or 0.14
	local dropletSizeMax = cfg.dropletSizeMax or 0.80

	local created = 0
	local f = mk(folder, "Folder", { Name="__Liquified" })
	Debris:AddItem(f, 10)

	for _, inst in ipairs(folder:GetDescendants()) do
		if created >= maxDropletsTotal then break end
		if inst:IsA("Part") then
			if inst.Name == "BeamHost" then continue end
			if inst.Transparency >= 0.98 then continue end

			local size = inst.Size
			local vol = size.X * size.Y * size.Z
			local isBig = (vol >= 10) or (size.Magnitude >= 5.5)
			local isNeon = (inst.Material == Enum.Material.Neon)

			if not (isBig or isNeon) then continue end

			local scale = clamp((size.Magnitude / 10), 0.7, 3.0)
			local n = clamp(math.floor(dropletPerPart * scale), 8, 56)

			local baseC = inst.Color
			local center = inst.Position

			tween(inst, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 })
			task.delay(0.12, function()
				if inst and inst.Parent then inst.Parent = nil end
			end)

			for i = 1, n do
				if created >= maxDropletsTotal then break end
				created += 1
				local seed = created

				local dir = randDir(seed, 3.3, 7.7)
				local off = dir * lerp(0.18, 0.72, hash01(seed, 1.1, 1.2)) * math.max(2.0, size.Magnitude * 0.30)

				local s = lerp(dropletSizeMin, dropletSizeMax, hash01(seed, 2.1, 2.2))
				local droplet = mk(f, "Part", {
					Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false,
					CastShadow=false,
					Material=Enum.Material.Neon,
					Color=c3lerp(baseC, palette.core, 0.20 + 0.28*hash01(seed, 4.4, 4.5)),
					Transparency=lerp(0.02, 0.18, hash01(seed, 5.5, 5.6)),
					Size=Vector3.new(s, s, s),
					CFrame=CFrame.new(center + off),
				})

				local up = Vector3.new(0,1,0)
				local tang = safeUnit(up:Cross(dir))
				if tang.Magnitude < 0.01 then tang = safeUnit(Vector3.new(1,0,0):Cross(dir)) end

				local v = (tang * (70 + 170*intensity)) + (dir * (35 + 90*intensity))
				local ang = Vector3.new(
					(hash01(seed, 8.1, 8.2)-0.5)*34,
					(hash01(seed, 8.3, 8.4)-0.5)*56,
					(hash01(seed, 8.5, 8.6)-0.5)*34
				)
				rtAddVortexPart(rt, droplet, v, ang, "liquid", droplet.Size, 10)

				if hash01(seed, 9.1, 9.2) < ribbonChance then
					local rLen = lerp(2.4, 11.5, hash01(seed, 9.3, 9.4)) * (0.85 + 0.8*intensity)
					local ribbon = mk(f, "Part", {
						Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false,
						CastShadow=false,
						Material=Enum.Material.Neon,
						Color=c3lerp(palette.primary, palette.core, 0.24),
						Transparency=lerp(0.08, 0.26, hash01(seed, 9.5, 9.6)),
						Size=Vector3.new(s*0.42, s*0.42, rLen),
						CFrame=CFrame.lookAt(center + off, center + off + dir) * CFrame.new(0,0,-rLen*0.5),
					})
					rtAddVortexPart(rt, ribbon, v * lerp(0.95, 1.45, hash01(seed, 9.7, 9.8)), ang * 1.5, "ribbon", ribbon.Size, 10)
				end
			end
		end
	end
end

--////////////////////////////////////////////////////////////
-- LAYERS
--////////////////////////////////////////////////////////////
local Layers = {}

-- MORE DETAILED CORE: multiple rotating shells + microbursts + shards
function Layers.DetailedCore(folder, center, radius, totalDur, palette, intensity)
	local f = mk(folder, "Folder", { Name="DetailedCore" })
	Debris:AddItem(f, totalDur + 10)

	local baseSize = math.max(14, radius * 0.10)
	local core = mk(f, "Part", {
		Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false,
		Shape=Enum.PartType.Ball, Material=Enum.Material.Neon,
		Color=palette.primary, Transparency=0.00,
		Size=Vector3.new(baseSize, baseSize, baseSize),
		CFrame=CFrame.new(center),
	})
	local hot = mk(f, "Part", {
		Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false,
		Shape=Enum.PartType.Ball, Material=Enum.Material.Neon,
		Color=c3lerp(palette.primary, palette.core, 0.22),
		Transparency=0.18,
		Size=Vector3.new(baseSize*1.35, baseSize*1.35, baseSize*1.35),
		CFrame=CFrame.new(center),
	})
	local halo = mk(f, "Part", {
		Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false,
		Shape=Enum.PartType.Ball, Material=Enum.Material.Neon,
		Color=c3lerp(palette.primary, palette.secondary, 0.35),
		Transparency=0.80,
		Size=Vector3.new(baseSize*1.95, baseSize*1.95, baseSize*1.95),
		CFrame=CFrame.new(center),
	})

	local light = mk(core, "PointLight", { Color=palette.core, Brightness=0, Range=0, Shadows=false })
	tween(light, TweenInfo.new(0.05, Enum.EasingStyle.Linear), { Brightness = 70*intensity, Range = radius*2.9 })
	tween(light, TweenInfo.new(0.70, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.08), { Brightness = 0, Range = radius*1.0 })

	-- Rotating shard halo (looks like fractured energy plates)
	local shardCount = clamp(math.floor(lerp(18, 42, 0.95) * intensity), 14, 70)
	for i = 1, shardCount do
		local dir = randDir(i, 6.6, 7.7)
		local dist = baseSize * lerp(1.05, 2.25, hash01(i, 1.1, 1.2))
		local sX = lerp(0.6, 2.6, hash01(i, 2.1, 2.2))
		local sY = lerp(0.08, 0.35, hash01(i, 3.1, 3.2))
		local sZ = lerp(1.4, 5.2, hash01(i, 4.1, 4.2))
		local shard = mk(f, "Part", {
			Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false,
			CastShadow=false,
			Material=Enum.Material.Neon,
			Color=c3lerp(palette.primary, palette.core, 0.20 + 0.35*hash01(i, 5.1, 5.2)),
			Transparency=lerp(0.12, 0.42, hash01(i, 6.1, 6.2)),
			Size=Vector3.new(sX, sY, sZ),
			CFrame=CFrame.lookAt(center + dir*dist, center) * CFrame.Angles(0, 0, math.rad(90)),
		})
		Debris:AddItem(shard, totalDur + 10)
	end

	-- Microbursts around core (tiny flash balls)
	local burstCount = clamp(math.floor(lerp(40, 110, 0.95) * intensity), 30, 160)
	for i = 1, burstCount do
		local delay = hash01(i, 9.1, 9.2) * 0.35
		task.delay(delay, function()
			if not f.Parent then return end
			local dir = randDir(i, 8.2, 3.4)
			local dist = baseSize * lerp(0.35, 1.85, hash01(i, 5.5, 5.6))
			local s = lerp(0.6, 2.2, hash01(i, 7.1, 7.2))
			local b = mk(f, "Part", {
				Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false,
				Shape=Enum.PartType.Ball,
				Material=Enum.Material.Neon,
				Color=c3lerp(palette.core, palette.primary, 0.35),
				Transparency=0.10,
				Size=Vector3.new(s,s,s),
				CFrame=CFrame.new(center + dir*dist),
			})
			tween(b, TweenInfo.new(0.10, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Size = Vector3.new(s*lerp(2.2, 4.0, intensity), s*lerp(2.2, 4.0, intensity), s*lerp(2.2, 4.0, intensity)),
				Transparency = 1
			})
			Debris:AddItem(b, 0.25)
		end)
	end
end

-- SHOCKWAVE TEAR RINGS: fast razor rings + vertical shear rings
function Layers.TearShockRings(folder, center, radius, totalDur, palette, rt, outwardTime, holdTime, quality, intensity)
	local f = mk(folder, "Folder", { Name="TearShockRings" })
	Debris:AddItem(f, totalDur + 10)

	local ringCount = clamp(math.floor(lerp(8, 16, quality) * (0.9 + 0.6*intensity)), 6, 22)

	for i = 1, ringCount do
		local t = (i-1) / math.max(ringCount-1, 1)
		local delay = lerp(0.00, 0.18, t)
		local y = (t - 0.5) * (radius * 0.14)
		local tilt = (hash01(i, 3.3, 4.4)-0.5) * math.rad(45)
		local roll = (hash01(i, 5.5, 6.6)-0.5) * math.rad(35)

		local p = mk(f, "Part", {
			Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false,
			CastShadow=false,
			Material=Enum.Material.Neon,
			Color=c3lerp(palette.core, palette.primary, 0.35 + 0.35*t),
			Transparency=0.22,
			Size=Vector3.new(2, 1, 2),
			CFrame=CFrame.new(center + Vector3.new(0,y,0)) * CFrame.Angles(math.rad(90), tilt, roll),
		})
		local mesh = mk(p, "SpecialMesh", { MeshType=Enum.MeshType.Cylinder, Scale=Vector3.new(1, 0.02, 1) })

		-- Violent “tear” expansion then stop (no further growth during hold)
		local endR = radius * lerp(1.55, 2.45, t)
		task.delay(delay, function()
			if not p.Parent then return end
			tween(mesh, TweenInfo.new(outwardTime * 0.95, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Scale = Vector3.new(endR*2.0, 0.02, endR*2.0)
			})
			tween(p, TweenInfo.new(outwardTime * 0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 0.78
			})
		end)

		-- Add to absorb runtime so it gets liquified/dragged too
		rtAddVortexPart(rt, p, Vector3.zero, Vector3.new(0, 14*intensity*(0.6+t), 0), "shockRing", p.Size, totalDur)
	end

	-- Shear rings (vertical slices)
	local shearCount = clamp(math.floor(lerp(6, 12, quality) * intensity), 4, 16)
	for i = 1, shearCount do
		local delay = hash01(i, 7.7, 8.8) * 0.22
		local ang = hash01(i, 1.1, 2.2) * math.pi * 2
		local yaw = ang
		local p = mk(f, "Part", {
			Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false,
			CastShadow=false,
			Material=Enum.Material.Neon,
			Color=c3lerp(palette.primary, palette.core, 0.25),
			Transparency=0.30,
			Size=Vector3.new(2, 1, 2),
			CFrame=CFrame.new(center) * CFrame.Angles(0, yaw, math.rad(90)),
		})
		local mesh = mk(p, "SpecialMesh", { MeshType=Enum.MeshType.Cylinder, Scale=Vector3.new(1, 0.02, 1) })

		task.delay(delay, function()
			if not p.Parent then return end
			local endR = radius * lerp(1.35, 2.1, hash01(i, 3.3, 3.4))
			tween(mesh, TweenInfo.new(outwardTime * 0.90, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Scale = Vector3.new(endR*2.0, 0.02, endR*2.0)
			})
			tween(p, TweenInfo.new(outwardTime * 0.90, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 0.85
			})
		end)

		rtAddVortexPart(rt, p, Vector3.zero, Vector3.new(0, 18*intensity, 0), "shockRing", p.Size, totalDur)
	end
end

-- Primary energy beam (outward), later gets sucked in via the beam runtime
function Layers.PrimaryEnergyBeam(folder, center, radius, palette, rt, outwardTime, holdTime, intensity)
	local f = mk(folder, "Folder", { Name="PrimaryEnergyBeam" })
	Debris:AddItem(f, outwardTime + holdTime + 10)

	local dir = Vector3.new(0, 1, 0) -- dramatic upward beam
	local len = radius * (2.2 + 0.7*intensity)
	local p0 = center + dir * (radius * 0.02)
	local p1 = p0 + dir * len

	local host = mk(f, "Part", {
		Name="BeamHost",
		Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false,
		Transparency=1, Size=Vector3.new(1,1,1), CFrame=CFrame.new(center),
	})
	local a0 = mk(host, "Attachment", { Position = host.CFrame:PointToObjectSpace(p0) })
	local a1 = mk(host, "Attachment", { Position = host.CFrame:PointToObjectSpace(p0) })

	local beam = mk(host, "Beam", {
		Attachment0 = a0, Attachment1 = a1,
		FaceCamera = true,
		LightEmission = 1, LightInfluence = 0,
		TextureMode = Enum.TextureMode.Stretch,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.0, palette.core),
			ColorSequenceKeypoint.new(0.4, palette.primary),
			ColorSequenceKeypoint.new(1.0, palette.accent),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, 0.02),
			NumberSequenceKeypoint.new(0.6, 0.10),
			NumberSequenceKeypoint.new(1.0, 0.92),
		}),
		Width0 = 0.01, Width1 = 0.01,
	})

	local thickness = 3.5 * (0.85 + 0.8*intensity)
	tween(beam, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Width0 = thickness, Width1 = thickness * 0.55 })

	-- register it into beamItems so it also spirals inward later
	rt.beamItems[#rt.beamItems+1] = {
		host = host, a0 = a0, a1 = a1,
		p0 = p0, p1 = p1,
		dir = dir, len = len,
		swirl = 2.8, -- bigger swirl
		outT = outwardTime * 0.85,
		holdT = holdTime,
		age = 0,
		thickness = thickness,
		index = 9999,
	}
end

-- Debris scatter (unchanged behavior, but absorption loop now forces capture)
function Layers.DebrisScatter(folder, center, radius, palette, rt, totalDur, quality, intensity)
	local count = clamp(math.floor(lerp(160, 520, quality) * intensity), 90, 720)
	local speedMin = radius * 0.32
	local speedMax = radius * 1.05
	local upBoost  = radius * 0.25
	local spread   = radius * 0.06
	local sizeMin  = 0.30
	local sizeMax  = 2.35

	local f = mk(folder, "Folder", { Name="DebrisScatter" })
	Debris:AddItem(f, totalDur + 10)

	for i = 1, count do
		local s = lerp(sizeMin, sizeMax, hash01(i, 1.2, 3.4))
		local p = mk(f, "Part", {
			Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false,
			CastShadow=false,
			Material=Enum.Material.Slate,
			Color=palette.debris,
			Transparency=0,
			Size=Vector3.new(
				s,
				s*lerp(0.55, 1.25, hash01(i, 2.2, 2.3)),
				s*lerp(0.75, 1.55, hash01(i, 3.2, 3.3))
			),
			CFrame=CFrame.new(center + Vector3.new(
				(hash01(i, 9.1, 9.2)-0.5)*2*spread,
				(hash01(i, 9.3, 9.4)-0.5)*2*spread,
				(hash01(i, 9.5, 9.6)-0.5)*2*spread
				)),
		})

		local dir = randDir(i, 4.4, 5.5)
		dir = safeUnit(Vector3.new(dir.X, math.abs(dir.Y) + 0.24, dir.Z))
		local spd = lerp(speedMin, speedMax, hash01(i, 6.6, 7.7)) * (0.70 + 0.85*intensity)
		local vel = dir * spd + Vector3.new(0, upBoost, 0)

		local ang = Vector3.new(
			(hash01(i, 8.1, 8.2)-0.5)*16,
			(hash01(i, 8.3, 8.4)-0.5)*24,
			(hash01(i, 8.5, 8.6)-0.5)*16
		)
		rtAddVortexPart(rt, p, vel, ang, "debris", p.Size, totalDur)
	end
end

--////////////////////////////////////////////////////////////
-- VORTEX ABSORB LOOP (FIXED: ACTUALLY ENTERS TORSO)
--////////////////////////////////////////////////////////////
local function startVortexAbsorb(folder, rt, toPart, toPosFn, palette, intensity, cfg, postPack, gui, folderToNuke)
	cfg = cfg or {}

	-- More “go into torso” force, less “orbit forever”
	local pull = cfg.pull or (5200 * intensity)
	local swirl = cfg.swirl or (34 * intensity)
	local swirlRamp = cfg.swirlRamp or 2.6
	local drag = cfg.drag or 0.25

	local vortexLife = cfg.life or 1.85
	local vortexRadius = cfg.vortexRadius or 380
	local shrinkRadius = cfg.shrinkRadius or 130

	-- Hard capture so nothing misses the chest:
	local captureRadius = cfg.captureRadius or 18
	local mergeRadius = cfg.mergeRadius or 10

	local funnelTightness = cfg.funnelTightness or 1.22
	local axisBias = cfg.axisBias or 0.90

	local liquidStretch = cfg.liquidStretch or (2.2 + 0.9*intensity)
	local tearJitter = cfg.tearJitter or (0.80 + 0.6*intensity)

	-- Sink point pushes slightly into torso-facing direction
	local chestInset = cfg.chestInset or 0.35

	local startT = os.clock()
	local stage2At = startT + 0.28
	local stage3At = startT + vortexLife * 0.78

	rt.freezeUntil = impactFrame(gui, postPack, palette, intensity, 0.035) -- reversal impact
	cameraShake(intensity, 1.25, 0.30)

	LiquifyAtAbsorbStart(folder, rt, palette, intensity, cfg.liquify)

	local didStage2, didStage3 = false, false

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		local t = now - startT
		if t > vortexLife then
			conn:Disconnect()
			if folderToNuke and folderToNuke.Parent then
				folderToNuke:ClearAllChildren()
				folderToNuke.Parent = nil
			end
			return
		end

		if now < (rt.freezeUntil or 0) then return end

		local sink = (toPosFn and toPosFn()) or (toPart and toPart.Position)
		if not sink then return end

		local axisUp = Vector3.new(0,1,0)
		local chestForward = Vector3.new(0,0,-1)
		if toPart and toPart.Parent then
			axisUp = toPart.CFrame.UpVector
			chestForward = toPart.CFrame.LookVector
			sink = sink + chestForward * chestInset
		end

		if (not didStage2) and now >= stage2At then
			didStage2 = true
			rt.freezeUntil = impactFrame(gui, postPack, palette, intensity, 0.028) -- vortex forms
			cameraShake(intensity, 1.05, 0.25)
		end
		if (not didStage3) and now >= stage3At then
			didStage3 = true
			rt.freezeUntil = impactFrame(gui, postPack, palette, intensity, 0.040) -- compression
			cameraShake(intensity, 1.55, 0.35)
		end

		-- BEAMS: outward -> hold -> helical spiral into sink
		for i = #rt.beamItems, 1, -1 do
			local it = rt.beamItems[i]
			local host = it.host
			if not (host and host.Parent) then
				table.remove(rt.beamItems, i)
			else
				it.age += dt
				local outT = it.outT or 0.22
				local holdT = it.holdT or 0.0

				if it.age <= outT then
					local p = it.p0:Lerp(it.p1, clamp(it.age / outT, 0, 1))
					it.a1.Position = host.CFrame:PointToObjectSpace(p)
				elseif it.age <= (outT + holdT) then
					it.a1.Position = host.CFrame:PointToObjectSpace(it.p1)
				else
					local inwardT = clamp((it.age - outT - holdT) / vortexLife, 0, 1)
					local from = it.p1
					local straight = from:Lerp(sink, inwardT)

					local rel = (from - sink)
					local radial = rel - axisUp * rel:Dot(axisUp)
					local rMag = radial.Magnitude
					local rDir = rMag > 1e-6 and (radial / rMag) or safeUnit(randDir(i, 1.1, 2.2))
					local tang = safeUnit(axisUp:Cross(rDir))

					local collapseR = rMag * ((1 - inwardT) ^ funnelTightness)
					local ang = now * (swirl * (it.swirl or 1.5)) * (1 + inwardT*swirlRamp)
					local helixOff = (rDir * (math.cos(ang) * collapseR)) + (tang * (math.sin(ang) * collapseR))
					local p = straight + helixOff

					it.a1.Position = host.CFrame:PointToObjectSpace(p)

					local beam = host:FindFirstChildOfClass("Beam")
					if beam then
						local w0 = (it.thickness or 2) * lerp(1.0, 0.03, inwardT)
						beam.Width0 = w0
						beam.Width1 = w0 * 0.35
					end

					if (p - sink).Magnitude < mergeRadius then
						host.Parent = nil
					end
				end
			end
		end

		-- PARTS: FIXED inward capture + reduced endless orbit
		for i = #rt.vortexItems, 1, -1 do
			local it = rt.vortexItems[i]
			local p = it.part
			if not (p and p.Parent) then
				table.remove(rt.vortexItems, i)
			else
				it.age += dt
				if it.age > (it.life or 10) then
					p.Parent = nil
				else
					local pos = p.Position
					local toV = (sink - pos)
					local dist = toV.Magnitude
					local dirTo = safeUnit(toV)

					-- Capture zone: once close enough, force it straight into torso
					if dist < captureRadius then
						local snapSpeed = lerp(35, 140, clamp((captureRadius - dist) / captureRadius, 0, 1))
						local newPos = pos:Lerp(sink, clamp(dt * snapSpeed, 0, 1))
						p.CFrame = CFrame.new(newPos)
						p.Transparency = math.max(p.Transparency, lerp(0.0, 0.8, 1 - dist / captureRadius))
						if (newPos - sink).Magnitude < mergeRadius then
							p.Parent = nil
						end
						continue
					end

					local rel = (pos - sink)
					local axial = axisUp * rel:Dot(axisUp)
					local radial = rel - axial
					local rMag = radial.Magnitude
					local rDir = rMag > 1e-6 and (radial / rMag) or safeUnit(randDir(i, 2.2, 3.3))
					local tang = safeUnit(axisUp:Cross(rDir))

					local closeness = 1 - clamp(dist / vortexRadius, 0, 1)
					local axisPull = axisUp * (-rel:Dot(axisUp)) * axisBias

					-- Strong inward bias that increases near the sink
					local inwardBias = clamp(0.25 + closeness * 0.95, 0.25, 1.25)

					-- Heavier debris: less tangential, more inward (prevents infinite orbit)
					local tangMul = 1.0
					if it.kind == "debris" then
						tangMul = lerp(0.45, 0.18, closeness)
					elseif it.kind == "shockRing" then
						tangMul = lerp(0.75, 0.35, closeness)
					end

					local spinMul = (1 + closeness * swirlRamp)
					local accel =
						(dirTo * (pull * inwardBias)) +
						(tang * (swirl * spinMul * tangMul)) +
						(axisPull * (8 + 12*closeness))

					-- Tear jitter
					local n = math.sin(now*18 + i*0.7) + math.cos(now*23 + i*1.3)
					local jitter = (rDir * (n * tearJitter * (0.35 + 1.1*closeness)))

					-- Integrate velocity; kill sideways drift a bit so it commits inward
					it.vel = (it.vel + (accel + jitter) * dt)
					-- Damp tangential component as it gets close so it doesn’t orbit
					local velRadial = rDir * it.vel:Dot(rDir)
					local velTang   = tang * it.vel:Dot(tang)
					local velAx     = axisUp * it.vel:Dot(axisUp)
					local tangDamp = lerp(0.92, 0.70, closeness)
					it.vel = (velRadial + velTang * tangDamp + velAx) * math.exp(-drag * dt)

					local vStep = it.vel * dt
					local vMag = it.vel.Magnitude

					-- Move
					local nextPos = pos + vStep

					-- Align to velocity for liquid strand look
					if vMag > 1e-3 then
						local look = safeUnit(it.vel)
						p.CFrame = CFrame.lookAt(nextPos, nextPos + look)
					else
						p.CFrame = CFrame.new(nextPos)
					end
					p.CFrame = p.CFrame * CFrame.Angles(it.ang.X*dt, it.ang.Y*dt, it.ang.Z*dt)

					-- Liquid stretch
					if vMag > 1e-3 then
						local stretch = clamp((vMag / 200) * liquidStretch, 1.0, 7.0)
						local base = it.size0
						local squash = lerp(1.0, 0.50, closeness)
						p.Size = Vector3.new(base.X * squash, base.Y * squash, math.max(base.Z, base.X) * stretch)
					end

					-- Fade as it gets near the sink, but don’t “vanish early”
					if dist < shrinkRadius then
						local s = clamp(dist / shrinkRadius, 0.05, 1)
						p.Transparency = clamp(1 - s, 0, 1)
					end

					if (nextPos - sink).Magnitude < mergeRadius then
						p.Parent = nil
					end
				end
			end
		end
	end)
end

--////////////////////////////////////////////////////////////
-- MAIN API
--////////////////////////////////////////////////////////////
function M.Play(center: Vector3, opts: table?)
	opts = opts or {}

	local radius    = opts.radius or 1400
	local intensity = opts.intensity or 1.0
	local quality   = clamp(opts.quality or 0.95, 0.05, 1.0)

	-- TIMING: expand to cap -> HOLD -> ABSORB
	local outwardTime = (opts.timeline and opts.timeline.outwardTime) or 0.22
	local holdTime    = (opts.timeline and opts.timeline.holdTime) or 2.00
	local absorbTime  = (opts.timeline and opts.timeline.absorbTime) or 1.85
	local totalDur    = outwardTime + holdTime + absorbTime

	local base = opts.baseColor or DEFAULT_PALETTE.primary
	local soul = resolveSoulColor(opts)
	if soul then base = soul end
	local palette = opts.palette or paletteFromBase(base)

	local layers = opts.layers
	if layers == nil then
		layers = {
			post=true,
			screenFX=true,
			core=true,
			tearRings=true,
			debris=true,
			primaryBeam=true,
			vortexAbsorb=true,
		}
	end
	if opts.disablePost == true then layers.post = false end
	local function on(name) return layers[name] ~= false end

	local folder = Instance.new("Folder")
	folder.Name = "__CataclysmExplosion"
	folder.Parent = (opts and opts.parent) or workspace
	Debris:AddItem(folder, totalDur + 12)

	local rt = newRuntime()
	local postPack = nil
	if on("post") and RunService:IsClient() then postPack = ensurePostPack() end
	local gui = nil
	if on("screenFX") then gui = ensureScreenFX() end

	-- Detonation punch (stronger)
	if RunService:IsClient() then
		screenFlash(gui, 0.82, 0.02, 0.12)
		cameraShake(intensity, 1.30, 0.40)
		if postPack then
			postPulse(postPack, palette, intensity, {
				tIn=0.03, tHold=0.02, tOut=0.26,
				bloomI=11.0*intensity, bloomTh=0.48, bloomSize=190,
				blur=34,
				ccB=0.68*intensity, ccC=1.60*intensity, ccS=0.42*intensity,
				tint=palette.core,
				sun=0.70*intensity
			})
		end
	end

	if on("core") then
		Layers.DetailedCore(folder, center, radius, totalDur, palette, intensity)
	end

	if on("tearRings") then
		Layers.TearShockRings(folder, center, radius, totalDur, palette, rt, outwardTime, holdTime, quality, intensity)
	end

	if on("debris") then
		Layers.DebrisScatter(folder, center, radius, palette, rt, totalDur, quality, intensity)
	end

	if on("primaryBeam") then
		Layers.PrimaryEnergyBeam(folder, center, radius, palette, rt, outwardTime, holdTime, intensity)
	end

	-- Torso-first return target (locks onto torso)
	local toPart, _ = getReturnTarget(opts)
	local function toPosFn()
		if typeof(opts.returnTo) == "Vector3" then
			return opts.returnTo
		end
		if toPart and toPart.Parent then
			return toPart.Position
		end
		local p2, v2 = getReturnTarget(opts)
		if p2 then toPart = p2 end
		return v2
	end

	if on("vortexAbsorb") then
		task.delay(outwardTime + holdTime, function()
			local posNow = toPosFn()
			if not posNow then
				if folder and folder.Parent then
					folder:ClearAllChildren()
					folder.Parent = nil
				end
				return
			end

			startVortexAbsorb(
				folder,
				rt,
				toPart,
				toPosFn,
				palette,
				intensity,
				opts.vortex or {
					pull = 5200 * intensity,
					swirl = 34 * intensity,
					swirlRamp = 2.6,
					drag = 0.25,
					vortexRadius = 380,
					shrinkRadius = 130,
					captureRadius = 18,
					mergeRadius = 10,
					funnelTightness = 1.22,
					axisBias = 0.90,
					liquidStretch = 2.2 + 0.9*intensity,
					tearJitter = 0.80 + 0.6*intensity,
					chestInset = 0.35,
					life = absorbTime,
					liquify = {
						dropletPerPart = 18,
						maxDropletsTotal = 1500,
						ribbonChance = 0.28,
						dropletSizeMin = 0.14,
						dropletSizeMax = 0.80,
					},
				},
				postPack,
				gui,
				folder
			)
		end)
	end

	return folder
end

function M.Spawn(center, CFG, vfxParent, tw, randf)
	return M.Play(center, {
		disablePost = true,
		parent = (type(vfxParent) == "function") and vfxParent() or workspace,
	})
end

function M.SpawnAt(center, CFG, vfxParent, tw, randf)
	return M.Spawn(center, CFG, vfxParent, tw, randf)
end

return M
