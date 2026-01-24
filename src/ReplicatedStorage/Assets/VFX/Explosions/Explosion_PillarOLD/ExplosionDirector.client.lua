-- ExplosionDirector.lua (FULL AMENDED - MODEL RINGS FIX)
-- ✅ Rings can be Models OR Parts and will expand outward + fade
-- ✅ Stable ring rotation using pivot + cached local transforms
-- ✅ Works with client-spawned explosion as long as this is a LocalScript

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local IS_CLIENT = RunService:IsClient()
local model = script.Parent

local core = model:WaitForChild("PillarCore")
local glow = model:WaitForChild("PillarGlow")
local base = model:WaitForChild("BaseFlare")

local ringBottom = model:FindFirstChild("RingBottom")
local ringMid = model:FindFirstChild("RingMid")
local ringTop = model:FindFirstChild("RingTop")

local sphereCore = model:WaitForChild("SphereCore")
local sphereShell = model:WaitForChild("SphereShell")

-- -------------------------------
-- Helpers
-- -------------------------------
local function tw(obj, t, props, style, dir)
	style = style or Enum.EasingStyle.Exponential
	dir = dir or Enum.EasingDirection.Out
	local tween = TweenService:Create(obj, TweenInfo.new(t, style, dir), props)
	tween:Play()
	return tween
end

local function clamp01(x) return math.clamp(x, 0, 1) end
local function lerp(a,b,t) return a + (b-a)*t end

local function setT(p, v)
	if p and p.Parent then p.Transparency = v end
end

local function getParts(obj)
	local parts = {}
	if not obj then return parts end

	if obj:IsA("BasePart") then
		table.insert(parts, obj)
	elseif obj:IsA("Model") then
		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	end
	return parts
end

local function setTransparency(obj, alpha)
	for _, p in ipairs(getParts(obj)) do
		p.Transparency = alpha
	end
end

local function tweenTransparency(obj, time, alpha)
	for _, p in ipairs(getParts(obj)) do
		tw(p, time, {Transparency = alpha}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
end

-- -------------------------------
-- Ring “Model scaling” system
-- -------------------------------
local function captureRig(obj)
	if not obj then return nil end
	local rig = {
		obj = obj,
		parts = getParts(obj),
		basePivot = nil,
		base = {}, -- [part] = {localPos, localRot, size0}
	}

	-- GetPivot works for both Model and BasePart in modern Roblox
	local pivot = obj:GetPivot()
	rig.basePivot = pivot

	for _, p in ipairs(rig.parts) do
		local localCF = pivot:ToObjectSpace(p.CFrame)
		local localPos = localCF.Position
		local localRot = localCF - localPos

		rig.base[p] = {
			localPos = localPos,
			localRot = localRot,
			size0 = p.Size,
		}
	end

	return rig
end

local function applyRig(rig, scaleXZ, scaleY, rotY, transparency)
	if not rig or not rig.obj or not rig.obj.Parent then return end
	scaleXZ = scaleXZ or 1
	scaleY = scaleY or 1
	rotY = rotY or 0

	local pivot = rig.basePivot * CFrame.Angles(0, rotY, 0)

	for part, info in pairs(rig.base) do
		if part and part.Parent then
			local lp = info.localPos
			local scaledPos = Vector3.new(lp.X * scaleXZ, lp.Y * scaleY, lp.Z * scaleXZ)
			part.CFrame = pivot * CFrame.new(scaledPos) * info.localRot

			local s0 = info.size0
			part.Size = Vector3.new(s0.X * scaleXZ, s0.Y * scaleY, s0.Z * scaleXZ)

			if transparency ~= nil then
				part.Transparency = transparency
			end
		end
	end
end

local function animateRig(rig, duration, fromXZ, toXZ, fromY, toY, fromA, toA, easingPow)
	easingPow = easingPow or 2.4
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not rig or not rig.obj or not rig.obj.Parent then
			conn:Disconnect()
			return
		end

		local t = (os.clock() - t0) / duration
		if t >= 1 then
			applyRig(rig, toXZ, toY, rig._rotY or 0, toA)
			conn:Disconnect()
			return
		end

		-- Exponential-ish ease out
		local e = 1 - ((1 - t) ^ easingPow)

		local sxz = lerp(fromXZ, toXZ, e)
		local sy = lerp(fromY, toY, e)
		local a = lerp(fromA, toA, e)

		applyRig(rig, sxz, sy, rig._rotY or 0, a)
	end)
