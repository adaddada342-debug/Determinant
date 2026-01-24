-- ServerScriptService/DeathRefusalExplosion.server.lua
-- Spawns Explosion_Pillar server-owned + catastrophic animation + fade-out
-- ✅ Reads ModuleScript "ExplosionRotationConfig" inside Explosion_Pillar (rot + UpOffset)
-- ✅ Strong initial burst + secondary pulse + beam surge
-- ✅ Fade after payload.fadeAfter, never deleted early
-- ✅ Basic validation + throttling

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

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
-- TEMPLATE LOOKUP
-- ReplicatedStorage/Assets/VFX/Explosions/Explosion_Pillar
--============================================================
local function getTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	local vfx = assets:FindFirstChild("VFX")
	if not vfx then return nil end
	local explosions = vfx:FindFirstChild("Explosions")
	if not explosions then return nil end
	local model = explosions:FindFirstChild("Explosion_Pillar")
	if model and model:IsA("Model") then return model end
	return nil
end

--============================================================
-- CONFIG (ModuleScript inside the MODEL)
--============================================================
local function readConfig(template: Model, payload: any): (CFrame, number)
	local cfg = template:FindFirstChild("ExplosionRotationConfig", true)

	local data = {}
	if cfg and cfg:IsA("ModuleScript") then
		local ok, required = pcall(require, cfg)
		if ok and type(required) == "table" then
			data = required
		else
			warn("[DeathRefusalExplosion] ExplosionRotationConfig exists but invalid; defaults used.")
		end
	else
		warn("[DeathRefusalExplosion] Missing ExplosionRotationConfig; defaults used.")
	end

	local function pickNumber(...)
		for i = 1, select("#", ...) do
			local k = select(i, ...)
			local v = data[k]
			if v ~= nil then
				local n = tonumber(v)
				if n ~= nil then return n end
			end
		end
		return nil
	end

	local rx  = pickNumber("RotX","rx","XRot") or 0
	local ry  = pickNumber("RotY","ry","YRot") or 0
	local rz  = pickNumber("RotZ","rz","ZRot") or 0
	local yaw = pickNumber("Yaw","yaw","YawDeg") or 0
	local up  = pickNumber("UpOffset","upOffset","Up","up","YOffset","yOffset","Y","y","Height","height") or 0

	-- Optional payload overrides (debug)
	if typeof(payload) == "table" and payload.allowUpOverride == true then
		local p = tonumber(payload.upOffset)
		if p ~= nil then up = p end
	end
	if typeof(payload) == "table" and payload.allowYawOverride == true then
		local p = tonumber(payload.yawOffsetDeg)
		if p ~= nil then yaw = p end
	end

	local rot = CFrame.Angles(math.rad(rx), math.rad(ry + yaw), math.rad(rz))
	return rot, up
end

--============================================================
-- MODEL PREP
--============================================================
local function ensurePrimaryPart(model: Model)
	if model.PrimaryPart then return end
	local pp = model:FindFirstChildWhichIsA("BasePart", true)
	if pp then pcall(function() model.PrimaryPart = pp end) end
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
		elseif d:IsA("Beam") or d:IsA("Trail") then
			d.Enabled = true
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			d.Enabled = true
		end
	end
end

local function collectParts(root: Instance): {BasePart}
	local t = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(t, d) end
	end
	return t
end

local function cacheSizes(parts: {BasePart})
	for _, p in ipairs(parts) do
		if p:GetAttribute("OrigX") == nil then
			p:SetAttribute("OrigX", p.Size.X)
			p:SetAttribute("OrigY", p.Size.Y)
			p:SetAttribute("OrigZ", p.Size.Z)
		end
	end
end

