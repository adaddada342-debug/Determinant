-- StarterPlayerScripts/OrbitalStrikeSFX.client.lua
-- Orbital Strike SFX scorer (NO ThemeSong, NO Glitch).
-- Listens to ReplicatedStorage/Remotes/OrbitalStrikeFX:
--   "Marker" -> charge build (+ EARLY Detonation)
--   "Impact" -> hard cut + massive impact stack + aftermath (NO detonation here)
--   "Cancel" -> stop charge
--
-- ✅ AMENDED: Detonation now runs BEFORE the laser ever arrives by triggering during Marker only.
--            Impact no longer plays Detonation (prevents late/double hits).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FX = Remotes:WaitForChild("OrbitalStrikeFX")

local AudioRoot = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Audio")

--============================================================
-- CONFIG
--============================================================
local CFG = {
	USE_POSITIONAL_AUDIO = true,
	DEFAULT_RAMP_TIME = 1.0,
	PRE_IMPACT_SILENCE = 0.04,

	-- ✅ NEW: Guaranteed early detonation (relative to Marker)
	-- This is the "before laser ever arrives" timing. Tune it.
	DET_DELAY_AFTER_MARKER = 0.18, -- seconds after Marker to play Detonation
	DET_MIN_DELAY = 0.02,          -- prevents same-frame issues

	-- ✅ Rumble safety
	RUMBLE_MAX = 0.75,
	RUMBLE_FADE = 0.18,
	SOULRUMBLE_MAX = 0.55,
	SOULRUMBLE_FADE = 0.16,

	JITTER = {
		LOW = {0.88, 0.98},
		MID = {0.93, 1.05},
		HIGH = {0.98, 1.14},
	},

	VOL = {
		AMBIENCE = 0.18,
		CHARGE_MAIN = 0.55,
		CHARGE_UNDER = 0.22,
		MECH = 0.18,

		TAPESTOP = 0.75,

		SUBDROP = 0.95,
		DET = 0.90,
		BOOM = 0.55,
		ELECTRIC = 0.75,

		CRACK_HIGH = 0.85,
		CRACK_LOW  = 0.65,
		CRACK_EXTRA = 0.35,

		METAL = 0.55,

		RUMBLE = 0.80,
		SOULRUMBLE = 0.45,
		EARRING = 0.45,
		ECHO = 0.35,
	},

	N = {
		AfterEffectDivineEcho = "AfterEffectDivineEcho",
		Ambience = "Ambience",
		ChargeUp = "Charge up",
		Crack = "Crack",
		Detonation = "Detonation",
		EarRing = "Ear Ring",
		MechanicalClicks = "Mechanical Clicks",
		SoulEntryRumble = "SoulEntryRumble",
		TapeStop = "Tape-Stop",
		CinematicImpactBoom = "cinematic-impact-boom",
		SoulShatter = "soul shatter",

		OrbitalFolder = "OrbitalLaser",
		CinematicRumble = "Cinematic Rumble",
		ElectricBlast = "ElectricBlast",
		LaserCharge = "Laser Charge",
		MetalImpact = "Metal Impact Container Door",
		SubBassDrop = "sub-bass-drop",
	},
}

--============================================================
-- HELPERS
--============================================================
local function findSound(path: {string}): Sound?
	local cur: Instance = AudioRoot
	for _, name in ipairs(path) do
		cur = cur:FindFirstChild(name)
		if not cur then return nil end
	end
	return (cur:IsA("Sound") and cur) or nil
end

local function randRange(a: number, b: number)
	return a + (math.random() * (b - a))
end

local function jitter(sound: Sound, preset: "LOW"|"MID"|"HIGH")
	local r = CFG.JITTER[preset]
	if r then sound.PlaybackSpeed = randRange(r[1], r[2]) end
end

local function makeWorldAnchor(pos: Vector3): BasePart
	local p = Instance.new("Part")
	p.Name = "_OrbitalSFXAnchor"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	Debris:AddItem(p, 4.0)
	return p
end

local function playOneShot(template: Sound?, parent: Instance, volume: number, preset: "LOW"|"MID"|"HIGH"?, delaySec: number?)
	if not template then return nil end
	local s = template:Clone()
	s.Parent = parent
	s.Volume = volume
	s.Looped = false
	if preset then jitter(s, preset) end

	if delaySec and delaySec > 0 then
		task.delay(delaySec, function()
			if s.Parent then s:Play() end
		end)
	else
		s:Play()
	end

	s.Ended:Once(function()
		if s and s.Parent then s:Destroy() end
	end)

	return s
end

local function stopAndDestroy(s: Sound?)
	if s and s.Parent then
		pcall(function() s:Stop() end)
		s:Destroy()
	end
end

