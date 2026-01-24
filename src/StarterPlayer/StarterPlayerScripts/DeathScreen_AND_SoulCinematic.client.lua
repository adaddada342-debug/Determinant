--TEST
-- PART 1/2 (CLIENT) - FULL Phase3 + Death Refusal injection (AMENDED)
-- Fixes in this revision:
-- A) Explosion zoom-out wasn't happening because endCineCamera() killed the scriptable camera immediately.
--    Now we do an explicit "ExplosionShot" cine camera for a short window, THEN snap to player.
-- B) Snap-to-player now explicitly restores CameraType.Custom + CameraSubject (no relying on old state).
-- C) New Death Refusal animation no longer starts at CalmReturn. It is preloaded, then started later
--    (configurable) so it doesn't look goofy/early.
-- D) No random impact spam outside explosion moment.

--////////////////////////////////////////////////////////////
-- SERVICES
--////////////////////////////////////////////////////////////
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Optional external cleanup hook (kept nil unless you assign it somewhere)
-- Renamed to avoid confusion with clearFaceLock() (the internal RenderStepped disconnect).
local stopFaceLockCallback: (() -> ())? = nil

--////////////////////////////////////////////////////////////
-- REMOTES / ASSETS
--////////////////////////////////////////////////////////////
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StartDeathSequenceRE = Remotes:WaitForChild("StartDeathSequenceRE")
local FinishDeathSequenceRE = Remotes:WaitForChild("FinishDeathSequenceRE")
local DeathRefusalExplosionRE = Remotes:WaitForChild("DeathRefusalExplosionRE")

local Assets = ReplicatedStorage:WaitForChild("Assets")
local SoulTemplate = Assets:WaitForChild("SoulModel")

local AudioFolder, VFXFolder, AurasFolder
local function resolveAssetFolders(timeout)
	timeout = timeout or 6
	local okAssets, assets = pcall(function()
		return ReplicatedStorage:WaitForChild("Assets", timeout)
	end)
	if not okAssets or not assets then
		return false
	end

	local okAudio, audio = pcall(function()
		return assets:WaitForChild("Audio", timeout)
	end)
	if okAudio then
		AudioFolder = audio
	end

	local okVfx, vfx = pcall(function()
		return assets:WaitForChild("VFX", timeout)
	end)
	if okVfx then
		VFXFolder = vfx
		local okAuras, auras = pcall(function()
			return vfx:WaitForChild("Auras", timeout)
		end)
		if okAuras then
			AurasFolder = auras
		end
	end

	return true
end

--////////////////////////////////////////////////////////////
-- BOOT GUARD
--////////////////////////////////////////////////////////////
_G.__DeathScreenIllegalToRender = _G.__DeathScreenIllegalToRender or {}
local BOOT = _G.__DeathScreenIllegalToRender
BOOT._deathQueue = BOOT._deathQueue or {}
BOOT._deathDrainRunning = BOOT._deathDrainRunning or false

--////////////////////////////////////////////////////////////
-- CONFIG
--////////////////////////////////////////////////////////////
local CFG = {
	Debug = true,

	-- Cutscene pacing
	ExplosionWitnessTime = 4.25, -- how long we hold after detonation (still frozen)
	AweHoldTime = 3.50, -- extra hold after witness (still frozen)

	-- When to START the DeathRefusal animation relative to beat drop.
	-- Example: 1.10 means start 1.10s BEFORE BeatDrop so it reaches the pose at the drop.
	AnimLeadBeforeBeatDrop = 1.10,

	-- If your anim is longer/shorter, adjust this instead of moving BeatDrop time.
	DeathRefusal_NewAnimId = 127165878955339,
	DeathRefusal_PauseAt = 5.26, -- the exact pose frame you want to HOLD on

	-- Refusal frames + highlight
	RefusalFrameDuration = 1.0,

	-- Keep aura after cutscene ends until theme ends
	KeepThemeAfterCutscene = true,

	-- Misc
	UsePostFX = true,
	ImpactFrameEnabled = false, -- keep off unless you explicitly want it
}

local CAMCFG = {
	SnapBackExtraDelay = 1, -- extra hold AFTER the explosion shot before snapping back
	NearDist = 70,
	NearHeight = 18,
	FarDist = 260,
	FarHeight = 68,

	-- The BIG zoom-out shot during explosion (scriptable)
	ExplodeDist = 420,
	ExplodeHeight = 120,
	ExplodeFov = 58,

	-- How long we keep the explosion camera before snapping back to player camera
	ExplodeShotDuration = 2,

	-- General shakes
	BaseShake = 2.4,
	MaxShake = 9.0,

	-- Standard cine fovs
	FOV_Base = 72,
	FOV_Punch = 78,

	-- Close-up after madness ends
	CloseDist = 9,
	CloseHeight = 3,
	CloseFov = 58,
}

local THEME_ID = 118521019128779
local THEME_TIMES = {
	ChargeStart = 4,
	MadnessStart = 16,
	CalmReturn = 40,
	PreDetonate = 54,
	BeatDrop = 55,
}

local OUR_RAGE_GUI_NAME = "RageTextGui"
local OUR_VIGNETTE_GUI_NAME = "DeathVignetteOverlay"

--////////////////////////////////////////////////////////////
-- STATE
--////////////////////////////////////////////////////////////
local State = { runId = 0, mode = "Idle" }

local function bumpRun()
	State.runId += 1
	return State.runId
end

local function aliveRun(id)
	return State.runId == id
end

local function dprint(...)
	if CFG.Debug then
		print("[DeathRefusal]", ...)
	end
end

local function tw(obj, info, props)
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end

--////////////////////////////////////////////////////////////
-- FREEZE + FACE LOCK
--////////////////////////////////////////////////////////////
local freezeState = { active = false }
local faceLockConn: RBXScriptConnection? = nil
local lockedYaw: number? = nil

local function clearFaceLock()
	if faceLockConn then
		faceLockConn:Disconnect()
		faceLockConn = nil
	end
	lockedYaw = nil
end

local function setFrozen(frozen)
	local char = player.Character
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end

	if frozen and not freezeState.active then
		freezeState.active = true
		freezeState.ws = hum.WalkSpeed
		freezeState.jp = hum.JumpPower
		freezeState.jh = hum.JumpHeight
		freezeState.ar = hum.AutoRotate
		pcall(function()
			hum.WalkSpeed = 0
		end)
		pcall(function()
			hum.JumpPower = 0
		end)
		pcall(function()
			hum.JumpHeight = 0
		end)
		pcall(function()
			hum.AutoRotate = false
		end)
	elseif (not frozen) and freezeState.active then
		freezeState.active = false
		pcall(function()
			hum.WalkSpeed = freezeState.ws or 16
		end)
		pcall(function()
			hum.JumpPower = freezeState.jp or 50
		end)
		pcall(function()
			hum.JumpHeight = freezeState.jh or 7.2
		end)
		pcall(function()
			hum.AutoRotate = (freezeState.ar ~= false)
		end)
	end
end

--////////////////////////////////////////////////////////////
-- HARD CAMERA + LOOK BUG FIX
--////////////////////////////////////////////////////////////
local function forceRestoreLook()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid") or nil

	-- optional external cleanup hook (if you ever assign it)
	pcall(function()
		if stopFaceLockCallback then
			stopFaceLockCallback()
			stopFaceLockCallback = nil
		end
	end)

	-- always clear our own face lock too
	clearFaceLock()

	if hum then
		pcall(function()
			hum.AutoRotate = true
		end)
	end

	pcall(function()
		cam.CameraType = Enum.CameraType.Custom
	end)
	pcall(function()
		if hum then
			cam.CameraSubject = hum
		end
	end)

	pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)
	pcall(function()
		UserInputService.MouseIconEnabled = true
	end)
