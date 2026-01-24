-- ServerScriptService/DeathRefusalExplosion.server.lua
-- Shared Death Refusal explosion:
-- ✅ Spawns Explosion_Pillar for everyone (server-owned)
-- ✅ Uses ExplosionRotationConfig inside the MODEL as the single source of truth (rotation + height)
-- ✅ Broadcasts camera "anti-blind" zoom-out to all clients
-- ✅ Actively spins SwirlCloud around X-axis (server-owned, always-on)
-- ✅ NEW: Broadcasts impact frames (Lighting.RefusalFrame1 -> RefusalFrame2) to all clients

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

--============================================================
-- REMOTE SETUP
--============================================================
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RE = Remotes:FindFirstChild("DeathRefusalExplosionRE")
if not RE then
	RE = Instance.new("RemoteEvent")
	RE.Name = "DeathRefusalExplosionRE"
	RE.Parent = Remotes
end

--============================================================
-- TEMPLATE LOOKUP (supports both structures)
--============================================================
local CANDIDATE_PATHS = {
	{"VFX","Explosions","Explosion_Pillar"},
	{"Assets","VFX","Explosions","Explosion_Pillar"},
	{"Assets","Vfx","Explosions","Explosion_Pillar"},
	{"Assets","Effects","Explosions","Explosion_Pillar"},
}

local function getByPath(root: Instance, path: {string})
	local cur: Instance? = root
	for _, name in ipairs(path) do
		if not cur then return nil end
		cur = cur:FindFirstChild(name)
	end
	return cur
end

local function getTemplate(): Model?
	for _, path in ipairs(CANDIDATE_PATHS) do
		local obj = getByPath(ReplicatedStorage, path)
		if obj and obj:IsA("Model") then
			return obj
		end
	end
	return nil
end

--============================================================
-- CONFIG (Rotation + Height)
--============================================================
local function readConfig(template: Model): (CFrame, number)
	local cfg = template:FindFirstChild("ExplosionRotationConfig", true)
	if not (cfg and cfg:IsA("ModuleScript")) then
		warn("[DeathRefusalExplosion] Missing ExplosionRotationConfig. Defaults used.")
		return CFrame.new(), 0
	end

	local ok, data = pcall(require, cfg)
	if not ok or type(data) ~= "table" then
		warn("[DeathRefusalExplosion] ExplosionRotationConfig invalid. Defaults used.")
		return CFrame.new(), 0
	end

	local function n(...)
		for i = 1, select("#", ...) do
			local k = select(i, ...)
			local v = data[k]
			if v ~= nil then
				local num = tonumber(v)
				if num ~= nil then return num end
			end
		end
		return nil
	end

	local rx = n("RotX","rx","X") or 0
	local ry = n("RotY","ry","YRot","RotYDeg") or 0
	local rz = n("RotZ","rz","Z") or 0
	local yaw = n("Yaw","yaw","YAW") or 0

	-- THIS is the important part:
	-- Accept UpOffset OR y/Y/Height/etc
	local up  = n("UpOffset","upOffset","Up","up","YOffset","yOffset","Y","y","Height","height") or 0

	local rot = CFrame.Angles(math.rad(rx), math.rad(ry + yaw), math.rad(rz))

	print(("[DeathRefusalExplosion] Config applied: Up=%s Rot=(%s,%s,%s) Yaw=%s")
		:format(tostring(up), tostring(rx), tostring(ry), tostring(rz), tostring(yaw)))

	return rot, up
end


--============================================================
-- MODEL PREP
--============================================================
local function ensurePrimaryPart(model: Model)
	if model.PrimaryPart then return end
	local pp = model:FindFirstChildWhichIsA("BasePart", true)
	if pp then
		pcall(function() model.PrimaryPart = pp end)
	end
end