local function ramp(sound: Sound, duration: number, targetVol: number?, targetPitch: number?)
	if not sound or not sound.Parent then return end
	local t0 = os.clock()
	local v0 = sound.Volume
	local p0 = sound.PlaybackSpeed
	local dur = math.max(0.001, duration)

	task.spawn(function()
		while sound and sound.Parent do
			local a = (os.clock() - t0) / dur
			if a >= 1 then break end
			if targetVol then sound.Volume = v0 + (targetVol - v0) * a end
			if targetPitch then sound.PlaybackSpeed = p0 + (targetPitch - p0) * a end
			task.wait()
		end
		if sound and sound.Parent then
			if targetVol then sound.Volume = targetVol end
			if targetPitch then sound.PlaybackSpeed = targetPitch end
		end
	end)
end

local function fadeOutAndStop(sound: Sound, fadeTime: number)
	if not sound or not sound.Parent then return end
	fadeTime = math.max(0.01, tonumber(fadeTime) or 0.15)

	local v0 = sound.Volume
	local t0 = os.clock()

	task.spawn(function()
		while sound and sound.Parent do
			local a = (os.clock() - t0) / fadeTime
			if a >= 1 then break end
			sound.Volume = v0 * (1 - a)
			task.wait()
		end
		if sound and sound.Parent then
			pcall(function() sound:Stop() end)
			sound:Destroy()
		end
	end)
end

local function playOneShotCapped(template: Sound?, parent: Instance, volume: number, preset: "LOW"|"MID"|"HIGH"?, delaySec: number?, maxTime: number?, fadeTime: number?)
	local s = playOneShot(template, parent, volume, preset, delaySec)
	if not s then return nil end

	maxTime = tonumber(maxTime) or 0
	fadeTime = tonumber(fadeTime) or 0.15

	if maxTime > 0 then
		task.delay(maxTime, function()
			if s and s.Parent then
				fadeOutAndStop(s, fadeTime)
			end
		end)
	end

	return s
end

--============================================================
-- TEMPLATES
--============================================================
local T = {}
T.Ambience = findSound({CFG.N.Ambience})
T.ChargeUp = findSound({CFG.N.ChargeUp})
T.Crack = findSound({CFG.N.Crack})
T.Detonation = findSound({CFG.N.Detonation})
T.EarRing = findSound({CFG.N.EarRing})
T.MechanicalClicks = findSound({CFG.N.MechanicalClicks})
T.SoulEntryRumble = findSound({CFG.N.SoulEntryRumble})
T.TapeStop = findSound({CFG.N.TapeStop})
T.Echo = findSound({CFG.N.AfterEffectDivineEcho})
T.CinematicImpactBoom = findSound({CFG.N.CinematicImpactBoom})
T.SoulShatter = findSound({CFG.N.SoulShatter})

T.OrbitalCinematicRumble = findSound({CFG.N.OrbitalFolder, CFG.N.CinematicRumble})
T.OrbitalElectricBlast = findSound({CFG.N.OrbitalFolder, CFG.N.ElectricBlast})
T.OrbitalLaserCharge = findSound({CFG.N.OrbitalFolder, CFG.N.LaserCharge})
T.OrbitalMetalImpact = findSound({CFG.N.OrbitalFolder, CFG.N.MetalImpact})
T.OrbitalSubDrop = findSound({CFG.N.OrbitalFolder, CFG.N.SubBassDrop})

--============================================================
-- STATE
--============================================================
local activeChargeMain: Sound? = nil
local activeChargeUnder: Sound? = nil
local activeAmbience: Sound? = nil

-- ✅ Guard to cancel scheduled detonation on Cancel/new Marker
local detToken = 0

local function stopChargeAll()
	stopAndDestroy(activeChargeMain); activeChargeMain = nil
	stopAndDestroy(activeChargeUnder); activeChargeUnder = nil
	stopAndDestroy(activeAmbience); activeAmbience = nil
end