end

local function rotateAndLockFacingCamera(runId)
	clearFaceLock()

	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	local camPos = cam.CFrame.Position
	local lookAt = Vector3.new(camPos.X, hrp.Position.Y, camPos.Z)
	local targetCF = CFrame.new(hrp.Position, lookAt)
	tw(hrp, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = targetCF })

	task.delay(0.20, function()
		if not aliveRun(runId) then
			return
		end
		if not hrp.Parent then
			return
		end

		local _, y, _ = hrp.CFrame:ToOrientation()
		lockedYaw = y

		faceLockConn = RunService.RenderStepped:Connect(function()
			if not aliveRun(runId) then
				clearFaceLock()
				return
			end
			if not hrp.Parent then
				clearFaceLock()
				return
			end
			local pos = hrp.Position
			hrp.CFrame = CFrame.new(pos) * CFrame.Angles(0, lockedYaw or 0, 0)
		end)
	end)
end

--////////////////////////////////////////////////////////////
-- REFUSAL HIGHLIGHT
--////////////////////////////////////////////////////////////
local function getOrCreateRefusalHighlight()
	local char = player.Character
	if not char then
		return nil
	end

	local h = char:FindFirstChild("__RefusalHL")
	if h and h:IsA("Highlight") then
		return h
	end

	h = Instance.new("Highlight")
	h.Name = "__RefusalHL"
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Enabled = false
	h.FillColor = Color3.fromRGB(255, 255, 255)
	h.FillTransparency = 0
	h.OutlineColor = Color3.fromRGB(255, 0, 4)
	h.OutlineTransparency = 1
	h.Parent = char
	return h
end

local function setRefusalHighlight(on: boolean)
	local h = getOrCreateRefusalHighlight()
	if h then
		h.Enabled = (on and true or false)
	end
end

--////////////////////////////////////////////////////////////
-- SOUND
--////////////////////////////////////////////////////////////
local warnedMissing = {}
local SOUND_ALIAS = {
	Phase3_Rumble = "Cinematic Rumble",
	Crack = "Crack",
	Detonation = "Detonation",
	["soul shatter"] = "soul shatter",
	["big-energy-explosion"] = "big-energy-explosion",
	["cinematic-impact-boom"] = "cinematic-impact-boom",
	["sub-bass-drop"] = "sub-bass-drop",
	["Ear Ring"] = "Ear Ring",
	Glitch = "Glitch",
	["Mechanical Clicks"] = "Mechanical Clicks",
}

local function getSoundTemplate(name: string)
	if not AudioFolder then
		return nil
	end
	name = SOUND_ALIAS[name] or name
	local s = AudioFolder:FindFirstChild(name, true)
	if s and s:IsA("Sound") then
		return s
	end
	if not warnedMissing[name] then
		warnedMissing[name] = true
		warn("[DeathScreen] Missing sound:", name)
	end
	return nil
end

local function playNamed(name: string, volume: number?, pitch: number?)
	local tmpl = getSoundTemplate(name)
	if not tmpl then
		return nil
	end
	local s = tmpl:Clone()
	if volume ~= nil then
		s.Volume = volume
	end
	if pitch ~= nil then
		s.PlaybackSpeed = pitch
	end
	s.Looped = false
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		pcall(function()
			s:Destroy()
		end)
	end)
	return s
end

local function playAfter(delaySec, name, volume, pitch)
	task.delay(math.max(0, tonumber(delaySec) or 0), function()
		playNamed(name, volume, pitch)
	end)
end

--////////////////////////////////////////////////////////////
-- THEME
--////////////////////////////////////////////////////////////
local themeSound: Sound? = nil
local themeStartClock = 0
local themeEndConn: RBXScriptConnection? = nil

local function startTheme()
	if themeSound and themeSound.Parent then
		return themeSound
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(THEME_ID)
	s.Volume = 0.85
	s.PlaybackSpeed = 1
	s.Looped = false
	s.Parent = SoundService
	themeSound = s
	themeStartClock = os.clock()
	s:Play()
	return s
end

local function themeTime()
	if not themeSound then
		return 0
	end
	local tp = 0
	pcall(function()
		tp = themeSound.TimePosition
	end)
	local fallback = os.clock() - themeStartClock
	return math.max(tp or 0, math.max(0, fallback))
end

--////////////////////////////////////////////////////////////
-- INPUT LOCK
--////////////////////////////////////////////////////////////
local inputLocked = false
local BLOCK_ACTION = "DS_BlockInput"
local BLOCK_KEYS = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Space,
	Enum.KeyCode.LeftShift,
	Enum.KeyCode.RightShift,
	Enum.KeyCode.Tab,
	Enum.KeyCode.E,
	Enum.KeyCode.Q,
	Enum.KeyCode.R,
	Enum.KeyCode.Return,
	Enum.KeyCode.KeypadEnter,
}

local function lockInput()
	if inputLocked then
		return
	end
	inputLocked = true
	ContextActionService:BindActionAtPriority(
		BLOCK_ACTION,
		function()
			return Enum.ContextActionResult.Sink
		end,
		false,
		999999999,
		table.unpack(BLOCK_KEYS)
	)
end

local function unlockInput()
	if not inputLocked then
		return
	end
	inputLocked = false
	pcall(function()
		ContextActionService:UnbindAction(BLOCK_ACTION)
	end)
end

--////////////////////////////////////////////////////////////
-- CAMERA (Cine + ExplosionShot + SnapToPlayer)
--////////////////////////////////////////////////////////////
local camConn: RBXScriptConnection? = nil
local camOrigType, camOrigSubject, camOrigFOV
local camTargetPos: Vector3? = nil
local camDesiredDist, camDesiredHeight
local camBaseCF: CFrame? = nil
local shakePowerWorld = 0

local function resolveCharacterSubject()
	local char = player.Character
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Humanoid")
end

local function restoreCameraClean()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local subj = camOrigSubject
	if not subj or (typeof(subj) == "Instance" and subj.Parent == nil) then
		subj = resolveCharacterSubject()
	end
	pcall(function()
		cam.CameraType = camOrigType or Enum.CameraType.Custom
	end)
	pcall(function()
		if subj then
			cam.CameraSubject = subj
		end
	end)
	pcall(function()
		cam.FieldOfView = camOrigFOV or CAMCFG.FOV_Base
	end)
	forceRestoreLook()
end