end

-- -------------------------------
-- Client-only Lighting slam
-- -------------------------------
local cc, bloom, blur
if IS_CLIENT then
	cc = Lighting:FindFirstChild("__ExplosionCC") or Instance.new("ColorCorrectionEffect")
	cc.Name = "__ExplosionCC"
	cc.Parent = Lighting

	bloom = Lighting:FindFirstChild("__ExplosionBloom") or Instance.new("BloomEffect")
	bloom.Name = "__ExplosionBloom"
	bloom.Parent = Lighting

	blur = Lighting:FindFirstChild("__ExplosionBlur") or Instance.new("BlurEffect")
	blur.Name = "__ExplosionBlur"
	blur.Parent = Lighting
end

local function lightingSlam()
	if not IS_CLIENT then return end

	cc.TintColor = Color3.fromRGB(255, 90, 70)
	cc.Contrast = 0.55
	cc.Saturation = 0.25
	cc.Brightness = 0.08

	bloom.Intensity = 3.4
	bloom.Size = 80
	bloom.Threshold = 0.55

	blur.Size = 10

	task.delay(0.12, function()
		if cc and cc.Parent then
			tw(cc, 1.0, {Contrast = 0, Saturation = 0, Brightness = 0, TintColor = Color3.fromRGB(255,255,255)}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
		if bloom and bloom.Parent then
			tw(bloom, 1.0, {Intensity = 0.65, Size = 26, Threshold = 0.8}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
		if blur and blur.Parent then
			tw(blur, 0.5, {Size = 0}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
	end)
end

-- -------------------------------
-- Client-only camera punch
-- -------------------------------
local cam = workspace.CurrentCamera
local function cameraPunch()
	if not IS_CLIENT then return end
	if not cam then return end

	local startFov = cam.FieldOfView
	cam.FieldOfView = startFov + 12
	task.delay(0.06, function()
		if cam then
			tw(cam, 0.22, {FieldOfView = startFov}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
	end)

	local t0 = os.clock()
	local shakeDur = 0.22
	local shakeAmt = 0.55
	local baseCF = cam.CFrame

	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not cam then conn:Disconnect() return end
		local t = os.clock() - t0
		if t > shakeDur then conn:Disconnect() return end

		local falloff = 1 - (t / shakeDur)
		local x = (math.random() - 0.5) * 2 * shakeAmt * falloff
		local y = (math.random() - 0.5) * 2 * shakeAmt * falloff
		cam.CFrame = baseCF * CFrame.new(x, y, 0)
	end)
end

-- -------------------------------
-- Runtime particle setup
-- -------------------------------
local function makeEmitter(parent, props)
	local att = Instance.new("Attachment")
	att.Name = "__ExplosionAtt"
	att.Parent = parent

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "__ExplosionPE"
	pe.Parent = att

	pe.Enabled = false
	pe.LightEmission = 0.8
	pe.Rate = 0
	pe.Speed = NumberRange.new(0, 0)
	pe.Lifetime = NumberRange.new(0.35, 0.8)
	pe.Drag = 4
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-90, 90)
	pe.Size = NumberSequence.new(0.5)
	pe.Transparency = NumberSequence.new(0, 1)
	pe.Acceleration = Vector3.new(0, 0, 0)
	pe.LockedToPart = false
	pe.Color = ColorSequence.new(Color3.new(1, 0.4, 0.3))

	for k, v in pairs(props or {}) do
		pe[k] = v
	end

	return pe, att
end

local sparks, sparksAtt = makeEmitter(core, {
	Texture = "rbxasset://textures/particles/sparkles_main.dds",
	Lifetime = NumberRange.new(0.25, 0.55),
	Speed = NumberRange.new(55, 95),
	Drag = 6,
	LightEmission = 1,
	Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.2, 0.55),
		NumberSequenceKeypoint.new(1, 0),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Color = ColorSequence.new(Color3.fromRGB(255, 160, 120)),
})

local smoke, smokeAtt = makeEmitter(base, {
	Texture = "rbxasset://textures/particles/smoke_main.dds",
	Lifetime = NumberRange.new(0.8, 1.6),
	Speed = NumberRange.new(10, 22),
	Drag = 2,
	LightEmission = 0.35,
	Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 4.6),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Color = ColorSequence.new(Color3.fromRGB(255, 140, 120)),
})

