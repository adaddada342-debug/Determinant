-- ServerScriptService/DeterminantCombat/BulletHellService.server.lua
-- Boss-only bullet hell: server sim + hit validation. Client renders Parts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("DeterminantCombat"):WaitForChild("Modules"):WaitForChild("CombatConstants"))
local PatternSets = require(ReplicatedStorage:WaitForChild("DeterminantCombat"):WaitForChild("Modules"):WaitForChild("PatternSets"))

local CombatService = _G.DeterminantCombatService
assert(CombatService, "CombatService must load before BulletHellService")

local remotes = ReplicatedStorage:WaitForChild("DeterminantCombat"):WaitForChild("Remotes")
local BulletHellRE = remotes:WaitForChild("BulletHellRE")
local CombatRE = remotes:WaitForChild("CombatRE")

local BulletHellService = {}
_G.BulletHellService = BulletHellService

-- Session per player (1 boss + 1 player minimum; supports more)
-- session = {
--   active=true, boss=Instance, endTime=number,
--   bullets={}, hazards={}, nextPatternAt=number, patternSet=table, rngSeed=number,
-- }
local sessions = {}

local function now()
	return os.clock()
end

local function randRange(rng, a, b)
	return a + (b - a) * rng:NextNumber()
end

local function getHRP(plr)
	local ch = plr.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function bossPosition(boss)
	if not boss then return nil end
	if boss:IsA("BasePart") then return boss.Position end
	if boss:IsA("Model") then
		local pp = boss.PrimaryPart or boss:FindFirstChild("HumanoidRootPart", true) or boss:FindFirstChildWhichIsA("BasePart", true)
		return pp and pp.Position or nil
	end
	return nil
end

