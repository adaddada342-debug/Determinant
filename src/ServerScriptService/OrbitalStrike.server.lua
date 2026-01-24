-- ServerScriptService/OrbitalStrike.server.lua
-- Orbital Strike VFX spawner (Marker -> 1s -> OrbitalCannon)
-- + Impact frames remote
-- + Server-authoritative radial damage
-- + FULL procedural cinematic sequence (no extra assets)
--   - charge halo + pilot beam
--   - shockwave ring + dust + smoke + afterglow
--   - 3-layer beam (core/body/atmosphere)
--   - constant stable spin

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

--============================================================
-- CONFIG (EDIT THESE ONLY)
--============================================================
local CONFIG = {
	VFX_FOLDER_PATH = {"VFX"},
	MARKER_NAME = "Marker",
	CANNON_NAME = "OrbitalCannon",

	SPAWN_FORWARD = 10,
	GROUND_Y_OFFSET = 0.0,

	DELAY_BEFORE_CANNON = 1.0,
	MARKER_FADE_IN = 0.25,
	CANNON_FADE_IN = 0.35,

	IMPACT_FRAME1 = 1/60,
	IMPACT_FRAME2 = 2/60,

	CLEANUP_AFTER = 6.0,
	SERVER_COOLDOWN = 2.0,

	RAY_UP = 8,
	RAY_DOWN = 250,

	ROT_OFFSET_MARKER = CFrame.Angles(math.rad(90), 0, 0),
	ROT_OFFSET_CANNON = CFrame.identity,

	MARKER_POS_OFFSET = Vector3.new(0, 0, 0),
	CANNON_POS_OFFSET = Vector3.new(0, 0, 0),

	DAMAGE_RADIUS = 18,
	DAMAGE_AMOUNT = 25,
	KNOCKBACK = 70,
	KNOCKBACK_UP = 35,

	FX_TO_ALL_CLIENTS = false,

	--========================
	-- SPIN (constant)
	--========================
	SPIN_ENABLED = true,
	SPIN_AXIS = "Y", -- "Y" = spin in place. Use "X" if you really want flipping.
	SPIN_RAD_PER_SEC = math.rad(1440), -- 4 rotations/sec

	--========================
	-- Procedural VFX tuning
	--========================
	BEAM_HEIGHT = 220,          -- how tall the beam is
	BEAM_LIFETIME = 2.6,        -- how long the beam stays before fading
	CHARGE_TIME = 0.6,          -- charge halo duration (within marker->cannon delay)
	PILOT_BEAM_TIME = 0.22,

	-- rings
	CHARGE_RING_START = 10,
	CHARGE_RING_END = 18,
	SHOCK_RING_START = 12,
	SHOCK_RING_END = 52,
	AFTERGLOW_START = 16,
	AFTERGLOW_END = 20,

	-- Colors
	COLOR_MAIN = Color3.fromRGB(120, 220, 255),
	COLOR_CORE = Color3.fromRGB(255, 255, 255),
	COLOR_BODY = Color3.fromRGB(80, 200, 255),
	COLOR_ATMOS = Color3.fromRGB(120, 220, 255),
}

--============================================================
-- REMOTE SETUP
--============================================================
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local RE = Remotes:FindFirstChild("OrbitalStrikeRequest")
if not RE then
	RE = Instance.new("RemoteEvent")
	RE.Name = "OrbitalStrikeRequest"
	RE.Parent = Remotes
end

local FX = Remotes:FindFirstChild("OrbitalStrikeFX")
if not FX then
	FX = Instance.new("RemoteEvent")
	FX.Name = "OrbitalStrikeFX"
	FX.Parent = Remotes
end

--============================================================
-- HELPERS
--============================================================
local function getFolder(root: Instance, path: {string}): Instance?
	local cur: Instance = root
	for _, name in ipairs(path) do
		cur = cur:FindFirstChild(name)
		if not cur then return nil end
	end
	return cur
end

local function getHRP(plr: Player): BasePart?
	local ch = plr.Character
	if not ch then return nil end
	return ch:FindFirstChild("HumanoidRootPart")
