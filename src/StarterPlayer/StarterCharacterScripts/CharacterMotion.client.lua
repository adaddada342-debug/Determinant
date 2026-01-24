--!strict
-- StarterCharacterScripts/AAAPolish_Character.client.lua
-- Character polish: procedural lean + head follow + material-based footsteps + subtle cloth/whoosh.

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Config = {
	Enable = {
		ProceduralLean = true,
		HeadFollow = true,
		Footsteps = true,
		ClothRustle = true,
	},

	-- Procedural lean (Motor6D.Transform)
	Lean = {
		MaxDegrees = 8,        -- torso lean when strafing/accelerating
		Responsiveness = 10,
		Damping = 14,
	},

	-- Head follow (small, to sell "alive")
	Head = {
		MaxDegrees = 6,
		Responsiveness = 9,
	},

	-- Footsteps
	Footsteps = {
		StepIntervalWalk = 0.42,  -- seconds per step at walkRef
		WalkRefSpeed = 10,
		SprintRefSpeed = 20,
		Volume = 0.18,
		PitchMin = 0.96,
		PitchMax = 1.06,
		MinSpeedToStep = 2.5,
	},

	-- Cloth rustle (subtle speed-based loop)
	Cloth = {
		SoundId = "rbxassetid://0", -- optional; if 0, rustle disabled unless you provide a real sound
		MaxVolume = 0.12,
		MinVolume = 0.0,
		MinSpeed = 3,
		MaxSpeed = 20,
		Responsiveness = 10,
	},

	-- Footstep sound ids by material (use your own; safe fallback included)
	-- If an id is "0", it will skip that material and use Default.
	FootstepSounds = {
		Default = "rbxassetid://0",
		[Enum.Material.Grass] = "rbxassetid://0",
		[Enum.Material.Ground] = "rbxassetid://0",
		[Enum.Material.Sand] = "rbxassetid://0",
		[Enum.Material.Concrete] = "rbxassetid://0",
		[Enum.Material.Asphalt] = "rbxassetid://0",
		[Enum.Material.Metal] = "rbxassetid://0",
		[Enum.Material.Wood] = "rbxassetid://0",
		[Enum.Material.WoodPlanks] = "rbxassetid://0",
	},
}

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------
local RunService = game:GetService("RunService")

----------------------------------------------------------------
-- UTILS
----------------------------------------------------------------
local function expAlpha(k: number, dt: number): number
	if k <= 0 then return 1 end
	return 1 - math.exp(-k * dt)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

local function rad(deg: number): number
	return deg * math.pi / 180
end

----------------------------------------------------------------
-- SETUP
----------------------------------------------------------------
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart

-- Try to find R15 motors. If R6, we just do footsteps and cloth.
local upperTorso = character:FindFirstChild("UpperTorso")
local head = character:FindFirstChild("Head")

local waist: Motor6D? = nil
local neck: Motor6D? = nil

if upperTorso then
	waist = (upperTorso:FindFirstChild("Waist") :: Motor6D?) or nil
end
if head then
	neck = (head:FindFirstChild("Neck") :: Motor6D?) or nil
end

-- Cache original transforms
local waistBase = CFrame.identity
local neckBase = CFrame.identity
if waist then waistBase = waist.Transform end
if neck then neckBase = neck.Transform end

-- Footstep sounds: create a small pool of Sound instances (no per-step Instance.new)
local soundFolder = Instance.new("Folder")
soundFolder.Name = "AAAPolish_Sounds"
soundFolder.Parent = character

local stepSounds: { [string]: Sound } = {}
local function getOrMakeSound(key: string, soundId: string): Sound
	local s = stepSounds[key]
	if s then return s end
	local ns = Instance.new("Sound")
	ns.Name = key
	ns.SoundId = soundId
	ns.Volume = 0
	ns.RollOffMode = Enum.RollOffMode.InverseTapered
	ns.RollOffMaxDistance = 35
	ns.RollOffMinDistance = 8
	ns.Parent = soundFolder
	stepSounds[key] = ns
	return ns
end

local clothSound: Sound? = nil
if Config.Enable.ClothRustle and Config.Cloth.SoundId ~= "rbxassetid://0" then
	local s = Instance.new("Sound")
	s.Name = "ClothRustle"
	s.SoundId = Config.Cloth.SoundId
	s.Looped = true
	s.Volume = 0
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = 40
	s.RollOffMinDistance = 10
	s.Parent = soundFolder
	clothSound = s
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local lastVel = Vector3.zero
local stepTimer = 0.0
local leanX = 0.0
local leanZ = 0.0
local headYaw = 0.0
local headPitch = 0.0
local clothVol = 0.0

local function chooseFootstepId(mat: Enum.Material): string
	local id = Config.FootstepSounds[mat]
	if typeof(id) == "string" and id ~= "rbxassetid://0" then
		return id
	end
	return Config.FootstepSounds.Default
