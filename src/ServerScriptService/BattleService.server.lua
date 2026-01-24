-- ServerScriptService/Systems/BattleService.server.lua
-- Bulletproof battle authority (server-owned enemy + server arena + strict phases)
-- ✅ AMENDED: OFF-THE-CHARTS arena VFX shell (cosmetic-only) + client animator signals

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Systems = ServerScriptService:WaitForChild("Systems")
local AwakeningService = require(Systems:WaitForChild("AwakeningService"))
local BattleData = require(ReplicatedStorage:WaitForChild("BattleData"))

-- Remotes folder
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local function ensureRE(name)
	local re = Remotes:FindFirstChild(name)
	if not re then
		re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = Remotes
	end
	return re
end

local BattleRE         = ensureRE("BattleRE")
local BulletHellRE     = ensureRE("BulletHellRE")
local Phase2Enter      = ensureRE("Phase2Enter")
local Phase2Exit       = ensureRE("Phase2Exit")
local BattleArenaVFXRE = ensureRE("BattleArenaVFXRE") -- NEW: cosmetic-only

local CONFIG = {
	AttackWindow = 6.0,
	AfterMenuActionDelay = 0.25,
	EnemyTurnMin = 3.0,
	EnemyTurnMax = 10.0,

	MaxMoveDamagePerHit = 80,
	MaxMoveDamagePerHitAfterMult = 250,
	MinDamageInterval = 0.08,
}

-- Arena teleport
local ARENA_Y = 9000
local ARENA_SPACING = 300

local function computeArenaCenter(plr: Player)
	return Vector3.new((plr.UserId % 50) * ARENA_SPACING, ARENA_Y, 0)
end

local function getHRP(plr: Player)
	local ch = plr.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local battles = {}

local function setPhase(plr, phase)
	plr:SetAttribute("__BattlePhase", phase) -- "Player" | "Phase2" | "Enemy" | "None"
end

local function setEnemyTurnId(plr, id)
	plr:SetAttribute("__EnemyTurnId", id or 0)
end

-- ============================================================
-- SERVER COLLISION ARENA (prevents void fall)
-- ============================================================
local ArenaRoot = workspace:FindFirstChild("__BattleArenas") or Instance.new("Folder")
ArenaRoot.Name = "__BattleArenas"
ArenaRoot.Parent = workspace

local ARENA_SIZE = Vector3.new(48, 1, 48) -- match your BulletHell3D arena size
local WALL_HEIGHT = 28
local WALL_THICKNESS = 2

local function destroyArena(plr: Player)
	local f = ArenaRoot:FindFirstChild(tostring(plr.UserId))
	if f then f:Destroy() end
end

local function makeArenaPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Metal
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false

	p.CanCollide = true
	p.CanTouch = false
	p.CanQuery = true

	p.Parent = parent
	return p
end