end

local function ensurePrimaryPart(m: Model): BasePart?
	if m.PrimaryPart and m.PrimaryPart:IsA("BasePart") then
		return m.PrimaryPart
	end
	local pp = m:FindFirstChildWhichIsA("BasePart", true)
	if pp then
		m.PrimaryPart = pp
	end
	return pp
end

local function raycastToGround(origin: Vector3): (Vector3, Vector3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local ignore = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	params.FilterDescendantsInstances = ignore

	local result = workspace:Raycast(origin + Vector3.new(0, CONFIG.RAY_UP, 0), Vector3.new(0, -CONFIG.RAY_DOWN, 0), params)
	if result then
		return result.Position, result.Normal
	end
	return origin, Vector3.new(0, 1, 0)
end

local function collectTargets(container: Instance)
	local parts = {}
	local beams = {}
	local emitters = {}
	local lights = {}

	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("Beam") then
			table.insert(beams, d)
		elseif d:IsA("ParticleEmitter") then
			table.insert(emitters, d)
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			table.insert(lights, d)
		end
	end
	return parts, beams, emitters, lights
end

local function setBeamAlpha(beam: Beam, alpha: number)
	beam.Transparency = NumberSequence.new(alpha)
end

local function fadeInModel(model: Model, duration: number)
	local parts, beams, emitters, lights = collectTargets(model)

	local originalPartTrans = {}
	local originalLight = {}
	local originalBeamTrans = {}
	local originalEmitterEnabled = {}

	for _, p in ipairs(parts) do
		originalPartTrans[p] = p.Transparency
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
	end

	for _, l in ipairs(lights) do
		originalLight[l] = {Brightness = l.Brightness, Enabled = l.Enabled}
		l.Enabled = true
		l.Brightness = 0
	end

	for _, b in ipairs(beams) do
		originalBeamTrans[b] = b.Transparency
		setBeamAlpha(b, 1)
		b.FaceCamera = false
	end

	for _, e in ipairs(emitters) do
		originalEmitterEnabled[e] = e.Enabled
		e.Enabled = false
	end

	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, p in ipairs(parts) do
		TweenService:Create(p, info, {Transparency = originalPartTrans[p] or 0}):Play()
	end
	for _, l in ipairs(lights) do
		local targetB = (originalLight[l] and originalLight[l].Brightness) or 1
		TweenService:Create(l, info, {Brightness = targetB}):Play()
	end

	task.spawn(function()
		local t0 = os.clock()
		while true do
			local a = (os.clock() - t0) / duration
			if a >= 1 then break end
			local alpha = 1 - a
			for _, b in ipairs(beams) do
				setBeamAlpha(b, alpha)
			end
			task.wait()
		end
		for _, b in ipairs(beams) do
			if originalBeamTrans[b] then
				b.Transparency = originalBeamTrans[b]
			else
				setBeamAlpha(b, 0)
			end
		end
	end)

	task.delay(math.max(0.05, duration * 0.35), function()
		for _, e in ipairs(emitters) do
			e.Enabled = (originalEmitterEnabled[e] ~= nil) and originalEmitterEnabled[e] or true
		end
	end)
end

local function pivotModelTo(model: Model, worldPos: Vector3, rotOffset: CFrame)
	ensurePrimaryPart(model)
	model:PivotTo(CFrame.new(worldPos) * rotOffset)
end

--============================================================
-- STABLE CONSTANT SPIN (no wobble)
--============================================================
local function spinModelConstant(model: Model, radPerSec: number, axis: string)
	if not model or not model.Parent then return end
	radPerSec = radPerSec or 0
	axis = axis or "Y"

	ensurePrimaryPart(model)

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end

	local basePivot = model:GetPivot()
	local angle = 0
	local axisVec =
		(axis == "X" and Vector3.new(1, 0, 0)) or
		(axis == "Z" and Vector3.new(0, 0, 1)) or
		Vector3.new(0, 1, 0)

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent then
			if conn then conn:Disconnect() end
			return
		end
		angle += radPerSec * dt
		model:PivotTo(basePivot * CFrame.fromAxisAngle(axisVec, angle))
	end)
