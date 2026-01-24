-- ServerScriptService/BossBulletHell/BossBulletHellService.server.lua
-- Boss-only bullet hell layer (mid-fight pressure). Server sim + hit validation.
-- Respects your existing dodge iFrames: Character:GetAttribute("IFrames") == true.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BulletHellRE = Remotes:WaitForChild("BulletHellRE")

local Constants = require(ReplicatedStorage:WaitForChild("BossBulletHell"):WaitForChild("Constants"))
local PatternSets = require(ReplicatedStorage:WaitForChild("BossBulletHell"):WaitForChild("PatternSets"))

local BossBulletHellService = {}
_G.BossBulletHellService = BossBulletHellService

-- session per player
-- { boss=Instance, endTime=number, bullets={}, hazards={}, nextPatternAt=number, rng=Random, set=table }
local sessions = {}

local function now() return os.clock() end

local function getHRP(plr)
	local ch = plr.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function getHum(plr)
	local ch = plr.Character
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function bossPos(boss)
	if not boss then return nil end
	if boss:IsA("BasePart") then return boss.Position end
	if boss:IsA("Model") then
		local pp = boss.PrimaryPart or boss:FindFirstChild("HumanoidRootPart", true) or boss:FindFirstChildWhichIsA("BasePart", true)
		return pp and pp.Position or nil
	end
	return nil
end

local function canTakeDamage(plr)
	local ch = plr.Character
	if not ch then return false end
	if ch:GetAttribute("IFrames") then return false end

	local immuneUntil = ch:GetAttribute("__BossBH_ImmuneUntil") or 0
	return now() >= immuneUntil
end

local function applyDamage(plr, amount, source)
	local hum = getHum(plr)
	local ch = plr.Character
	if not (hum and ch) then return end
	if hum.Health <= 0 then return end
	if not canTakeDamage(plr) then return end

	hum:TakeDamage(amount)
	ch:SetAttribute("__BossBH_ImmuneUntil", now() + Constants.POST_HIT_IMMUNITY)
end

