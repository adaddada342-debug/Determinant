--!strict
-- StarterPlayerScripts/AAACameraFeelPlusShiftLock.client.lua
-- Cinematic camera feel package + CUSTOM ShiftLock (over-shoulder) with custom icon.
-- Still does NOT write Camera.CFrame. It only:
--   - Camera.FieldOfView
--   - Humanoid.CameraOffset (additive layer)
--   - Optional Lighting post FX modulation (no auto-create unless enabled)
--   - Optional wind/cloth whoosh Sound (only if it exists)
-- Custom ShiftLock:
--   - Locks mouse (desktop), aligns character yaw to camera
--   - Offsets camera to the RIGHT so the character sits LEFT in frame
--   - Provides its own icon button (mobile + optional desktop)

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Config = {
	-- Master toggles (per feature)
	Enable = {
		FOV = true,
		CameraOffsetLayer = true, -- position-only layer via Humanoid.CameraOffset (safe with other CFrame sway)
		Bob = true,
		Lean = true, -- "pseudo roll" via lateral + slight vertical offset (true roll requires Camera.CFrame)
		Inertia = true,
		LandingJump = true,
		PostFX = true,
		Audio = true,

		CustomShiftLock = true,
	},

	-- Dynamic FOV
	DefaultFOV = 70,
	WalkFOV = 66,
	SprintFOV = 64,
	FOVResponsiveness = 10,

	-- Head bob / walk bounce (subtle)
	BobIntensity = Vector3.new(0.06, 0.09, 0),
	BobFrequency = 1.85,
	BobResponsiveness = 12,
	BobVariation = 0.22,

	-- Camera "roll" / lean (simulated without Camera.CFrame)
	RollMaxDegrees = 2.2,
	RollSpeed = 10,

	-- Acceleration "push" (inertia) via offset
	InertiaStrength = 0.12,
	InertiaDamping = 14,

	-- Landing / jump response
	LandingImpactStrength = 0.28,
	LandingRecoverySpeed = 18,
	JumpLiftStrength = 0.08,

	-- Speed mapping
	Speed = {
		WalkRef = 10,
		SprintRef = 20,
		MaxConsidered = 28,
	},

	-- Custom ShiftLock (over-the-shoulder)
	ShiftLock = {
		Key = Enum.KeyCode.LeftShift,
		-- Positive X moves camera to the RIGHT in character space -> character appears LEFT in view (what you asked for).
		ShoulderOffset = Vector3.new(1.75, 0.15, 0.0),
		OffsetResponsiveness = 14, -- smooth camera offset blending
		AlignCharacterToCamera = true,
		AlignResponsiveness = 18, -- yaw alignment smoothing (character rotation)
		DisableHumanoidAutoRotate = true,

		-- UI
		UseCustomIcon = true,
		IconAssetId = "rbxassetid://0", -- put your icon asset id here (ImageButton.Image)
		IconSize = 44,
		IconPadding = 18,
		ShowOnDesktop = true, -- also show button on PC (still supports keybind)
	},

	-- PostFX (optional and safe)
	PostFX = {
		CreateMissingFX = false,
		Blur = {
			Enabled = true,
			MaxSize = 3.5,
			IdleSize = 0.0,
			Responsiveness = 8,
			Name = "AAACam_Blur",
		},
		DepthOfField = {
			Enabled = true,
			MovingNearIntensity = 0.12,
			IdleNearIntensity = 0.02,
			MovingFarIntensity = 0.14,
			IdleFarIntensity = 0.04,
			Responsiveness = 6,
			Name = "AAACam_DOF",
		},
		Bloom = {
			Enabled = false,
			MovingIntensityAdd = 0.05,
			Responsiveness = 5,
			Name = "AAACam_Bloom",
		},
		ColorCorrection = {
			Enabled = false,
			MovingContrastAdd = 0.03,
			MovingSaturationAdd = 0.02,
			Responsiveness = 5,
			Name = "AAACam_CC",
		},
	},

	-- Audio micro-immersion (optional)
	Audio = {
		SoundPath = "SoundService.Ambient.WindWhoosh",
		MinVolume = 0.0,
		MaxVolume = 0.18,
		MinPlaybackSpeed = 0.95,
		MaxPlaybackSpeed = 1.08,
		Responsiveness = 10,
	},
}

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