end

--============================================================
-- PROCEDURAL VFX (no assets required)
--============================================================
local function makeNeonPart(name: string)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.CastShadow = false
	return p
end

local function spawnRing(pos: Vector3, yOffset: number, startSize: number, endSize: number, startTrans: number, endTrans: number, duration: number, color: Color3)
	local ring = makeNeonPart("Ring")
	ring.Color = color
	ring.Transparency = startTrans
	ring.Size = Vector3.new(startSize, 0.25, startSize)
	ring.CFrame = CFrame.new(pos + Vector3.new(0, yOffset, 0)) * CFrame.Angles(math.rad(90), 0, 0)

	local mesh = Instance.new("CylinderMesh")
	mesh.Parent = ring

	ring.Parent = workspace

	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, {
		Size = Vector3.new(endSize, 0.25, endSize),
		Transparency = endTrans,
	}):Play()

	Debris:AddItem(ring, duration + 0.35)
	return ring
end

local function spawnPilotBeam(pos: Vector3, height: number, duration: number, color: Color3)
	local beam = makeNeonPart("PilotBeam")
	beam.Color = color
	beam.Transparency = 0.35
	beam.Size = Vector3.new(0.7, height, 0.7)
	beam.CFrame = CFrame.new(pos + Vector3.new(0, height/2, 0))
	beam.Parent = workspace

	TweenService:Create(beam, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1}):Play()
	Debris:AddItem(beam, duration + 0.2)
	return beam
end

local function spawnBeamLayer(pos: Vector3, height: number, radius: number, color: Color3, transparency: number, fadeOutTime: number, name: string)
	local p = makeNeonPart(name)
	p.Color = color
	p.Transparency = transparency
	p.Size = Vector3.new(radius * 2, height, radius * 2)
	p.CFrame = CFrame.new(pos + Vector3.new(0, height/2, 0))
	p.Shape = Enum.PartType.Cylinder
	p.Orientation = Vector3.new(0, 0, 90) -- stand the cylinder upright

	p.Parent = workspace

	task.delay(math.max(0, fadeOutTime), function()
		if p.Parent then
			TweenService:Create(p, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1}):Play()
		end
	end)

	Debris:AddItem(p, fadeOutTime + 0.6)
	return p
end

local function spawnDustBurst(pos: Vector3)
	local p = Instance.new("Part")
	p.Name = "DustBurst"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(1,1,1)
	p.CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0))
	p.Parent = workspace

	local em = Instance.new("ParticleEmitter")
	em.Rate = 0
	em.Lifetime = NumberRange.new(0.6, 1.2)
	em.Speed = NumberRange.new(14, 26)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Rotation = NumberRange.new(0, 360)
	em.RotSpeed = NumberRange.new(-140, 140)
	em.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 3.4),
	})
	em.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	em.Parent = p

	em:Emit(90)
	Debris:AddItem(p, 1.6)
end

local function spawnSmokeColumn(pos: Vector3)
	local p = Instance.new("Part")
	p.Name = "SmokeColumn"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(1,1,1)
	p.CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0))
	p.Parent = workspace

	local em = Instance.new("ParticleEmitter")
	em.Rate = 40
	em.Lifetime = NumberRange.new(1.6, 2.9)
	em.Speed = NumberRange.new(2, 6)
	em.SpreadAngle = Vector2.new(20, 20)
	em.Rotation = NumberRange.new(0, 360)
	em.RotSpeed = NumberRange.new(-60, 60)
	em.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.0),
		NumberSequenceKeypoint.new(1, 7.0),
	})
	em.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	em.Parent = p

	task.delay(3.2, function()
		if em.Parent then em.Rate = 0 end
	end)

	Debris:AddItem(p, 4.2)
end

