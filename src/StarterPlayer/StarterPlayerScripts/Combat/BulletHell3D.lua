-- StarterPlayerScripts/Combat/BulletHell3D.lua
-- 3D top-down bullet hell centered on player.
-- AMENDED:
--   + Persistent black 3D arena
--   + TRUE birds-eye camera lock (yaw first, then pitch) + hard lock every frame
--   + Adds "VoidCover" mega floor under arena to hide the void from birds-eye camera
--   + NEW (Patience): bullets slow down the more you move (Patience-only)
--   + NEW (Patience): random skill-check event; failing triggers an extreme barrage

local BulletHell3D = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local cam = Workspace.CurrentCamera

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BattleRE = Remotes:WaitForChild("BattleRE")

local CONFIG = {
	-- Arena
	ArenaSize = Vector3.new(48, 1, 48),
	WallHeight = 28,
	WallThickness = 2,

	-- Void cover (hides the void)
	VoidCoverSize = Vector3.new(1200, 4, 1200),
	VoidCoverYOffset = -6,
	VoidCoverColor = Color3.fromRGB(0, 0, 0),
	VoidCoverMaterial = Enum.Material.SmoothPlastic,
	VoidCoverTransparency = 0,

	-- Soul
	SoulSize = Vector3.new(1.2, 1.2, 1.2),
	SoulSpeed = 28,
	SoulPadding = 1.2,

	-- Bullets (normal)
	BulletSize = Vector3.new(1, 1, 1),
	BulletSpawnEvery = 0.14,
	BulletExtraChance = 0.25,
	BulletSpeedMin = 26,
	BulletSpeedMax = 42,
	BulletSideDrift = 14,

	-- Client hit report debounce (server still validates)
	ClientHitDebounce = 0.08,

	-- Camera (TRUE birds-eye)
	CameraHeight = 65,
	CameraYaw = 0,
	CameraTweenIn = 0.20,
	CameraTweenOut = 0.25,

	-- Fade avatar during enemy turn
	FadeTo = 1,

	--============================================================
	-- PATIENCE SOUL MECHANICS
	--============================================================
	PATIENCE = {
		-- How we detect the current soul on the player
		ATTR_NAMES = { "CurrentSoul", "Soul", "__Soul", "__CurrentSoul", "SoulType" },
		SOUL_NAMES = { "patience" }, -- lowercase compare

		-- Passive effect: bullets slow more when you move more (Patience only)
		-- speedMult = lerp(SLOW_AT_STILL, SLOW_AT_FULL_MOVE, moveFactor)
		-- moveFactor = 0..1 where 1 means moving at max SoulSpeed
		SLOW_AT_STILL = 1.00,       -- standing still -> normal bullet speed
		SLOW_AT_FULL_MOVE = 0.35,   -- moving a lot -> bullets crawl

		-- Random skill-check event (Patience only)
		EVENT_CHANCE = 0.32,        -- 32% chance per BulletHell run
		EVENT_MIN_TIME = 1.4,       -- don't trigger instantly
		EVENT_COOLDOWN = 6.0,       -- no repeat while running (seconds)
		CHECK_DURATION = 1.8,       -- window where we measure "movement"
		FAIL_MOVE_INTEGRAL = 22.0,  -- higher = more forgiving (units ~ studs)

		-- During the check, we keep the passive slow active AND track movement.
		-- If fail -> execute barrage.
		BARRAGE_DURATION = 0.55,
		BARRAGE_SPAWN_EVERY = 0.03,
		BARRAGE_ROWS_PER_TICK = 2,  -- how many "walls" per tick
		BARRAGE_SPEED = 110,        -- absurd speed
		BARRAGE_BULLET_SIZE = Vector3.new(1.2, 1.2, 1.2),
		BARRAGE_COLOR = Color3.fromRGB(245, 245, 255),

		-- If you want the barrage to be *literally* undodgeable, keep GAP = 0
		-- If you want “barely possible if god gamer”, set GAP ~ 1.8 to 2.6
		BARRAGE_GAP_WIDTH = 0.0,    -- studs of safety gap; 0 = none
	},
}

--============================================================
-- State
--============================================================
local running = false
local persistentArena = false

local arenaFolder : Folder? = nil
local arenaFloor : BasePart? = nil
local voidCover : BasePart? = nil
local soul : BasePart? = nil
local bullets = {} -- {id=string, part=BasePart, vel=Vector3}

local moveX, moveZ = 0, 0
local spawnT = 0
local hitDebounce = 0

local oldCamType, oldCamSubject, oldCamCFrame = nil, nil, nil
local charFadeCache = {}
local charCollideCache = {}