local function beginCineCamera(targetPos, startDist)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	camOrigType = cam.CameraType
	camOrigSubject = cam.CameraSubject
	camOrigFOV = cam.FieldOfView

	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = CAMCFG.FOV_Punch

	camTargetPos = targetPos
	camDesiredDist = startDist or CAMCFG.NearDist
	camDesiredHeight = CAMCFG.NearHeight

	camBaseCF = CFrame.new(targetPos + Vector3.new(0, camDesiredHeight, camDesiredDist), targetPos)
	shakePowerWorld = CAMCFG.BaseShake

	if camConn then
		camConn:Disconnect()
	end
	camConn = RunService.RenderStepped:Connect(function(dt)
		local c = workspace.CurrentCamera
		if not c or not camTargetPos then
			return
		end

		shakePowerWorld = math.max(0, shakePowerWorld - dt * 2.0)

		local desiredPos = camTargetPos + Vector3.new(0, camDesiredHeight, camDesiredDist)
		local desired = CFrame.new(desiredPos, camTargetPos)
		camBaseCF = (camBaseCF or desired):Lerp(desired, 0.10)

		local n1 = (math.noise(os.clock() * 11, 0, 0) - 0.5) * 2
		local n2 = (math.noise(os.clock() * 11, 10, 0) - 0.5) * 2
		local n3 = (math.noise(os.clock() * 11, 20, 0) - 0.5) * 2

		local rot = CFrame.Angles(n2 * 0.010 * shakePowerWorld, n3 * 0.008 * shakePowerWorld, n1 * 0.012 * shakePowerWorld)
		local posJitter = Vector3.new(n1, n2 * 0.6, n3) * (0.09 * shakePowerWorld)

		c.CFrame = (camBaseCF or desired) * CFrame.new(posJitter) * rot
	end)
end

local function endCineCamera()
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
	camBaseCF = nil
	camTargetPos = nil
	restoreCameraClean()
end

local function snapCameraToPlayer()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local hum = resolveCharacterSubject()
	pcall(function()
		cam.CameraType = Enum.CameraType.Custom
	end)
	pcall(function()
		if hum then
			cam.CameraSubject = hum
		end
	end)
	pcall(function()
		cam.FieldOfView = CAMCFG.FOV_Base
	end)
	forceRestoreLook()
end

local function explosionShot(targetPos: Vector3, duration: number)
	duration = tonumber(duration) or CAMCFG.ExplodeShotDuration
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	-- Force a clean scriptable shot (even if something else messed with the cine cam)
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end

	camOrigType = cam.CameraType
	camOrigSubject = cam.CameraSubject
	camOrigFOV = cam.FieldOfView

	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = CAMCFG.ExplodeFov

	local t0 = os.clock()
	local baseShake = math.max(4.0, shakePowerWorld)

	camConn = RunService.RenderStepped:Connect(function()
		if not cam then
			return
		end

		local dt = os.clock() - t0
		if dt >= duration then
			return
		end

		local desiredPos = targetPos + Vector3.new(0, CAMCFG.ExplodeHeight, CAMCFG.ExplodeDist)
		local desired = CFrame.new(desiredPos, targetPos)

		local n1 = (math.noise(os.clock() * 14, 0, 0) - 0.5) * 2
		local n2 = (math.noise(os.clock() * 14, 10, 0) - 0.5) * 2
		local n3 = (math.noise(os.clock() * 14, 20, 0) - 0.5) * 2

		local rot = CFrame.Angles(n2 * 0.010 * baseShake, n3 * 0.008 * baseShake, n1 * 0.012 * baseShake)
		local posJitter = Vector3.new(n1, n2 * 0.6, n3) * (0.12 * baseShake)

		cam.CFrame = desired * CFrame.new(posJitter) * rot
	end)

	task.delay(duration, function()
		if camConn then
			camConn:Disconnect()
			camConn = nil
		end
	end)
end

local function cameraSlamFOV(targetFov, backFov)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	tw(cam, TweenInfo.new(0.06, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { FieldOfView = targetFov })
	task.delay(0.07, function()
		tw(cam, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = backFov })
	end)
end

--////////////////////////////////////////////////////////////
-- POST FX (Catastrophic)
--////////////////////////////////////////////////////////////
local postFolder = Lighting:FindFirstChild("__DeathPostFX")
if postFolder then
	postFolder:Destroy()
end
postFolder = Instance.new("Folder")
postFolder.Name = "__DeathPostFX"
postFolder.Parent = Lighting

local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "CC"
cc.Enabled = false
cc.Brightness = -0.08
cc.Contrast = 0.35
cc.Saturation = -0.20
cc.TintColor = Color3.fromRGB(255, 210, 220)
cc.Parent = postFolder

local blur = Instance.new("BlurEffect")
blur.Name = "Blur"
blur.Enabled = false
blur.Size = 10
blur.Parent = postFolder

local bloom = Instance.new("BloomEffect")
bloom.Name = "Bloom"
bloom.Enabled = false
bloom.Intensity = 2.0
bloom.Size = 110
bloom.Threshold = 0.85
bloom.Parent = postFolder

local rays = Instance.new("SunRaysEffect")
rays.Name = "Rays"
rays.Enabled = false
rays.Intensity = 0.16
rays.Spread = 0.9
rays.Parent = postFolder

local dof = Instance.new("DepthOfFieldEffect")
dof.Name = "DOF"
dof.Enabled = false
dof.FocusDistance = 18
dof.InFocusRadius = 22
dof.NearIntensity = 0.20
dof.FarIntensity = 0.45
dof.Parent = postFolder

local ccExpl = Instance.new("ColorCorrectionEffect")
ccExpl.Name = "ExplosionGrade"
ccExpl.Enabled = false
ccExpl.Brightness = 0
ccExpl.Contrast = 0
ccExpl.Saturation = 0
ccExpl.TintColor = Color3.fromRGB(255, 255, 255)
ccExpl.Parent = postFolder

local function enablePostFX()
	if not CFG.UsePostFX then
		return
	end
	cc.Enabled, blur.Enabled, bloom.Enabled, rays.Enabled = true, true, true, true
end

local function disablePostFX()
	cc.Enabled, blur.Enabled, bloom.Enabled, rays.Enabled = false, false, false, false
	dof.Enabled = false
	ccExpl.Enabled = false
end

local function brutalFxOn()
	for _, name in ipairs({ "LaserBlur1", "LaserBlur2" }) do
		local fx = Lighting:FindFirstChild(name)
		if fx and fx:IsA("PostEffect") then
			fx.Enabled = true
		end
	end
end

local function brutalFxOff()
	for _, name in ipairs({ "LaserBlur1", "LaserBlur2" }) do
		local fx = Lighting:FindFirstChild(name)
		if fx and fx:IsA("PostEffect") then
			fx.Enabled = false
		end
	end
end

local function startExplosionGrade()
	ccExpl.Enabled = true
	dof.Enabled = true
	dof.NearIntensity = 0.35
	dof.FarIntensity = 0.70

	tw(ccExpl, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0.16,
		Contrast = 1.70,
		Saturation = -0.85,
		TintColor = Color3.fromRGB(255, 145, 170),
	})
	tw(bloom, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Intensity = 7.5,
		Size = 240,
		Threshold = 0.68,
	})
	tw(blur, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = 22 })
	tw(rays, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Intensity = 0.45 })

	brutalFxOn()
end

local function endExplosionGrade()
	tw(ccExpl, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
		TintColor = Color3.fromRGB(255, 255, 255),
	})
	task.delay(0.32, function()
		if ccExpl and ccExpl.Parent then
			ccExpl.Enabled = false
		end
	end)

	tw(bloom, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Intensity = 2.2,
		Size = 120,
		Threshold = 0.85,
	})
	tw(blur, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = 10 })
	tw(rays, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Intensity = 0.16 })

	task.delay(0.22, function()
		if dof and dof.Parent then
			dof.Enabled = false
		end
	end)

	task.delay(0.35, function()
		brutalFxOff()
	end)
end

