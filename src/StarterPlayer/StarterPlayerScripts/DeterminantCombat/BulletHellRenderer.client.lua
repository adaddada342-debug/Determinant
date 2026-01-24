-- StarterPlayerScripts/DeterminantCombat/BulletHellRenderer.client.lua
-- Client-only visuals: simple Parts with telegraphing, pooling, cleanup.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local remotes = ReplicatedStorage:WaitForChild("DeterminantCombat"):WaitForChild("Remotes")
local BulletHellRE = remotes:WaitForChild("BulletHellRE")

local renderRoot = workspace:FindFirstChild("__BulletHellVisuals") or Instance.new("Folder")
renderRoot.Name = "__BulletHellVisuals"
renderRoot.Parent = workspace

-- Simple Part pool (avoid GC churn)
local Pool = {}
Pool.free = {}
Pool.inUse = {}

function Pool:Get()
	local p = table.remove(self.free)
	if p then
		p.Parent = renderRoot
		p.Transparency = 0
		self.inUse[p] = true
		return p
	end

	p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Parent = renderRoot
	self.inUse[p] = true
	return p
end

function Pool:Release(p)
	if not p then return end
	if not self.inUse[p] then return end
	self.inUse[p] = nil
	p.Parent = nil
	table.insert(self.free, p)
end

-- Visual objects
local bullets = {}  -- {part, pos, vel, dieAt, r}
local hazards = {}  -- explosion/beam visuals

local function clearAll()
	for i = #bullets, 1, -1 do
		Pool:Release(bullets[i].part)
		table.remove(bullets, i)
	end
	for i = #hazards, 1, -1 do
		local h = hazards[i]
		if h.part then Pool:Release(h.part) end
		if h.part2 then Pool:Release(h.part2) end
		table.remove(hazards, i)
	end
end

local function spawnBulletVisual(spawnAt, origin, vel, radius, life)
	-- Telegraph: small yellow dot that becomes bullet at spawnAt
	local tele = Pool:Get()
	tele.Shape = Enum.PartType.Ball
	tele.Size = Vector3.new(radius * 1.4, radius * 1.4, radius * 1.4)
	tele.Color = Color3.fromRGB(255, 230, 120)
	tele.CFrame = CFrame.new(origin)
	tele.Transparency = 0.15

	local p = Pool:Get()
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	p.Color = Color3.fromRGB(255, 90, 90)
	p.Transparency = 1 -- hidden until spawnAt
	p.CFrame = CFrame.new(origin)

	local dieAt = workspace:GetServerTimeNow() + life

	table.insert(bullets, {
		part = p,
		pos = origin,
		vel = vel,
		dieAt = dieAt,
		r = radius,
		spawnAt = spawnAt,
		tele = tele,
	})
end

local function spawnExplosionTelegraph(startAt, pos, radius, telegraph, active)
	local ring = Pool:Get()
	ring.Shape = Enum.PartType.Cylinder
	ring.Color = Color3.fromRGB(255, 230, 120)
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))

	table.insert(hazards, {
		type = "Explosion",
		part = ring,
		pos = pos,
		radius = radius,
		teleEnd = startAt + telegraph,
		activeEnd = startAt + telegraph + active,
	})
end

local function spawnSweepingBeam(startAt, origin, len, width, telegraph, active, duration, startDir, endDir)
	local beam = Pool:Get()
	beam.Shape = Enum.PartType.Block
	beam.Color = Color3.fromRGB(255, 230, 120)
	beam.Transparency = 0.45
	beam.Size = Vector3.new(width, width, len)
	beam.CFrame = CFrame.new(origin, origin + startDir) * CFrame.new(0, 0, -len * 0.5)

	table.insert(hazards, {
		type = "Beam",
		part = beam,
		origin = origin,
		len = len,
		width = width,
		teleEnd = startAt + telegraph,
		activeEnd = startAt + telegraph + active,
		sweepEnd = startAt + duration,
		startAt = startAt,
		startDir = startDir,
		endDir = endDir,
	})
end