----------------------------------------------------------------
-- UTILS (dt-stable, low-allocation)
----------------------------------------------------------------
local function expSmoothingAlpha(responsiveness: number, dt: number): number
	if responsiveness <= 0 then return 1 end
	return 1 - math.exp(-responsiveness * dt)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

local function v3Lerp(a: Vector3, b: Vector3, t: number): Vector3
	return a + (b - a) * t
end

local function getByPath(path: string): Instance?
	local current: Instance = game
	for seg in string.gmatch(path, "[^%.]+") do
		local nextInst: Instance? = current:FindFirstChild(seg)
		if not nextInst then
			local ok, svc = pcall(function()
				return game:GetService(seg)
			end)
			if ok and typeof(svc) == "Instance" then
				nextInst = svc
			end
		end
		if not nextInst then return nil end
		current = nextInst
	end
	return current
end

----------------------------------------------------------------
-- SPRINGS (stable)
----------------------------------------------------------------
type Spring1D = { x: number, v: number }
type SpringV3 = { x: Vector3, v: Vector3 }

local function springStep1D(s: Spring1D, target: number, speed: number, damping: number, dt: number): number
	local dtn = clamp(dt, 0, 1/20)
	local a = (target - s.x) * speed
	s.v = (s.v + a * dtn) * math.exp(-damping * dtn)
	s.x = s.x + s.v * dtn
	return s.x
end

local function springStepV3(s: SpringV3, target: Vector3, speed: number, damping: number, dt: number): Vector3
	local dtn = clamp(dt, 0, 1/20)
	local a = (target - s.x) * speed
	s.v = (s.v + a * dtn) * math.exp(-damping * dtn)
	s.x = s.x + s.v * dtn
	return s.x
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local character: Model? = nil
local humanoid: Humanoid? = nil
local hrp: BasePart? = nil

local renderConn: RBXScriptConnection? = nil
local diedConn: RBXScriptConnection? = nil
local stateConn: RBXScriptConnection? = nil
local inputConnBegan: RBXScriptConnection? = nil

-- feel state
local baseCameraOffset = Vector3.zero -- the offset the character already had before we touch it
local fov = Config.DefaultFOV
local offsetSpring: SpringV3 = { x = Vector3.zero, v = Vector3.zero }
local leanSpring: Spring1D = { x = 0, v = 0 }
local inertiaSpring: Spring1D = { x = 0, v = 0 }
local landingSpring: Spring1D = { x = 0, v = 0 }
local jumpSpring: Spring1D = { x = 0, v = 0 }
local bobBlend = 0.0
local bobPhase = 0.0
local bobVec = Vector3.zero
local smoothedSpeed = 0.0
local lastHorizontalVel = Vector3.zero
local inFreefall = false

-- ShiftLock state
local shiftLockEnabled = false
local shiftLockBlend = 0.0
local shiftLockOffset = Vector3.zero
local shiftLockYaw: number? = nil

-- PostFX
local blurFx: BlurEffect? = nil
local dofFx: DepthOfFieldEffect? = nil
local bloomFx: BloomEffect? = nil
local ccFx: ColorCorrectionEffect? = nil
local blurBase = 0.0
local dofBaseNear = 0.0
local dofBaseFar = 0.0
local bloomBaseIntensity = 0.0
local ccBaseContrast = 0.0
local ccBaseSaturation = 0.0

-- Audio
local windSound: Sound? = nil
local audioVol = 0.0
local audioRate = 1.0

-- UI
local gui: ScreenGui? = nil
local shiftBtn: ImageButton? = nil

----------------------------------------------------------------
-- POST FX HELPERS
----------------------------------------------------------------
local function findOrCreatePostFx(className: string, name: string): Instance?
	for _, inst in ipairs(Lighting:GetChildren()) do
		if inst.ClassName == className and inst.Name == name then
			return inst
		end
	end
	for _, inst in ipairs(Lighting:GetChildren()) do
		if inst.ClassName == className then
			return inst
		end
	end
	if Config.PostFX.CreateMissingFX then
		local created = Instance.new(className)
		created.Name = name
		created.Parent = Lighting
		return created
	end
	return nil