--////////////////////////////////////////////////////////////
-- NEGATIVE FLASH (uses Lighting.RefusalFrame1/2) - 1s
--////////////////////////////////////////////////////////////
local function negativeWorldFlash(duration)
	duration = tonumber(duration) or (CFG.RefusalFrameDuration or 1.0)

	local f1 = Lighting:FindFirstChild("RefusalFrame1")
	local f2 = Lighting:FindFirstChild("RefusalFrame2")

	local list = {}
	if f1 and f1:IsA("PostEffect") then
		table.insert(list, f1)
	end
	if f2 and f2:IsA("PostEffect") then
		table.insert(list, f2)
	end

	if #list > 0 then
		for _, fx in ipairs(list) do
			fx.Enabled = true
		end
		task.delay(duration, function()
			for _, fx in ipairs(list) do
				if fx and fx.Parent then
					fx.Enabled = false
				end
			end
		end)
		return
	end

	local old = { cc.Brightness, cc.Contrast, cc.Saturation, cc.TintColor }
	cc.Enabled = true
	cc.Brightness = 0.12
	cc.Contrast = 2.0
	cc.Saturation = -1
	cc.TintColor = Color3.fromRGB(170, 255, 255)
	task.delay(duration, function()
		if cc and cc.Parent then
			cc.Brightness, cc.Contrast, cc.Saturation, cc.TintColor = old[1], old[2], old[3], old[4]
		end
	end)
end

--============================================================
-- STOP HERE for Part 1/2.
-- Part 2/2 continues with:
-- - VIGNETTE, AURAS, TAUNTS, WORLDSOUL (your same systems)
-- - NEW animation preload + delayed start logic
-- - Fixed BeatDrop explosion block (ExplosionShot -> SnapToPlayer)
-- - Entry/cleanup wiring
--============================================================

--////////////////////////////////////////////////////////////
-- VIGNETTE
--////////////////////////////////////////////////////////////
local vignetteGui, vignetteRoot
local vignetteEdges = {}

local function buildVignette()
	if vignetteGui and vignetteGui.Parent then
		return
	end
	local pg = player:WaitForChild("PlayerGui")

	vignetteGui = Instance.new("ScreenGui")
	vignetteGui.Name = OUR_VIGNETTE_GUI_NAME
	vignetteGui.ResetOnSpawn = false
	vignetteGui.IgnoreGuiInset = true
	vignetteGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	vignetteGui.DisplayOrder = 1999999998
	vignetteGui.Parent = pg
	vignetteGui.Enabled = false

	vignetteRoot = Instance.new("Frame")
	vignetteRoot.Size = UDim2.fromScale(1, 1)
	vignetteRoot.BackgroundTransparency = 1
	vignetteRoot.Parent = vignetteGui

	local function makeEdge(pos, size, rot)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.fromRGB(140, 0, 10)
		f.BackgroundTransparency = 1
		f.Position = pos
		f.Size = size
		f.Parent = vignetteRoot

		local g = Instance.new("UIGradient")
		g.Rotation = rot
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		return f
	end

	table.insert(vignetteEdges, makeEdge(UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.22, 0), 90))
	table.insert(vignetteEdges, makeEdge(UDim2.new(0, 0, 0.78, 0), UDim2.new(1, 0, 0.22, 0), 270))
	table.insert(vignetteEdges, makeEdge(UDim2.new(0, 0, 0, 0), UDim2.new(0.22, 0, 1, 0), 0))
	table.insert(vignetteEdges, makeEdge(UDim2.new(0.78, 0, 0, 0), UDim2.new(0.22, 0, 1, 0), 180))
end

local function setVignette(alpha)
	buildVignette()
	alpha = math.clamp(alpha or 0, 0, 0.75)
	if vignetteGui then
		vignetteGui.Enabled = alpha > 0.001
	end
	local bt = 1 - alpha
	for _, f in ipairs(vignetteEdges) do
		if f and f.Parent then
			f.BackgroundTransparency = bt
		end
	end
end

local function clearVignette()
	if vignetteGui then
		vignetteGui.Enabled = false
	end
	for _, f in ipairs(vignetteEdges) do
		if f and f.Parent then
			f.BackgroundTransparency = 1
		end
	end
end

--////////////////////////////////////////////////////////////
-- PHASE3 FOLDER (auras)
--////////////////////////////////////////////////////////////
local phase3Folder
local function ensurePhase3Folder()
	if phase3Folder and phase3Folder.Parent then
		return phase3Folder
	end
	phase3Folder = Instance.new("Folder")
	phase3Folder.Name = "__Phase3VFX"
	phase3Folder.Parent = workspace
	return phase3Folder
end

--////////////////////////////////////////////////////////////
-- AURAS
--////////////////////////////////////////////////////////////
local refusalAura = { stage = 0, inst = nil }

local function getAuraPrefabName(stage)
	if stage == 1 then
		return "RefusalAura_Stage1"
	end
	if stage == 2 then
		return "RefusalAura_Stage2"
	end
	if stage == 3 then
		return "DeathRefusal_Stage3"
	end
	return nil
end

local function cleanupRefusalAura()
	if refusalAura.inst and refusalAura.inst.Parent then
		refusalAura.inst:Destroy()
	end
	refusalAura.inst = nil
	refusalAura.stage = 0
end

local function findAuraRoot(model: Instance): BasePart?
	local r = model:FindFirstChild("AuraRoot", true)
	if r and r:IsA("BasePart") then
		return r
	end
	if model:IsA("Model") and model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local any = model:FindFirstChildWhichIsA("BasePart", true)
	if any and any:IsA("BasePart") then
		return any
	end
	return nil
end