--============================================================
-- TIMELINE
--============================================================
local function onMarker(payload)
	stopChargeAll()

	detToken += 1
	local myToken = detToken

	local rampTime = tonumber(payload and payload.rampTime) or CFG.DEFAULT_RAMP_TIME

	-- Optional positional anchor for early detonation
	local detParent: Instance = SoundService
	local impactPos = payload and payload.impactPos
	if CFG.USE_POSITIONAL_AUDIO and typeof(impactPos) == "Vector3" then
		detParent = makeWorldAnchor(impactPos)
	end

	-- ✅ EARLY DETONATION: plays shortly after Marker, BEFORE laser arrives.
	do
		local detDelay = tonumber(payload and payload.detDelay) or CFG.DET_DELAY_AFTER_MARKER
		detDelay = math.max(CFG.DET_MIN_DELAY, detDelay)

		task.delay(detDelay, function()
			if myToken ~= detToken then return end
			playOneShot(T.Detonation, detParent, CFG.VOL.DET, "LOW", 0)
		end)
	end

	-- Background ambience bed
	if T.Ambience then
		activeAmbience = T.Ambience:Clone()
		activeAmbience.Parent = SoundService
		activeAmbience.Volume = 0.05
		activeAmbience.PlaybackSpeed = 1.0
		activeAmbience.Looped = false
		activeAmbience:Play()
		ramp(activeAmbience, rampTime, CFG.VOL.AMBIENCE, 1.02)
	end

	-- Main charge
	local mainTemplate = T.OrbitalLaserCharge or T.ChargeUp
	if mainTemplate then
		activeChargeMain = mainTemplate:Clone()
		activeChargeMain.Parent = SoundService
		activeChargeMain.Volume = 0.08
		activeChargeMain.PlaybackSpeed = 0.88
		activeChargeMain.Looped = false
		activeChargeMain:Play()
		ramp(activeChargeMain, rampTime, CFG.VOL.CHARGE_MAIN, 1.15)
	end

	-- Under-bed rumble
	if T.SoulEntryRumble then
		activeChargeUnder = T.SoulEntryRumble:Clone()
		activeChargeUnder.Parent = SoundService
		activeChargeUnder.Volume = 0.03
		activeChargeUnder.PlaybackSpeed = 0.95
		activeChargeUnder.Looped = false
		activeChargeUnder:Play()
		ramp(activeChargeUnder, rampTime, CFG.VOL.CHARGE_UNDER, 1.0)
	end

	-- Optional: mechanical texture
	if T.MechanicalClicks then
		playOneShot(T.MechanicalClicks, SoundService, CFG.VOL.MECH, "MID", 0.15)
		playOneShot(T.MechanicalClicks, SoundService, CFG.VOL.MECH * 0.9, "MID", 0.45)
	end
end

local function onImpact(payload)
	-- invalidate any scheduled detonation (we don't want late re-fires)
	detToken += 1

	stopChargeAll()

	if T.TapeStop then
		playOneShot(T.TapeStop, SoundService, CFG.VOL.TAPESTOP, "MID", 0)
	end

	task.wait(CFG.PRE_IMPACT_SILENCE)

	local parent: Instance = SoundService
	local impactPos = payload and payload.impactPos
	if CFG.USE_POSITIONAL_AUDIO and typeof(impactPos) == "Vector3" then
		parent = makeWorldAnchor(impactPos)
	end

	-- IMPACT STACK (NO detonation here)
	playOneShot(T.OrbitalSubDrop, parent, CFG.VOL.SUBDROP, "LOW", 0)

	if T.CinematicImpactBoom then
		playOneShot(T.CinematicImpactBoom, parent, CFG.VOL.BOOM, "LOW", 0.01)
	end

	if T.Crack then
		playOneShot(T.Crack, parent, CFG.VOL.CRACK_HIGH, "HIGH", 0.035)
		playOneShot(T.Crack, parent, CFG.VOL.CRACK_LOW,  "LOW",  0.040)
	end

	if T.OrbitalElectricBlast then
		playOneShot(T.OrbitalElectricBlast, parent, CFG.VOL.ELECTRIC, "MID", 0.045)
		playOneShot(T.OrbitalElectricBlast, parent, CFG.VOL.ELECTRIC * 0.75, "HIGH", 0.060)
	end

	if T.SoulShatter then
		playOneShot(T.SoulShatter, parent, CFG.VOL.CRACK_EXTRA, "MID", 0.055)
	end

	if T.OrbitalMetalImpact then
		playOneShot(T.OrbitalMetalImpact, parent, CFG.VOL.METAL, "LOW", 0.07)
	end

	if T.EarRing then
		playOneShot(T.EarRing, SoundService, CFG.VOL.EARRING, "HIGH", 0.08)
	end

	if T.OrbitalCinematicRumble then
		playOneShotCapped(T.OrbitalCinematicRumble, parent, CFG.VOL.RUMBLE, "LOW", 0.12, CFG.RUMBLE_MAX, CFG.RUMBLE_FADE)
	end
	if T.SoulEntryRumble then
		playOneShotCapped(T.SoulEntryRumble, parent, CFG.VOL.SOULRUMBLE, "LOW", 0.16, CFG.SOULRUMBLE_MAX, CFG.SOULRUMBLE_FADE)
	end

	if T.Echo then
		playOneShot(T.Echo, parent, CFG.VOL.ECHO, "MID", 0.22)
	end
end

local function onCancel()
	detToken += 1
	stopChargeAll()
end

--============================================================
-- REMOTE LISTENER
--============================================================
FX.OnClientEvent:Connect(function(action, payload)
	if action == "Marker" then
		onMarker(payload)
	elseif action == "Impact" then
		onImpact(payload)
	elseif action == "Cancel" then
		onCancel()
	end
end)
