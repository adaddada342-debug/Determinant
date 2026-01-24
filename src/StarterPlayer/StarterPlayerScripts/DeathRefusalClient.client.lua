-- StarterPlayerScripts/DeathRefusalClient.lua
	-- Plays Death Refusal VFX on all clients when server fires.

	local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DeathRefusalRE = Remotes:WaitForChild("DeathRefusalRE")

local LOCAL_PLAYER = Players.LocalPlayer

-- ======== CONFIG ========
local FX_DURATION = 2.6
local SPHERE_MAX_SIZE = 220
local COLUMN_HEIGHT = 170
local COLUMN_RADIUS = 35

-- ======== POST EFFECTS (created once) ========
local cc = Lighting:FindFirstChild("DeathRefusal_CC") :: ColorCorrectionEffect
if not cc then
	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "DeathRefusal_CC"
	cc.Parent = Lighting
end

local blur = Lighting:FindFirstChild("DeathRefusal_Blur") :: BlurEffect
if not blur then
	blur = Instance.new("BlurEffect")
	blur.Name = "DeathRefusal_Blur"
	blur.Parent = Lighting
end

local bloom = Lighting:FindFirstChild("DeathRefusal_Bloom") :: BloomEffect
if not bloom then
	bloom = Instance.new("BloomEffect")
	bloom.Name = "DeathRefusal_Bloom"
	bloom.Parent = Lighting
end

-- Default off
cc.Enabled = false
blur.Enabled = false
bloom.Enabled = false

local function tween(inst, ti, props)
	local t = TweenService:Create(inst, ti, props)
	t:Play()
	return t
end

local function makeNeonPart(size: Vector3, cframe: CFrame, transparency: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Size = size
	p.CFrame = cframe
	p.Transparency = transparency
	p.Parent = workspace:FindFirstChild("TempFX") or workspace
	return p
end

local function playScreenFX(isLocalVictim: boolean)
	cc.Enabled = true
	blur.Enabled = true
	bloom.Enabled = true

	-- Start “wrong”
	cc.Saturation = -1
	cc.Contrast = 0.2
	cc.Brightness = 0.1
	cc.TintColor = Color3.fromRGB(220, 220, 255)

	blur.Size = 18
	bloom.Intensity = 2.5
	bloom.Size = 56
	bloom.Threshold = 0.7

	-- For the victim, make it harsher
	if isLocalVictim then
		blur.Size = 24
		cc.Brightness = 0.2
	end

	-- Snap in, then decay
	tween(cc, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Contrast = 0.55,
		Brightness = 0.25
	})

	task.delay(0.25, function()
		tween(cc, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Contrast = 0.15,
			Brightness = 0.05,
			Saturation = -0.4
		})
		tween(blur, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = 10 })
		tween(bloom, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Intensity = 1.1, Size = 40 })
	end)

	task.delay(FX_DURATION, function()
		-- Smooth off
		tween(cc, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Contrast = 0,
			Brightness = 0,
			Saturation = 0,
			TintColor = Color3.fromRGB(255, 255, 255)
		})
		tween(blur, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = 0 })
		tween(bloom, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Intensity = 0, Size = 0 })

		task.delay(0.36, function()
			cc.Enabled = false
			blur.Enabled = false
			bloom.Enabled = false
		end)
	end)
end

local function playCameraPunch(isLocalVictim: boolean)
	-- Subtle for everyone, harsher for victim
	local cam = workspace.CurrentCamera
	if not cam then return end

	local strength = isLocalVictim and 1.0 or 0.45
	local start = os.clock()

	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t >= 0.25 then
			conn:Disconnect()
			return
		end

		-- quick jitter that decays
		local decay = 1 - (t / 0.25)
		local x = (math.noise(t * 60, 0, 0) - 0.5) * 0.22 * strength * decay
		local y = (math.noise(0, t * 60, 0) - 0.5) * 0.18 * strength * decay

		cam.CFrame = cam.CFrame * CFrame.new(x, y, 0)
	end)
end

local function playWorldFX(pos: Vector3)
	-- Expanding “breach sphere”
	local sphere = makeNeonPart(Vector3.new(1, 1, 1), CFrame.new(pos), 0.65)
	sphere.Shape = Enum.PartType.Ball

	-- Fake “mushroom-ish” column (just visual)
	local column = makeNeonPart(Vector3.new(COLUMN_RADIUS, 1, COLUMN_RADIUS), CFrame.new(pos + Vector3.new(0, 0.5, 0)), 0.75)
	column.Shape = Enum.PartType.Cylinder
	column.CFrame = column.CFrame * CFrame.Angles(0, 0, math.rad(90))

	local cap = makeNeonPart(Vector3.new(1, 1, 1), CFrame.new(pos + Vector3.new(0, COLUMN_HEIGHT * 0.7, 0)), 0.72)
	cap.Shape = Enum.PartType.Ball

	local light = Instance.new("PointLight")
	light.Brightness = 12
	light.Range = 70
	light.Parent = sphere

	-- Animate
	tween(sphere, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(SPHERE_MAX_SIZE, SPHERE_MAX_SIZE, SPHERE_MAX_SIZE),
		Transparency = 0.9
	})
	tween(light, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
		Range = 0
	})

	-- Column rise
	tween(column, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(COLUMN_RADIUS, COLUMN_HEIGHT, COLUMN_RADIUS),
		Transparency = 0.88
	})
	tween(cap, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(COLUMN_RADIUS * 2.2, COLUMN_RADIUS * 1.2, COLUMN_RADIUS * 2.2),
		Transparency = 0.9
	})

	-- Cleanup
	task.delay(1.2, function()
		if sphere then sphere:Destroy() end
		if column then column:Destroy() end
		if cap then cap:Destroy() end
	end)
end

DeathRefusalRE.OnClientEvent:Connect(function(worldPos: Vector3, victimUserId: number)
	local isLocalVictim = (victimUserId == LOCAL_PLAYER.UserId)

	-- Screen + camera
	playScreenFX(isLocalVictim)
	playCameraPunch(isLocalVictim)

	-- World VFX at the position
	playWorldFX(worldPos)
end)