local function weldAuraToHRP(auraInst: Instance): boolean
	local char = player.Character
	if not char then
		return false
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return false
	end

	local root = findAuraRoot(auraInst)
	if not root then
		warn("[Aura] No root part in:", auraInst.Name)
		return false
	end

	local parts = {}
	for _, d in ipairs(auraInst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.LocalTransparencyModifier = 0
			if d.Transparency > 0.95 then
				d.Transparency = 0
			end
			table.insert(parts, d)
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = true
		elseif d:IsA("Light") or d:IsA("Beam") or d:IsA("Trail") then
			d.Enabled = true
		end
	end

	pcall(function()
		if auraInst:IsA("Model") then
			if auraInst.PrimaryPart == nil then
				auraInst.PrimaryPart = root
			end
			auraInst:PivotTo(hrp.CFrame)
		else
			root.CFrame = hrp.CFrame
		end
	end)

	local w0 = Instance.new("WeldConstraint")
	w0.Name = "__HRP_To_AuraRoot"
	w0.Part0 = hrp
	w0.Part1 = root
	w0.Parent = root

	for _, p in ipairs(parts) do
		if p ~= root then
			local w = Instance.new("WeldConstraint")
			w.Name = "__AuraWeld"
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
		end
	end

	return true
end

local function setRefusalAuraStage(stage: number)
	if refusalAura.stage == stage then
		return
	end
	cleanupRefusalAura()

	if not AurasFolder then
		warn("[Aura] AurasFolder missing")
		return
	end

	local prefabName = getAuraPrefabName(stage)
	local prefab = prefabName and AurasFolder:FindFirstChild(prefabName)
	if not prefab then
		warn("[Aura] Missing prefab:", prefabName)
		return
	end

	local clone = prefab:Clone()
	clone.Name = "__DeathRefusalAuraStage" .. tostring(stage)
	clone.Parent = ensurePhase3Folder()

	if not weldAuraToHRP(clone) then
		clone:Destroy()
		return
	end

	refusalAura.stage = stage
	refusalAura.inst = clone
end

--////////////////////////////////////////////////////////////
-- TAUNTS (Credits/Madness/Rare)
--////////////////////////////////////////////////////////////
local rageGui, rageLayer
local creditsViewport, creditsContent, creditsLayout
local creditsConn
local creditsStartClock = 0
local creditsBaseY = 0
local tauntMode = "off"

local ORDER_LIST_A = {
	"YOUR DAMAGE IS A SUGGESTION.",
	"DEATH REQUEST: REJECTED.",
	"REALITY IS BUFFERING.",
	"THE RULES DO NOT APPLY.",
	"YOU DON'T GET TO END ME.",
	"THE WORLD CAN'T TRACK ME.",
	"NOT A DEATH. AN INTERRUPTION.",
	"STILL STANDING.",
	"STILL HERE.",
	"STILL MOVING.",
	"TRY HARDER.",
	"NO.",
}

local ORDER_LIST_B = {
	"YOU SWUNG AT SHADOWS.",
	"YOUR HITBOXES ARE HOPEFUL.",
	"THE UNIVERSE IS LATE.",
	"YOUR POWER DOESN'T APPLY HERE.",
	"PERMISSION DENIED.",
	"REALITY CAN'T KEEP UP.",
	"YOU ARE ONLY STATIC.",
	"PATHETIC.",
	"USELESS.",
	"WEAK.",
	"NOT EVEN CLOSE.",
	"AGAIN.",
}

local CHAOS_LIST = {
	"PATHETIC.",
	"USELESS.",
	"NO.",
	"WEAK.",
	"TRY AGAIN.",
	"YOU MISSED.",
	"NOT EVEN CLOSE.",
	"STOP.",
	"STAY DOWN.",
	"I SAID NO.",
	"REALITY CAN'T KEEP UP.",
	"ERROR: YOU THOUGHT.",
	"YOU SWUNG AT SHADOWS.",
	"YOU'RE DONE.",
	"YOUR BEST WAS NOTHING.",
}

local function ensureRageGui()
	local pg = player:WaitForChild("PlayerGui")
	if rageGui and rageGui.Parent then
		rageGui.Enabled = true
		return
	end

	rageGui = Instance.new("ScreenGui")
	rageGui.Name = OUR_RAGE_GUI_NAME
	rageGui.ResetOnSpawn = false
	rageGui.IgnoreGuiInset = true
	rageGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	rageGui.DisplayOrder = 2000000000
	rageGui.Enabled = true
	rageGui.Parent = pg

	rageLayer = Instance.new("Frame")
	rageLayer.BackgroundTransparency = 1
	rageLayer.Size = UDim2.fromScale(1, 1)
	rageLayer.Parent = rageGui
end

local madnessBackdrop
local function setMadnessBackdrop(on: boolean, strength: number)
	ensureRageGui()
	strength = math.clamp(strength or 0.42, 0, 0.75)

	if not madnessBackdrop then
		madnessBackdrop = Instance.new("Frame")
		madnessBackdrop.Name = "MadnessBackdrop"
		madnessBackdrop.Size = UDim2.fromScale(1, 1)
		madnessBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		madnessBackdrop.BorderSizePixel = 0
		madnessBackdrop.ZIndex = 1
		madnessBackdrop.BackgroundTransparency = 1
		madnessBackdrop.Visible = false
		madnessBackdrop.Parent = rageLayer
	end

	if on then
		madnessBackdrop.Visible = true
		madnessBackdrop.BackgroundTransparency = 1
		tw(madnessBackdrop, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1 - strength,
		})
	else
		tw(madnessBackdrop, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		})
		task.delay(0.14, function()
			if madnessBackdrop then
				madnessBackdrop.BackgroundTransparency = 1
				madnessBackdrop.Visible = false
			end
		end)
	end
end

local function rageGuiOn()
	ensureRageGui()
	rageGui.Enabled = true
end

local function rageGuiOff()
	if rageGui then
		rageGui.Enabled = false
	end
	if madnessBackdrop then
		madnessBackdrop.BackgroundTransparency = 1
		madnessBackdrop.Visible = false
	end
end

local function destroyCredits()
	if creditsConn then
		creditsConn:Disconnect()
		creditsConn = nil
	end
	if creditsViewport and creditsViewport.Parent then
		creditsViewport:Destroy()
	end
	creditsViewport, creditsContent, creditsLayout = nil, nil, nil
end

local function clearRageLayer()
	if rageLayer then
		for _, c in ipairs(rageLayer:GetChildren()) do
			c:Destroy()
		end
	end
	madnessBackdrop = nil
end

local function mkMadnessLabel(text, absX, absY, size, z)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromOffset(absX, absY)
	t.Size = UDim2.new(0, 900, 0, 140)
	t.Font = Enum.Font.Arcade
	t.Text = text
	t.TextSize = size
	t.TextColor3 = Color3.fromRGB(245, 245, 245)
	t.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	t.TextStrokeTransparency = 0.40
	t.TextTransparency = 0
	t.Rotation = math.random(-20, 20)
	t.ZIndex = z or 120
	t.Parent = rageLayer
	return t
end

local function startCreditsRoll()
	tauntMode = "credits"
	rageGuiOn()
	clearRageLayer()
	destroyCredits()

	creditsViewport = Instance.new("Frame")
	creditsViewport.BackgroundTransparency = 1
	creditsViewport.Size = UDim2.fromScale(1, 1)
	creditsViewport.ClipsDescendants = true
	creditsViewport.Parent = rageLayer

	creditsContent = Instance.new("Frame")
	creditsContent.BackgroundTransparency = 1
	creditsContent.Size = UDim2.new(1, 0, 0, 0)
	creditsContent.Parent = creditsViewport

	creditsLayout = Instance.new("UIListLayout")
	creditsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	creditsLayout.Padding = UDim.new(0, 10)
	creditsLayout.Parent = creditsContent

	creditsStartClock = os.clock()
	creditsBaseY = creditsViewport.AbsoluteSize.Y + 40
	creditsContent.Position = UDim2.new(0, 0, 0, creditsBaseY)

	if creditsConn then
		creditsConn:Disconnect()
	end
	creditsConn = RunService.RenderStepped:Connect(function()
		if tauntMode ~= "credits" then
			return
		end
		if not creditsViewport or not creditsViewport.Parent then
			return
		end
		if not creditsContent or not creditsContent.Parent then
			return
		end
		local h = creditsLayout.AbsoluteContentSize.Y
		creditsContent.Size = UDim2.new(1, 0, 0, h)
		local dt = os.clock() - creditsStartClock
		local y = creditsBaseY - (dt * 62)
		creditsContent.Position = UDim2.new(0, 0, 0, y)
	end)
end
local function addCreditsLine(text, idx)
	if not (creditsContent and creditsContent.Parent) then
		return
	end
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, 56)
	t.Font = Enum.Font.Arcade
	t.Text = text
	t.TextSize = 34
	t.TextColor3 = Color3.fromRGB(245, 245, 245)
	t.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	t.TextStrokeTransparency = 0.55
	t.TextTransparency = 1
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.LayoutOrder = idx or 1
	t.ZIndex = 80
	t.Parent = creditsContent
	tw(t, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 })
end

