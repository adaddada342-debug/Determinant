--!strict
-- StarterPlayerScripts/AAAPolish_Visual.client.lua
-- Cinematic visual polish: adaptive post FX + subtle vignette + film grain + UI micro-motion (no camera CFrame writes).

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Config = {
	Enable = {
		PostFX = true,
		Vignette = true,
		FilmGrain = true,
		UIMicroMotion = true,
	},

	-- PostFX behavior (safe by default: won't create effects unless enabled)
	PostFX = {
		CreateMissing = false, -- if true, creates modest effects if absent

		-- Effects are gently modulated by movement + camera angular velocity (turning)
		Blur = { Enabled = true, Name = "AAAPolish_Blur", Idle = 0.0, Move = 2.2, TurnAdd = 0.8, Responsiveness = 7 },
		DepthOfField = {
			Enabled = true, Name = "AAAPolish_DOF",
			IdleNear = 0.02, MoveNear = 0.10,
			IdleFar  = 0.04, MoveFar  = 0.12,
			Responsiveness = 6,
		},
		Bloom = { Enabled = true, Name = "AAAPolish_Bloom", BaseAdd = 0.00, MoveAdd = 0.06, Responsiveness = 5 },
		ColorCorrection = {
			Enabled = true, Name = "AAAPolish_CC",
			MoveContrastAdd = 0.04,
			MoveSaturationAdd = 0.03,
			TurnContrastAdd = 0.02,
			Responsiveness = 5,
		},
		SunRays = { Enabled = false, Name = "AAAPolish_SunRays", MoveIntensityAdd = 0.01, Responsiveness = 3 },
	},

	-- Vignette overlay (UI). Provide your own image for best results.
	Vignette = {
		Image = "rbxassetid://0", -- set to a soft vignette PNG (transparent center, dark edges)
		IdleAlpha = 0.08,
		MoveAlpha = 0.14,
		TurnAlphaAdd = 0.04,
		Responsiveness = 8,
	},

	-- Film grain overlay (UI). Use a seamless noise texture if you have one.
	FilmGrain = {
		Image = "rbxassetid://0", -- set to a noise texture with transparency (tileable)
		IdleAlpha = 0.05,
		MoveAlpha = 0.07,
		Responsiveness = 10,
		ScrollSpeed = 0.35, -- subtle drift so it doesn't look like a static JPG
		TileScale = 1.6,
	},

	-- UI micro motion (very subtle parallax on the overlays so it feels “alive”)
	UIMicroMotion = {
		MaxPixels = 6,          -- max drift in pixels
		Responsiveness = 10,
	},

	-- Speed mapping (no humanoid dependency, uses velocity if possible)
	Speed = {
		WalkRef = 10,
		SprintRef = 20,
	},
}

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

----------------------------------------------------------------
-- UTILS
----------------------------------------------------------------
local function expAlpha(k: number, dt: number): number
	if k <= 0 then return 1 end
	return 1 - math.exp(-k * dt)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

local function findOrCreate(className: string, name: string, create: boolean): Instance?
	-- Prefer exact name, then any instance of same class in Lighting
	for _, inst in ipairs(Lighting:GetChildren()) do
		if inst.ClassName == className and inst.Name == name then
			return inst
		end
	end
	for _, inst in ipairs(Lighting:GetChildren()) do
		if inst.ClassName == className then
			return inst
		end
	end
	if create then
		local created = Instance.new(className)
		created.Name = name
		created.Parent = Lighting
		return created
	end
	return nil
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local char: Model? = nil
local hrp: BasePart? = nil

local blurFx: BlurEffect? = nil
local dofFx: DepthOfFieldEffect? = nil
local bloomFx: BloomEffect? = nil
local ccFx: ColorCorrectionEffect? = nil
local sunFx: SunRaysEffect? = nil

local blurBase = 0.0
local dofNearBase = 0.0
local dofFarBase = 0.0
local bloomBase = 0.0
local ccContrastBase = 0.0
local ccSaturationBase = 0.0
local sunIntensityBase = 0.0

-- UI overlays
local gui: ScreenGui? = nil
local vignette: ImageLabel? = nil
local grain: ImageLabel? = nil

local vignetteAlpha = 0.0
local grainAlpha = 0.0
local uiOffsetX, uiOffsetY = 0.0, 0.0
local lastCamLook = camera.CFrame.LookVector

----------------------------------------------------------------
-- UI BUILD
----------------------------------------------------------------
local function destroyUI()
	if gui then gui:Destroy() end
	gui, vignette, grain = nil, nil, nil
end

local function buildUI()
	destroyUI()

	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end

	gui = Instance.new("ScreenGui")
	gui.Name = "AAAPolish_VisualUI"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = pg

	if Config.Enable.Vignette then
		local img = Instance.new("ImageLabel")
		img.Name = "Vignette"
		img.BackgroundTransparency = 1
		img.Image = Config.Vignette.Image
		img.ImageTransparency = 1
		img.ScaleType = Enum.ScaleType.Stretch
		img.Size = UDim2.fromScale(1, 1)
		img.Position = UDim2.fromScale(0, 0)
		img.ZIndex = 1000
		img.Parent = gui
		vignette = img
	end

	if Config.Enable.FilmGrain then
		local img = Instance.new("ImageLabel")
		img.Name = "FilmGrain"
		img.BackgroundTransparency = 1
		img.Image = Config.FilmGrain.Image
		img.ImageTransparency = 1
		img.ScaleType = Enum.ScaleType.Tile
		img.TileSize = UDim2.fromScale(1 / Config.FilmGrain.TileScale, 1 / Config.FilmGrain.TileScale)
		img.Size = UDim2.fromScale(1, 1)
		img.Position = UDim2.fromScale(0, 0)
		img.ZIndex = 999
		img.Parent = gui
		grain = img
	end
end

----------------------------------------------------------------
-- FX CACHE
----------------------------------------------------------------
local function cacheFX()
	if not Config.Enable.PostFX then return end
	local create = Config.PostFX.CreateMissing

	if Config.PostFX.Blur.Enabled then
		blurFx = findOrCreate("BlurEffect", Config.PostFX.Blur.Name, create) :: BlurEffect?
		if blurFx then blurBase = blurFx.Size end
	end
	if Config.PostFX.DepthOfField.Enabled then
		dofFx = findOrCreate("DepthOfFieldEffect", Config.PostFX.DepthOfField.Name, create) :: DepthOfFieldEffect?
		if dofFx then
			dofNearBase = dofFx.NearIntensity
			dofFarBase = dofFx.FarIntensity
		end
	end
	if Config.PostFX.Bloom.Enabled then
		bloomFx = findOrCreate("BloomEffect", Config.PostFX.Bloom.Name, create) :: BloomEffect?
		if bloomFx then bloomBase = bloomFx.Intensity end
	end
	if Config.PostFX.ColorCorrection.Enabled then
		ccFx = findOrCreate("ColorCorrectionEffect", Config.PostFX.ColorCorrection.Name, create) :: ColorCorrectionEffect?
		if ccFx then
			ccContrastBase = ccFx.Contrast
			ccSaturationBase = ccFx.Saturation
		end
	end
	if Config.PostFX.SunRays.Enabled then
		sunFx = findOrCreate("SunRaysEffect", Config.PostFX.SunRays.Name, create) :: SunRaysEffect?
		if sunFx then sunIntensityBase = sunFx.Intensity end
	end
end

local function restoreFX()
	if blurFx then blurFx.Size = blurBase end
	if dofFx then
		dofFx.NearIntensity = dofNearBase
		dofFx.FarIntensity = dofFarBase
	end
	if bloomFx then bloomFx.Intensity = bloomBase end
	if ccFx then
		ccFx.Contrast = ccContrastBase
		ccFx.Saturation = ccSaturationBase
	end
	if sunFx then sunFx.Intensity = sunIntensityBase end
end

----------------------------------------------------------------
-- CHARACTER BIND
----------------------------------------------------------------
local function bindCharacter(c: Model)
	char = c
	hrp = c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		local t0 = os.clock()
		while os.clock() - t0 < 5 do
			task.wait(0.1)
			if char ~= c then return end
			hrp = c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then break end
		end
	end
end

player.CharacterAdded:Connect(function(c)
	bindCharacter(c)
end)
if player.Character then bindCharacter(player.Character) end

cacheFX()
buildUI()

----------------------------------------------------------------
-- LOOP
----------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt: number)
	if not camera then camera = workspace.CurrentCamera end

	-- Movement scalar (0..1)
	local speed = 0.0
	if hrp then
		local v = hrp.AssemblyLinearVelocity
		speed = Vector3.new(v.X, 0, v.Z).Magnitude
	end
	local moveT = clamp(speed / Config.Speed.SprintRef, 0, 1)

	-- Turn scalar from camera look delta
	local look = camera.CFrame.LookVector
	local turnDot = clamp(lastCamLook:Dot(look), -1, 1)
	lastCamLook = look
	local turn = clamp((1 - turnDot) * 4.0, 0, 1) -- cheap but stable

	-- PostFX modulation
	if Config.Enable.PostFX then
		if blurFx and Config.PostFX.Blur.Enabled then
			local target = lerp(Config.PostFX.Blur.Idle, Config.PostFX.Blur.Move, moveT) + Config.PostFX.Blur.TurnAdd * turn
			blurFx.Size = lerp(blurFx.Size, target, expAlpha(Config.PostFX.Blur.Responsiveness, dt))
		end
		if dofFx and Config.PostFX.DepthOfField.Enabled then
			local targetNear = lerp(Config.PostFX.DepthOfField.IdleNear, Config.PostFX.DepthOfField.MoveNear, moveT)
			local targetFar  = lerp(Config.PostFX.DepthOfField.IdleFar,  Config.PostFX.DepthOfField.MoveFar,  moveT)
			local a = expAlpha(Config.PostFX.DepthOfField.Responsiveness, dt)
			dofFx.NearIntensity = lerp(dofFx.NearIntensity, dofNearBase + targetNear, a)
			dofFx.FarIntensity  = lerp(dofFx.FarIntensity,  dofFarBase  + targetFar,  a)
		end
		if bloomFx and Config.PostFX.Bloom.Enabled then
			local target = bloomBase + Config.PostFX.Bloom.BaseAdd + (Config.PostFX.Bloom.MoveAdd * moveT)
			bloomFx.Intensity = lerp(bloomFx.Intensity, target, expAlpha(Config.PostFX.Bloom.Responsiveness, dt))
		end
		if ccFx and Config.PostFX.ColorCorrection.Enabled then
			local targetC = ccContrastBase + (Config.PostFX.ColorCorrection.MoveContrastAdd * moveT) + (Config.PostFX.ColorCorrection.TurnContrastAdd * turn)
			local targetS = ccSaturationBase + (Config.PostFX.ColorCorrection.MoveSaturationAdd * moveT)
			local a = expAlpha(Config.PostFX.ColorCorrection.Responsiveness, dt)
			ccFx.Contrast = lerp(ccFx.Contrast, targetC, a)
			ccFx.Saturation = lerp(ccFx.Saturation, targetS, a)
		end
		if sunFx and Config.PostFX.SunRays.Enabled then
			local target = sunIntensityBase + (Config.PostFX.SunRays.MoveIntensityAdd * moveT)
			sunFx.Intensity = lerp(sunFx.Intensity, target, expAlpha(Config.PostFX.SunRays.Responsiveness, dt))
		end
	end

	-- Vignette + Grain
	if vignette and Config.Enable.Vignette then
		local target = lerp(Config.Vignette.IdleAlpha, Config.Vignette.MoveAlpha, moveT) + Config.Vignette.TurnAlphaAdd * turn
		vignetteAlpha = lerp(vignetteAlpha, target, expAlpha(Config.Vignette.Responsiveness, dt))
		vignette.ImageTransparency = clamp(1 - vignetteAlpha, 0, 1)
	end
	if grain and Config.Enable.FilmGrain then
		local target = lerp(Config.FilmGrain.IdleAlpha, Config.FilmGrain.MoveAlpha, moveT)
		grainAlpha = lerp(grainAlpha, target, expAlpha(Config.FilmGrain.Responsiveness, dt))
		grain.ImageTransparency = clamp(1 - grainAlpha, 0, 1)

		-- subtle drift to avoid "static overlay" look
		local s = Config.FilmGrain.ScrollSpeed
		grain.Position = grain.Position + UDim2.fromOffset((s * 60) * dt, (s * 30) * dt)
	end

	-- UI micro motion (tiny parallax from turning)
	if gui and Config.Enable.UIMicroMotion then
		local targetX = (turn * Config.UIMicroMotion.MaxPixels) * (look.X >= 0 and 1 or -1)
		local targetY = (turn * (Config.UIMicroMotion.MaxPixels * 0.35)) * (look.Y >= 0 and -1 or 1)
		local a = expAlpha(Config.UIMicroMotion.Responsiveness, dt)
		uiOffsetX = lerp(uiOffsetX, targetX, a)
		uiOffsetY = lerp(uiOffsetY, targetY, a)
		gui.DisplayOrder = 1000
		if vignette then vignette.Position = UDim2.fromOffset(uiOffsetX, uiOffsetY) end
		if grain then grain.Position = UDim2.fromOffset(uiOffsetX * 0.7, uiOffsetY * 0.7) end
	end
end)

script.Destroying:Connect(function()
	restoreFX()
	destroyUI()
end)