local embers, embersAtt = makeEmitter(core, {
	Texture = "rbxasset://textures/particles/fire_main.dds",
	Lifetime = NumberRange.new(0.45, 0.9),
	Speed = NumberRange.new(18, 40),
	Drag = 3,
	LightEmission = 0.9,
	Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.35, 0.55),
		NumberSequenceKeypoint.new(1, 0),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.2, 0.12),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Color = ColorSequence.new(Color3.fromRGB(255, 120, 90)),
})

-- -------------------------------
-- Animator (pillar wobble + stable ring rotation)
-- -------------------------------
local alive = true

local baseCF_core = core.CFrame
local baseCF_glow = glow.CFrame
local baseCF_base = base.CFrame

local spinSpeed = math.rad(340)
local wobbleAmt = 0.06
local flickerMin = 0.08

-- Capture ring rigs (Models supported)
local rigBottom = captureRig(ringBottom)
local rigMid = captureRig(ringMid)
local rigTop = captureRig(ringTop)

local function startAnimator()
	local tStart = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not alive then
			conn:Disconnect()
			return
		end

		local t = os.clock() - tStart
		local wobX = math.sin(t * 12) * wobbleAmt
		local wobZ = math.cos(t * 10.5) * wobbleAmt
		local spin = t * spinSpeed

		if core and core.Parent then
			core.CFrame = baseCF_core * CFrame.Angles(wobX, spin, wobZ)
		end
		if glow and glow.Parent then
			glow.CFrame = baseCF_glow * CFrame.Angles(-wobZ * 0.7, spin * 1.05, wobX * 0.7)
		end
		if base and base.Parent then
			base.CFrame = baseCF_base * CFrame.Angles(0, -spin * 0.35, 0)
		end

		-- Rotate rings (without breaking their cached transforms)
		local ringSpin = spin * 0.65
		if rigBottom then rigBottom._rotY = ringSpin; applyRig(rigBottom, 1, 1, ringSpin, nil) end
		if rigMid then rigMid._rotY = ringSpin; applyRig(rigMid, 1, 1, ringSpin, nil) end
		if rigTop then rigTop._rotY = ringSpin; applyRig(rigTop, 1, 1, ringSpin, nil) end

		-- Glow flicker
		if glow and glow.Parent then
			local f = (math.noise(t * 8, 0, 0) + 1) * 0.5
			local targetT = math.clamp(glow.Transparency + (0.18 - f * 0.22), flickerMin, 0.65)
			glow.Transparency = glow.Transparency + (targetT - glow.Transparency) * clamp01(dt * 10)
		end
	end)
end