--============================================================
-- DAMAGE
--============================================================
--============================================================
-- DAMAGE (Battle-aware)
--============================================================
local function applyOrbitalDamage(caster: Player, center: Vector3)
	-- 1) If we're in a battle session, damage the battle enemy via BattleService
	local BS = _G.BattleService
	if BS and BS.GetSession and BS.GetEnemyModel then
		local session = BS.GetSession(caster)
		if session and session.active then
			local enemyModel = BS.GetEnemyModel(caster)
			if enemyModel and enemyModel.Parent then
				local enemyRoot =
					(enemyModel.PrimaryPart and enemyModel.PrimaryPart:IsA("BasePart") and enemyModel.PrimaryPart)
					or enemyModel:FindFirstChild("HumanoidRootPart", true)
					or enemyModel:FindFirstChildWhichIsA("BasePart", true)

				if enemyRoot and (enemyRoot.Position - center).Magnitude <= CONFIG.DAMAGE_RADIUS then
					-- IMPORTANT: keep battle HP authoritative
					if BS.DealPhase2BattleDamage then
						BS.DealPhase2BattleDamage(caster, CONFIG.DAMAGE_AMOUNT)
					else
						-- Fallback: if your BattleService API changes, at least damage the humanoid
						local hum = enemyModel:FindFirstChildWhichIsA("Humanoid", true)
						if hum and hum.Health > 0 then
							hum:TakeDamage(CONFIG.DAMAGE_AMOUNT)
						end
					end

					-- Optional knockback in battle (usually you *don't* want this)
					return
				end
			end
			-- If we're in battle but missed the enemy by radius, do nothing (prevents nuking random stuff at Y=9000)
			return
		end
	end

	-- 2) Overworld / non-battle: AoE scan all non-player humanoids in radius
	local radius = CONFIG.DAMAGE_RADIUS
	local radiusSq = radius * radius

	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Humanoid") then
			local hum = inst
			if hum.Health > 0 then
				local model = hum.Parent
				if model and model:IsA("Model") then
					-- Ignore players
					if Players:GetPlayerFromCharacter(model) == nil then
						local hrp = model:FindFirstChild("HumanoidRootPart")
						if hrp and hrp:IsA("BasePart") then
							local offset = hrp.Position - center
							if offset:Dot(offset) <= radiusSq then
								hum:TakeDamage(CONFIG.DAMAGE_AMOUNT)

								local dir = offset.Magnitude > 0.001 and offset.Unit or Vector3.new(0, 1, 0)
								local bv = Instance.new("BodyVelocity")
								bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
								bv.Velocity = dir * CONFIG.KNOCKBACK + Vector3.new(0, CONFIG.KNOCKBACK_UP, 0)
								bv.Parent = hrp
								Debris:AddItem(bv, 0.15)
							end
						end
					end
				end
			end
		end
	end
end


local function fireImpactFrames(plr: Player)
	local payload = { frame1 = CONFIG.IMPACT_FRAME1, frame2 = CONFIG.IMPACT_FRAME2 }
	if CONFIG.FX_TO_ALL_CLIENTS then
		FX:FireAllClients("Impact", payload)
	else
		FX:FireClient(plr, "Impact", payload)
	end
end

--============================================================
-- COOLDOWN
--============================================================
local lastCast: {[Player]: number} = {}

local function canCast(plr: Player): boolean
	local now = os.clock()
	local prev = lastCast[plr] or -1e9
	if now - prev < CONFIG.SERVER_COOLDOWN then
		return false
	end
	lastCast[plr] = now
	return true
end

Players.PlayerRemoving:Connect(function(plr)
	lastCast[plr] = nil
end)