local function chooseWeighted(rng, patterns)
	local total = 0
	for _, p in ipairs(patterns) do total += (p.weight or 1) end
	local r = rng:NextNumber() * total
	local acc = 0
	for _, p in ipairs(patterns) do
		acc += (p.weight or 1)
		if r <= acc then return p end
	end
	return patterns[#patterns]
end

-- bullet: {pos, vel, r, dmg, spawnAt, dieAt}
local function spawnBullet(session, pos, vel, r, dmg, spawnDelay, life)
	local t0 = now()
	table.insert(session.bullets, {
		pos = pos,
		vel = vel,
		r = r,
		dmg = dmg,
		spawnAt = t0 + spawnDelay,
		dieAt = t0 + spawnDelay + life,
	})
end

-- hazard types:
-- Explosion {type="Explosion", pos, radius, teleEnd, activeEnd, dmg, hit=false}
-- Beam     {type="Beam", origin, len, width, teleEnd, activeEnd, dmg, tickCD, lastTick, startDir, endDir, sweepStart, sweepEnd}
local function spawnExplosion(session, pos, radius, tele, active, dmg)
	local t0 = now()
	table.insert(session.hazards, {
		type = "Explosion",
		pos = pos,
		radius = radius,
		teleEnd = t0 + tele,
		activeEnd = t0 + tele + active,
		dmg = dmg,
		hit = false,
	})
end

local function spawnBeam(session, origin, startDir, endDir, len, width, tele, active, dmg, sweepDuration)
	local t0 = now()
	table.insert(session.hazards, {
		type = "Beam",
		origin = origin,
		len = len,
		width = width,
		teleEnd = t0 + tele,
		activeEnd = t0 + tele + active,
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
	local denom = math.max(1e-6, ab:Dot(ab))
	local t = (p - a):Dot(ab) / denom
	t = math.clamp(t, 0, 1)
	local closest = a + ab * t
	return (p - closest).Magnitude
end

local function rotY(v, ang)
	local ca, sa = math.cos(ang), math.sin(ang)
	return Vector3.new(v.X * ca - v.Z * sa, 0, v.X * sa + v.Z * ca)
end

local function scheduleNext(session)
	local a = session.set.intervalMin or 1.2
	local b = session.set.intervalMax or 2.1
	session.nextPatternAt = now() + (a + (b - a) * session.rng:NextNumber())
end

local function emit(plr, packets)
	-- One remote call per pattern batch to keep things cheap
	BulletHellRE:FireClient(plr, "BossSpawnBatch", packets)
end

local function runPattern(plr, session, def)
	local hrp = getHRP(plr)
	if not hrp then return end

	local bossP = bossPos(session.boss) or (hrp.Position + Vector3.new(0, 8, 0))
	local serverTime = workspace:GetServerTimeNow()

	if def.type == "RadialBurst" then
		local bullets = def.bullets or 16
		local speed = def.speed or 60
		local r = def.radius or Constants.BULLET_RADIUS
		local life = def.life or Constants.BULLET_LIFE
		local tele = def.telegraph or 0.25

		emit(plr, {{
			type="RadialBurst",
			spawnAt = serverTime + tele,
			origin = bossP,
			bullets = bullets,
			speed = speed,
			radius = r,
			life = life,
			telegraph = tele,
		}})

		for i = 1, bullets do
			local ang = (i-1) * (2*math.pi / bullets)
			local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
			spawnBullet(session, bossP, dir * speed, r, Constants.BULLET_DAMAGE, tele, life)
		end

	elseif def.type == "AimedVolley" then
		local shots = def.shots or 5
		local gap = def.shotGap or 0.1
		local speed = def.speed or 70
		local spreadDeg = def.spreadDeg or 6
		local r = def.radius or Constants.BULLET_RADIUS
		local life = def.life or Constants.BULLET_LIFE
		local tele = def.telegraph or 0.18

		emit(plr, {{
			type="AimedVolley",
			spawnAt = serverTime + tele,
			origin = bossP,
			shots = shots,
			shotGap = gap,
			speed = speed,
			spreadDeg = spreadDeg,
			radius = r,
			life = life,
			telegraph = tele,
		}})

		local base = hrp.Position - bossP
		base = Vector3.new(base.X, 0, base.Z)
		if base.Magnitude < 1e-3 then base = Vector3.new(0,0,-1) end
		base = base.Unit

		for i = 1, shots do
			local delay = tele + (i-1) * gap
			local offset = math.rad(session.rng:NextNumber(-spreadDeg, spreadDeg))
			local dir = rotY(base, offset).Unit
			spawnBullet(session, bossP, dir * speed, r, Constants.BULLET_DAMAGE, delay, life)
		end

	elseif def.type == "DelayedExplosions" then
		local count = def.count or 3
		local radius = def.radius or 7
		local tele = def.telegraph or 0.9
		local active = def.active or 0.2

		local packets = {}
		for i=1, count do
			-- Fair: near player, but offset so you always have reaction time + escape vector
			local offset = Vector3.new(session.rng:NextNumber(-10, 10), 0, session.rng:NextNumber(-10, 10))
			local pos = hrp.Position + offset

			table.insert(packets, {
				type="DelayedExplosion",
				startAt = serverTime,
				pos = pos,
				radius = radius,
				telegraph = tele,
				active = active,
			})

			spawnExplosion(session, pos, radius, tele, active, Constants.EXPLOSION_DAMAGE)
		end
		emit(plr, packets)

	elseif def.type == "SweepingBeam" then
		local len = def.length or 120
		local width = def.width or 3.5
		local tele = def.telegraph or 0.7
		local active = def.active or 1.2
		local sweepDeg = def.sweepDeg or 120
		local duration = def.duration or 1.8

		local toPlayer = hrp.Position - bossP
		toPlayer = Vector3.new(toPlayer.X, 0, toPlayer.Z)
		if toPlayer.Magnitude < 1e-3 then toPlayer = Vector3.new(0,0,-1) end
		toPlayer = toPlayer.Unit

		local sign = (session.rng:NextNumber() < 0.5) and -1 or 1
		local half = math.rad(sweepDeg * 0.5)

		local startDir = rotY(toPlayer, -half * sign)
		local endDir = rotY(toPlayer,  half * sign)

		emit(plr, {{
			type="SweepingBeam",
			startAt = serverTime,
			origin = bossP,
			len = len,
			width = width,
			telegraph = tele,
			active = active,
			duration = duration,
			startDir = startDir,
			endDir = endDir,
		}})

		spawnBeam(session, bossP, startDir, endDir, len, width, tele, active, Constants.BEAM_DAMAGE, duration)
	end
end

local function step(plr, session, dt)
	local hrp = getHRP(plr)
	if not hrp then return end
	local playerPos = hrp.Position
	local playerR = Constants.PLAYER_HIT_RADIUS
	local t = now()

	-- schedule patterns
	if t >= session.nextPatternAt then
		local def = chooseWeighted(session.rng, session.set.patterns)
		runPattern(plr, session, def)
		scheduleNext(session)
	end

	-- bullets
	for i = #session.bullets, 1, -1 do
		local b = session.bullets[i]
		if t < b.spawnAt then
			-- wait
		elseif t >= b.dieAt then
			table.remove(session.bullets, i)
		else
			b.pos = b.pos + b.vel * dt
			if canTakeDamage(plr) then
				if (b.pos - playerPos).Magnitude <= (b.r + playerR) then
					applyDamage(plr, b.dmg, "bullet")
					table.remove(session.bullets, i)
				end
			end
		end
	end

	-- hazards
	for i = #session.hazards, 1, -1 do
		local h = session.hazards[i]

		if h.type == "Explosion" then
			if t >= h.activeEnd then
				table.remove(session.hazards, i)
			elseif t >= h.teleEnd and t <= h.activeEnd and not h.hit then
				if canTakeDamage(plr) then
					if (playerPos - h.pos).Magnitude <= (h.radius + playerR) then
						h.hit = true
						applyDamage(plr, h.dmg, "explosion")
					end
				end
			end

		elseif h.type == "Beam" then
			if t >= h.activeEnd then
				table.remove(session.hazards, i)
			else
				local alpha
				if t <= h.sweepStart then alpha = 0
				elseif t >= h.sweepEnd then alpha = 1
				else alpha = (t - h.sweepStart) / math.max(1e-6, (h.sweepEnd - h.sweepStart)) end

				local dir = (h.startDir:Lerp(h.endDir, alpha)).Unit
				local a = h.origin
				local b = a + dir * h.len

				if t >= h.teleEnd and t <= h.activeEnd then
					if canTakeDamage(plr) and (t - (h.lastTick or 0) >= h.tickCD) then
						local d = pointToSegmentDistance(playerPos, a, b)
						if d <= (h.width + playerR) then
							h.lastTick = t
							applyDamage(plr, h.dmg, "beam")
						end
					end
				end
			end
		end
	end

	-- end phase
	if t >= session.endTime then
		BossBulletHellService.Stop(plr)
	end
end

function BossBulletHellService.Start(plr, boss, setName, duration)
	setName = setName or "DefaultBoss"
	duration = math.clamp(tonumber(duration) or 10, Constants.PHASE_MIN, Constants.PHASE_MAX)

	local set = PatternSets[setName]
	assert(set, ("PatternSet '%s' missing"):format(setName))

	BossBulletHellService.Stop(plr)

	local seed = math.random(1, 1e9)
	local session = {
		boss = boss,
		endTime = now() + duration,
		bullets = {},
		hazards = {},
		rng = Random.new(seed),
		set = set,
		nextPatternAt = now() + 0.25,
	}
	sessions[plr] = session

	BulletHellRE:FireClient(plr, "BossStart", {
		setName = setName,
		seed = seed,
		endsAt = workspace:GetServerTimeNow() + duration,
	})

	scheduleNext(session)
end

function BossBulletHellService.Stop(plr)
	if not sessions[plr] then return end
	sessions[plr] = nil
	BulletHellRE:FireClient(plr, "BossStop", {})
end

RunService.Heartbeat:Connect(function(dt)
	for plr, session in pairs(sessions) do
		if plr.Parent == nil then
			sessions[plr] = nil
		else
			step(plr, session, dt)
		end
	end
end)

print("[BossBulletHellService] Loaded. Use _G.BossBulletHellService.Start(player, boss, 'DefaultBoss', 10)")
