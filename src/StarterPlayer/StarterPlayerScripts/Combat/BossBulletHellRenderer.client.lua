-- StarterPlayerScripts/Combat/BossBulletHellRenderer.client.lua
-- Visual-only renderer: parts, telegraphs, pooling. No gameplay logic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BulletHellRE = Remotes:WaitForChild("BulletHellRE")

local renderRoot = workspace:FindFirstChild("__BossBulletHellVisuals") or Instance.new("Folder")
renderRoot.Name = "__BossBulletHellVisuals"
renderRoot.Parent = workspace

-- Part pool
local Pool = { free = {}, inUse = {} }

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
	p.CanTouch = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Parent = renderRoot
	self.inUse[p] = true
	return p
end

function Pool:Release(p)
	if not p or not self.inUse[p] then return end
	self.inUse[p] = nil
	p.Parent = nil
	table.insert(self.free, p)
end

local bullets = {} -- {part, tele, pos, vel, r, spawnAt, dieAt}
local hazards = {} -- explosions/beams

local function clearAll()
	for i=#bullets,1,-1 do
		Pool:Release(bullets[i].part)
		Pool:Release(bullets[i].tele)
		table.remove(bullets,i)
	end
	for i=#hazards,1,-1 do
		local h = hazards[i]
		if h.part then Pool:Release(h.part) end
		table.remove(hazards,i)
	end
end

local function spawnBulletVisual(spawnAt, origin, vel, radius, life)
	local tele = Pool:Get()
	tele.Shape = Enum.PartType.Ball
	tele.Size = Vector3.new(radius*1.4, radius*1.4, radius*1.4)
	tele.Color = Color3.fromRGB(255, 230, 120)
	tele.Transparency = 0.15
	tele.CFrame = CFrame.new(origin)

	local part = Pool:Get()
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(radius*2, radius*2, radius*2)
	part.Color = Color3.fromRGB(255, 90, 90)
	part.Transparency = 1
	part.CFrame = CFrame.new(origin)

	table.insert(bullets, {
		part = part,
		tele = tele,
		pos = origin,
		vel = vel,
		r = radius,
		spawnAt = spawnAt,
		dieAt = workspace:GetServerTimeNow() + life,
	})
end

local function spawnExplosionTelegraph(startAt, pos, radius, telegraph, active)
	local ring = Pool:Get()
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, radius*2, radius*2)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0,0,math.rad(90))
	ring.Color = Color3.fromRGB(255, 230, 120)
	ring.Transparency = 0.35

	table.insert(hazards, {
		type="Explosion",
		part = ring,
		teleEnd = startAt + telegraph,
		activeEnd = startAt + telegraph + active,
	})
end

local function spawnBeam(startAt, origin, len, width, telegraph, active, duration, startDir, endDir)
	local beam = Pool:Get()
	beam.Shape = Enum.PartType.Block
	beam.Size = Vector3.new(width, width, len)
	beam.CFrame = CFrame.new(origin, origin + startDir) * CFrame.new(0,0,-len*0.5)
	beam.Color = Color3.fromRGB(255, 230, 120)
	beam.Transparency = 0.55

	table.insert(hazards, {
		type="Beam",
		part = beam,
		origin = origin,
		len = len,
		width = width,
		startAt = startAt,
		sweepEnd = startAt + duration,
		teleEnd = startAt + telegraph,
		activeEnd = startAt + telegraph + active,
		startDir = startDir,
		endDir = endDir,
	})
end

local function rotUpdateBeam(h, t)
	local alpha
	if t <= h.startAt then alpha = 0
	elseif t >= h.sweepEnd then alpha = 1
	else alpha = (t - h.startAt) / math.max(1e-6, (h.sweepEnd - h.startAt)) end

	local dir = (h.startDir:Lerp(h.endDir, alpha)).Unit
	h.part.CFrame = CFrame.new(h.origin, h.origin + dir) * CFrame.new(0,0,-h.len*0.5)

	if t < h.teleEnd then
		h.part.Color = Color3.fromRGB(255, 230, 120)
		h.part.Transparency = 0.55
	else
		h.part.Color = Color3.fromRGB(255, 90, 90)
		h.part.Transparency = 0.35
	end
end

local function handlePacket(packet)
	local tNow = workspace:GetServerTimeNow()

	if packet.type == "RadialBurst" then
		local origin = packet.origin
		for i=1, packet.bullets do
			local ang = (i-1) * (2*math.pi/packet.bullets)
			local dir = Vector3.new(math.cos(ang),0,math.sin(ang))
			spawnBulletVisual(packet.spawnAt, origin, dir*packet.speed, packet.radius, packet.life)
		end

	elseif packet.type == "AimedVolley" then
		-- Visual approx: still readable + matches telegraph timings
		local origin = packet.origin
		for i=1, packet.shots do
			local ang = math.rad((math.random()*2-1) * packet.spreadDeg)
			local dir = Vector3.new(math.cos(ang),0,math.sin(ang))
			spawnBulletVisual(packet.spawnAt + (i-1)*packet.shotGap, origin, dir*packet.speed, packet.radius, packet.life)
		end

	elseif packet.type == "DelayedExplosion" then
		spawnExplosionTelegraph(packet.startAt, packet.pos, packet.radius, packet.telegraph, packet.active)

	elseif packet.type == "SweepingBeam" then
		spawnBeam(packet.startAt, packet.origin, packet.len, packet.width, packet.telegraph, packet.active, packet.duration, packet.startDir, packet.endDir)
	end
end

-- Public-ish entry (called by BulletHellController after it receives Boss messages)
local Renderer = {}

function Renderer.Start()
	-- nothing needed
end

function Renderer.Stop()
	clearAll()
end

function Renderer.SpawnBatch(list)
	for _, packet in ipairs(list) do
		handlePacket(packet)
	end
end

-- Step visuals
RunService.RenderStepped:Connect(function(dt)
	local t = workspace:GetServerTimeNow()

	for i=#bullets,1,-1 do
		local b = bullets[i]
		if t >= b.dieAt then
			Pool:Release(b.part)
			Pool:Release(b.tele)
			table.remove(bullets,i)
		else
			if t < b.spawnAt then
				local scale = 1 + 0.25*math.sin((t - (b.spawnAt-0.3))*18)
				b.tele.Size = Vector3.new(b.r*1.4, b.r*1.4, b.r*1.4) * scale
				b.part.Transparency = 1
			else
				b.tele.Transparency = 1
				b.pos = b.pos + b.vel * dt
				b.part.Transparency = 0.05
				b.part.CFrame = CFrame.new(b.pos)
			end
		end
	end

	for i=#hazards,1,-1 do
		local h = hazards[i]
		if t >= h.activeEnd then
			Pool:Release(h.part)
			table.remove(hazards,i)
		else
			if h.type == "Explosion" then
				if t < h.teleEnd then
					h.part.Color = Color3.fromRGB(255, 230, 120)
				else
					h.part.Color = Color3.fromRGB(255, 90, 90)
					h.part.Transparency = 0.55
				end
			elseif h.type == "Beam" then
				rotUpdateBeam(h, t)
			end
		end
	end
end)

return Renderer