-- ============================================================
-- OFF-THE-CHARTS VFX SHELL (cosmetic-only)
-- ============================================================
local function addArenaVFX(folder: Folder, center: Vector3, halfX: number, halfZ: number, floorY: number, h: number)
	local vfx = Instance.new("Folder")
	vfx.Name = "VFX"
	vfx.Parent = folder

	-- Metadata for client animator
	folder:SetAttribute("__ArenaCenter", center)
	folder:SetAttribute("__ArenaHalfX", halfX)
	folder:SetAttribute("__ArenaHalfZ", halfZ)
	folder:SetAttribute("__ArenaFloorY", floorY)
	folder:SetAttribute("__ArenaWallH", h)

	-- Palette (edit here)
	local neonA = Color3.fromRGB(140, 70, 255)   -- purple
	local neonB = Color3.fromRGB(255, 40, 120)   -- hot pink
	local neonC = Color3.fromRGB(30, 255, 210)   -- cyan
	local dark  = Color3.fromRGB(8, 8, 10)

	local function makeVFXPart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, transparency: number)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Massless = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Transparency = transparency

		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CastShadow = false

		-- ✅ NEVER affect gameplay
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false

		p.Parent = vfx
		return p
	end

	-- 0) Under-floor void pad
	makeVFXPart("VoidPad", Vector3.new((halfX*2) + 36, 0.2, (halfZ*2) + 36),
		CFrame.new(center.X, floorY - 0.35, center.Z), dark, Enum.Material.SmoothPlastic, 0.35)

	-- 1) Neon rails near floor
	local railY = floorY + 0.12
	makeVFXPart("RailN", Vector3.new((halfX*2) - 1, 0.35, 0.35),
		CFrame.new(center.X, railY, center.Z - (halfZ - 0.8)), neonA, Enum.Material.Neon, 0.12)
	makeVFXPart("RailS", Vector3.new((halfX*2) - 1, 0.35, 0.35),
		CFrame.new(center.X, railY, center.Z + (halfZ - 0.8)), neonA, Enum.Material.Neon, 0.12)
	makeVFXPart("RailW", Vector3.new(0.35, 0.35, (halfZ*2) - 1),
		CFrame.new(center.X - (halfX - 0.8), railY, center.Z), neonC, Enum.Material.Neon, 0.16)
	makeVFXPart("RailE", Vector3.new(0.35, 0.35, (halfZ*2) - 1),
		CFrame.new(center.X + (halfX - 0.8), railY, center.Z), neonC, Enum.Material.Neon, 0.16)

	-- 2) Corner pillars + caps
	local pillarY = center.Y + (h * 0.5)
	local pillarSize = Vector3.new(0.7, h + 3, 0.7)
	local capSize = Vector3.new(2.2, 0.35, 2.2)
	local cornerOffsets = {
		{ "NW", Vector3.new(-halfX + 0.6, pillarY, -halfZ + 0.6), neonB },
		{ "NE", Vector3.new( halfX - 0.6, pillarY, -halfZ + 0.6), neonA },
		{ "SW", Vector3.new(-halfX + 0.6, pillarY,  halfZ - 0.6), neonA },
		{ "SE", Vector3.new( halfX - 0.6, pillarY,  halfZ - 0.6), neonB },
	}
	for _, c in ipairs(cornerOffsets) do
		local tag, off, col = c[1], c[2], c[3]
		makeVFXPart("Pillar"..tag, pillarSize, CFrame.new(center + off), col, Enum.Material.Neon, 0.22)
		makeVFXPart("Cap"..tag, capSize, CFrame.new((center + off) + Vector3.new(0, (h*0.5)+1.75, 0)), neonC, Enum.Material.Neon, 0.55)
	end

	-- 3) Layered floor glows
	makeVFXPart("FloorGlowA", Vector3.new((halfX*2) + 5, 0.12, (halfZ*2) + 5),
		CFrame.new(center.X, floorY + 0.05, center.Z), neonB, Enum.Material.Neon, 0.84)
	makeVFXPart("FloorGlowB", Vector3.new((halfX*2) + 12, 0.10, (halfZ*2) + 12),
		CFrame.new(center.X, floorY + 0.03, center.Z), neonA, Enum.Material.Neon, 0.92)

	-- 4) Mid-air frame rings
	local ringY = center.Y + (h * 0.55)
	makeVFXPart("MidRingN", Vector3.new((halfX*2) + 6, 0.22, 0.35),
		CFrame.new(center.X, ringY, center.Z - (halfZ + 1.0)), neonC, Enum.Material.Neon, 0.62)
	makeVFXPart("MidRingS", Vector3.new((halfX*2) + 6, 0.22, 0.35),
		CFrame.new(center.X, ringY, center.Z + (halfZ + 1.0)), neonC, Enum.Material.Neon, 0.62)
	makeVFXPart("MidRingW", Vector3.new(0.35, 0.22, (halfZ*2) + 6),
		CFrame.new(center.X - (halfX + 1.0), ringY, center.Z), neonC, Enum.Material.Neon, 0.68)
	makeVFXPart("MidRingE", Vector3.new(0.35, 0.22, (halfZ*2) + 6),
		CFrame.new(center.X + (halfX + 1.0), ringY, center.Z), neonC, Enum.Material.Neon, 0.68)

	-- 5) Roof plate anchor (client adds dome + beams + orbits)
	local roofY = center.Y + h + 2.6
	makeVFXPart("RoofGlow", Vector3.new((halfX*2) + 14, 0.35, (halfZ*2) + 14),
		CFrame.new(center.X, roofY, center.Z), neonA, Enum.Material.Neon, 0.80)

	-- 6) Beam anchors (attachments around a circle)
	local anchors = Instance.new("Folder")
	anchors.Name = "BeamAnchors"
	anchors.Parent = vfx

	local anchorHost = Instance.new("Part")
	anchorHost.Name = "AnchorHost"
	anchorHost.Anchored = true
	anchorHost.Transparency = 1
	anchorHost.CanCollide = false
	anchorHost.CanTouch = false
	anchorHost.CanQuery = false
	anchorHost.Size = Vector3.new(1, 1, 1)
	anchorHost.CFrame = CFrame.new(center.X, roofY, center.Z)
	anchorHost.Parent = anchors

	local N = 12
	local r = math.max(halfX, halfZ) + 6
	for i = 1, N do
		local a = Instance.new("Attachment")
		a.Name = ("A%d"):format(i)
		local ang = (i / N) * math.pi * 2
		a.Position = Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
		a.Parent = anchorHost
	end

	-- 7) Particles (mist + sparks) on FloorGlowA
	local floorHost = vfx:FindFirstChild("FloorGlowA")
	if floorHost and floorHost:IsA("BasePart") then
		local att = Instance.new("Attachment")
		att.Name = "EnergyAttachment"
		att.Parent = floorHost

		local mist = Instance.new("ParticleEmitter")
		mist.Name = "EnergyMist"
		mist.Enabled = true
		mist.Rate = 28
		mist.Lifetime = NumberRange.new(1.0, 2.2)
		mist.Speed = NumberRange.new(0.6, 2.2)
		mist.SpreadAngle = Vector2.new(35, 35)
		mist.Rotation = NumberRange.new(0, 360)
		mist.RotSpeed = NumberRange.new(-80, 80)
		mist.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(1, 0),
		})
		mist.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		mist.LightEmission = 0.85
		mist.Parent = att

		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Sparks"
		sparks.Enabled = true
		sparks.Rate = 10
		sparks.Lifetime = NumberRange.new(0.35, 0.75)
		sparks.Speed = NumberRange.new(6, 12)
		sparks.SpreadAngle = Vector2.new(20, 20)
		sparks.Drag = 5
		sparks.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparks.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		})
		sparks.LightEmission = 1
		sparks.Parent = att
	end

	vfx:SetAttribute("__VFXPack", "OFF_THE_CHARTS_V3")