--============================================================
-- CATASTROPHIC ANIMATION
--============================================================
local function animateExplosion(model: Model)
	local sphereFolder = model:FindFirstChild("Sphere")
	local pillarFolder = model:FindFirstChild("EnergyPillar")
	local shockWave = model:FindFirstChild("ShockWave")

	local sphereParts = sphereFolder and collectParts(sphereFolder) or {}
	local pillarParts = pillarFolder and collectParts(pillarFolder) or {}
	local shockParts = {}
	if shockWave and shockWave:IsA("BasePart") then shockParts = {shockWave} end

	cacheSizes(sphereParts)
	cacheSizes(pillarParts)
	cacheSizes(shockParts)

	-- Start: hide sphere/shock then nuke them into view
	for _, p in ipairs(sphereParts) do p.Transparency = 1 end
	for _, p in ipairs(shockParts) do p.Transparency = 1 end

	-- ========== DETONATION BURST ==========
	for _, p in ipairs(sphereParts) do
		local ox, oy, oz = p:GetAttribute("OrigX"), p:GetAttribute("OrigY"), p:GetAttribute("OrigZ")
		if ox then
			p.Size = Vector3.new(ox, oy, oz) * 0.06
			p.Transparency = 1

			TweenService:Create(p, TweenInfo.new(0.08, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Transparency = 0.04,
				Size = Vector3.new(ox, oy, oz) * 1.60,
			}):Play()

			task.delay(0.09, function()
				if p.Parent then
					TweenService:Create(p, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.InOut), {
						Size = Vector3.new(ox, oy, oz) * 1.05,
					}):Play()
				end
			end)

			task.delay(0.35, function()
				if p.Parent then
					local up = TweenInfo.new(0.10, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
					local down = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					local t1 = TweenService:Create(p, up, {Size = Vector3.new(ox, oy, oz) * 1.22})
					t1:Play()
					t1.Completed:Connect(function()
						if p.Parent then
							TweenService:Create(p, down, {Size = Vector3.new(ox, oy, oz) * 1.08}):Play()
						end
					end)
				end
			end)

			task.spawn(function()
				task.wait(0.60)
				local upInfo = TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				local downInfo = TweenInfo.new(0.60, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				for _ = 1, 4 do
					if not p.Parent then return end
					local t1 = TweenService:Create(p, upInfo, {Size = Vector3.new(ox, oy, oz) * 1.12})
					t1:Play(); t1.Completed:Wait()
					if not p.Parent then return end
					local t2 = TweenService:Create(p, downInfo, {Size = Vector3.new(ox, oy, oz) * 1.06})
					t2:Play(); t2.Completed:Wait()
				end
			end)
		end
	end

	-- ShockWave
	for _, p in ipairs(shockParts) do
		local ox, oy, oz = p:GetAttribute("OrigX"), p:GetAttribute("OrigY"), p:GetAttribute("OrigZ")
		if ox then
			p.Size = Vector3.new(ox, oy, oz) * 0.18
			p.Transparency = 0.18

			TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Size = Vector3.new(ox, oy, oz) * 6.2,
				Transparency = 0.70,
			}):Play()

			task.delay(0.18, function()
				if p.Parent then
					TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Transparency = 1,
					}):Play()
				end
			end)
		end
	end

	-- Beam surge
	for _, p in ipairs(pillarParts) do
		local ox, oy, oz = p:GetAttribute("OrigX"), p:GetAttribute("OrigY"), p:GetAttribute("OrigZ")
		if ox then
			p.Transparency = math.min(p.Transparency, 0.06)

			p.Size = Vector3.new(ox, oy, oz) * 0.85
			TweenService:Create(p, TweenInfo.new(0.10, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Size = Vector3.new(ox, oy, oz) * 1.35,
			}):Play()

			task.delay(0.12, function()
				if p.Parent then
					TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Size = Vector3.new(ox, oy, oz) * 1.05,
					}):Play()
				end
			end)

			task.spawn(function()
				task.wait(0.55)
				local upInfo = TweenInfo.new(0.34, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				local downInfo = TweenInfo.new(0.40, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				for _ = 1, 5 do
					if not p.Parent then return end
					local t1 = TweenService:Create(p, upInfo, {Size = Vector3.new(ox, oy, oz) * 1.10})
					t1:Play(); t1.Completed:Wait()
					if not p.Parent then return end
					local t2 = TweenService:Create(p, downInfo, {Size = Vector3.new(ox, oy, oz) * 1.03})
					t2:Play(); t2.Completed:Wait()
				end
			end)
		end
	end

	-- Model rotation: intense first second, then slow
	local basePivot = model:GetPivot()
	local spin = 0
	local fastSpin = true
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent then
			if conn then conn:Disconnect() end
			return
		end

		local speed = fastSpin and math.rad(42) or math.rad(10)
		spin += dt * speed

		local pos = basePivot.Position
		local _, y, _ = basePivot:ToOrientation()
		model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, y + spin, 0))
	end)

	task.delay(1.0, function() fastSpin = false end)
	task.delay(12, function()
		if conn then conn:Disconnect() end
	end)