end

local function cachePostFx()
	if not Config.Enable.PostFX then return end

	if Config.PostFX.Blur.Enabled then
		blurFx = findOrCreatePostFx("BlurEffect", Config.PostFX.Blur.Name) :: BlurEffect?
		if blurFx then blurBase = blurFx.Size end
	end
	if Config.PostFX.DepthOfField.Enabled then
		dofFx = findOrCreatePostFx("DepthOfFieldEffect", Config.PostFX.DepthOfField.Name) :: DepthOfFieldEffect?
		if dofFx then
			dofBaseNear = dofFx.NearIntensity
			dofBaseFar = dofFx.FarIntensity
		end
	end
	if Config.PostFX.Bloom.Enabled then
		bloomFx = findOrCreatePostFx("BloomEffect", Config.PostFX.Bloom.Name) :: BloomEffect?
		if bloomFx then bloomBaseIntensity = bloomFx.Intensity end
	end
	if Config.PostFX.ColorCorrection.Enabled then
		ccFx = findOrCreatePostFx("ColorCorrectionEffect", Config.PostFX.ColorCorrection.Name) :: ColorCorrectionEffect?
		if ccFx then
			ccBaseContrast = ccFx.Contrast
			ccBaseSaturation = ccFx.Saturation
		end
	end
end

local function restorePostFx()
	if blurFx then blurFx.Size = blurBase end
	if dofFx then
		dofFx.NearIntensity = dofBaseNear
		dofFx.FarIntensity = dofBaseFar
	end
	if bloomFx then bloomFx.Intensity = bloomBaseIntensity end
	if ccFx then
		ccFx.Contrast = ccBaseContrast
		ccFx.Saturation = ccBaseSaturation
	end
end

----------------------------------------------------------------
-- AUDIO HELPERS
----------------------------------------------------------------
local function cacheAudio()
	if not Config.Enable.Audio then return end
	local inst = getByPath(Config.Audio.SoundPath)
	if inst and inst:IsA("Sound") then
		windSound = inst
		audioVol = windSound.Volume
		audioRate = windSound.PlaybackSpeed
	end
end

----------------------------------------------------------------
-- CUSTOM SHIFTLOCK UI
----------------------------------------------------------------
local function destroyUI()
	if gui then
		gui:Destroy()
		gui = nil
		shiftBtn = nil
	end
end

local function shouldShowButton(): boolean
	if not Config.Enable.CustomShiftLock then return false end
	if not Config.ShiftLock.UseCustomIcon then return false end
	if UserInputService.TouchEnabled then return true end
	return Config.ShiftLock.ShowOnDesktop
end

local function buildUI()
	destroyUI()
	if not shouldShowButton() then return end

	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end

	gui = Instance.new("ScreenGui")
	gui.Name = "AAACam_ShiftLockUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = pg

	local btn = Instance.new("ImageButton")
	btn.Name = "ShiftLockButton"
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Size = UDim2.fromOffset(Config.ShiftLock.IconSize, Config.ShiftLock.IconSize)
	btn.Position = UDim2.new(1, -Config.ShiftLock.IconPadding, 1, -Config.ShiftLock.IconPadding)
	btn.BackgroundTransparency = 1
	btn.AutoButtonColor = true
	btn.Image = Config.ShiftLock.IconAssetId
	btn.ImageTransparency = 0.0
	btn.Parent = gui

	-- subtle feedback frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.55
	stroke.Parent = btn

	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(1, 0)
	cr.Parent = btn

	btn.Activated:Connect(function()
		shiftLockEnabled = not shiftLockEnabled
	end)

	shiftBtn = btn
end