end

local function buildArena(plr: Player)
	destroyArena(plr)

	local folder = Instance.new("Folder")
	folder.Name = tostring(plr.UserId)
	folder.Parent = ArenaRoot

	local center = computeArenaCenter(plr)
	local halfX = ARENA_SIZE.X * 0.5
	local halfZ = ARENA_SIZE.Z * 0.5
	local h = WALL_HEIGHT
	local t = WALL_THICKNESS

	local floorY = center.Y + (ARENA_SIZE.Y * 0.5)

	local floorColor = Color3.fromRGB(12, 12, 12)
	local wallColor  = Color3.fromRGB(0, 0, 0)

	-- ✅ REAL COLLISION PARTS (unchanged)
	makeArenaPart(folder, "Floor", ARENA_SIZE, CFrame.new(Vector3.new(center.X, floorY, center.Z)), floorColor)

	makeArenaPart(folder, "WallN", Vector3.new(ARENA_SIZE.X + t*2, h, t),
		CFrame.new(center + Vector3.new(0, h*0.5, -halfZ - t*0.5)), wallColor)

	makeArenaPart(folder, "WallS", Vector3.new(ARENA_SIZE.X + t*2, h, t),
		CFrame.new(center + Vector3.new(0, h*0.5,  halfZ + t*0.5)), wallColor)

	makeArenaPart(folder, "WallW", Vector3.new(t, h, ARENA_SIZE.Z),
		CFrame.new(center + Vector3.new(-halfX - t*0.5, h*0.5, 0)), wallColor)

	makeArenaPart(folder, "WallE", Vector3.new(t, h, ARENA_SIZE.Z),
		CFrame.new(center + Vector3.new( halfX + t*0.5, h*0.5, 0)), wallColor)

	-- ✅ VFX SHELL (cosmetic only)
	addArenaVFX(folder, center, halfX, halfZ, floorY, h)

	-- Tell client to animate VFX
	BattleArenaVFXRE:FireClient(plr, "ArenaSpawned", { arenaFolderName = folder.Name })