local function chooseWeighted(rng, patterns)
	local total = 0
	for _, p in ipairs(patterns) do
		total += (p.weight or 1)
	end
	local roll = rng:NextNumber() * total
	local acc = 0
	for _, p in ipairs(patterns) do
		acc += (p.weight or 1)
		if roll <= acc then
			return p
		end
	end
	return patterns[#patterns]
end

local function sendBatch(plr, kind, list)
	-- Batching reduces remote spam.
	BulletHellRE:FireClient(plr, kind, list)
end

-- Bullet struct:
-- {pos=Vector3, vel=Vector3, r=number, dmg=number, dieAt=number}
local function spawnBullet(session, plr, spawnAt, pos, vel, r, dmg, life)
	local b = {
		pos = pos,
		vel = vel,
		r = r,
		dmg = dmg,
		spawnAt = spawnAt,
		dieAt = spawnAt + life,
	}
	table.insert(session.bullets, b)
end

-- Hazard structs:
-- Explosion: {type="Explosion", pos, radius, telegraphEnd, activeEnd, dmg, hit=false}
-- Beam: {type="Beam", origin, len, width, telegraphEnd, activeEnd, dmg, tickCD, lastTick=0,
--        startDir, endDir, sweepStart, sweepEnd}
local function spawnExplosion(session, pos, radius, telegraph, active, dmg)
	local t0 = now()
	table.insert(session.hazards, {
		type = "Explosion",
		pos = pos,
		radius = radius,
		telegraphEnd = t0 + telegraph,
		activeEnd = t0 + telegraph + active,
		dmg = dmg,
		hit = false,
	})
end

local function spawnBeam(session, origin, startDir, endDir, len, width, telegraph, active, dmg, sweepDuration)
	local t0 = now()
	table.insert(session.hazards, {
		type = "Beam",
		origin = origin,
		len = len,
		width = width,
		telegraphEnd = t0 + telegraph,
		activeEnd = t0 + telegraph + active,
		dmg = dmg,
		tickCD = Constants.BEAM_TICK_COOLDOWN,
		lastTick = 0,
		startDir = startDir.Unit,
		endDir = endDir.Unit,
		sweepStart = t0,
		sweepEnd = t0 + sweepDuration,
	})
end

local function pointToSegmentDistance(p, a, b)
	local ab = b - a
	local t = (p - a):Dot(ab) / math.max(1e-6, ab:Dot(ab))
	t = math.clamp(t, 0, 1)
	local closest = a + ab * t
	return (p - closest).Magnitude
end

local function stepSession(plr, session, dt)
	local hrp = getHRP(plr)
	if not hrp then return end

	local t = now()

	-- Schedule new pattern spawns
	if t >= session.nextPatternAt then
		local rng = session.rng
		local def = chooseWeighted(rng, session.patternSet.patterns)

		local bossPos = bossPosition(session.boss) or (hrp.Position + Vector3.new(0, 10, 0))
		local spawnTime = workspace:GetServerTimeNow() -- for client visual sync

		-- Build spawn instructions for client (visual only), while server creates sim objects too.
		if def.type == "RadialBurst" then
			local bullets = def.bullets or 16
			local speed = def.speed or 60
			local r = def.radius or Constants.BULLET_RADIUS
			local life = def.life or Constants.BULLET_LIFE
			local tele = def.telegraph or 0.25

			local spawnAt = spawnTime + tele

			local packet = {
				type = "RadialBurst",
				spawnAt = spawnAt,
				origin = bossPos,
				bullets = bullets,
				speed = speed,
				radius = r,
				life = life,
				telegraph = tele,
			}
			sendBatch(plr, "SpawnBatch", { packet })

			for i = 1, bullets do
				local ang = (i - 1) * (2 * math.pi / bullets)
				local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
				local vel = dir * speed
				spawnBullet(session, plr, now() + tele, bossPos, vel, r, Constants.BULLET_DAMAGE, life)
			end

		elseif def.type == "AimedVolley" then
			local shots = def.shots or 5
			local gap = def.shotGap or 0.1
			local speed = def.speed or 70
			local spreadDeg = def.spreadDeg or 6
			local r = def.radius or Constants.BULLET_RADIUS
			local life = def.life or Constants.BULLET_LIFE
			local tele = def.telegraph or 0.18

			local packet = {
				type = "AimedVolley",
				spawnAt = spawnTime + tele,
				origin = bossPos,
				shots = shots,
				shotGap = gap,
				speed = speed,
				spreadDeg = spreadDeg,
				radius = r,
				life = life,
				telegraph = tele,
			}
			sendBatch(plr, "SpawnBatch", { packet })

			local target = hrp.Position
			local baseDir = (target - bossPos)
			if baseDir.Magnitude < 1e-3 then
				baseDir = Vector3.new(0, 0, -1)
			end
			baseDir = baseDir.Unit

			for i = 1, shots do
				local delay = tele + (i - 1) * gap
				-- Random spread around Y axis (readable, dodgable)
				local offset = math.rad(rng:NextNumber(-spreadDeg, spreadDeg))
				local ca, sa = math.cos(offset), math.sin(offset)
				local d = Vector3.new(
					baseDir.X * ca - baseDir.Z * sa,
					0,
					baseDir.X * sa + baseDir.Z * ca
				).Unit

				spawnBullet(session, plr, now() + delay, bossPos, d * speed, r, Constants.BULLET_DAMAGE, life)
			end

		elseif def.type == "DelayedExplosions" then
			local count = def.count or 3
			local radius = def.radius or 7
			local tele = def.telegraph or 0.9
			local active = def.active or 0.2

			local packets = {}
			for i = 1, count do
				-- Place near the player but not directly under them every time (fairness)
				local offset = Vector3.new(
					rng:NextNumber(-10, 10),
					0,
					rng:NextNumber(-10, 10)
				)
				local pos = hrp.Position + offset

				table.insert(packets, {
					type = "DelayedExplosion",
					startAt = spawnTime,
					pos = pos,
					radius = radius,
					telegraph = tele,
					active = active,
				})

				spawnExplosion(session, pos, radius, tele, active, Constants.EXPLOSION_DAMAGE)
			end
			sendBatch(plr, "SpawnBatch", packets)

		elseif def.type == "SweepingBeam" then
			local len = def.length or 120
			local width = def.width or 3.5
			local tele = def.telegraph or 0.7
			local active = def.active or 1.2
			local sweepDeg = def.sweepDeg or 120
			local duration = def.duration or 1.8

			-- Beam aimed roughly toward player with an arc sweep
			local toPlayer = (hrp.Position - bossPos)
			if toPlayer.Magnitude < 1e-3 then toPlayer = Vector3.new(0, 0, -1) end
			toPlayer = Vector3.new(toPlayer.X, 0, toPlayer.Z)
			if toPlayer.Magnitude < 1e-3 then toPlayer = Vector3.new(0, 0, -1) end
			toPlayer = toPlayer.Unit

			local dirSign = (rng:NextNumber() < 0.5) and -1 or 1
			local half = math.rad(sweepDeg * 0.5)

			local function rotY(v, ang)
				local ca, sa = math.cos(ang), math.sin(ang)
				return Vector3.new(v.X * ca - v.Z * sa, 0, v.X * sa + v.Z * ca)
			end

			local startDir = rotY(toPlayer, -half * dirSign)
			local endDir = rotY(toPlayer, half * dirSign)

			sendBatch(plr, "SpawnBatch", {
				{
					type = "SweepingBeam",
					startAt = spawnTime,
					origin = bossPos,
					len = len,
					width = width,
					telegraph = tele,
					active = active,
					duration = duration,
					startDir = startDir,
					endDir = endDir,
				}
			})

			spawnBeam(session, bossPos, startDir, endDir, len, width, tele, active, Constants.BEAM_DAMAGE, duration)
		end

		-- Next schedule
		session.nextPatternAt = t + randRange(session.rng, session.patternSet.intervalMin, session.patternSet.intervalMax)
	end

	-- Step bullets + hits
	local playerPos = hrp.Position
	local playerR = Constants.PLAYER_HIT_RADIUS

	for i = #session.bullets, 1, -1 do
		local b = session.bullets[i]
		if t < b.spawnAt then
			-- not spawned yet
		elseif t >= b.dieAt then
			table.remove(session.bullets, i)
		else
			b.pos = b.pos + b.vel * dt

			-- Basic hit check (sphere)
			if CombatService.CanTakeDamage(plr) then
				local dist = (b.pos - playerPos).Magnitude
				if dist <= (b.r + playerR) then
					CombatService.ApplyDamage(plr, b.dmg, "bullet")
					table.remove(session.bullets, i)
				end
			end
		end
	end

	-- Step hazards + hits
	for i = #session.hazards, 1, -1 do
		local h = session.hazards[i]

		if h.type == "Explosion" then
			if t >= h.activeEnd then
				table.remove(session.hazards, i)
			elseif (t >= h.telegraphEnd) and (t <= h.activeEnd) and (not h.hit) then
				if CombatService.CanTakeDamage(plr) then
					local dist = (playerPos - h.pos).Magnitude
					if dist <= (h.radius + playerR) then
						h.hit = true
						CombatService.ApplyDamage(plr, h.dmg, "explosion")
					end
				end
			end

		elseif h.type == "Beam" then
			if t >= h.activeEnd then
				table.remove(session.hazards, i)
			else
				-- Determine current beam direction (sweep over duration)
				local alpha
				if t <= h.sweepStart then
					alpha = 0
				elseif t >= h.sweepEnd then
					alpha = 1
				else
					alpha = (t - h.sweepStart) / math.max(1e-6, (h.sweepEnd - h.sweepStart))
				end

				local dir = (h.startDir:Lerp(h.endDir, alpha)).Unit
				local a = h.origin
				local b = a + dir * h.len

				if t >= h.telegraphEnd and t <= h.activeEnd then
					if CombatService.CanTakeDamage(plr) and (t - (h.lastTick or 0) >= h.tickCD) then
						local d = pointToSegmentDistance(playerPos, a, b)
						if d <= (h.width + playerR) then
							h.lastTick = t
							CombatService.ApplyDamage(plr, h.dmg, "beam")
						end
					end
				end
			end
		end
	end

	-- End phase
	if now() >= session.endTime then
		BulletHellService.StopPhase(plr)
	end
end

function BulletHellService.StartPhase(plr, boss, setName, duration)
	setName = setName or "Boss_Default"
	duration = tonumber(duration) or 10
	duration = math.clamp(duration, 5, 15)

	local set = PatternSets[setName]
	assert(set, ("Pattern set '%s' missing in PatternSets.lua"):format(setName))

	-- Stop existing session
	BulletHellService.StopPhase(plr)

	local seed = math.random(1, 1e9)
	local rng = Random.new(seed)

	local session = {
		active = true,
		boss = boss,
		endTime = now() + duration,
		bullets = {},
		hazards = {},
		patternSet = set,
		rng = rng,
		nextPatternAt = now() + 0.25,
	}

	sessions[plr] = session

	BulletHellRE:FireClient(plr, "StartPhase", {
		setName = setName,
		seed = seed,
		endsAt = workspace:GetServerTimeNow() + duration,
	})

	CombatRE:FireClient(plr, "Banner", { text = "BULLET HELL PHASE", duration = 1.2 })

	print(("[BulletHell] Started for %s (%ss, set=%s)"):format(plr.Name, duration, setName))
end

function BulletHellService.StopPhase(plr)
	local session = sessions[plr]
	if not session then return end
	sessions[plr] = nil

	BulletHellRE:FireClient(plr, "StopPhase", {})
	CombatRE:FireClient(plr, "Banner", { text = "PHASE END", duration = 0.8 })

	print(("[BulletHell] Stopped for %s"):format(plr.Name))
end

-- Main loop (single heartbeat for all sessions)
RunService.Heartbeat:Connect(function(dt)
	for plr, session in pairs(sessions) do
		if plr.Parent == nil then
			sessions[plr] = nil
		else
			stepSession(plr, session, dt)
		end
	end
end)

print("[DeterminantCombat] BulletHellService loaded")