local function updateUIButtonVisual()
	if not shiftBtn then return end
	-- When enabled, make icon slightly more opaque and stroke stronger.
	if shiftLockEnabled then
		shiftBtn.ImageTransparency = 0.0
		local s = shiftBtn:FindFirstChildOfClass("UIStroke")
		if s then
			s.Transparency = 0.25
			s.Thickness = 2
		end
	else
		shiftBtn.ImageTransparency = 0.15
		local s = shiftBtn:FindFirstChildOfClass("UIStroke")
		if s then
			s.Transparency = 0.55
			s.Thickness = 1
		end
	end
end

----------------------------------------------------------------
-- SHIFTLOCK CORE
----------------------------------------------------------------
local function setMouseLock(on: boolean)
	-- Don’t try to "break mobile". On touch, MouseBehavior is irrelevant.
	if UserInputService.TouchEnabled then return end
	UserInputService.MouseBehavior = on and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not on
end

local function setShiftLock(on: boolean)
	if not Config.Enable.CustomShiftLock then
		shiftLockEnabled = false
		return
	end
	shiftLockEnabled = on
	updateUIButtonVisual()

	-- Humanoid settings
	if humanoid then
		if Config.ShiftLock.DisableHumanoidAutoRotate then
			humanoid.AutoRotate = not on
		end
	end

	setMouseLock(on)

	-- reset alignment state so it eases in
	shiftLockYaw = nil
end