end

-- ============================================================
-- SERVER ENEMY (REAL HUMANOID)
-- ============================================================
local EnemyRoot = workspace:FindFirstChild("__BattleEnemies") or Instance.new("Folder")
EnemyRoot.Name = "__BattleEnemies"
EnemyRoot.Parent = workspace

local function disableScriptsIn(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d.Disabled = true
		end
	end
end

local function forcePrimaryPart(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart", true)
	if hrp and hrp:IsA("BasePart") then
		model.PrimaryPart = hrp
		return hrp
	end
	local any = model:FindFirstChildWhichIsA("BasePart", true)
	if any then
		model.PrimaryPart = any
		return any
	end
	return nil
end

local function ensureHumanoid(model: Model): Humanoid
	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	if not hum then
		hum = Instance.new("Humanoid")
		hum.Parent = model
	end
	hum.BreakJointsOnDeath = false
	return hum
end

local function anchorModel(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
end

local function destroyServerEnemy(plr: Player)
	local folder = EnemyRoot:FindFirstChild(tostring(plr.UserId))
	if folder then folder:Destroy() end
end

local function spawnServerEnemy(plr: Player, enemyId: string, maxHP: number)
	destroyServerEnemy(plr)

	local folder = Instance.new("Folder")
	folder.Name = tostring(plr.UserId)
	folder.Parent = EnemyRoot

	local def = BattleData.Enemies[enemyId]
	local modelName = (def and def.modelName) or enemyId

	local srcFolder = ReplicatedStorage:FindFirstChild("Enemies")
	local src = srcFolder and srcFolder:FindFirstChild(modelName)

	local model: Model
	if src and src:IsA("Model") then
		model = src:Clone()
	else
		model = Instance.new("Model")
		model.Name = modelName
		local p = Instance.new("Part")
		p.Name = "HumanoidRootPart"
		p.Size = Vector3.new(6, 8, 2)
		p.Parent = model
	end

	model.Name = "Enemy"
	model:SetAttribute("__BattleOwner", plr.UserId)
	model:SetAttribute("__BattleEnemy", true)

	disableScriptsIn(model)
	forcePrimaryPart(model)

	local hum = ensureHumanoid(model)
	hum.MaxHealth = maxHP
	hum.Health = maxHP

	anchorModel(model)
	model.Parent = folder

	local center = computeArenaCenter(plr)
	local pos = center + Vector3.new(0, 3, -18)
	model:PivotTo(CFrame.new(pos, center + Vector3.new(0, 3, 16)))

	return model, hum
end

local function syncEnemyHumanoid(b)
	if not b or not b.enemyHum or not b.enemyHum.Parent then return end
	local hum = b.enemyHum
	hum.MaxHealth = b.enemyMaxHP
	hum.Health = math.clamp(b.enemyHP, 0, b.enemyMaxHP)
end

-- ============================================================
-- TELEPORT BACK
-- ============================================================
local function teleportToArenaServer(plr: Player)
	local hrp = getHRP(plr)
	if not hrp then return end
	local center = computeArenaCenter(plr)
	hrp.CFrame = CFrame.new(center + Vector3.new(0, 3, 16), center + Vector3.new(0, 3, -18))
end

local function teleportBackServer(plr: Player)
	local hrp = getHRP(plr)
	local b = battles[plr]
	local cf = b and b._returnCFrame
	if hrp and typeof(cf) == "CFrame" then
		hrp.CFrame = cf
	end
	if b then b._returnCFrame = nil end
end

-- ============================================================
-- OUTCOME + CLEANUP
-- ============================================================
local function recordOutcomeOnce(plr, reason)
	local b = battles[plr]
	if not b or b._outcomeLogged then return end
	b._outcomeLogged = true

	if reason == "EnemyDefeated" then
		AwakeningService:RecordKill(plr, { source = "Battle", enemyId = b.enemyId })
	elseif reason == "Spared" then
		AwakeningService:RecordSpare(plr, { source = "Battle", enemyId = b.enemyId })
	end
end

local function cleanupBattle(plr)
	destroyServerEnemy(plr)
	destroyArena(plr)
	battles[plr] = nil
	setPhase(plr, "None")
	setEnemyTurnId(plr, 0)

	BattleArenaVFXRE:FireClient(plr, "ArenaDestroyed", {})
end

local function endBattle(plr, reason, victory)
	local b = battles[plr]
	if not b then return end
	if b._ending then return end
	b._ending = true

	Phase2Exit:FireClient(plr, { reason = "BattleEnd:" .. tostring(reason) })
	BulletHellRE:FireClient(plr, "Stop", { reason = "BattleEnd:" .. tostring(reason) })

	recordOutcomeOnce(plr, tostring(reason))

	if victory then
		BattleRE:FireClient(plr, "Victory", { reason = tostring(reason) })
	end
	BattleRE:FireClient(plr, "End", { reason = tostring(reason) })

	task.defer(function()
		teleportBackServer(plr)
		cleanupBattle(plr)
	end)
end

-- ============================================================
-- TURN FLOW
-- ============================================================
local function startEnemyTurn(plr)
	local b = battles[plr]
	if not b or not b.active then return end
	if b.enemyHP <= 0 then
		endBattle(plr, "EnemyDefeated", true)
		return
	end

	b.phase = "Enemy"
	setPhase(plr, "Enemy")

	b.enemyTurnId += 1
	setEnemyTurnId(plr, b.enemyTurnId)

	local enemy = BattleData.Enemies[b.enemyId]
	local atk = (enemy and enemy.attack) or { mode = "BulletHell3D", duration = 5 }
	local duration = math.clamp(tonumber(atk.duration) or 5, CONFIG.EnemyTurnMin, CONFIG.EnemyTurnMax)

	BattleRE:FireClient(plr, "EnemyTurnBegin", { turnId = b.enemyTurnId })
	BattleRE:FireClient(plr, "Text", { line = (enemy and enemy.attackLines and enemy.attackLines[1]) or "* The enemy attacks!" })

	if atk.mode == "BulletHell3D" then
		BulletHellRE:FireClient(plr, "Start", {
			phase = "Enemy",
			turnId = b.enemyTurnId,
			duration = duration,
			enemyId = b.enemyId,
			pattern = atk.pattern,
			params = atk.params,
		})
	end

	task.delay(duration, function()
		local bb = battles[plr]
		if not bb or not bb.active then return end
		if bb.phase ~= "Enemy" then return end
		if bb.enemyTurnId ~= b.enemyTurnId then return end

		BulletHellRE:FireClient(plr, "Stop", { reason = "EnemyTurnEnd", turnId = bb.enemyTurnId })
		BattleRE:FireClient(plr, "EnemyTurnEnd", { turnId = bb.enemyTurnId })

		bb.phase = "Player"
		bb.playerActed = false
		setPhase(plr, "Player")

		BattleRE:FireClient(plr, "PlayerTurn", {
			waiting = true,
			enemyHP = bb.enemyHP,
			enemyMaxHP = bb.enemyMaxHP,
		})
	end)
end

local function beginPlayerAttackWindow(plr)
	local b = battles[plr]
	if not b or not b.active then return end

	b.phase = "Phase2"
	setPhase(plr, "Phase2")

	b.turnToken += 1
	local token = b.turnToken
	b.attackEndsAt = os.clock() + CONFIG.AttackWindow
	b._phase2Finished = false

	Phase2Enter:FireClient(plr, { duration = CONFIG.AttackWindow })
	BattleRE:FireClient(plr, "PlayerAttackBegin", { timeLeft = CONFIG.AttackWindow })

	task.delay(CONFIG.AttackWindow, function()
		local bb = battles[plr]
		if not bb or not bb.active then return end
		if bb.turnToken ~= token then return end
		if bb.phase ~= "Phase2" then return end
		if bb._phase2Finished then return end

		bb._phase2Finished = true
		Phase2Exit:FireClient(plr, { reason = "AttackWindowEnd" })

		BattleRE:FireClient(plr, "PlayerAttackEnd", {})
		startEnemyTurn(plr)
	end)
end

-- ============================================================
-- DAMAGE (server-only)
-- ============================================================
local function applyDamage(plr: Player, rawAmount: any)
	local b = battles[plr]
	if not b or not b.active then return end
	if b.phase ~= "Phase2" then return end
	if os.clock() > (b.attackEndsAt or 0) then return end

	local now = os.clock()
	if (now - (b.lastDamageAt or 0)) < CONFIG.MinDamageInterval then return end
	b.lastDamageAt = now

	local amt = math.floor(tonumber(rawAmount) or 0)
	amt = math.clamp(amt, 0, CONFIG.MaxMoveDamagePerHit)
	if amt <= 0 then return end

	local mult = AwakeningService:GetOutgoingDamageMultiplier(plr, "Battle")
	amt = math.floor((amt * mult) + 0.5)
	amt = math.clamp(amt, 0, CONFIG.MaxMoveDamagePerHitAfterMult)
	if amt <= 0 then return end

	b.enemyHP = math.max(0, b.enemyHP - amt)
	syncEnemyHumanoid(b)

	BattleRE:FireClient(plr, "DamageResult", {
		amount = amt,
		enemyHP = b.enemyHP,
		enemyMaxHP = b.enemyMaxHP,
	})

	if b.enemyHP <= 0 then
		b._phase2Finished = true
		endBattle(plr, "EnemyDefeated", true)
	end
end

-- ============================================================
-- START BATTLE
-- ============================================================
local function startBattle(plr, enemyId)
	local enemy = BattleData.Enemies[enemyId]
	if not enemy then
		warn("[BattleService] Missing enemyId:", enemyId)
		return
	end

	if battles[plr] then
		endBattle(plr, "Restart", false)
	end

	local maxHP = tonumber(enemy.maxHP) or 30

	battles[plr] = {
		active = true,
		enemyId = enemyId,
		enemyHP = maxHP,
		enemyMaxHP = maxHP,

		phase = "Player",
		playerActed = false,

		enemyTurnId = 0,
		turnToken = 0,
		attackEndsAt = 0,

		lastDamageAt = 0,
		_outcomeLogged = false,
		_phase2Finished = false,

		_returnCFrame = nil,
		_ending = false,

		enemyModel = nil,
		enemyHum = nil,
	}

	local b = battles[plr]
	local hrp = getHRP(plr)
	if hrp then
		b._returnCFrame = hrp.CFrame
	end

	setEnemyTurnId(plr, 0)
	setPhase(plr, "Player")

	buildArena(plr)
	teleportToArenaServer(plr)

	local model, hum = spawnServerEnemy(plr, enemyId, maxHP)
	b.enemyModel = model
	b.enemyHum = hum

	hum.Died:Connect(function()
		local bb = battles[plr]
		if not bb or bb._ending then return end
		bb.enemyHP = 0
		endBattle(plr, "EnemyDefeated", true)
	end)

	BattleRE:FireClient(plr, "Begin", {
		enemyId = enemyId,
		enemyName = enemy.name or enemyId,
		enemyHP = maxHP,
		enemyMaxHP = maxHP,
		intro = enemy.intro or ("* " .. enemyId .. " appeared."),
	})

	BattleRE:FireClient(plr, "Text", { line = enemy.intro or ("* " .. enemyId .. " appeared.") })

	BattleRE:FireClient(plr, "PlayerTurn", {
		waiting = true,
		enemyHP = maxHP,
		enemyMaxHP = maxHP,
	})
end

local function handleAction(plr, payload)
	local b = battles[plr]
	if not b or not b.active then return end
	payload = payload or {}
	local t = tostring(payload.type or "")

	if t == "DealDamage" then
		applyDamage(plr, payload.amount)
		return
	end

	if b.phase ~= "Player" then return end
	if b.playerActed then return end
	b.playerActed = true

	if t == "Fight" or t == "EnterAttack" then
		BattleRE:FireClient(plr, "Text", { line = "* You move in." })
		beginPlayerAttackWindow(plr)
		return
	end

	if t == "Act" then
		BattleRE:FireClient(plr, "Text", { line = "* You check the enemy." })
		task.delay(CONFIG.AfterMenuActionDelay, function()
			if battles[plr] then startEnemyTurn(plr) end
		end)
		return
	end

	if t == "Item" then
		BattleRE:FireClient(plr, "Text", { line = "* You check your pockets.\n* Nothing useful." })
		task.delay(CONFIG.AfterMenuActionDelay, function()
			if battles[plr] then startEnemyTurn(plr) end
		end)
		return
	end

	if t == "Mercy" then
		local choice = tostring(payload.choice or "")
		if choice == "Flee" then
			BattleRE:FireClient(plr, "Text", { line = "* You fled." })
			task.delay(0.1, function()
				if battles[plr] then endBattle(plr, "Fled", false) end
			end)
			return
		end
		if choice == "Spare" then
			BattleRE:FireClient(plr, "Text", { line = "* You spared!" })
			task.delay(0.1, function()
				if battles[plr] then endBattle(plr, "Spared", true) end
			end)
			return
		end
	end

	b.playerActed = false
end

BattleRE.OnServerEvent:Connect(function(plr, kind, payload)
	if kind == "StartTest" then
		local b = battles[plr]
		if b and b.active then return end
		startBattle(plr, tostring(payload and payload.enemyId or "Froggit"))
		return
	end

	if kind == "Action" then
		handleAction(plr, payload)
		return
	end

	if kind == "End" then
		if battles[plr] then endBattle(plr, "ClientEnd", false) end
		return
	end
end)

-- ============================================================
-- STABLE PUBLIC API FOR WEAPON ROUTER
-- ============================================================
_G.BattleService = _G.BattleService or {}

_G.BattleService.GetSession = function(plr: Player)
	return battles[plr]
end

_G.BattleService.GetEnemyModel = function(plr: Player)
	local b = battles[plr]
	if not b or not b.active then return nil end
	return b.enemyModel
end

_G.BattleService.CanAcceptWeaponSwing = function(plr: Player)
	local b = battles[plr]
	if not b or not b.active then return false end
	if b._ending then return false end
	if b.phase ~= "Phase2" then return false end
	if os.clock() > (b.attackEndsAt or 0) then return false end
	return true
end

_G.BattleService.DealPhase2BattleDamage = function(plr: Player, amount: number)
	applyDamage(plr, amount)
end

Players.PlayerRemoving:Connect(function(plr)
	if battles[plr] then
		endBattle(plr, "PlayerLeaving", false)
	end
end)

print("[BattleService] Loaded (bulletproof arena + enemy + phases + OFF-THE-CHARTS VFX shell).")