end

--============================================================
-- FADE OUT MODEL (smooth)
--============================================================
local function fadeOutAndDestroy(model: Model, fadeDur: number)
	fadeDur = tonumber(fadeDur) or 2.0
	if not model or not model.Parent then return end

	local parts = collectParts(model)
	for _, p in ipairs(parts) do
		TweenService:Create(p, TweenInfo.new(fadeDur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
		}):Play()
	end

	task.delay(fadeDur + 0.35, function()
		if model and model.Parent then model:Destroy() end
	end)
end

--============================================================
-- THROTTLE
--============================================================
local lastFire: {[number]: number} = {}
local COOLDOWN = 2.5
Players.PlayerRemoving:Connect(function(p) lastFire[p.UserId] = nil end)

--============================================================
-- BASIC VALIDATION
-- Only allow explosions near the firing player's character
--============================================================
local function isNearCharacter(player: Player, pos: Vector3, maxDist: number): boolean
	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return false end
	return (hrp.Position - pos).Magnitude <= maxDist
end

--============================================================
-- MAIN
--============================================================
RE.OnServerEvent:Connect(function(player, payload)
	if typeof(payload) ~= "table" then return end
	if payload.kind ~= "pillar" then return end

	-- cooldown
	local now = os.clock()
	local uid = player.UserId
	if lastFire[uid] and (now - lastFire[uid]) < COOLDOWN then return end
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

	-- validation: stop clients nuking random map coords
	if not isNearCharacter(player, cf.Position, 600) then
		warn("[DeathRefusalExplosion] Rejected: center too far from player.")
		return
	end

	local template = getTemplate()
	if not template then
		warn("[DeathRefusalExplosion] Template not found at ReplicatedStorage/Assets/VFX/Explosions/Explosion_Pillar")
		return
	end

	local rotFix, up = readConfig(template, payload)

	-- Clone + prep
	local model = template:Clone()
	model.Name = "__DeathRefusalExplosion"
	disableInternalScripts(model)
	ensurePrimaryPart(model)
	prepVfxModel(model)

	-- Spawn with UpOffset + rotation fix
	local spawnCF = (cf + Vector3.new(0, up, 0)) * rotFix
	model:PivotTo(spawnCF)
	model.Parent = workspace

	-- Animate catastrophic burst
	animateExplosion(model)

	-- Fade scheduling
	local fadeAfter = tonumber(payload.fadeAfter) or 7.0
	local fadeDur = tonumber(payload.fadeDur) or 2.25
	task.delay(fadeAfter, function()
		fadeOutAndDestroy(model, fadeDur)
	end)

	-- Debris must never delete early
	local lifetime = tonumber(payload.lifetime)
	if not lifetime then
		lifetime = fadeAfter + fadeDur + 3.0
	end
	lifetime = math.max(lifetime, fadeAfter + fadeDur + 3.0)
	Debris:AddItem(model, lifetime)
end)