----------------------------------------------------------------
-- HUMANOID STATE: LANDING + JUMP IMPULSES
----------------------------------------------------------------
local function onHumanoidStateChanged(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
	if not humanoid or not hrp then return end
	if not (Config.Enable.LandingJump and Config.Enable.CameraOffsetLayer) then return end

	if new == Enum.HumanoidStateType.Freefall then
		inFreefall = true
	elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.RunningNoPhysics then
		if inFreefall then
			inFreefall = false
			local vy = hrp.AssemblyLinearVelocity.Y
			local fallSpeed = clamp((-vy) / 70, 0, 1)
			local impulse = fallSpeed * Config.LandingImpactStrength
			landingSpring.v -= impulse * 42
		end
	end

	if new == Enum.HumanoidStateType.Jumping then
		jumpSpring.v += Config.JumpLiftStrength * 26
	end
end

----------------------------------------------------------------
-- CORE UPDATE LOOP
----------------------------------------------------------------
local function update(dt: number)
	if not humanoid or not hrp or not camera then return end

	-- Movement data
	local v = hrp.AssemblyLinearVelocity
	local horizontalVel = Vector3.new(v.X, 0, v.Z)
	local speed = horizontalVel.Magnitude

	-- Smooth speed
	smoothedSpeed = lerp(smoothedSpeed, speed, expSmoothingAlpha(12, dt))
	local speed01 = clamp(smoothedSpeed / Config.Speed.SprintRef, 0, 1)
	local moveDir = humanoid.MoveDirection
	local moving = (moveDir.Magnitude > 1e-3)

	-- map MoveDirection into HRP local space (consistent)
	local localMove = hrp.CFrame:VectorToObjectSpace(moveDir)

	----------------------------------------------------------------
	-- Custom ShiftLock blending + character yaw alignment
	----------------------------------------------------------------
	if Config.Enable.CustomShiftLock and Config.Enable.CameraOffsetLayer then
		local targetBlend = shiftLockEnabled and 1 or 0
		shiftLockBlend = lerp(shiftLockBlend, targetBlend, expSmoothingAlpha(Config.ShiftLock.OffsetResponsiveness, dt))
		shiftLockOffset = Config.ShiftLock.ShoulderOffset * shiftLockBlend

		-- Align character yaw to camera (only when enabled)
		if shiftLockEnabled and Config.ShiftLock.AlignCharacterToCamera then
			local camLook = camera.CFrame.LookVector
			local yaw = math.atan2(-camLook.X, -camLook.Z) -- Roblox yaw around Y

			if shiftLockYaw == nil then
				shiftLockYaw = yaw
			else
				-- shortest-angle interpolation
				local current = shiftLockYaw
				local delta = (yaw - current)
				delta = (delta + math.pi) % (2 * math.pi) - math.pi
				shiftLockYaw = current + delta * expSmoothingAlpha(Config.ShiftLock.AlignResponsiveness, dt)
			end

			-- Apply yaw to character root without touching camera CFrame
			-- Only rotate around Y, preserve position.
			local pos = hrp.Position
			local targetCF = CFrame.new(pos) * CFrame.Angles(0, shiftLockYaw :: number, 0)
			hrp.CFrame = hrp.CFrame:Lerp(targetCF, expSmoothingAlpha(Config.ShiftLock.AlignResponsiveness, dt))
		end
	else
		shiftLockBlend = lerp(shiftLockBlend, 0, expSmoothingAlpha(12, dt))
		shiftLockOffset = Vector3.zero
	end

	updateUIButtonVisual()

	----------------------------------------------------------------
	-- 1) Dynamic FOV (movement decreases, idle restores)
	----------------------------------------------------------------
	if Config.Enable.FOV then
		local targetFOV: number
		if not moving then
			targetFOV = Config.DefaultFOV
		else
			local sprintT = clamp(smoothedSpeed / Config.Speed.SprintRef, 0, 1)
			local moveFOV = lerp(Config.WalkFOV, Config.SprintFOV, sprintT)
			local walkT = clamp(smoothedSpeed / Config.Speed.WalkRef, 0, 1)
			targetFOV = lerp(Config.DefaultFOV, moveFOV, walkT)
		end
		fov = lerp(fov, targetFOV, expSmoothingAlpha(Config.FOVResponsiveness, dt))
		camera.FieldOfView = fov
	end

	----------------------------------------------------------------
	-- 2) Bob (cinematic, damped, slightly irregular)
	----------------------------------------------------------------
	if Config.Enable.CameraOffsetLayer and Config.Enable.Bob then
		local targetBlend = moving and clamp(smoothedSpeed / (Config.Speed.WalkRef * 0.6), 0, 1) or 0
		bobBlend = lerp(bobBlend, targetBlend, expSmoothingAlpha(Config.BobResponsiveness, dt))

		local cadence = Config.BobFrequency * lerp(0.85, 1.35, clamp(smoothedSpeed / Config.Speed.SprintRef, 0, 1))
		bobPhase += cadence * (2 * math.pi) * clamp(dt, 0, 1/15)

		local s1 = math.sin(bobPhase)
		local s2 = math.sin(bobPhase * 2 + 0.7) * 0.35
		local stepPulse = math.abs(s1) ^ 1.6
		local n = math.noise(bobPhase * 0.15, 0.0, 0.0) * Config.BobVariation

		local bobX = (math.sin(bobPhase + 1.2) * 0.55 + s2 * 0.45 + n * 0.25)
		local bobY = (-(stepPulse - 0.5) * 1.1 + (math.sin(bobPhase + 0.1) * 0.1) + n * 0.15)

		local targetBob = Vector3.new(
			bobX * Config.BobIntensity.X,
			bobY * Config.BobIntensity.Y,
			0
		) * bobBlend

		bobVec = v3Lerp(bobVec, targetBob, expSmoothingAlpha(10, dt))
	else
		bobBlend = lerp(bobBlend, 0, expSmoothingAlpha(10, dt))
		bobVec = v3Lerp(bobVec, Vector3.zero, expSmoothingAlpha(12, dt))
	end

	----------------------------------------------------------------
	-- 3) Lean (simulated "roll" without Camera.CFrame)
	----------------------------------------------------------------
	local leanOffsetX = 0.0
	local leanOffsetY = 0.0
	if Config.Enable.CameraOffsetLayer and Config.Enable.Lean then
		local maxDeg = math.rad(Config.RollMaxDegrees)
		local leanTarget = clamp(localMove.X, -1, 1) * maxDeg * (0.8 + 0.2 * speed01)
		local lean = springStep1D(leanSpring, leanTarget, Config.RollSpeed * 18, Config.RollSpeed * 2.2, dt)
		leanOffsetX = lean * 0.55
		leanOffsetY = -math.abs(lean) * 0.22
	end

	----------------------------------------------------------------
	-- 4) Inertia push
	----------------------------------------------------------------
	local inertiaOffsetZ = 0.0
	if Config.Enable.CameraOffsetLayer and Config.Enable.Inertia then
		local dv = (horizontalVel - lastHorizontalVel)
		lastHorizontalVel = horizontalVel

		local localDv = hrp.CFrame:VectorToObjectSpace(dv)
		local accelForward = -localDv.Z
		local target = clamp(accelForward * 0.0025, -1, 1) * Config.InertiaStrength
		local inertia = springStep1D(inertiaSpring, target, Config.InertiaDamping * 20, Config.InertiaDamping * 1.6, dt)
		inertiaOffsetZ = inertia
	end

	----------------------------------------------------------------
	-- 5) Landing/jump (spring back to 0)
	----------------------------------------------------------------
	local landDip = 0.0
	local jumpLift = 0.0
	if Config.Enable.CameraOffsetLayer and Config.Enable.LandingJump then
		landDip = springStep1D(landingSpring, 0, Config.LandingRecoverySpeed * 22, Config.LandingRecoverySpeed * 1.9, dt)
		jumpLift = springStep1D(jumpSpring, 0, 20, 8, dt)
	end

	----------------------------------------------------------------
	-- Apply final CameraOffset (base + shiftlock + feel layer)
	----------------------------------------------------------------
	if Config.Enable.CameraOffsetLayer then
		local feelTarget =
			(bobVec)
			+ Vector3.new(leanOffsetX, leanOffsetY, inertiaOffsetZ)
			+ Vector3.new(0, landDip + jumpLift, 0)

		local finalFeel = springStepV3(offsetSpring, feelTarget, 50, 16, dt)

		-- ShiftLock offset is a separate clean layer (so you can toggle it without nuking the feel)
		humanoid.CameraOffset = baseCameraOffset + shiftLockOffset + finalFeel
	end

	----------------------------------------------------------------
	-- PostFX
	----------------------------------------------------------------
	if Config.Enable.PostFX then
		local moveT = moving and speed01 or 0
		if blurFx and Config.PostFX.Blur.Enabled then
			local target = lerp(Config.PostFX.Blur.IdleSize, Config.PostFX.Blur.MaxSize, moveT)
			blurFx.Size = lerp(blurFx.Size, target, expSmoothingAlpha(Config.PostFX.Blur.Responsiveness, dt))
		end
		if dofFx and Config.PostFX.DepthOfField.Enabled then
			local targetNear = lerp(Config.PostFX.DepthOfField.IdleNearIntensity, Config.PostFX.DepthOfField.MovingNearIntensity, moveT)
			local targetFar = lerp(Config.PostFX.DepthOfField.IdleFarIntensity, Config.PostFX.DepthOfField.MovingFarIntensity, moveT)
			local a = expSmoothingAlpha(Config.PostFX.DepthOfField.Responsiveness, dt)
			dofFx.NearIntensity = lerp(dofFx.NearIntensity, dofBaseNear + targetNear, a)
			dofFx.FarIntensity = lerp(dofFx.FarIntensity, dofBaseFar + targetFar, a)
		end
		if bloomFx and Config.PostFX.Bloom.Enabled then
			local target = bloomBaseIntensity + (Config.PostFX.Bloom.MovingIntensityAdd * moveT)
			bloomFx.Intensity = lerp(bloomFx.Intensity, target, expSmoothingAlpha(Config.PostFX.Bloom.Responsiveness, dt))
		end
		if ccFx and Config.PostFX.ColorCorrection.Enabled then
			local targetC = ccBaseContrast + (Config.PostFX.ColorCorrection.MovingContrastAdd * moveT)
			local targetS = ccBaseSaturation + (Config.PostFX.ColorCorrection.MovingSaturationAdd * moveT)
			local a = expSmoothingAlpha(Config.PostFX.ColorCorrection.Responsiveness, dt)
			ccFx.Contrast = lerp(ccFx.Contrast, targetC, a)
			ccFx.Saturation = lerp(ccFx.Saturation, targetS, a)
		end
	end

	----------------------------------------------------------------
	-- Audio
	----------------------------------------------------------------
	if Config.Enable.Audio and windSound then
		local t = moving and speed01 or 0
		local targetVol = lerp(Config.Audio.MinVolume, Config.Audio.MaxVolume, t)
		local targetRate = lerp(Config.Audio.MinPlaybackSpeed, Config.Audio.MaxPlaybackSpeed, t)

		local a = expSmoothingAlpha(Config.Audio.Responsiveness, dt)
		audioVol = lerp(audioVol, targetVol, a)
		audioRate = lerp(audioRate, targetRate, a)

		windSound.Volume = audioVol
		windSound.PlaybackSpeed = audioRate

		if audioVol > 0.02 then
			if not windSound.IsPlaying then pcall(function() windSound:Play() end) end
		else
			if windSound.IsPlaying then pcall(function() windSound:Stop() end) end
		end
	end