local madnessConn
local function stopMadnessFlood()
	if madnessConn then
		madnessConn:Disconnect()
		madnessConn = nil
	end
	setMadnessBackdrop(false, 0.42)
end

local function startMadnessFlood(runId)
	tauntMode = "madness"
	rageGuiOn()
	destroyCredits()
	clearRageLayer()
	setMadnessBackdrop(true, 0.42)

	RunService.RenderStepped:Wait()

	local wordsPerSec = 2000
	local spawnAccumulator = 0
	local aliveCount = 0
	local maxAlive = 800

	local function spawnOne(layerBoost)
		if not rageLayer or not rageLayer.Parent then
			return
		end
		if aliveCount >= maxAlive then
			return
		end

		local text = CHAOS_LIST[math.random(1, #CHAOS_LIST)]
		local w = rageLayer.AbsoluteSize.X
		local h = rageLayer.AbsoluteSize.Y
		local x = math.random(0, w)
		local y = math.random(0, h)

		x = x + math.random(-18, 18)
		y = y + math.random(-18, 18)

		local size = math.random(34, 70)
		if layerBoost then
			size = math.floor(size * layerBoost)
		end

		local z = layerBoost and 115 or 125
		local lbl = mkMadnessLabel(text, x, y, size, z)
		aliveCount += 1

		local life = 0.22 + (0.70 - 0.22) * math.random()

		lbl.TextTransparency = 1
		tw(lbl, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 })

		task.delay(math.max(0.05, life - 0.12), function()
			if lbl and lbl.Parent then
				tw(lbl, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
			end
		end)

		task.delay(life + 0.05, function()
			if lbl and lbl.Parent then
				lbl:Destroy()
			end
			aliveCount = math.max(0, aliveCount - 1)
		end)
	end

	if madnessConn then
		madnessConn:Disconnect()
	end
	madnessConn = RunService.RenderStepped:Connect(function(dt)
		if not aliveRun(runId) then
			return
		end
		if tauntMode ~= "madness" then
			return
		end

		spawnAccumulator += dt * wordsPerSec
		local n = math.floor(spawnAccumulator)
		if n > 0 then
			spawnAccumulator -= n
			n = math.clamp(n, 1, 25)
			for i = 1, n do
				spawnOne(nil)
				if i % 3 == 0 then
					spawnOne(0.92)
				end
			end
		end
	end)
end

local function startRareLoop(runId)
	tauntMode = "rare"
	rageGuiOn()
	task.spawn(function()
		while aliveRun(runId) and tauntMode == "rare" do
			local w = rageLayer and rageLayer.AbsoluteSize.X or 800
			local h = rageLayer and rageLayer.AbsoluteSize.Y or 600
			local text = CHAOS_LIST[math.random(1, #CHAOS_LIST)]
			local lbl = mkMadnessLabel(text, math.random(0, w), math.random(0, h), math.random(34, 56), 110)
			lbl.TextTransparency = 0

			local life = 0.35 + (0.9 - 0.35) * math.random()
			task.delay(life - 0.12, function()
				if lbl and lbl.Parent then
					tw(lbl, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
				end
			end)
			task.delay(life + 0.05, function()
				if lbl and lbl.Parent then
					lbl:Destroy()
				end
			end)

			task.wait(1.00 + (1.80 - 1.00) * math.random())
		end
	end)
end

local function stopTaunts()
	tauntMode = "off"
	stopMadnessFlood()
	destroyCredits()
	clearRageLayer()
	rageGuiOff()
end

--////////////////////////////////////////////////////////////
-- WORLD SOUL (short)
--////////////////////////////////////////////////////////////
local function prepSoulModel(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
		end
	end
end

local function getChestAnchor()
	local char = player.Character
	if not char then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	local upper = char:FindFirstChild("UpperTorso")
	local torso = char:FindFirstChild("Torso")
	local chestPart = upper or torso or root
	if not (chestPart and chestPart:IsA("BasePart")) then
		return nil
	end

	local forward = (root and root.CFrame.LookVector) or chestPart.CFrame.LookVector
	forward = Vector3.new(forward.X, 0.1, forward.Z)
	if forward.Magnitude < 0.05 then
		forward = Vector3.new(0, 0.2, -1)
	end
	forward = forward.Unit

	local heartPos = chestPart.Position + Vector3.new(0, 0.7, 0) + forward * 0.25
	local heartCF = CFrame.new(heartPos, heartPos + forward)
	return chestPart, heartCF, forward
end

local function playWorldSoul(runId)
	local _, heartCF, forward = getChestAnchor()
	if not heartCF then
		return
	end
	local basePos = heartCF.Position
	local topPos = basePos + Vector3.new(0, 12, 0)

	local soul = SoulTemplate:Clone()
	soul.Name = "__WorldSoul"
	soul.Parent = workspace
	prepSoulModel(soul)

	local core = soul:FindFirstChild("Core") or soul:FindFirstChildWhichIsA("BasePart", true)
	if not (core and core:IsA("BasePart")) then
		soul:Destroy()
		return
	end

	soul:PivotTo(CFrame.new(basePos - forward * 0.25, basePos + forward))
	beginCineCamera(basePos, 42)
	enablePostFX()

	playNamed("cinematic-impact-boom", 0.60, 0.98)

	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not aliveRun(runId) then
			if conn then
				conn:Disconnect()
			end
			return
		end
		local a = math.clamp((os.clock() - t0) / 0.75, 0, 1)
		local eased = a * a * (3 - 2 * a)
		local pos = basePos:Lerp(topPos, eased)
		local rotY = (os.clock() - t0) * 7.0
		soul:PivotTo(CFrame.new(pos, pos + forward) * CFrame.Angles(0, rotY, 0))
	end)
	task.wait(0.78)
	if conn then
		conn:Disconnect()
	end

	disablePostFX()
	endCineCamera()
	soul:Destroy()
end

--////////////////////////////////////////////////////////////
-- ANIMATION (Preload + Delayed Start + Pause At)
--////////////////////////////////////////////////////////////
local function getAnimator(hum: Humanoid)
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	animator = Instance.new("Animator")
	animator.Parent = hum
	return animator
end

local function stopAllTracks(hum: Humanoid)
	local animator = getAnimator(hum)
	for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
		pcall(function()
			tr:Stop(0)
		end)
	end
end

local function restoreAnimate(handle)
	if not handle then
		return
	end
	if handle.track then
		pcall(function()
			handle.track:Stop(0)
		end)
	end
	if handle.animate then
		pcall(function()
			handle.animate.Disabled = false
		end)
	end
	forceRestoreLook()
end

local function preloadDeathRefusalAnimation(runId)
	local char = player.Character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end

	stopAllTracks(hum)
	local animate = char:FindFirstChild("Animate")
	if animate then
		pcall(function()
			animate.Disabled = true
		end)
	end

	local animator = getAnimator(hum)
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(CFG.DeathRefusal_NewAnimId)

	local track
	local ok, err = pcall(function()
		track = animator:LoadAnimation(anim)
	end)
	if not ok or not track then
		warn("[DeathRefusalNewAnim] LoadAnimation failed:", err)
		if animate then
			pcall(function()
				animate.Disabled = false
			end)
		end
		return nil
	end

	pcall(function()
		track.Priority = Enum.AnimationPriority.Action4
		-- DO NOT PLAY YET
	end)

	return { track = track, animate = animate, started = false }
end

local function startAndAutoPauseDeathRefusal(handle, runId)
	if not handle or not handle.track then
		return
	end
	if handle.started then
		return
	end
	handle.started = true

	local track = handle.track
	local pauseAt = tonumber(CFG.DeathRefusal_PauseAt) or 5.26

	-- Start clean
	pcall(function()
		track:Play(0)
		track:AdjustSpeed(1.0)
	end)

	-- FORCE start at 0 (prevents "starts half way" nonsense)
	task.defer(function()
		if not aliveRun(runId) or not track then
			return
		end
		pcall(function()
			track.TimePosition = 0
		end)
	end)

	task.spawn(function()
		local t0 = os.clock()
		local last = -1
		while aliveRun(runId) and track and track.IsPlaying do
			local pos = 0
			pcall(function()
				pos = track.TimePosition
			end)

			if pos > 0.05 and pos >= last then
				break
			end
			last = pos

			if (os.clock() - t0) > 1.5 then
				break
			end
			RunService.Heartbeat:Wait()
		end

		while aliveRun(runId) and track and track.IsPlaying do
			local pos = 0
			pcall(function()
				pos = track.TimePosition
			end)
			if pos >= pauseAt then
				pcall(function()
					track:AdjustSpeed(0)
				end)
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

--////////////////////////////////////////////////////////////
-- EXPLOSION SPAWN (server-owned)
--////////////////////////////////////////////////////////////
local function spawnExplosionPillar(centerPos: Vector3)
	DeathRefusalExplosionRE:FireServer({
		kind = "pillar",
		center = centerPos,
		cameraDuration = CFG.ExplosionWitnessTime,
		cameraDist = 350,
		cameraHeight = 94,
		cameraFov = 78,
		fadeAfter = CFG.ExplosionWitnessTime + CFG.AweHoldTime,
		fadeDur = 2.25,
		lifetime = CFG.ExplosionWitnessTime + CFG.AweHoldTime + 2.25 + 2.0,
	})
end

--////////////////////////////////////////////////////////////
-- DECIDERS
--////////////////////////////////////////////////////////////
local function serverWantsRefusal(data)
	if typeof(data) ~= "table" then
		return false
	end
	if data.refusal == true or data.deathRefusal == true or data.isRefusal == true then
		return true
	end
	local mode = tostring(data.mode or data.sequence or data.kind or ""):lower()
	if mode == "refusal" or mode == "deathrefusal" then
		return true
	end
	if tostring(data.outcome or ""):lower() == "refusal" then
		return true
	end
	return false
end

local function serverWantsPhase3(data)
	if typeof(data) ~= "table" then
		return false
	end
	if data.phase3 == true or data.isPhase3 == true or data.doPhase3 == true then
		return true
	end
	local mode = tostring(data.mode or ""):lower()
	local seq = tostring(data.sequence or ""):lower()
	local kind = tostring(data.kind or ""):lower()
	local function isP3(s)
		return s == "phase3" or s == "phase_3" or s == "phase-3" or s == "phasethree" or s == "phase_three" or s == "p3"
	end
	return isP3(mode) or isP3(seq) or isP3(kind)
end

--////////////////////////////////////////////////////////////
-- IMPORTANT CAMERA FIX HELPERS
--////////////////////////////////////////////////////////////
local function stopCineWithoutRestore()
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
	camBaseCF = nil
	camTargetPos = nil
end

--////////////////////////////////////////////////////////////
-- PHASE3 MAIN (Fixed explosion zoom + snap + delayed anim)
--////////////////////////////////////////////////////////////
local function playPhase3(runId, injectRefusal)
	local _, heartCF = getChestAnchor()
	if not heartCF then
		return
	end
	local heartPos = heartCF.Position

	resolveAssetFolders(6)

	State.mode = "Phase3"
	ensurePhase3Folder()

	clearFaceLock()
	stopTaunts()
	clearVignette()
	brutalFxOff()
	cleanupRefusalAura()

	lockInput()
	setFrozen(true)
	rageGuiOn()

	beginCineCamera(heartPos, CAMCFG.NearDist)
	enablePostFX()

	startTheme()
	playNamed("Phase3_Rumble", 0.70, 0.90)
	playAfter(0.85, "Mechanical Clicks", 0.30, 1.00)
	playAfter(1.25, "Mechanical Clicks", 0.28, 0.96)

	if injectRefusal then
		setRefusalAuraStage(1)
	end

	local T_MAD = THEME_TIMES.MadnessStart
	local T_CALM2 = THEME_TIMES.CalmReturn
	local T_PRE = THEME_TIMES.PreDetonate
	local T_DROP = THEME_TIMES.BeatDrop

	startCreditsRoll()
	task.spawn(function()
		local idx = 0
		while aliveRun(runId) and themeSound and themeTime() < T_MAD do
			local t = themeTime()
			if t >= 3.0 and t <= 15.0 and tauntMode == "credits" then
				idx += 1
				local src = (idx % 2 == 0) and ORDER_LIST_A or ORDER_LIST_B
				addCreditsLine(src[((idx - 1) % #src) + 1], idx)
				task.wait(0.13 + (0.18 - 0.13) * math.random())
			else
				task.wait(0.06)
			end
		end
	end)

	while aliveRun(runId) and themeSound and themeTime() < T_MAD do
		local t = themeTime()
		local a = math.clamp((t - THEME_TIMES.ChargeStart) / math.max(0.01, (T_MAD - THEME_TIMES.ChargeStart)), 0, 1)
		a = a * a * (3 - 2 * a)
		camDesiredDist = CAMCFG.NearDist + a * (CAMCFG.FarDist - CAMCFG.NearDist)
		camDesiredHeight = CAMCFG.NearHeight + a * (CAMCFG.FarHeight - CAMCFG.NearHeight)
		shakePowerWorld = math.min(CAMCFG.MaxShake, shakePowerWorld + 0.03 + a * 0.02)
		RunService.RenderStepped:Wait()
	end
	if not aliveRun(runId) then
		return
	end

	while aliveRun(runId) and themeSound and themeTime() < (T_MAD + 1.2) do
		shakePowerWorld = math.min(CAMCFG.MaxShake, shakePowerWorld + 0.12)
		RunService.RenderStepped:Wait()
	end
	if not aliveRun(runId) then
		return
	end

	startMadnessFlood(runId)

	while aliveRun(runId) and themeSound and themeTime() < T_CALM2 do
		shakePowerWorld = math.min(CAMCFG.MaxShake, shakePowerWorld + 0.08)
		RunService.Heartbeat:Wait()
	end
	if not aliveRun(runId) then
		return
	end

	stopMadnessFlood()
	stopTaunts()

	if injectRefusal then
		setRefusalAuraStage(2)
	end

	local cam = workspace.CurrentCamera
	if cam then
		tw(cam, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = CAMCFG.CloseFov })
	end
	camDesiredDist = CAMCFG.CloseDist
	camDesiredHeight = CAMCFG.CloseHeight
	shakePowerWorld = 1.8

	rotateAndLockFacingCamera(runId)

	local animHandle = preloadDeathRefusalAnimation(runId)

	startRareLoop(runId)

	local startAt = T_DROP - math.max(0.05, tonumber(CFG.AnimLeadBeforeBeatDrop) or 1.10)
	while aliveRun(runId) and themeSound and themeTime() < startAt do
		RunService.RenderStepped:Wait()
	end
	if not aliveRun(runId) then
		restoreAnimate(animHandle)
		clearFaceLock()
		return
	end

	if animHandle and animHandle.track then
		startAndAutoPauseDeathRefusal(animHandle, runId)
	end

	while aliveRun(runId) and themeSound and themeTime() < T_PRE do
		RunService.RenderStepped:Wait()
	end
	if not aliveRun(runId) then
		restoreAnimate(animHandle)
		clearFaceLock()
		return
	end

	local lead = 2.0
	while aliveRun(runId) and themeSound and themeTime() < T_DROP do
		local t = themeTime()
		local startWarn = T_DROP - lead
		if t >= startWarn then
			local a = math.clamp((t - startWarn) / math.max(0.01, (T_DROP - startWarn)), 0, 1)
			a = a * a * (3 - 2 * a)
			setVignette(a * 0.66)
			if math.random() < (0.05 + a * 0.08) then
				playNamed("Glitch", 0.16, 0.9 + 0.2 * math.random())
			end
		end
		RunService.RenderStepped:Wait()
	end
	if not aliveRun(runId) then
		restoreAnimate(animHandle)
		clearFaceLock()
		return
	end

	--========================================================
	-- BEAT DROP EXPLOSION (Fixed zoom-out + snap back)
	--========================================================
	if animHandle and animHandle.track then
		pcall(function()
			animHandle.track:AdjustSpeed(0)
		end)
	end

	negativeWorldFlash(1.0)
	setRefusalHighlight(true)
	task.delay(1.0, function()
		setRefusalHighlight(false)
	end)

	playNamed("Crack", 0.95, 1.00)
	playNamed("soul shatter", 0.85, 1.00)
	task.wait(0.04)
	playNamed("Detonation", 1.00, 1.00)
	task.wait(0.02)

	startExplosionGrade()
	playNamed("big-energy-explosion", 1.00, 1.00)
	playNamed("cinematic-impact-boom", 0.95, 0.98)
	playAfter(0.03, "sub-bass-drop", 1.00, 0.90)
	playAfter(0.08, "Ear Ring", 0.65, 1.00)

	shakePowerWorld = CAMCFG.MaxShake

	if injectRefusal then
		setRefusalAuraStage(3)
	end
	spawnExplosionPillar(heartPos)

	clearFaceLock()
	stopCineWithoutRestore()

	explosionShot(heartPos, CAMCFG.ExplodeShotDuration)

	task.delay(CAMCFG.ExplodeShotDuration + (CAMCFG.SnapBackExtraDelay or 0), function()
		if not aliveRun(runId) then
			return
		end
		snapCameraToPlayer()
	end)

	local hold0 = os.clock()
	while aliveRun(runId) and (os.clock() - hold0) < (CFG.ExplosionWitnessTime + CFG.AweHoldTime) do
		RunService.Heartbeat:Wait()
	end

	endExplosionGrade()

	if animHandle and animHandle.track then
		pcall(function()
			animHandle.track:Stop(0)
		end)
		animHandle.track = nil
	end

	if animHandle and animHandle.animate then
		pcall(function()
			animHandle.animate.Disabled = false
		end)
	end

	disablePostFX()
	clearVignette()
	stopTaunts()

	restoreAnimate(animHandle)
	clearFaceLock()
	unlockInput()
	setFrozen(false)

	if themeEndConn then
		themeEndConn:Disconnect()
		themeEndConn = nil
	end
	if themeSound then
		themeEndConn = themeSound.Ended:Connect(function()
			cleanupRefusalAura()
			themeEndConn = nil
		end)
	end

	forceRestoreLook()
end

--////////////////////////////////////////////////////////////
-- CLEANUP (does NOT delete aura unless forced)
--////////////////////////////////////////////////////////////
local function hardCleanup(forceKillAura: boolean)
	State.mode = "Cleaning"
	clearFaceLock()
	stopTaunts()
	clearVignette()
	endExplosionGrade()
	disablePostFX()
	brutalFxOff()

	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
	camBaseCF = nil
	camTargetPos = nil
	restoreCameraClean()

	unlockInput()
	setFrozen(false)
	forceRestoreLook()

	if forceKillAura then
		cleanupRefusalAura()
	end

	if not CFG.KeepThemeAfterCutscene and themeSound then
		pcall(function()
			themeSound:Stop()
		end)
	end

	State.mode = "Idle"
end

--////////////////////////////////////////////////////////////
-- ENTRY
--////////////////////////////////////////////////////////////
local function BeginDeathSequence(data)
	if typeof(data) ~= "table" then
		return
	end
	if State.mode ~= "Idle" then
		return
	end

	local isRefusal = serverWantsRefusal(data)
	local isPhase3 = serverWantsPhase3(data)
	if not isRefusal and not isPhase3 then
		return
	end

	local runId = bumpRun()
	resolveAssetFolders(6)

	task.spawn(function()
		pcall(function()
			playWorldSoul(runId)
		end)
		if not aliveRun(runId) then
			hardCleanup(true)
			return
		end

		local ok, err = pcall(function()
			playPhase3(runId, isRefusal)
		end)
		if not ok then
			warn("[DeathScreen] Phase3 error:", err)
		end
		if not aliveRun(runId) then
			hardCleanup(true)
			return
		end

		pcall(function()
			FinishDeathSequenceRE:FireServer({ outcome = "empower", postIFrames = 3.50 })
		end)

		hardCleanup(false)
	end)
end

-- Boot queue drain
local function getBeginFn()
	local fn = nil
	pcall(function()
		fn = BOOT.BeginDeathSequence
		if typeof(fn) ~= "function" then
			fn = _G.BeginDeathSequence
		end
		local sh = rawget(_G, "shared")
		if typeof(fn) ~= "function" and type(sh) == "table" then
			fn = sh.BeginDeathSequence
		end
	end)
	return (typeof(fn) == "function") and fn or nil
end

local function drainDeathQueue()
	if BOOT._deathDrainRunning then
		return
	end
	BOOT._deathDrainRunning = true
	task.defer(function()
		for _ = 1, 120 do
			local fn = getBeginFn()
			if fn then
				while #BOOT._deathQueue > 0 do
					local payload = table.remove(BOOT._deathQueue, 1)
					local ok, err = pcall(fn, payload)
					if not ok then
						warn("[DeathScreen] BeginDeathSequence error:", err)
					end
				end
				BOOT._deathDrainRunning = false
				return
			end
			RunService.Heartbeat:Wait()
		end
		BOOT._deathQueue = {}
		BOOT._deathDrainRunning = false
	end)
end

_G.BeginDeathSequence = BeginDeathSequence
shared.BeginDeathSequence = BeginDeathSequence
BOOT.BeginDeathSequence = BeginDeathSequence
drainDeathQueue()

if BOOT.startConn then
	pcall(function()
		BOOT.startConn:Disconnect()
	end)
	BOOT.startConn = nil
end
BOOT.startConn = StartDeathSequenceRE.OnClientEvent:Connect(function(data)
	if State.mode ~= "Idle" then
		return
	end
	table.insert(BOOT._deathQueue, data)
	drainDeathQueue()
end)

if BOOT.charConn then
	pcall(function()
		BOOT.charConn:Disconnect()
	end)
	BOOT.charConn = nil
end
BOOT.charConn = player.CharacterAdded:Connect(function()
	if State.mode ~= "Idle" then
		return
	end
	bumpRun()
	hardCleanup(true)
end)

hardCleanup(true)