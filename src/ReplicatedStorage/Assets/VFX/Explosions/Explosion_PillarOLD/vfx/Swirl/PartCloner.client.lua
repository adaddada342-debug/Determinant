-- LocalScript (put INSIDE the particle-emitting Part)
-- Clones this part N times and moves the clones along strict 3D spherical orbits around the original.
-- Works best for cutscenes / client VFX. (Particles still billboard. We cheat with 3D emitter motion.)

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local host: BasePart = script.Parent
if not host or not host:IsA("BasePart") then
	warn("OrbitalEmitter: script.Parent must be a BasePart")
	return
end

-- =========================
-- CONFIG (tweak these)
-- =========================
local CFG = {
	-- How many clones to spawn (random in range)
	MinClones = 6,
	MaxClones = 14,

	-- Orbit radius (studs). "isnt too big" so keep this modest.
	MinRadius = 4,
	MaxRadius = 9,

	-- Speed (radians/sec). Higher = faster orbit.
	MinSpeed = 1.2,
	MaxSpeed = 2.8,

	-- Optional wobble (keeps it from looking like a perfect screensaver)
	-- Set WobbleStrength = 0 for perfectly strict orbits.
	WobbleStrength = 0.08,  -- 0.0 to 0.15 is reasonable
	WobbleFrequency = 1.6,  -- wobble speed

	-- Tilt range in degrees (adds real 3D feel)
	MinTiltDeg = -25,
	MaxTiltDeg = 25,

	-- Lifetime control
	RunForSeconds = 8.0,     -- set to math.huge to run forever
	FadeOutSeconds = 0.25,   -- fade clones out at end (0 to disable)

	-- Behavior
	FollowHostIfMoved = true, -- if your host part moves, orbit center follows it
	CloneTransparencyOverride = nil, -- set number 0-1 to force clone transparency (nil keeps original)
	AnchoredClones = true,
	DisableCollisions = true,
}

-- =========================
-- Internal helpers
-- =========================
local function randf(a: number, b: number): number
	return a + (b - a) * math.random()
end

local function clamp(n, a, b)
	if n < a then return a end
	if n > b then return b end
	return n
end

local function safeSetDescendants(part: Instance, prop: string, value: any)
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			-- keep emitters enabled; you can tweak Rate separately if you want
		end
	end
	if part:IsA("BasePart") then
		part[prop] = value
	end
end

-- Returns a point on a unit sphere using spherical coords
local function unitFromSpherical(theta: number, phi: number): Vector3
	-- theta: 0..2pi around Y
	-- phi:   0..pi from top to bottom
	return Vector3.new(
		math.sin(phi) * math.cos(theta),
		math.cos(phi),
		math.sin(phi) * math.sin(theta)
	)
end

-- Rotate a vector by a tilt around X and Z to get real 3D orbit planes
local function tiltVector(v: Vector3, tiltX: number, tiltZ: number): Vector3
	local cx, sx = math.cos(tiltX), math.sin(tiltX)
	local cz, sz = math.cos(tiltZ), math.sin(tiltZ)

	-- rotate around X
	local y1 = v.Y * cx - v.Z * sx
	local z1 = v.Y * sx + v.Z * cx
	local x1 = v.X

	-- rotate around Z
	local x2 = x1 * cz - y1 * sz
	local y2 = x1 * sz + y1 * cz
	local z2 = z1

	return Vector3.new(x2, y2, z2)
end

-- =========================
-- Spawn clones
-- =========================
math.randomseed(os.clock() * 1e6)

local cloneCount = math.random(CFG.MinClones, CFG.MaxClones)
cloneCount = clamp(cloneCount, 0, 80) -- sanity cap

local clones = table.create(cloneCount)
local params = table.create(cloneCount)