end

----------------------------------------------------------------
-- CLEANUP / REBIND
----------------------------------------------------------------
local function disconnectAll()
	if renderConn then renderConn:Disconnect() renderConn = nil end
	if diedConn then diedConn:Disconnect() diedConn = nil end
	if stateConn then stateConn:Disconnect() stateConn = nil end
	if inputConnBegan then inputConnBegan:Disconnect() inputConnBegan = nil end
end

local function clearRefs()
	character = nil
	humanoid = nil
	hrp = nil

	baseCameraOffset = Vector3.zero

	offsetSpring.x, offsetSpring.v = Vector3.zero, Vector3.zero
	leanSpring.x, leanSpring.v = 0, 0
	inertiaSpring.x, inertiaSpring.v = 0, 0
	landingSpring.x, landingSpring.v = 0, 0
	jumpSpring.x, jumpSpring.v = 0, 0

	bobBlend = 0
	bobPhase = 0
	bobVec = Vector3.zero
	smoothedSpeed = 0
	lastHorizontalVel = Vector3.zero
	inFreefall = false

	shiftLockEnabled = false
	shiftLockBlend = 0
	shiftLockOffset = Vector3.zero
	shiftLockYaw = nil

	setMouseLock(false)
end

local function bindCharacter(char: Model)
	disconnectAll()
	clearRefs()

	character = char
	humanoid = char:FindFirstChildOfClass("Humanoid")
	hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Wait briefly for character to be ready (no infinite yields)
	if not humanoid or not hrp then
		local t0 = os.clock()
		while os.clock() - t0 < 5 do
			task.wait(0.1)
			if character ~= char then return end
			humanoid = char:FindFirstChildOfClass("Humanoid")
			hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if humanoid and hrp then break end
		end
	end
	if not humanoid or not hrp then return end

	-- Cache base offset and initial FOV
	baseCameraOffset = humanoid.CameraOffset
	fov = camera.FieldOfView

	-- PostFX + Audio caching
	cachePostFx()
	cacheAudio()

	-- Build UI (once; persists through respawns because ResetOnSpawn=false)
	buildUI()

	-- Input: toggle shiftlock
	if Config.Enable.CustomShiftLock then
		inputConnBegan = UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
			if gp then return end
			if input.KeyCode == Config.ShiftLock.Key then
				setShiftLock(not shiftLockEnabled)
			end
		end)
	end

	stateConn = humanoid.StateChanged:Connect(onHumanoidStateChanged)
	diedConn = humanoid.Died:Connect(function()
		-- Restore stuff
		if humanoid then
			humanoid.CameraOffset = baseCameraOffset
			-- Put AutoRotate back
			humanoid.AutoRotate = true
		end
		setMouseLock(false)
		restorePostFx()
		if windSound and windSound.IsPlaying then pcall(function() windSound:Stop() end) end
	end)

	renderConn = RunService.RenderStepped:Connect(update)
end

----------------------------------------------------------------
-- INIT
----------------------------------------------------------------
player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

-- Script shutdown restore
script.Destroying:Connect(function()
	disconnectAll()
	if humanoid then
		humanoid.CameraOffset = baseCameraOffset
		humanoid.AutoRotate = true
	end
	setMouseLock(false)
	restorePostFx()
	if windSound and windSound.IsPlaying then pcall(function() windSound:Stop() end) end
	destroyUI()
end)