-- -------------------------------
-- Ring pulse (Model-safe outward expansion + fade)
-- -------------------------------
local function ringPulseRig(rig, delayT, endScaleXZ, yThicknessScale)
	if not rig then return end
	yThicknessScale = yThicknessScale or 1.15

	task.delay(delayT, function()
		if not rig.obj or not rig.obj.Parent then return end

		-- Start smaller + visible
		applyRig(rig, 0.55, 0.75, rig._rotY or 0, 0.22)

		-- Snap brighter + slightly thicker
		animateRig(rig, 0.10, 0.55, 0.85, 0.75, yThicknessScale, 0.22, 0.14, 3.0)

		-- Main outward blast + fade out
		task.delay(0.05, function()
			if not rig.obj or not rig.obj.Parent then return end
			animateRig(rig, 0.28, 0.85, endScaleXZ, yThicknessScale, yThicknessScale * 0.95, 0.14, 1.0, 2.6)
		end)
	end)
end

local function emitBurst()
	if sparksAtt then sparksAtt.CFrame = CFrame.Angles(math.rad(-15), 0, 0) end
	if embersAtt then embersAtt.CFrame = CFrame.Angles(math.rad(-10), 0, 0) end
	if smokeAtt then smokeAtt.CFrame = CFrame.Angles(math.rad(-25), 0, 0) end

	sparks:Emit(120)
	embers:Emit(90)
	smoke:Emit(45)
end

-- -------------------------------
-- Explosion sequence
-- -------------------------------
local function playExplosion()
	setT(sphereCore, 1)
	setT(sphereShell, 1)

	startAnimator()

	-- Phase A: CHARGE
	local coreT0 = core.Transparency
	local glowT0 = glow.Transparency
	local baseT0 = base.Transparency
	local baseSize0 = base.Size

	tw(base, 0.10, {Size = baseSize0 * 0.85, Transparency = math.max(0.10, baseT0 - 0.15)}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tw(glow, 0.12, {Transparency = math.max(0.05, glowT0 - 0.25)}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	tw(core, 0.12, {Transparency = math.max(0.02, coreT0 - 0.18)}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

	task.wait(0.10)

	tw(base, 0.14, {Size = baseSize0 * 1.45, Transparency = math.max(0.06, baseT0 - 0.25)}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	task.wait(0.08)

	-- Phase B: DETONATION
	lightingSlam()
	cameraPunch()
	emitBurst()

	-- Sphere core (fast bright pop)
	sphereCore.Size = Vector3.new(3, 3, 3)
	sphereCore.Transparency = 0.15
	tw(sphereCore, 0.18, {Size = Vector3.new(130, 130, 130)}, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	task.delay(0.05, function()
		if sphereCore and sphereCore.Parent then
			tw(sphereCore, 0.22, {Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
	end)

	-- Sphere shell (bigger, slower)
	sphereShell.Size = Vector3.new(7, 7, 7)
	sphereShell.Transparency = 0.8
	tw(sphereShell, 0.42, {Size = Vector3.new(215, 215, 215), Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- ✅ Rings: outward expansion + fade (Models supported)
	ringPulseRig(rigBottom, 0.00, 6.2, 1.20)
	ringPulseRig(rigMid,    0.06, 4.8, 1.18)
	ringPulseRig(rigTop,    0.12, 3.9, 1.16)

	-- Secondary micro-bursts
	task.delay(0.12, function() if alive then emitBurst() end end)
	task.delay(0.20, function() if alive then sparks:Emit(80); embers:Emit(60) end end)

	-- Phase C: linger, then fade pillar
	task.delay(0.28, function()
		if glow and glow.Parent then tw(glow, 0.18, {Transparency = 0.55}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) end
		if core and core.Parent then tw(core, 0.18, {Transparency = 0.35}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) end
	end)

	task.delay(0.55, function()
		alive = false

		tw(core, 0.75, {Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tw(glow, 0.75, {Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tw(base, 0.75, {Transparency = 1, Size = baseSize0 * 0.9}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)

	-- Cleanup particle attachments
	task.delay(3.5, function()
		if sparksAtt then sparksAtt:Destroy() end
		if embersAtt then embersAtt:Destroy() end
		if smokeAtt then smokeAtt:Destroy() end
	end)
end

playExplosion()