local inputBeganConn, inputEndedConn, renderConn

-- Patience event state
local patienceEventNextAllowed = 0
local patienceEventTriggered = false
local patienceCheckActive = false
local patienceCheckEndsAt = 0
local patienceMoveIntegral = 0

local barrageActive = false
local barrageEndsAt = 0
local barrageSpawnT = 0

--============================================================
-- Helpers
--============================================================
local function clamp(v, a, b)
	if v < a then return a end
	if v > b then return b end
	return v
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function getChar()
	return player.Character
end

local function setCharFaded(on: boolean)
	local c = getChar()
	if not c then return end

	for _, inst in ipairs(c:GetDescendants()) do
		if inst:IsA("BasePart") then
			if on then
				if charFadeCache[inst] == nil then
					charFadeCache[inst] = inst.LocalTransparencyModifier
					charCollideCache[inst] = inst.CanCollide
				end
				inst.LocalTransparencyModifier = CONFIG.FadeTo
				inst.CanCollide = false
			else
				inst.LocalTransparencyModifier = charFadeCache[inst] or 0
				if charCollideCache[inst] ~= nil then
					inst.CanCollide = charCollideCache[inst]
				end
			end
		end
	end

	if not on then
		table.clear(charFadeCache)
		table.clear(charCollideCache)
	end
end

-- Birds-eye CFrame: yaw first (world Y), then pitch down
local function birdsEyeCFrame(center: Vector3)
	local camPos = center + Vector3.new(0, CONFIG.CameraHeight, 0)
	return CFrame.new(camPos)
		* CFrame.Angles(0, math.rad(CONFIG.CameraYaw), 0)
		* CFrame.Angles(math.rad(-90), 0, 0)
end

local function lockCamera(center: Vector3)
	oldCamType = cam.CameraType
	oldCamSubject = cam.CameraSubject
	oldCamCFrame = cam.CFrame

	cam.CameraType = Enum.CameraType.Scriptable

	local targetCF = birdsEyeCFrame(center)
	TweenService:Create(
		cam,
		TweenInfo.new(CONFIG.CameraTweenIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = targetCF }
	):Play()
end

local function unlockCamera()
	if oldCamType == nil then return end

	local restoreType = oldCamType
	local restoreSubject = oldCamSubject
	local restoreCF = oldCamCFrame

	local t = TweenService:Create(
		cam,
		TweenInfo.new(CONFIG.CameraTweenOut, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = restoreCF }
	)
	t:Play()
	t.Completed:Once(function()
		cam.CameraType = restoreType
		cam.CameraSubject = restoreSubject
	end)

	oldCamType, oldCamSubject, oldCamCFrame = nil, nil, nil
end