local function disableInternalScripts(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d.Disabled = true
		end
	end
end

local function prepVfxModel(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = true
			local burst = d:GetAttribute("Burst")
			if typeof(burst) == "number" and burst > 0 then
				pcall(function() d:Emit(math.floor(burst)) end)
			end
		elseif d:IsA("Beam") or d:IsA("Trail") then
			d.Enabled = true
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			d.Enabled = true
		end
	end
end

--============================================================
-- ACTIVE SPIN (server-owned)
--============================================================
local SPIN_PART_NAME = "SwirlCloud"  -- ✅ your part name
local SPIN_SPEED_DEG = 60           -- tweak rotation speed here
local spinConns = setmetatable({}, { __mode = "k" }) -- weak keys

local function findSpinPart(model: Model): BasePart?
	local p = model:FindFirstChild(SPIN_PART_NAME, true)
	if p and p:IsA("BasePart") then return p end
	return nil
end

local function startSpin(model: Model)
	local part = findSpinPart(model)
	if not part then
		warn("[DeathRefusalExplosion] Spin part not found:", SPIN_PART_NAME)
		return
	end

	if spinConns[model] then
		spinConns[model]:Disconnect()
		spinConns[model] = nil
	end

	local speed = math.rad(SPIN_SPEED_DEG)
	local angle = 0

	-- Lock the base rotation (no drift) + keep position stable
	local basePos = part.Position
	local baseRot = part.CFrame - part.CFrame.Position -- rotation-only CFrame

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent or not part.Parent then
			if conn then conn:Disconnect() end
			spinConns[model] = nil
			return
		end

		angle += speed * dt

		-- Rotate around the PART'S ORIGINAL local axis (stable, no wobble)
		local newRot = baseRot * CFrame.Angles(0, angle, 0)
		part.CFrame = CFrame.new(basePos) * newRot
	end)

	spinConns[model] = conn
end

--============================================================
-- THROTTLE
--============================================================
local lastFire: {[number]: number} = {}
local COOLDOWN = 6.0

Players.PlayerRemoving:Connect(function(p)
	lastFire[p.UserId] = nil
end)

--============================================================
-- MAIN
--============================================================
RE.OnServerEvent:Connect(function(player, payload)
	if typeof(payload) ~= "table" then return end

	-- cooldown
	local now = os.clock()
	local uid = player.UserId
	if lastFire[uid] and (now - lastFire[uid]) < COOLDOWN then
		return
	end
	lastFire[uid] = now

	-- center
	local center = payload.center
	local cf: CFrame?
	if typeof(center) == "Vector3" then
		cf = CFrame.new(center)
	elseif typeof(center) == "CFrame" then
		cf = center
	else
		return
	end

	local template = getTemplate()
	if not template then
		warn("[DeathRefusalExplosion] Template not found.")
		return
	end

	-- Read config ONCE (rotation + up)
	local rotFix, cfgUp = readConfig(template)

	-- Decide UpOffset:
	local up = cfgUp
	if payload.allowUpOverride == true then
		local pUp = tonumber(payload.upOffset)
		if pUp ~= nil then up = pUp end
	end

	print(("[DeathRefusalExplosion] up=%s (cfg=%s, payload=%s, override=%s)")
		:format(tostring(up), tostring(cfgUp), tostring(payload.upOffset), tostring(payload.allowUpOverride)))

	-- Clone + prep
	local model = template:Clone()
	model.Name = "__DeathRefusalExplosion"

	disableInternalScripts(model)
	ensurePrimaryPart(model)
	prepVfxModel(model)

	-- Apply offset + rotation (single PivotTo)
	local spawnCF = (cf + Vector3.new(0, up, 0)) * rotFix
	model:PivotTo(spawnCF)
	model.Parent = workspace

	-- Start swirl spin (server-owned)
	startSpin(model)

	--============================================================
	-- BROADCAST: CAMERA SAFETY
	--============================================================
	local duration = tonumber(payload.cameraDuration) or 4.25
	RE:FireAllClients({
		kind = "camera",
		center = spawnCF.Position,
		duration = duration,
		dist = tonumber(payload.cameraDist) or 320,
		height = tonumber(payload.cameraHeight) or 110,
		fov = tonumber(payload.cameraFov) or 78,
	})

	--============================================================
	-- ✅ NEW: BROADCAST IMPACT FRAMES (client-side Lighting effects)
	--============================================================
	-- Total time both frames combined should be ~0.25–0.5s.
	-- Default: 0.35s total, split 50/50.
	RE:FireAllClients({
		kind = "impactFrames",
		total = tonumber(payload.impactTotal) or 0.35, -- combined duration
		split = tonumber(payload.impactSplit) or 0.5, -- 0..1 portion for Frame1
		-- optional: allow payload to override exact names if you ever rename them
		frame1 = tostring(payload.frame1 or "RefusalFrame1"),
		frame2 = tostring(payload.frame2 or "RefusalFrame2"),
	})

	Debris:AddItem(model, tonumber(payload.lifetime) or 18)
end)