end

local function playFootstep()
	if not Config.Enable.Footsteps then return end

	local id = chooseFootstepId(humanoid.FloorMaterial)
	if not id or id == "rbxassetid://0" then
		return -- safe: user didn't provide ids
	end

	local key = "Step_" .. tostring(humanoid.FloorMaterial)
	local s = getOrMakeSound(key, id)

	-- update sound id if changed
	if s.SoundId ~= id then s.SoundId = id end

	-- subtle pitch variance
	local speed = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
	local t = clamp(speed / Config.Footsteps.SprintRefSpeed, 0, 1)
	s.Volume = Config.Footsteps.Volume * (0.75 + 0.25 * t)
	s.PlaybackSpeed = lerp(Config.Footsteps.PitchMin, Config.Footsteps.PitchMax, math.random())

	-- Restart cleanly (no overlap chaos)
	s:Stop()
	s:Play()
end

----------------------------------------------------------------
-- LOOP
----------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt: number)
	local v = hrp.AssemblyLinearVelocity
	local horizontalVel = Vector3.new(v.X, 0, v.Z)
	local speed = horizontalVel.Magnitude

	-- Procedural lean (R15 only)
	if Config.Enable.ProceduralLean and waist then
		local dv = (horizontalVel - Vector3.new(lastVel.X, 0, lastVel.Z))
		lastVel = v

		local localMove = hrp.CFrame:VectorToObjectSpace(humanoid.MoveDirection)
		local localDv = hrp.CFrame:VectorToObjectSpace(dv)

		-- Lean into strafe + a touch into acceleration
		local targetX = clamp(localMove.X, -1, 1) * rad(Config.Lean.MaxDegrees)
		local targetZ = clamp(-localDv.Z * 0.003, -1, 1) * rad(Config.Lean.MaxDegrees * 0.55)

		local a = expAlpha(Config.Lean.Responsiveness, dt)
		leanX = lerp(leanX, targetX, a)
		leanZ = lerp(leanZ, targetZ, a)

		waist.Transform = waistBase * CFrame.Angles(0, 0, -leanX) * CFrame.Angles(leanZ, 0, 0)
	end

	-- Head follow (R15 only, subtle)
	if Config.Enable.HeadFollow and neck then
		-- Use camera look direction if available (best effort, no hard dependency)
		local cam = workspace.CurrentCamera
		if cam then
			local look = cam.CFrame.LookVector
			-- Convert look into HRP local to get yaw/pitch
			local localLook = hrp.CFrame:VectorToObjectSpace(look)
			local targetYaw = clamp(-math.atan2(localLook.X, -localLook.Z), -rad(Config.Head.MaxDegrees), rad(Config.Head.MaxDegrees))
			local targetPitch = clamp(math.asin(clamp(localLook.Y, -1, 1)) * 0.6, -rad(Config.Head.MaxDegrees), rad(Config.Head.MaxDegrees))

			local a = expAlpha(Config.Head.Responsiveness, dt)
			headYaw = lerp(headYaw, targetYaw, a)
			headPitch = lerp(headPitch, targetPitch, a)

			neck.Transform = neckBase * CFrame.Angles(headPitch, headYaw, 0)
		end
	end

	-- Footsteps
	if Config.Enable.Footsteps then
		local moving = humanoid.MoveDirection.Magnitude > 0.05 and speed > Config.Footsteps.MinSpeedToStep
		if moving and humanoid.FloorMaterial ~= Enum.Material.Air then
			local stepBase = Config.Footsteps.StepIntervalWalk
			local t = clamp(speed / Config.Footsteps.WalkRefSpeed, 0.6, 1.6)
			local interval = stepBase / t

			stepTimer += dt
			if stepTimer >= interval then
				stepTimer -= interval
				playFootstep()
			end
		else
			stepTimer = 0
		end
	end

	-- Cloth rustle loop (optional)
	if clothSound then
		local t = clamp((speed - Config.Cloth.MinSpeed) / (Config.Cloth.MaxSpeed - Config.Cloth.MinSpeed), 0, 1)
		local targetVol = lerp(Config.Cloth.MinVolume, Config.Cloth.MaxVolume, t)
		clothVol = lerp(clothVol, targetVol, expAlpha(Config.Cloth.Responsiveness, dt))
		clothSound.Volume = clothVol
		clothSound.PlaybackSpeed = lerp(0.96, 1.06, t)

		if clothVol > 0.02 then
			if not clothSound.IsPlaying then clothSound:Play() end
		else
			if clothSound.IsPlaying then clothSound:Stop() end
		end
	end
end)

script.Destroying:Connect(function()
	-- Restore motor transforms
	if waist then waist.Transform = waistBase end
	if neck then neck.Transform = neckBase end
end)