--============================================================
-- MAIN
--============================================================
RE.OnServerEvent:Connect(function(plr: Player)
	if not canCast(plr) then return end

	local hrp = getHRP(plr)
	if not hrp then return end

	local vfxFolder = getFolder(ReplicatedStorage, CONFIG.VFX_FOLDER_PATH)
	if not vfxFolder then
		warn("OrbitalStrike: Missing ReplicatedStorage/" .. table.concat(CONFIG.VFX_FOLDER_PATH, "/"))
		return
	end

	local markerSrc = vfxFolder:FindFirstChild(CONFIG.MARKER_NAME)
	local cannonSrc = vfxFolder:FindFirstChild(CONFIG.CANNON_NAME)
	if not markerSrc or not cannonSrc then
		warn("OrbitalStrike: Missing VFX models:", CONFIG.MARKER_NAME, CONFIG.CANNON_NAME)
		return
	end
	if not markerSrc:IsA("Model") or not cannonSrc:IsA("Model") then
		warn("OrbitalStrike: Marker/Cannon must be Models.")
		return
	end

	local desired = hrp.Position + hrp.CFrame.LookVector * CONFIG.SPAWN_FORWARD
	local hitPos = select(1, raycastToGround(desired))
	hitPos = hitPos + Vector3.new(0, CONFIG.GROUND_Y_OFFSET, 0)

	-- Marker
	local marker = markerSrc:Clone()
	marker.Parent = workspace
	pivotModelTo(marker, hitPos + CONFIG.MARKER_POS_OFFSET, CONFIG.ROT_OFFSET_MARKER)
	fadeInModel(marker, CONFIG.MARKER_FADE_IN)
	Debris:AddItem(marker, CONFIG.CLEANUP_AFTER)

	-- Anticipation: charge ring immediately
	spawnRing(hitPos, 0.05, CONFIG.CHARGE_RING_START, CONFIG.CHARGE_RING_END, 0.7, 0.35, CONFIG.CHARGE_TIME, CONFIG.COLOR_MAIN)

	-- Pilot beam slightly before cannon spawn
	task.delay(math.max(0, CONFIG.DELAY_BEFORE_CANNON - CONFIG.PILOT_BEAM_TIME), function()
		spawnPilotBeam(hitPos, CONFIG.BEAM_HEIGHT, CONFIG.PILOT_BEAM_TIME, CONFIG.COLOR_MAIN)
	end)

	-- Cannon after delay (Impact happens HERE)
	task.delay(CONFIG.DELAY_BEFORE_CANNON, function()
		if not marker.Parent then return end

		local cannon = cannonSrc:Clone()
		cannon.Parent = workspace
		pivotModelTo(cannon, hitPos + CONFIG.CANNON_POS_OFFSET, CONFIG.ROT_OFFSET_CANNON)
		fadeInModel(cannon, CONFIG.CANNON_FADE_IN)
		Debris:AddItem(cannon, CONFIG.CLEANUP_AFTER)

		-- 3-layer beam (procedural, so no asset work)
		-- Core: thin + bright
		spawnBeamLayer(hitPos, CONFIG.BEAM_HEIGHT, 1.2, CONFIG.COLOR_CORE, 0.08, CONFIG.BEAM_LIFETIME, "BeamCore")
		-- Body: thicker
		spawnBeamLayer(hitPos, CONFIG.BEAM_HEIGHT, 2.6, CONFIG.COLOR_BODY, 0.22, CONFIG.BEAM_LIFETIME, "BeamBody")
		-- Atmosphere: fattest + faintest
		spawnBeamLayer(hitPos, CONFIG.BEAM_HEIGHT, 4.8, CONFIG.COLOR_ATMOS, 0.55, CONFIG.BEAM_LIFETIME, "BeamAtmos")

		-- Impact ground reaction (procedural)
		spawnRing(hitPos, 0.07, CONFIG.SHOCK_RING_START, CONFIG.SHOCK_RING_END, 0.25, 1.0, 0.25, CONFIG.COLOR_MAIN)
		spawnDustBurst(hitPos)
		spawnSmokeColumn(hitPos)
		spawnRing(hitPos, 0.03, CONFIG.AFTERGLOW_START, CONFIG.AFTERGLOW_END, 0.6, 1.0, 1.2, CONFIG.COLOR_MAIN)

		-- Constant spin (cannon geometry spins; procedural particles are separate parts so they don't “spin ugly”)
		if CONFIG.SPIN_ENABLED then
			spinModelConstant(cannon, CONFIG.SPIN_RAD_PER_SEC, CONFIG.SPIN_AXIS)
		end

		-- Impact frames + damage
		fireImpactFrames(plr)
		applyOrbitalDamage(plr, hitPos)
	end)
end)