-- Interpret batched pattern packets
local function handlePacket(packet)
	local tNow = workspace:GetServerTimeNow()
	local ptype = packet.type

	if ptype == "RadialBurst" then
		local origin = packet.origin
		local bulletsCount = packet.bullets
		local speed = packet.speed
		local r = packet.radius
		local life = packet.life
		local spawnAt = packet.spawnAt

		for i = 1, bulletsCount do
			local ang = (i - 1) * (2 * math.pi / bulletsCount)
			local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
			spawnBulletVisual(spawnAt, origin, dir * speed, r, life)
		end

	elseif ptype == "AimedVolley" then
		-- Client doesn’t need exact spread; visuals only. We’ll approximate with random spread.
		local origin = packet.origin
		local shots = packet.shots
		local gap = packet.shotGap
		local speed = packet.speed
		local spreadDeg = packet.spreadDeg
		local r = packet.radius
		local life = packet.life
		local spawnAt = packet.spawnAt

		local cam = workspace.CurrentCamera
		local baseDir = cam and cam.CFrame.LookVector or Vector3.new(0,0,-1)
		baseDir = Vector3.new(baseDir.X, 0, baseDir.Z)
		if baseDir.Magnitude < 0.05 then baseDir = Vector3.new(0,0,-1) end
		baseDir = baseDir.Unit

		for i = 1, shots do
			local offset = math.rad((math.random() * 2 - 1) * spreadDeg)
			local ca, sa = math.cos(offset), math.sin(offset)
			local d = Vector3.new(
				baseDir.X * ca - baseDir.Z * sa,
				0,
				baseDir.X * sa + baseDir.Z * ca
			).Unit
			spawnBulletVisual(spawnAt + (i - 1) * gap, origin, d * speed, r, life)
		end

	elseif ptype == "DelayedExplosion" then
		spawnExplosionTelegraph(packet.startAt, packet.pos, packet.radius, packet.telegraph, packet.active)

	elseif ptype == "SweepingBeam" then
		spawnSweepingBeam(packet.startAt, packet.origin, packet.len, packet.width, packet.telegraph, packet.active, packet.duration, packet.startDir, packet.endDir)
	end
end

BulletHellRE.OnClientEvent:Connect(function(msg, data)
	if msg == "StartPhase" then
		-- Optional: you could show a tiny banner, but HUD script does that
	elseif msg == "StopPhase" then
		clearAll()
	elseif msg == "SpawnBatch" then
		for _, packet in ipairs(data) do
			handlePacket(packet)
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local t = workspace:GetServerTimeNow()

	-- Bullets update
	for i = #bullets, 1, -1 do
		local b = bullets[i]
		if t >= b.dieAt then
			Pool:Release(b.part)
			Pool:Release(b.tele)
			table.remove(bullets, i)
		else
			if t < b.spawnAt then
				-- Telegraph pulse
				local scale = 1 + 0.25 * math.sin((t - (b.spawnAt - 0.3)) * 18)
				b.tele.Size = Vector3.new(b.r * 1.4, b.r * 1.4, b.r * 1.4) * scale
				b.part.Transparency = 1
			else
				-- Activate bullet and hide telegraph
				b.tele.Transparency = 1
				b.pos = b.pos + b.vel * dt
				b.part.Transparency = 0.05
				b.part.CFrame = CFrame.new(b.pos)
			end
		end
	end

	-- Hazards update (visual telegraph → active)
	for i = #hazards, 1, -1 do
		local h = hazards[i]
		if t >= h.activeEnd then
			Pool:Release(h.part)
			table.remove(hazards, i)
		else
			if h.type == "Explosion" then
				if t < h.teleEnd then
					h.part.Color = Color3.fromRGB(255, 230, 120)
				else
					h.part.Color = Color3.fromRGB(255, 90, 90)
					h.part.Transparency = 0.55
				end

			elseif h.type == "Beam" then
				local alpha
				if t <= h.startAt then alpha = 0
				elseif t >= h.sweepEnd then alpha = 1
				else alpha = (t - h.startAt) / math.max(1e-6, (h.sweepEnd - h.startAt)) end

				local dir = (h.startDir:Lerp(h.endDir, alpha)).Unit
				h.part.CFrame = CFrame.new(h.origin, h.origin + dir) * CFrame.new(0, 0, -h.len * 0.5)

				if t < h.teleEnd then
					h.part.Color = Color3.fromRGB(255, 230, 120)
					h.part.Transparency = 0.55
				else
					h.part.Color = Color3.fromRGB(255, 90, 90)
					h.part.Transparency = 0.35
				end
			end
		end
	end
end)