for i = 1, cloneCount do
	local c: BasePart = host:Clone()
	c.Name = host.Name .. "_Orbiter_" .. i

	if CFG.DisableCollisions then
		c.CanCollide = false
		c.CanQuery = false
		c.CanTouch = false
	end

	if CFG.AnchoredClones then
		c.Anchored = true
	end

	if CFG.CloneTransparencyOverride ~= nil then
		c.Transparency = clamp(CFG.CloneTransparencyOverride, 0, 1)
	end

	-- Parent next to host (same parent) so it appears in same place in workspace hierarchy
	c.Parent = host.Parent

	-- Random orbit parameters
	local radius = randf(CFG.MinRadius, CFG.MaxRadius)
	local speed  = randf(CFG.MinSpeed, CFG.MaxSpeed)

	-- Different phases so they don't stack
	local theta0 = randf(0, math.pi * 2)
	local phi0   = randf(0.25 * math.pi, 0.75 * math.pi) -- avoid exact poles (looks weird)

	-- Random tilt plane
	local tiltX = math.rad(randf(CFG.MinTiltDeg, CFG.MaxTiltDeg))
	local tiltZ = math.rad(randf(CFG.MinTiltDeg, CFG.MaxTiltDeg))

	clones[i] = c
	params[i] = {
		r = radius,
		w = speed,
		t0 = theta0,
		p0 = phi0,
		tiltX = tiltX,
		tiltZ = tiltZ,
		wobPhase = randf(0, math.pi*2),
	}

	-- Optional cleanup if you want them to be auto-removed anyway
	Debris:AddItem(c, CFG.RunForSeconds + 2)
end

-- =========================
-- Orbit loop
-- =========================
local startTime = os.clock()
local conn
conn = RunService.RenderStepped:Connect(function()
	if not host.Parent then
		-- host got removed, kill everything
		if conn then conn:Disconnect() end
		for _, c in ipairs(clones) do
			if c and c.Parent then c:Destroy() end
		end
		return
	end

	local t = os.clock() - startTime
	local centerCFrame = CFG.FollowHostIfMoved and host.CFrame or host.CFrame -- same either way, but kept readable
	local centerPos = centerCFrame.Position

	-- End condition
	if t >= CFG.RunForSeconds then
		if conn then conn:Disconnect() end

		-- optional fade out
		if CFG.FadeOutSeconds and CFG.FadeOutSeconds > 0 then
			local fadeStart = os.clock()
			local fadeConn
			fadeConn = RunService.RenderStepped:Connect(function()
				local ft = os.clock() - fadeStart
				local a = clamp(ft / CFG.FadeOutSeconds, 0, 1)
				for _, c in ipairs(clones) do
					if c and c.Parent then
						c.Transparency = clamp(c.Transparency + a * 0.12, 0, 1)
					end
				end
				if a >= 1 then
					if fadeConn then fadeConn:Disconnect() end
					for _, c in ipairs(clones) do
						if c and c.Parent then c:Destroy() end
					end
				end
			end)
		else
			for _, c in ipairs(clones) do
				if c and c.Parent then c:Destroy() end
			end
		end
		return
	end

	for i, c in ipairs(clones) do
		if c and c.Parent then
			local p = params[i]

			-- Strict spherical motion:
			-- theta progresses with time, phi also oscillates a bit for a true 3D "wrap"
			local theta = p.t0 + t * p.w
			local phi = p.p0 + math.sin((t * p.w * 0.55) + p.wobPhase) * 0.22  -- controlled vertical travel

			-- Base sphere direction
			local dir = unitFromSpherical(theta, phi)

			-- Tilt orbit plane into 3D
			dir = tiltVector(dir, p.tiltX, p.tiltZ)

			-- Optional tiny wobble (keeps it alive, still basically strict)
			if CFG.WobbleStrength and CFG.WobbleStrength > 0 then
				local wob = math.sin(t * CFG.WobbleFrequency + p.wobPhase) * CFG.WobbleStrength
				dir = (dir + Vector3.new(wob, -wob * 0.5, wob * 0.75)).Unit
			end

			local pos = centerPos + dir * p.r

			-- Face outward for consistency (optional)
			c.CFrame = CFrame.new(pos, centerPos)
		end
	end
end)