local function makePart(name, size, color, anchored, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Anchored = anchored
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function cleanupBulletsAndSoul()
	if soul then
		soul:Destroy()
		soul = nil
	end
	for i = #bullets, 1, -1 do
		local b = bullets[i]
		if b.part then b.part:Destroy() end
		table.remove(bullets, i)
	end
end

local function cleanupArenaAll()
	cleanupBulletsAndSoul()
	if arenaFolder then arenaFolder:Destroy() end
	arenaFolder = nil
	arenaFloor = nil
	voidCover = nil
end

local function ensureVoidCover(center: Vector3)
	if voidCover and voidCover.Parent then
		voidCover.Position = center + Vector3.new(0, CONFIG.VoidCoverYOffset, 0)
		return
	end
	voidCover = makePart("VoidCover", CONFIG.VoidCoverSize, CONFIG.VoidCoverColor, true, arenaFolder)
	voidCover.Material = CONFIG.VoidCoverMaterial
	voidCover.Transparency = CONFIG.VoidCoverTransparency
	voidCover.CanCollide = false
	voidCover.Position = center + Vector3.new(0, CONFIG.VoidCoverYOffset, 0)
end

local function makeArena(center: Vector3)
	cleanupArenaAll()

	arenaFolder = Instance.new("Folder")
	arenaFolder.Name = "__BattleArena3D"
	arenaFolder.Parent = Workspace

	ensureVoidCover(center)

	local size = CONFIG.ArenaSize
	local halfX = size.X * 0.5
	local halfZ = size.Z * 0.5
	local h = CONFIG.WallHeight
	local t = CONFIG.WallThickness

	arenaFloor = makePart("ArenaFloor", size, Color3.fromRGB(12, 12, 12), true, arenaFolder)
	arenaFloor.Material = Enum.Material.Metal
	arenaFloor.Position = center + Vector3.new(0, size.Y * 0.5, 0)

	local wallColor = Color3.fromRGB(0, 0, 0)

	local wallN = makePart("WallN", Vector3.new(size.X + t*2, h, t), wallColor, true, arenaFolder)
	wallN.Position = center + Vector3.new(0, h*0.5, -halfZ - t*0.5)

	local wallS = makePart("WallS", Vector3.new(size.X + t*2, h, t), wallColor, true, arenaFolder)
	wallS.Position = center + Vector3.new(0, h*0.5, halfZ + t*0.5)

	local wallW = makePart("WallW", Vector3.new(t, h, size.Z), wallColor, true, arenaFolder)
	wallW.Position = center + Vector3.new(-halfX - t*0.5, h*0.5, 0)

	local wallE = makePart("WallE", Vector3.new(t, h, size.Z), wallColor, true, arenaFolder)
	wallE.Position = center + Vector3.new(halfX + t*0.5, h*0.5, 0)

	return center
end

local function ensureArena(center: Vector3)
	if arenaFloor and arenaFloor.Parent then
		local c = arenaFloor.Position - Vector3.new(0, CONFIG.ArenaSize.Y * 0.5, 0)
		ensureVoidCover(c)
		return c
	end
	return makeArena(center)
end

local function spawnSoul(center: Vector3)
	if soul then return end
	soul = makePart("Soul", CONFIG.SoulSize, Color3.fromRGB(255, 70, 70), true, arenaFolder)
	soul.CanCollide = false
	soul.Material = Enum.Material.Neon
	soul.Position = center + Vector3.new(0, 2.2, 0)
end

-- Detect current soul via attributes (Patience gating)
local function getCurrentSoulLower(): string?
	for _, attr in ipairs(CONFIG.PATIENCE.ATTR_NAMES) do
		local v = player:GetAttribute(attr)
		if type(v) == "string" and v ~= "" then
			return string.lower(v)
		end
	end
	return nil
end

local function isPatienceActive(): boolean
	local s = getCurrentSoulLower()
	if not s then return false end
	for _, name in ipairs(CONFIG.PATIENCE.SOUL_NAMES) do
		if s == name then return true end
	end
	return false
end

local function spawnBullet(center: Vector3)
	local size = CONFIG.ArenaSize
	local halfZ = size.Z * 0.5

	local startX = (math.random() - 0.5) * (size.X - 6)
	local startZ = -halfZ - 2

	local b = makePart("Bullet", CONFIG.BulletSize, Color3.fromRGB(255, 240, 90), true, arenaFolder)
	b.CanCollide = false
	b.Material = Enum.Material.Neon
	b.Position = center + Vector3.new(startX, 2.2, startZ)

	local speed = CONFIG.BulletSpeedMin + math.random() * (CONFIG.BulletSpeedMax - CONFIG.BulletSpeedMin)
	local drift = (math.random() - 0.5) * CONFIG.BulletSideDrift
	local vel = Vector3.new(drift, 0, speed)

	table.insert(bullets, {
		id = HttpService:GenerateGUID(false),
		part = b,
		vel = vel,
	})
end

local function spawnBarrageWall(center: Vector3, fromNorth: boolean)
	if not arenaFolder then return end

	local size = CONFIG.ArenaSize
	local halfX = size.X * 0.5
	local halfZ = size.Z * 0.5

	local startZ = fromNorth and (-halfZ - 2) or (halfZ + 2)
	local dirZ = fromNorth and 1 or -1

	-- Optional "gap" (0 = none)
	local gapW = CONFIG.PATIENCE.BARRAGE_GAP_WIDTH
	local gapCenterX = 0
	if gapW > 0 then
		gapCenterX = (math.random() - 0.5) * (size.X - 6)
	end

	local step = CONFIG.PATIENCE.BARRAGE_BULLET_SIZE.X
	for x = -halfX + 1, halfX - 1, step do
		-- If gap enabled, skip bullets inside gap range
		if gapW > 0 then
			if math.abs(x - gapCenterX) <= (gapW * 0.5) then
				continue
			end
		end

		local p = makePart("BarrageBullet", CONFIG.PATIENCE.BARRAGE_BULLET_SIZE, CONFIG.PATIENCE.BARRAGE_COLOR, true, arenaFolder)
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Position = center + Vector3.new(x, 2.2, startZ)

		local vel = Vector3.new(0, 0, CONFIG.PATIENCE.BARRAGE_SPEED * dirZ)
		table.insert(bullets, {
			id = HttpService:GenerateGUID(false),
			part = p,
			vel = vel,
		})
	end
end

local function aabbHit(p1: BasePart, p2: BasePart)
	local a = p1.Position
	local b = p2.Position
	local as = p1.Size * 0.5
	local bs = p2.Size * 0.5
	return math.abs(a.X - b.X) <= (as.X + bs.X)
		and math.abs(a.Y - b.Y) <= (as.Y + bs.Y)
		and math.abs(a.Z - b.Z) <= (as.Z + bs.Z)
end

local function reportHit(bulletId: string)
	if hitDebounce > 0 then return end
	hitDebounce = CONFIG.ClientHitDebounce
	BattleRE:FireServer("BulletHellHit", { bulletId = bulletId })
end

--============================================================
-- API
--============================================================
function BulletHell3D:IsRunning()
	return running
end

function BulletHell3D:PrepareBattleArena(center: Vector3)
	persistentArena = true
	ensureArena(center)
	cleanupBulletsAndSoul()
end

function BulletHell3D:TeardownBattleArena()
	persistentArena = false
	self:Stop("BattleEnd")
	cleanupArenaAll()
end

function BulletHell3D:GetArenaCenter()
	if not arenaFloor then return nil end
	return arenaFloor.Position - Vector3.new(0, CONFIG.ArenaSize.Y * 0.5, 0)
end

function BulletHell3D:Start(payload)
	if running then return end
	running = true

	payload = payload or {}

	local center = payload.center
	if typeof(center) ~= "Vector3" then
		center = self:GetArenaCenter()
	end
	if typeof(center) ~= "Vector3" then
		local ch = getChar()
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		center = hrp and (hrp.Position + Vector3.new(0, 10, 0)) or Vector3.new(0, 12, 0)
	end

	local arenaCenter = ensureArena(center)
	ensureVoidCover(arenaCenter)

	setCharFaded(true)
	lockCamera(arenaCenter)

	moveX, moveZ = 0, 0
	spawnT = 0
	hitDebounce = 0

	-- reset Patience event state each run
	patienceEventTriggered = false
	patienceCheckActive = false
	patienceMoveIntegral = 0
	patienceCheckEndsAt = 0
	barrageActive = false
	barrageEndsAt = 0
	barrageSpawnT = 0
	patienceEventNextAllowed = 0

	spawnSoul(arenaCenter)

	inputBeganConn = UserInputService.InputBegan:Connect(function(input, gp)
		if gp or not running then return end
		local kc = input.KeyCode
		if kc == Enum.KeyCode.W or kc == Enum.KeyCode.Up then moveZ = -1 end
		if kc == Enum.KeyCode.S or kc == Enum.KeyCode.Down then moveZ = 1 end
		if kc == Enum.KeyCode.A or kc == Enum.KeyCode.Left then moveX = -1 end
		if kc == Enum.KeyCode.D or kc == Enum.KeyCode.Right then moveX = 1 end
	end)

	inputEndedConn = UserInputService.InputEnded:Connect(function(input, gp)
		if gp or not running then return end
		local kc = input.KeyCode
		if kc == Enum.KeyCode.W or kc == Enum.KeyCode.Up then if moveZ == -1 then moveZ = 0 end end
		if kc == Enum.KeyCode.S or kc == Enum.KeyCode.Down then if moveZ == 1 then moveZ = 0 end end
		if kc == Enum.KeyCode.A or kc == Enum.KeyCode.Left then if moveX == -1 then moveX = 0 end end
		if kc == Enum.KeyCode.D or kc == Enum.KeyCode.Right then if moveX == 1 then moveX = 0 end end
	end)

	local startedAt = os.clock()

	renderConn = RunService.RenderStepped:Connect(function(dt)
		if hitDebounce > 0 then hitDebounce -= dt end
		if not running then return end
		if not arenaFloor or not soul or not arenaFolder then
			self:Stop("MissingArena")
			return
		end

		local c = self:GetArenaCenter()
		if not c then
			self:Stop("MissingCenter")
			return
		end

		ensureVoidCover(c)

		local halfX = CONFIG.ArenaSize.X * 0.5
		local halfZ = CONFIG.ArenaSize.Z * 0.5

		-- move soul
		local pos = soul.Position
		local vx = moveX * CONFIG.SoulSpeed
		local vz = moveZ * CONFIG.SoulSpeed
		if moveX ~= 0 and moveZ ~= 0 then
			local inv = 1 / math.sqrt(2)
			vx *= inv
			vz *= inv
		end

		local pad = CONFIG.SoulPadding
		local newX = clamp(pos.X + vx * dt, c.X - halfX + pad, c.X + halfX - pad)
		local newZ = clamp(pos.Z + vz * dt, c.Z - halfZ + pad, c.Z + halfZ - pad)
		soul.Position = Vector3.new(newX, pos.Y, newZ)

		-- camera hard lock
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = birdsEyeCFrame(c)

		--========================================================
		-- PATIENCE: bullets slow down the more you move
		--========================================================
		local speedMult = 1.0
		local patienceOn = isPatienceActive()
		if patienceOn then
			local moveMag = math.sqrt(vx*vx + vz*vz) -- studs/s
			local moveFactor = clamp(moveMag / math.max(1, CONFIG.SoulSpeed), 0, 1)
			speedMult = lerp(CONFIG.PATIENCE.SLOW_AT_STILL, CONFIG.PATIENCE.SLOW_AT_FULL_MOVE, moveFactor)
		end

		--========================================================
		-- PATIENCE: random skill-check event
		--========================================================
		local now = os.clock()

		-- Trigger the check at most once per run, Patience-only
		if patienceOn and (not patienceEventTriggered) and (now - startedAt) >= CONFIG.PATIENCE.EVENT_MIN_TIME and now >= patienceEventNextAllowed then
			-- Probability gate
			if math.random() < CONFIG.PATIENCE.EVENT_CHANCE then
				patienceEventTriggered = true
				patienceCheckActive = true
				patienceMoveIntegral = 0
				patienceCheckEndsAt = now + CONFIG.PATIENCE.CHECK_DURATION
				patienceEventNextAllowed = now + CONFIG.PATIENCE.EVENT_COOLDOWN

				-- Optional: you can notify UI via BattleRE if you want (commented out)
				-- BattleRE:FireServer("ClientNote", { kind="PatienceCheckStart" })
			end
		end

		-- During check, accumulate movement integral
		if patienceCheckActive then
			local moveMag = math.sqrt(vx*vx + vz*vz)
			patienceMoveIntegral += moveMag * dt

			if now >= patienceCheckEndsAt then
				patienceCheckActive = false

				-- Fail condition => barrage
				if patienceMoveIntegral >= CONFIG.PATIENCE.FAIL_MOVE_INTEGRAL then
					barrageActive = true
					barrageEndsAt = now + CONFIG.PATIENCE.BARRAGE_DURATION
					barrageSpawnT = 0
				else
					-- Passed: do nothing (the reward is not dying)
				end
			end
		end

		--========================================================
		-- Spawning bullets
		-- If barrage active: override normal spawns with barrage walls
		--========================================================
		if barrageActive then
			if now >= barrageEndsAt then
				barrageActive = false
			else
				barrageSpawnT += dt
				if barrageSpawnT >= CONFIG.PATIENCE.BARRAGE_SPAWN_EVERY then
					barrageSpawnT = 0

					for _ = 1, CONFIG.PATIENCE.BARRAGE_ROWS_PER_TICK do
						-- Alternate north/south walls to make it feel like an execution
						local fromNorth = (math.random() < 0.5)
						spawnBarrageWall(c, fromNorth)
					end
				end
			end
		else
			-- normal spawns
			spawnT += dt
			if spawnT >= CONFIG.BulletSpawnEvery then
				spawnT = 0
				spawnBullet(c)
				if math.random() < CONFIG.BulletExtraChance then
					spawnBullet(c)
				end
			end
		end

		--========================================================
		-- bullets update (apply speed multiplier here)
		--========================================================
		for i = #bullets, 1, -1 do
			local b = bullets[i]
			local p = b.part
			if not p or not p.Parent then
				table.remove(bullets, i)
			else
				p.Position = p.Position + (b.vel * dt * speedMult)

				local rel = p.Position - c
				if rel.Z > halfZ + 12 or rel.Z < -halfZ - 12 or rel.X < -halfX - 12 or rel.X > halfX + 12 then
					p:Destroy()
					table.remove(bullets, i)
				else
					if aabbHit(soul, p) then
						reportHit(b.id)
						p:Destroy()
						table.remove(bullets, i)
					end
				end
			end
		end
	end)
end

function BulletHell3D:Stop(reason)
	if not running and not persistentArena then return end

	running = false

	if renderConn then renderConn:Disconnect() renderConn = nil end
	if inputBeganConn then inputBeganConn:Disconnect() inputBeganConn = nil end
	if inputEndedConn then inputEndedConn:Disconnect() inputEndedConn = nil end

	-- reset Patience state
	patienceEventTriggered = false
	patienceCheckActive = false
	patienceMoveIntegral = 0
	patienceCheckEndsAt = 0
	barrageActive = false
	barrageEndsAt = 0
	barrageSpawnT = 0
	patienceEventNextAllowed = 0

	cleanupBulletsAndSoul()
	setCharFaded(false)
	unlockCamera()

	if not persistentArena then
		cleanupArenaAll()
	end
end

return BulletHell3D
