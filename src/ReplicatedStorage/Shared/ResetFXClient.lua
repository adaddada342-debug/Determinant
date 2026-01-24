-- ReplicatedStorage/Shared/ResetFXClient
-- Undertale-inspired RESET: intentional, violent, cinematic collapse + forced rebuild.
-- Client FX + requests server reset via Remotes.ResetRequest if present (safe/no hard dependency).
-- Requires a LocalScript starter that calls: require(ResetFXClient).HoldToReset({...})

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local M = {}

------------------------------------------------------------
-- utils
------------------------------------------------------------

local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function safeDestroy(x)
	if x and x.Destroy then
		pcall(function() x:Destroy() end)
	end
end

local function clamp(x, a, b)
	if x < a then return a end
	if x > b then return b end
	return x
end

local function lerp(a, b, t) return a + (b - a) * t end
local function smoothstep(t) t = clamp(t, 0, 1); return t * t * (3 - 2 * t) end

local function qstep(x, step)
	return math.floor(x / step + 0.5) * step
end

local function qvec(v, step)
	return Vector3.new(qstep(v.X, step), qstep(v.Y, step), qstep(v.Z, step))
end

local function now() return os.clock() end
local function rsign() return (math.random() < 0.5) and -1 or 1 end

------------------------------------------------------------
-- global game audio manipulation (existing sounds in SoundService)
------------------------------------------------------------

local function getSounds()
	local sounds = {}
	for _, s in ipairs(SoundService:GetDescendants()) do
		if s:IsA("Sound") then
			sounds[#sounds + 1] = s
		end
	end
	return sounds
end

local function rememberSounds(sounds)
	for _, s in ipairs(sounds) do
		if s.Parent then
			if s:GetAttribute("__ResetBaseVol") == nil then s:SetAttribute("__ResetBaseVol", s.Volume) end
			if s:GetAttribute("__ResetBasePitch") == nil then s:SetAttribute("__ResetBasePitch", s.PlaybackSpeed) end
		end
	end
end

local function setSounds(sounds, volMult, pitchMult)
	for _, s in ipairs(sounds) do
		if s.Parent then
			local bv = s:GetAttribute("__ResetBaseVol")
			local bp = s:GetAttribute("__ResetBasePitch")
			if typeof(bv) == "number" then s.Volume = bv * volMult end
			if typeof(bp) == "number" then s.PlaybackSpeed = bp * pitchMult end
		end
	end
end

local function restoreSounds(sounds)
	for _, s in ipairs(sounds) do
		if s.Parent then
			local bv = s:GetAttribute("__ResetBaseVol")
			local bp = s:GetAttribute("__ResetBasePitch")
			if typeof(bv) == "number" then s.Volume = bv end
			if typeof(bp) == "number" then s.PlaybackSpeed = bp end
		end
	end
end

------------------------------------------------------------
-- Dedicated RESET SFX loader (uses ONLY provided set)
------------------------------------------------------------

local function loadResetSFX()
	local ok, folder = pcall(function()
		return ReplicatedStorage:WaitForChild("Assets"):WaitForChild("ResetSFX")
	end)
	if not ok or not folder then
		return nil, {}
	end

	local runtime = Instance.new("Folder")
	runtime.Name = "__ResetSFXRuntime"
	runtime.Parent = SoundService

	local S = {}
	for _, snd in ipairs(folder:GetChildren()) do
		if snd:IsA("Sound") then
			local c = snd:Clone()
			c.Parent = runtime
			S[c.Name] = c
			c.Looped = false
		end
	end
	return runtime, S
end

local function sfxPlay(S, name, vol, pitch, looped)
	local s = S and S[name]
	if not s then return end
	s.Looped = looped or false
	if vol ~= nil then s.Volume = vol end
	if pitch ~= nil then s.PlaybackSpeed = pitch end
	if not s.IsPlaying then
		pcall(function() s:Play() end)
	end
end

local function sfxStop(S, name)
	local s = S and S[name]
	if s and s.IsPlaying then
		pcall(function() s:Stop() end)
	end
end

local function sfxStopAll(S)
	if not S then return end
	for _, s in pairs(S) do
		if typeof(s) == "Instance" and s:IsA("Sound") and s.IsPlaying then
			pcall(function() s:Stop() end)
		end
	end
end

------------------------------------------------------------
-- Sound effects attached to SoundService (global processing)
------------------------------------------------------------

local function attachGlobalSoundEffects()
	local folder = mk("Folder", { Name = "__ResetSoundFX" }, SoundService)

	local distortion = mk("DistortionSoundEffect", {
		Name = "Distortion",
		Level = 0,
		Priority = 50,
	}, folder)

	local chorus = mk("ChorusSoundEffect", {
		Name = "Chorus",
		Depth = 0,
		Mix = 0,
		Rate = 0,
		Priority = 49,
	}, folder)

	local eq = mk("EqualizerSoundEffect", {
		Name = "EQ",
		HighGain = 0,
		LowGain = 0,
		MidGain = 0,
		Priority = 48,
	}, folder)

	local reverb = mk("ReverbSoundEffect", {
		Name = "Reverb",
		Density = 0,
		Diffusion = 0,
		DryLevel = 0,
		WetLevel = 0,
		Priority = 47,
	}, folder)

	return folder, distortion, chorus, eq, reverb
end

------------------------------------------------------------
-- PostFX + Atmosphere
------------------------------------------------------------

local function makePostFX()
	local folder = mk("Folder", { Name = "__ResetPostFX" }, Lighting)

	local cc = mk("ColorCorrectionEffect", {
		Name = "CC",
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
		TintColor = Color3.fromRGB(255, 255, 255),
	}, folder)

	local bloom = mk("BloomEffect", {
		Name = "Bloom",
		Intensity = 0,
		Size = 32,
		Threshold = 1,
	}, folder)

	local blur = mk("BlurEffect", { Name = "Blur", Size = 0 }, folder)

	local dof = mk("DepthOfFieldEffect", {
		Name = "DOF",
		Enabled = false,
		FarIntensity = 0,
		NearIntensity = 0,
		FocusDistance = 10,
		InFocusRadius = 20,
	}, folder)

	local rays = mk("SunRaysEffect", {
		Name = "Rays",
		Intensity = 0,
		Spread = 0.85,
	}, folder)

	local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
	local createdTempAtmos = false
	if not atmos then
		createdTempAtmos = true
		atmos = mk("Atmosphere", {
			Name = "__ResetAtmosTemp",
			Density = 0,
			Offset = 0,
			Color = Color3.fromRGB(255, 255, 255),
			Decay = Color3.fromRGB(255, 255, 255),
			Glare = 0,
			Haze = 0,
		}, Lighting)
	end

	return folder, cc, bloom, blur, dof, rays, atmos, createdTempAtmos
end

local function snapshotLighting()
	return {
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		ExposureCompensation = Lighting.ExposureCompensation,
		FogColor = Lighting.FogColor,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
		ColorShift_Bottom = Lighting.ColorShift_Bottom,
		ColorShift_Top = Lighting.ColorShift_Top,
	}
end

local function restoreLighting(s)
	if not s then return end
	for k, v in pairs(s) do
		pcall(function() Lighting[k] = v end)
	end
end

local function snapshotAtmosphere()
	local a = Lighting:FindFirstChildOfClass("Atmosphere")
	if not a then return { exists = false } end
	return {
		exists = true,
		ref = a,
		Density = a.Density,
		Offset = a.Offset,
		Color = a.Color,
		Decay = a.Decay,
		Glare = a.Glare,
		Haze = a.Haze,
	}
end

local function restoreAtmosphere(s)
	if not s or not s.exists then return end
	local a = s.ref
	if not (a and a.Parent) then return end
	pcall(function()
		a.Density = s.Density
		a.Offset = s.Offset
		a.Color = s.Color
		a.Decay = s.Decay
		a.Glare = s.Glare
		a.Haze = s.Haze
	end)
end

------------------------------------------------------------
-- Sky snapshot + void
------------------------------------------------------------

local function snapshotSky()
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then return { exists = false } end
	return {
		exists = true,
		sky = sky,
		SkyboxBk = sky.SkyboxBk,
		SkyboxDn = sky.SkyboxDn,
		SkyboxFt = sky.SkyboxFt,
		SkyboxLf = sky.SkyboxLf,
		SkyboxRt = sky.SkyboxRt,
		SkyboxUp = sky.SkyboxUp,
		SunTextureId = sky.SunTextureId,
		MoonTextureId = sky.MoonTextureId,
		StarCount = sky.StarCount,
	}
end

local function applySkySnapshot(s)
	if not s or not s.exists then return end
	local sky = s.sky
	if not (sky and sky.Parent) then return end
	pcall(function()
		sky.SkyboxBk = s.SkyboxBk
		sky.SkyboxDn = s.SkyboxDn
		sky.SkyboxFt = s.SkyboxFt
		sky.SkyboxLf = s.SkyboxLf
		sky.SkyboxRt = s.SkyboxRt
		sky.SkyboxUp = s.SkyboxUp
		sky.SunTextureId = s.SunTextureId
		sky.MoonTextureId = s.MoonTextureId
		sky.StarCount = s.StarCount
	end)
end

local function makeVoidSky()
	return mk("Sky", {
		Name = "__ResetVoidSky",
		SkyboxBk = "",
		SkyboxDn = "",
		SkyboxFt = "",
		SkyboxLf = "",
		SkyboxRt = "",
		SkyboxUp = "",
		SunTextureId = "",
		MoonTextureId = "",
		StarCount = 0,
	}, Lighting)
end

local function destroyVoidSky()
	local v = Lighting:FindFirstChild("__ResetVoidSky")
	if v then safeDestroy(v) end
end

------------------------------------------------------------
-- UI helpers
------------------------------------------------------------

local function randomCodeLine()
	local chars = "01/\\[]{}<>-=+*#@"
	local len = math.random(14, 40)
	local t = {}
	for i = 1, len do
		local idx = math.random(1, #chars)
		t[i] = chars:sub(idx, idx)
	end
	return table.concat(t)
end

local function randomGarbled(str, intensity)
	str = tostring(str or "")
	intensity = clamp(intensity or 0, 0, 1)
	if intensity <= 0 or #str == 0 then return str end

	local pool = { "R","E","S","T","0","1","/","\\","[","]","{","}","<",">","#","@","*","=","-","+" }
	local out = {}

	for i = 1, #str do
		local ch = str:sub(i, i)
		if ch ~= " " and math.random() < intensity * 0.45 then
			out[i] = pool[math.random(1, #pool)]
		else
			out[i] = ch
		end
	end

	return table.concat(out)
end


local function buildUI(title, subtitle)
	local pg = player:WaitForChild("PlayerGui")
	local gui = mk("ScreenGui", {
		Name = "__ResetUI",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 999999,
		Enabled = false, -- ✅ IMPORTANT: don't show on load
	}, pg)


	local root = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)

	local blackout = mk("Frame", {
		Name = "Blackout",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 200,
	}, root)

	local flash = mk("Frame", {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 201,
	}, root)

	local chroma = mk("Frame", { Name = "Chroma", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 120 }, root)
	local chromR = mk("Frame", { Name = "R", BackgroundColor3 = Color3.fromRGB(255,60,60), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1,1) }, chroma)
	local chromG = mk("Frame", { Name = "G", BackgroundColor3 = Color3.fromRGB(60,255,90), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1,1) }, chroma)
	local chromB = mk("Frame", { Name = "B", BackgroundColor3 = Color3.fromRGB(70,120,255), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1,1) }, chroma)

	local tearLayer = mk("Frame", { Name="Tear", BackgroundTransparency=1, Size=UDim2.fromScale(1,1), ZIndex=140 }, root)
	local tears = {}
	for i = 1, 34 do
		local h = math.random(8, 34)
		local y = math.random()
		tears[i] = mk("Frame", {
			BackgroundColor3 = Color3.fromRGB(255,255,255),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1,0,0,h),
			Position = UDim2.new(0,0,y,0),
		}, tearLayer)
	end

	local rain = mk("Frame", { BackgroundTransparency=1, Size=UDim2.fromScale(1,1), ZIndex=170 }, root)
	local cols = {}
	for i = 1, 44 do
		local x = (i - 1) / 44
		cols[i] = mk("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(x, 0, -1, 0),
			Size = UDim2.new(0, 18, 2, 0),
			Font = Enum.Font.Code,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(255,70,70),
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = "",
			Visible = false,
			ZIndex = 170,
		}, rain)
	end

	local shatter = mk("Frame", { BackgroundTransparency=1, Size=UDim2.fromScale(1,1), ZIndex=165 }, root)
	local strips = {}
	for i = 1, 48 do
		local w = math.random(10, 34)
		strips[i] = mk("Frame", {
			BackgroundColor3 = Color3.fromRGB(255,255,255),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(0, w, 1, 0),
			Position = UDim2.new(math.random(), 0, 0, 0),
			Visible = false,
			ZIndex = 165,
		}, shatter)
	end

	local btnWrap = mk("Frame", {
		Name="ResetButtonWrap",
		AnchorPoint=Vector2.new(0.5,1),
		Position=UDim2.new(0.5,0,1,-28),
		Size=UDim2.fromOffset(360,84),
		BackgroundTransparency=1,
		ZIndex=40,
	}, root)

	local box = mk("Frame", { Size=UDim2.fromScale(1,1), BackgroundColor3=Color3.fromRGB(0,0,0), BorderSizePixel=0, ZIndex=40 }, btnWrap)
	mk("UIStroke", { Color=Color3.fromRGB(255,255,255), Thickness=2, Transparency=0.08 }, box)
	mk("UICorner", { CornerRadius=UDim.new(0,3) }, box)

	local inner = mk("Frame", {
		AnchorPoint=Vector2.new(0.5,0.5),
		Position=UDim2.fromScale(0.5,0.5),
		Size=UDim2.new(1,-10,1,-10),
		BackgroundColor3=Color3.fromRGB(10,10,10),
		BorderSizePixel=0,
		ZIndex=41,
	}, box)
	mk("UIStroke", { Color=Color3.fromRGB(255,70,70), Thickness=1, Transparency=0.35 }, inner)
	mk("UICorner", { CornerRadius=UDim.new(0,2) }, inner)

	local heart = mk("Frame", {
		Name="Heart",
		AnchorPoint=Vector2.new(0,0.5),
		Position=UDim2.new(0,14,0.5,0),
		Size=UDim2.fromOffset(14,14),
		BackgroundColor3=Color3.fromRGB(255,70,70),
		BorderSizePixel=0,
		ZIndex=43,
	}, inner)
	mk("UICorner", { CornerRadius=UDim.new(0,2) }, heart)

	local label = mk("TextLabel", {
		Name="Label",
		BackgroundTransparency=1,
		Position=UDim2.new(0,42,0,10),
		Size=UDim2.new(1,-54,0,28),
		Font=Enum.Font.Arcade,
		Text=title or "RESET",
		TextSize=26,
		TextColor3=Color3.fromRGB(255,70,70),
		TextTransparency=0.05,
		TextXAlignment=Enum.TextXAlignment.Left,
		ZIndex=43,
	}, inner)
	mk("UIStroke", { Color=Color3.fromRGB(0,0,0), Thickness=2, Transparency=0.1 }, label)

	local hint = mk("TextLabel", {
		Name="Hint",
		BackgroundTransparency=1,
		Position=UDim2.new(0,42,0,40),
		Size=UDim2.new(1,-54,0,22),
		Font=Enum.Font.Code,
		Text=subtitle or "Hold to overwrite timeline",
		TextSize=15,
		TextColor3=Color3.fromRGB(235,235,235),
		TextTransparency=0.22,
		TextXAlignment=Enum.TextXAlignment.Left,
		ZIndex=43,
	}, inner)

	local barBack = mk("Frame", {
		Name="BarBack",
		AnchorPoint=Vector2.new(0.5,1),
		Position=UDim2.new(0.5,0,1,-8),
		Size=UDim2.new(1,-20,0,8),
		BackgroundColor3=Color3.fromRGB(18,18,18),
		BorderSizePixel=0,
		ZIndex=42,
	}, inner)
	mk("UIStroke", { Color=Color3.fromRGB(255,255,255), Thickness=1, Transparency=0.6 }, barBack)

	local barFill = mk("Frame", {
		Name="BarFill",
		Size=UDim2.new(0,0,1,0),
		BackgroundColor3=Color3.fromRGB(255,70,70),
		BorderSizePixel=0,
		ZIndex=43,
	}, barBack)

	local hit = mk("TextButton", {
		Name="Hit",
		BackgroundTransparency=1,
		Text="",
		Size=UDim2.fromScale(1,1),
		ZIndex=50,
		AutoButtonColor=false,
	}, btnWrap)

	local confirm = mk("Frame", {
		Name="Confirm",
		AnchorPoint=Vector2.new(0.5,0.5),
		Position=UDim2.fromScale(0.5,0.45),
		Size=UDim2.fromOffset(420,180),
		BackgroundColor3=Color3.fromRGB(0,0,0),
		BorderSizePixel=0,
		Visible=false,
		ZIndex=90,
	}, root)
	mk("UIStroke", { Color=Color3.fromRGB(255,70,70), Thickness=2, Transparency=0.12 }, confirm)
	mk("UICorner", { CornerRadius=UDim.new(0,4) }, confirm)

	local cTitle = mk("TextLabel", {
		BackgroundTransparency=1,
		Position=UDim2.new(0,18,0,14),
		Size=UDim2.new(1,-36,0,46),
		Font=Enum.Font.Arcade,
		Text="RESET?",
		TextSize=40,
		TextColor3=Color3.fromRGB(255,70,70),
		TextXAlignment=Enum.TextXAlignment.Left,
		ZIndex=91,
	}, confirm)
	mk("UIStroke", { Color=Color3.fromRGB(0,0,0), Thickness=2, Transparency=0.1 }, cTitle)

	local cDesc = mk("TextLabel", {
		BackgroundTransparency=1,
		Position=UDim2.new(0,18,0,68),
		Size=UDim2.new(1,-36,0,44),
		Font=Enum.Font.Code,
		Text="Reality will be overwritten.\nThis will feel wrong on purpose.",
		TextSize=16,
		TextColor3=Color3.fromRGB(235,235,235),
		TextTransparency=0.1,
		TextXAlignment=Enum.TextXAlignment.Left,
		TextYAlignment=Enum.TextYAlignment.Top,
		ZIndex=91,
	}, confirm)

	local yes = mk("TextButton", {
		Name="Yes",
		AnchorPoint=Vector2.new(0,1),
		Position=UDim2.new(0,18,1,-18),
		Size=UDim2.fromOffset(180,44),
		BackgroundColor3=Color3.fromRGB(20,20,20),
		Text="YES",
		Font=Enum.Font.Arcade,
		TextSize=26,
		TextColor3=Color3.fromRGB(255,70,70),
		AutoButtonColor=false,
		ZIndex=92,
	}, confirm)
	mk("UIStroke", { Color=Color3.fromRGB(255,70,70), Thickness=1, Transparency=0.22 }, yes)
	mk("UICorner", { CornerRadius=UDim.new(0,3) }, yes)

	local no = mk("TextButton", {
		Name="No",
		AnchorPoint=Vector2.new(1,1),
		Position=UDim2.new(1,-18,1,-18),
		Size=UDim2.fromOffset(180,44),
		BackgroundColor3=Color3.fromRGB(20,20,20),
		Text="NO",
		Font=Enum.Font.Arcade,
		TextSize=26,
		TextColor3=Color3.fromRGB(235,235,235),
		AutoButtonColor=false,
		ZIndex=92,
	}, confirm)
	mk("UIStroke", { Color=Color3.fromRGB(255,255,255), Thickness=1, Transparency=0.55 }, no)
	mk("UICorner", { CornerRadius=UDim.new(0,3) }, no)

	return {
		gui=gui,
		blackout=blackout, flash=flash,
		btnWrap=btnWrap, btnHit=hit,
		btnLabel=label, btnHint=hint,
		barFill=barFill, heart=heart,
		confirm=confirm, yes=yes, no=no, cTitle=cTitle, cDesc=cDesc,
		chromR=chromR, chromG=chromG, chromB=chromB,
		tears=tears, cols=cols, strips=strips
	}
end

local function hardFlash(ui, alpha, hold)
	ui.flash.BackgroundTransparency = 1
	TweenService:Create(ui.flash, TweenInfo.new(0.05), {BackgroundTransparency = alpha or 0.12}):Play()
	task.delay(hold or 0.06, function()
		if ui.flash and ui.flash.Parent then
			TweenService:Create(ui.flash, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
		end
	end)
end

local function setBlackout(ui, a, t)
	TweenService:Create(ui.blackout, TweenInfo.new(t or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = clamp(1 - a, 0, 1)
	}):Play()
end

------------------------------------------------------------
-- Input lock
------------------------------------------------------------

local function lockAllInput()
	local actionName = "__ResetLock"

	local function sink()
		return Enum.ContextActionResult.Sink
	end

	ContextActionService:BindActionAtPriority(
		actionName,
		sink,
		false,
		10000,

		-- Keyboard (use KeyCodes, not UserInputType.Keyboard)
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
		Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift,
		Enum.KeyCode.Tab, Enum.KeyCode.E, Enum.KeyCode.Q, Enum.KeyCode.R,
		Enum.KeyCode.Return, Enum.KeyCode.Backspace, Enum.KeyCode.Escape,

		-- Mouse + gamepad are fine as UserInputTypes
		Enum.UserInputType.MouseButton1,
		Enum.UserInputType.MouseButton2,
		Enum.UserInputType.MouseMovement,
		Enum.UserInputType.Gamepad1
	)

	return actionName
end


local function unlockAllInput(actionName)
	if actionName then
		pcall(function() ContextActionService:UnbindAction(actionName) end)
	end
end

------------------------------------------------------------
-- World destabilization (parts + texture tearing)
------------------------------------------------------------

local function collectParts(maxParts)
	local parts = {}
	local char = player.Character
	local ignore = {}
	if char then ignore[char] = true end

	for _, d in ipairs(workspace:GetDescendants()) do
		if #parts >= (maxParts or 180) then break end
		if d:IsA("BasePart") and d.Parent and d ~= workspace.Terrain then
			local p = d
			local top = p
			while top.Parent do
				if ignore[top] then p = nil break end
				top = top.Parent
				if top == workspace then break end
			end
			if p then parts[#parts + 1] = p end
		end
	end
	return parts
end

local function collectSurfaceAssets(parts, maxAssets)
	local assets = {}
	for _, p in ipairs(parts) do
		if #assets >= (maxAssets or 220) then break end
		if p and p.Parent then
			for _, child in ipairs(p:GetDescendants()) do
				if child:IsA("Decal") or child:IsA("Texture") then
					assets[#assets + 1] = child
					if #assets >= (maxAssets or 220) then break end
				end
			end
		end
	end
	return assets
end

local function snapshotParts(parts, assets)
	local snap = { parts = {}, assets = {} }

	for _, p in ipairs(parts) do
		if p and p.Parent then
			snap.parts[p] = {
				CFrame = p.CFrame,
				Color = p.Color,
				Material = p.Material,
				Transparency = p.Transparency,
				Size = p.Size,
			}
		end
	end

	for _, a in ipairs(assets or {}) do
		if a and a.Parent then
			snap.assets[a] = {
				Transparency = a.Transparency,
				Color3 = (a:IsA("Texture") and a.Color3) or nil,
				StudsPerTileU = (a:IsA("Texture") and a.StudsPerTileU) or nil,
				StudsPerTileV = (a:IsA("Texture") and a.StudsPerTileV) or nil,
				OffsetStudsU = (a:IsA("Texture") and a.OffsetStudsU) or nil,
				OffsetStudsV = (a:IsA("Texture") and a.OffsetStudsV) or nil,
				Rotation = (a:IsA("Texture") and a.Rotation) or nil,
			}
		end
	end

	return snap
end

local function restoreParts(snap)
	if not snap then return end

	for p, s in pairs(snap.parts or {}) do
		if p and p.Parent then
			pcall(function()
				p.CFrame = s.CFrame
				p.Color = s.Color
				p.Material = s.Material
				p.Transparency = s.Transparency
				p.Size = s.Size
			end)
		end
	end

	for a, s in pairs(snap.assets or {}) do
		if a and a.Parent then
			pcall(function()
				a.Transparency = s.Transparency
				if a:IsA("Texture") then
					if s.Color3 then a.Color3 = s.Color3 end
					if s.StudsPerTileU then a.StudsPerTileU = s.StudsPerTileU end
					if s.StudsPerTileV then a.StudsPerTileV = s.StudsPerTileV end
					if s.OffsetStudsU then a.OffsetStudsU = s.OffsetStudsU end
					if s.OffsetStudsV then a.OffsetStudsV = s.OffsetStudsV end
					if s.Rotation then a.Rotation = s.Rotation end
				end
			end)
		end
	end
end

local function spawnDebrisShards(count, originCFrame, intensity)
	count = count or 14
	intensity = intensity or 1

	for _ = 1, count do
		local shard = Instance.new("Part")
		shard.Size = Vector3.new(math.random(1,3)/4, math.random(1,4)/6, math.random(1,3)/4)
		shard.Anchored = false
		shard.CanCollide = false
		shard.Material = Enum.Material.Neon
		shard.Color = Color3.fromRGB(255,70,70)
		shard.Transparency = 0.18
		shard.CFrame = originCFrame
			* CFrame.new((math.random()-0.5)*3, (math.random()-0.5)*2, -math.random()*2)
			* CFrame.Angles(math.random(), math.random(), math.random())
		shard.Parent = workspace

		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
		bv.Velocity = Vector3.new((math.random()-0.5)*60, (math.random()-0.2)*50, -math.random()*55) * intensity
		bv.Parent = shard
		Debris:AddItem(bv, 0.25)

		TweenService:Create(shard, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1
		}):Play()
		Debris:AddItem(shard, 0.7)
	end
end
------------------------------------------------------------
-- Server reset request (SAFE)
------------------------------------------------------------

local function fireResetRequest()
	local ok, err = pcall(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 3)
		if not remotes then error("Remotes folder missing") end
		local re = remotes:WaitForChild("ResetRequest", 3)
		if not re then error("ResetRequest missing") end
		if not re:IsA("RemoteEvent") then error("ResetRequest is not a RemoteEvent") end
		re:FireServer()
	end)
	if not ok then
		warn("[ResetFX] fireResetRequest failed (no server reset will occur):", err)
	end
end

------------------------------------------------------------
-- Cinematic: collapse → void → rebuild
------------------------------------------------------------

local function runConfirmCinematic(ui, fx, sounds, soundFX, sfxRuntime, S, partSet, snap, skySnap, lightSnap, atmosSnap, cfg, seconds)
	local cam = workspace.CurrentCamera
	local baseFov = cam and cam.FieldOfView or 70

	local actionName = lockAllInput()

	local _, cc, bloom, blur, dof, rays, atmos, createdTempAtmos = table.unpack(fx)
	local sFolder, distortion, chorus, eq, reverb = table.unpack(soundFX)

	seconds = seconds or 5.5

	for _, c in ipairs(ui.cols) do c.Visible = true end
	for _, s in ipairs(ui.strips) do s.Visible = true end
	ui.btnWrap.Visible = false
	ui.confirm.Visible = false

	cc.Contrast = 0.9
	cc.Saturation = -0.75
	cc.Brightness = -0.14
	cc.TintColor = Color3.fromRGB(255, 150, 150)
	bloom.Intensity = 3.8
	blur.Size = 22
	dof.FarIntensity = 0.95
	dof.NearIntensity = 0.55
	dof.InFocusRadius = 4
	rays.Intensity = 0.45

	rememberSounds(sounds)
	setSounds(sounds, 0.16, 0.90)

	distortion.Level = 0.18
	chorus.Mix = 0.28
	chorus.Depth = 0.45
	chorus.Rate = 0.55
	eq.LowGain = -3
	eq.MidGain = 2
	eq.HighGain = 4
	reverb.WetLevel = -11
	reverb.DryLevel = 0

	sfxPlay(S, "Tape-Stop", 0.55, 1.0, false)
	sfxPlay(S, "Detonation", 0.85, 1.0, false)
	sfxPlay(S, "cinematic-impact-boom", 0.55, 0.95, false)
	sfxPlay(S, "Glitch", 0.25, 0.85, true)
	sfxStop(S, "heartbeat")

	if S and S["AfterEffectDivineEcho"] then
		local choir = S["AfterEffectDivineEcho"]
		choir.Looped = true
		choir.Volume = 0.14
		choir.PlaybackSpeed = 0.72
		pcall(function() choir:Play() end)
	end

	sfxPlay(S, "Crack", 0.40, 0.92, false)
	sfxPlay(S, "soul shatter", 0.50, 0.95, false)

	local voidSky
	if cfg.skyVoidExposure ~= false then
		voidSky = makeVoidSky()
	end

	hardFlash(ui, 0.10, 0.05)
	setBlackout(ui, 0.08, 0.08)

	local t0 = now()
	local freezeGate = 0
	local freezeHold = 0
	local lastCamCFrame = cam and cam.CFrame

	local function doVoidMoment()
		sfxStop(S, "Glitch")
		setSounds(sounds, 0.06, 0.92)
		sfxPlay(S, "Ear Ring", 0.65, 1.0, false)

		if S and S["AfterEffectDivineEcho"] then
			S["AfterEffectDivineEcho"].Volume = 0.06
			S["AfterEffectDivineEcho"].PlaybackSpeed = 0.68
		end
	end

	local function beginRebuild()
		sfxPlay(S, "Mechanical Clicks", 0.45, 1.0, true)
		sfxPlay(S, "Teleport", 0.22, 0.70, false)
		sfxPlay(S, "Crack", 0.26, 1.05, false)
	end

	local voidFired = false
	local rebuildFired = false

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = now() - t0
		local p = clamp(t / seconds, 0, 1)

		local collapse = smoothstep(clamp(p / 0.55, 0, 1))
		local rebuild = smoothstep(clamp((p - 0.55) / 0.35, 0, 1))
		local endBeat = smoothstep(clamp((p - 0.90) / 0.10, 0, 1))

		if (not voidFired) and collapse > 0.42 then
			voidFired = true
			doVoidMoment()
		end
		if (not rebuildFired) and rebuild > 0.05 then
			rebuildFired = true
			beginRebuild()
		end

		if cam then
			local targetFov = baseFov + lerp(0, 26, collapse) + lerp(0, -14, rebuild) + lerp(0, -10, endBeat)
			cam.FieldOfView = lerp(cam.FieldOfView, targetFov, clamp(dt * 10, 0, 1))

			freezeGate += dt
			local freezeEvery = lerp(0.16, 0.06, collapse)
			if collapse > 0.22 and collapse < 0.78 and freezeGate > freezeEvery then
				freezeGate = 0
				freezeHold = lerp(0.01, 0.06, collapse)
				lastCamCFrame = cam.CFrame
			end

			if freezeHold > 0 then
				freezeHold -= dt
				cam.CFrame = lastCamCFrame
			else
				local shake = lerp(0.15, 2.2, collapse) + lerp(0.0, 0.6, rebuild)
				local roll = (math.random()-0.5) * 0.03 * shake
				local dx = (math.random()-0.5) * 0.08 * shake
				local dy = (math.random()-0.5) * 0.07 * shake
				local z = lerp(0, -0.35, collapse) + lerp(0, 0.18, rebuild)
				cam.CFrame = cam.CFrame * CFrame.new(dx, dy, z) * CFrame.Angles(0, 0, roll)
			end
		end

		for _, b in ipairs(ui.tears) do
			local alpha = 0.96 - collapse * 0.55 + math.random() * 0.06
			b.BackgroundTransparency = clamp(alpha, 0.15, 1)
			b.Position = UDim2.new(0, math.random(-320, 320) * collapse, b.Position.Y.Scale, math.random(-28, 28))
			b.Size = UDim2.new(1, math.random(-520, 520) * collapse, 0, b.Size.Y.Offset)
		end

		local sep = lerp(0, 18, collapse) + lerp(18, -8, rebuild)
		ui.chromR.BackgroundTransparency = 0.995 - collapse * 0.07
		ui.chromG.BackgroundTransparency = 0.999 - collapse * 0.03
		ui.chromB.BackgroundTransparency = 0.995 - collapse * 0.07
		ui.chromR.Position = UDim2.new(0, math.floor(sep), 0, 0)
		ui.chromB.Position = UDim2.new(0, -math.floor(sep), 0, 0)

		for _, s in ipairs(ui.strips) do
			s.BackgroundTransparency = clamp(0.92 - collapse * 0.92 + rebuild * 0.55, 0, 1)
			if collapse > 0.12 then
				s.Position = s.Position + UDim2.new(0, rsign() * (18 + collapse * 120) * dt * 60, 0, 0)
			end
		end

		for _, c in ipairs(ui.cols) do
			local show = collapse > 0.10
			c.Visible = show
			if show then
				c.TextTransparency = 0.96 - collapse * 0.65 + rebuild * 0.40
				if math.random() < (0.12 + collapse * 0.60) then
					c.Text = c.Text .. randomCodeLine() .. "\n"
					if #c.Text > 1500 then c.Text = c.Text:sub(#c.Text - 950) end
				end
				c.Position = c.Position + UDim2.new(0, 0, (0.8 + collapse * 3.2) * dt, 0)
				if c.Position.Y.Scale > 0.25 then
					c.Position = UDim2.new(c.Position.X.Scale, 0, -1, math.random(-260, 0))
				end
			end
		end

		if skySnap and skySnap.exists and skySnap.sky and skySnap.sky.Parent then
			local sky = skySnap.sky
			if voidSky and collapse > 0.28 and collapse < 0.72 then
				sky.StarCount = 0
				sky.SunTextureId = ""
				sky.MoonTextureId = ""
			end
			if rebuild > 0 then
				sky.StarCount = math.floor(lerp(0, skySnap.StarCount, rebuild))
				if rebuild > 0.35 then
					sky.SunTextureId = skySnap.SunTextureId
					sky.MoonTextureId = skySnap.MoonTextureId
				end
			end
		end

		Lighting.ExposureCompensation = lerp(lightSnap.ExposureCompensation, -1.7, collapse) + math.sin((t0 + t) * 18) * 0.25 * collapse
		Lighting.Brightness = clamp(lerp(lightSnap.Brightness, 0.5, collapse) + (math.random()-0.5) * 0.45 * collapse, 0.1, 8)

		Lighting.Ambient = lightSnap.Ambient:Lerp(Color3.fromRGB(140,0,0), collapse)
		Lighting.OutdoorAmbient = lightSnap.OutdoorAmbient:Lerp(Color3.fromRGB(80,0,0), collapse)
		Lighting.FogColor = lightSnap.FogColor:Lerp(Color3.fromRGB(30,0,0), collapse)
		Lighting.FogStart = lerp(lightSnap.FogStart, 0, collapse)
		Lighting.FogEnd = lerp(lightSnap.FogEnd, 55, collapse)

		if collapse > 0.18 and math.random() < 0.08 * collapse then
			Lighting.ClockTime = (lightSnap.ClockTime + math.random(-8, 8)) % 24
		end

		if atmos and atmos.Parent then
			atmos.Density = lerp(atmos.Density, lerp(0.0, 0.78, collapse), clamp(dt * 6, 0, 1))
			atmos.Haze = lerp(atmos.Haze, lerp(0.0, 3.6, collapse), clamp(dt * 6, 0, 1))
			atmos.Glare = lerp(atmos.Glare, lerp(0.0, 1.9, collapse), clamp(dt * 6, 0, 1))
			atmos.Color = Color3.fromRGB(255, math.floor(lerp(255, 105, collapse)), math.floor(lerp(255, 105, collapse)))
			atmos.Decay = Color3.fromRGB(math.floor(lerp(255, 70, collapse)), 10, 10)
		end

		cc.Contrast = lerp(0.95, 0.10, rebuild)
		cc.Saturation = lerp(-0.78, 0.06, rebuild)
		cc.Brightness = lerp(-0.14, -0.02, rebuild)
		cc.TintColor = Color3.fromRGB(255, math.floor(lerp(150, 245, rebuild)), math.floor(lerp(150, 245, rebuild)))

		bloom.Intensity = lerp(4.0, 0.8, rebuild)
		blur.Size = lerp(22, 3, rebuild)
		dof.FarIntensity = lerp(0.95, 0.18, rebuild)
		dof.NearIntensity = lerp(0.55, 0.06, rebuild)
		dof.InFocusRadius = lerp(4, 14, rebuild)
		rays.Intensity = lerp(0.45, 0.06, rebuild)

		local wobble = 0.88 + math.sin((t0 + t) * 26) * 0.06 * collapse
		local vol = lerp(0.16, 0.04, collapse)
		local pitch = wobble
		if rebuild > 0 then
			vol = lerp(vol, 0.65, rebuild)
			pitch = lerp(pitch, 1.0, rebuild)
		end
		if endBeat > 0 then
			vol = lerp(vol, 0.02, endBeat)
			pitch = lerp(pitch, 0.95, endBeat)
		end
		setSounds(sounds, vol, pitch)

		if S and S["Glitch"] then
			S["Glitch"].Volume = lerp(0.25, 0.55, collapse) * (1 - rebuild * 0.85)
			S["Glitch"].PlaybackSpeed = lerp(0.85, 0.75, collapse) + math.sin((t0 + t) * 14) * 0.02
		end

		if S and S["Mechanical Clicks"] then
			S["Mechanical Clicks"].Volume = lerp(0, 0.52, rebuild)
			S["Mechanical Clicks"].PlaybackSpeed = lerp(0.95, 1.10, rebuild)
		end

		if S and S["AfterEffectDivineEcho"] then
			S["AfterEffectDivineEcho"].Volume = lerp(S["AfterEffectDivineEcho"].Volume, 0.10, rebuild * 0.25)
			if endBeat > 0 then
				S["AfterEffectDivineEcho"].Volume = lerp(S["AfterEffectDivineEcho"].Volume, 0.00, endBeat)
			end
		end

		if partSet and snap then
			local snapChance = 0.10 + collapse * 0.48
			local neonChance = 0.02 + collapse * 0.12
			local tearChance = 0.02 + collapse * 0.16
			local q = lerp(0.26, 0.05, collapse)
			local maxJ = lerp(0.05, 1.45, collapse)

			for i = 1, #partSet do
				local part = partSet[i]
				local ps = snap.parts[part]
				if part and part.Parent and ps then
					if (i % 2 == 0) or (math.random() < 0.42) then
						if collapse > 0.06 then
							if math.random() < snapChance then
								local off = qvec(Vector3.new(
									(math.random()-0.5) * maxJ,
									(math.random()-0.5) * maxJ * 0.85,
									(math.random()-0.5) * maxJ
									), q)

								local ang = lerp(0.0, 0.42, collapse)
								local rx = qstep((math.random()-0.5) * ang, 0.05)
								local ry = qstep((math.random()-0.5) * ang, 0.05)
								local rz = qstep((math.random()-0.5) * ang, 0.05)

								if math.random() < 0.12 + collapse * 0.18 then
									part.CFrame = part.CFrame
								else
									part.CFrame = ps.CFrame * CFrame.new(off) * CFrame.Angles(rx, ry, rz)
								end
							else
								part.CFrame = part.CFrame:Lerp(ps.CFrame, 0.04)
							end

							if math.random() < neonChance then
								part.Material = Enum.Material.Neon
								part.Color = Color3.fromRGB(255,70,70)
								part.Transparency = lerp(ps.Transparency, 0.20, collapse)
							end
						end

						if rebuild > 0 then
							local stepLerp = clamp(dt * (8 + rebuild * 18), 0, 1)
							if math.random() < (0.22 + rebuild * 0.35) then
								part.CFrame = ps.CFrame
							else
								part.CFrame = part.CFrame:Lerp(ps.CFrame, stepLerp)
							end
							part.Color = part.Color:Lerp(ps.Color, stepLerp)
							part.Transparency = lerp(part.Transparency, ps.Transparency, stepLerp)

							if rebuild > 0.55 then
								part.Material = ps.Material
								part.Size = ps.Size
							end
						end
					end
				end
			end

			for a, as in pairs(snap.assets) do
				if a and a.Parent and collapse > 0.10 then
					if math.random() < tearChance then
						a.Transparency = clamp(as.Transparency + ((math.random() < 0.5) and 0.25 or 0.0), 0, 1)
						if a:IsA("Texture") then
							a.StudsPerTileU = math.max(0.25, (as.StudsPerTileU or 1) * lerp(1.0, 0.55, collapse))
							a.StudsPerTileV = math.max(0.25, (as.StudsPerTileV or 1) * lerp(1.0, 0.55, collapse))
							a.OffsetStudsU = (as.OffsetStudsU or 0) + qstep((math.random()-0.5) * lerp(0, 1.8, collapse), 0.2)
							a.OffsetStudsV = (as.OffsetStudsV or 0) + qstep((math.random()-0.5) * lerp(0, 1.8, collapse), 0.2)
							a.Rotation = ((as.Rotation or 0) + math.random(-90, 90) * collapse) % 360
						end
					end
				end
			end
		end

		if cam and collapse > 0.20 and math.random() < (0.08 + collapse * 0.16) then
			spawnDebrisShards(math.random(10, 18), cam.CFrame, lerp(1.0, 1.6, collapse))
		end

		if collapse > 0.28 and math.random() < (0.06 + collapse * 0.12) then
			hardFlash(ui, 0.08, 0.03)
			if S and math.random() < 0.35 then
				sfxPlay(S, "Crack", 0.28 + collapse * 0.22, 0.9 + math.random() * 0.08, false)
				sfxPlay(S, "soul shatter", 0.22 + collapse * 0.30, 0.95, false)
			end
		end
		if collapse > 0.55 and math.random() < (0.04 + collapse * 0.10) then
			setBlackout(ui, 0.62, 0.04)
			task.delay(0.06, function()
				if ui.blackout and ui.blackout.Parent then setBlackout(ui, 0.10, 0.10) end
			end)
		end
	end)

	task.wait(seconds)
	if conn then conn:Disconnect() end

	setSounds(sounds, 0.02, 0.95)
	setBlackout(ui, 1.0, 0.10)
	task.wait(0.12)

	if S then
		for _, s in pairs(S) do
			if typeof(s) == "Instance" and s:IsA("Sound") then
				pcall(function()
					TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Volume = 0}):Play()
				end)
			end
		end
		task.wait(0.36)
	end

	pcall(function() restoreSounds(sounds) end)
	pcall(function() restoreLighting(lightSnap) end)
	pcall(function() restoreAtmosphere(atmosSnap) end)
	pcall(function() applySkySnapshot(skySnap) end)
	pcall(function() restoreParts(snap) end)

	if voidSky then safeDestroy(voidSky) end
	destroyVoidSky()

	if createdTempAtmos and atmos and atmos.Parent and atmos.Name == "__ResetAtmosTemp" then
		safeDestroy(atmos)
	end

	if cam then cam.FieldOfView = baseFov end

	safeDestroy(sFolder)
	sfxStopAll(S)
	safeDestroy(sfxRuntime)

	unlockAllInput(actionName)
end

------------------------------------------------------------
-- Main entry: HoldToReset
------------------------------------------------------------

function M.HoldToReset(cfg)
	cfg = cfg or {}
	local key = cfg.key or Enum.KeyCode.R
	local holdSeconds = cfg.holdSeconds or 3.0
	local cinematicSeconds = cfg.cinematicSeconds or 5.5

	local ui = buildUI(cfg.title, cfg.subtitle)
	local fxFolder, cc, bloom, blur, dof, rays, atmos, createdTempAtmos = makePostFX()
	local soundFolder, distortion, chorus, eq, reverb = attachGlobalSoundEffects()

	local sounds = getSounds()
	rememberSounds(sounds)

	local lightingSnap = snapshotLighting()
	local atmosSnap = snapshotAtmosphere()
	local skySnap = snapshotSky()

	local cam = workspace.CurrentCamera
	local baseFov = cam and cam.FieldOfView or 70

	local partSet = collectParts(cfg.maxWorldParts or 180)
	local assets = collectSurfaceAssets(partSet, cfg.maxSurfaceAssets or 220)
	local snap = snapshotParts(partSet, assets)

	local sfxRuntime, S = loadResetSFX()

	local state = "idle" -- idle, holding, confirming, cinematic, done
	local progress = 0
	local tStart = 0
	local holding = false
	local triggered = false

	local confirmHolding = false
	local confirmStart = 0

	local function fullRestore()
		pcall(function() restoreSounds(sounds) end)
		pcall(function() restoreLighting(lightingSnap) end)
		pcall(function() restoreAtmosphere(atmosSnap) end)
		pcall(function() applySkySnapshot(skySnap) end)
		pcall(function() restoreParts(snap) end)
		destroyVoidSky()

		if createdTempAtmos and atmos and atmos.Parent and atmos.Name == "__ResetAtmosTemp" then
			safeDestroy(atmos)
		end
		if cam then cam.FieldOfView = baseFov end
	end

	local function cleanup()
		fullRestore()
		sfxStopAll(S)
		safeDestroy(sfxRuntime)
		safeDestroy(soundFolder)
		safeDestroy(fxFolder)
		safeDestroy(ui.gui)
	end

	local function cancelSnapBack()
		holding = false
		progress = 0
		state = "idle"

		hardFlash(ui, 0.14, 0.05)

		TweenService:Create(blur, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = 0}):Play()
		TweenService:Create(bloom, TweenInfo.new(0.16), {Intensity = 0}):Play()
		TweenService:Create(cc, TweenInfo.new(0.18), {Contrast=0, Saturation=0, Brightness=0, TintColor=Color3.fromRGB(255,255,255)}):Play()
		TweenService:Create(dof, TweenInfo.new(0.16), {FarIntensity=0, NearIntensity=0, InFocusRadius=20}):Play()
		TweenService:Create(rays, TweenInfo.new(0.18), {Intensity=0}):Play()

		distortion.Level = 0
		chorus.Mix = 0
		chorus.Depth = 0
		chorus.Rate = 0
		eq.LowGain = 0
		eq.MidGain = 0
		eq.HighGain = 0
		reverb.WetLevel = 0
		reverb.DryLevel = 0

		setSounds(sounds, 1, 1)
		fullRestore()

		sfxStopAll(S)

		ui.chromR.BackgroundTransparency = 1
		ui.chromG.BackgroundTransparency = 1
		ui.chromB.BackgroundTransparency = 1
		for _, b in ipairs(ui.tears) do b.BackgroundTransparency = 1 end
		for _, c in ipairs(ui.cols) do c.Visible = false end
		for _, s in ipairs(ui.strips) do s.Visible = false end

		ui.confirm.Visible = false
		ui.btnWrap.Visible = true
		if ui.gui then ui.gui.Enabled = false end

	end

	local function armConfirm()
		state = "confirming"
		holding = false
		progress = 1
		ui.confirm.Visible = true
		ui.btnHint.Text = "Confirm. No accidents."
		hardFlash(ui, 0.10, 0.04)

		sfxPlay(S, "Glitch", 0.22, 0.95, true)
		if S and S["MenuMusic"] then
			sfxPlay(S, "MenuMusic", 0.12, 0.78, true)
		end
	end

	local function beginCinematic()
		if triggered then return end
		triggered = true
		state = "cinematic"

		sfxStop(S, "Charge up")
		sfxStop(S, "heartbeat")
		sfxStop(S, "SoulEntryRumble")

		local ok, err = pcall(function()
			runConfirmCinematic(
				ui,
				{fxFolder, cc, bloom, blur, dof, rays, atmos, createdTempAtmos},
				sounds,
				{soundFolder, distortion, chorus, eq, reverb},
				sfxRuntime,
				S,
				partSet,
				snap,
				skySnap,
				lightingSnap,
				atmosSnap,
				cfg,
				cinematicSeconds
			)
		end)

		if not ok then
			warn("[ResetFX] Cinematic error:", err)
		end

		task.delay(0.25, function()
			fireResetRequest()
			state = "done"
			if ui.gui then ui.gui.Enabled = false end
			cleanup()
		end)
	end

	-- Button hold
	ui.btnHit.MouseButton1Down:Connect(function()
		
		if state ~= "idle" then return end
		ui.gui.Enabled = true
		holding = true
		state = "holding"
		tStart = now()
		hardFlash(ui, 0.10, 0.03)

		sfxPlay(S, "Ambience", 0.20, 1.0, true)
		sfxPlay(S, "SoulEntryRumble", 0.05, 0.95, true)
		sfxPlay(S, "heartbeat", 0.05, 0.90, true)
		sfxPlay(S, "Charge up", 0.18, 1.0, true)
	end)

	ui.btnHit.MouseButton1Up:Connect(function()
		if state == "holding" and not triggered then
			holding = false
			if progress < 1 then cancelSnapBack() end
		end
	end)

	-- Keyboard hold (reliable: ignore only when typing)
	UserInputService.InputBegan:Connect(function(input, gp)
		if UserInputService:GetFocusedTextBox() then return end

		if input.KeyCode == key and state == "idle" and not triggered then
			ui.gui.Enabled = true

			holding = true
			state = "holding"
			tStart = now()
			hardFlash(ui, 0.10, 0.03)

			sfxPlay(S, "Ambience", 0.20, 1.0, true)
			sfxPlay(S, "SoulEntryRumble", 0.05, 0.95, true)
			sfxPlay(S, "heartbeat", 0.05, 0.90, true)
			sfxPlay(S, "Charge up", 0.18, 1.0, true)
		end

		if input.KeyCode == key and state == "confirming" then
			confirmHolding = true
			confirmStart = now()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == key and state == "holding" and not triggered then
			holding = false
			if progress < 1 then cancelSnapBack() end
		end
		if input.KeyCode == key then
			confirmHolding = false
		end
	end)

	ui.yes.MouseButton1Click:Connect(function()
		if state == "confirming" then beginCinematic() end
	end)
	ui.no.MouseButton1Click:Connect(function()
		if state == "confirming" then cancelSnapBack() end
	end)

	local renderConn
	renderConn = RunService.RenderStepped:Connect(function(dt)
		if not (ui.gui and ui.gui.Parent) then
			if renderConn then renderConn:Disconnect() end
			return
		end

		local t = now()

		if state == "confirming" then
			local flick = (math.sin(t * 20) * 0.5 + 0.5)

			ui.cTitle.Text = randomGarbled("RESET?", 0.18 + flick * 0.35)
			ui.btnLabel.Text = randomGarbled(cfg.title or "RESET", 0.12 + flick * 0.35)

			cc.Contrast = 0.72 + flick * 0.14
			cc.Saturation = -0.52 - flick * 0.12
			cc.Brightness = -0.09 - flick * 0.05
			cc.TintColor = Color3.fromRGB(255, 165, 165)

			bloom.Intensity = 2.6 + flick * 0.8
			blur.Size = 14 + flick * 7
			dof.FarIntensity = 0.80
			dof.NearIntensity = 0.30
			dof.InFocusRadius = 6
			rays.Intensity = 0.22

			local sep = 4 + flick * 12
			ui.chromR.BackgroundTransparency = 0.99
			ui.chromG.BackgroundTransparency = 0.999
			ui.chromB.BackgroundTransparency = 0.99
			ui.chromR.Position = UDim2.new(0, math.floor(sep), 0, 0)
			ui.chromB.Position = UDim2.new(0, -math.floor(sep), 0, 0)

			for _, b in ipairs(ui.tears) do
				b.BackgroundTransparency = 0.95 + math.random() * 0.03
				b.Position = UDim2.new(0, math.random(-180, 180), b.Position.Y.Scale, math.random(-16, 16))
				b.Size = UDim2.new(1, math.random(-320, 320), 0, b.Size.Y.Offset)
			end

			if confirmHolding then
				local cp = clamp((now() - confirmStart) / 0.65, 0, 1)
				ui.cDesc.Text = randomGarbled("Reality will be overwritten.\nThis will feel wrong on purpose.", 0.12 + cp * 0.45)
				if cp >= 1 then beginCinematic() end
			else
				ui.cDesc.Text = "Reality will be overwritten.\nThis will feel wrong on purpose."
			end

			return
		end

		if state ~= "holding" then
			ui.barFill.Size = UDim2.new(0, 0, 1, 0)
			ui.btnLabel.Text = cfg.title or "RESET"
			ui.btnHint.Text = cfg.subtitle or "Hold to overwrite timeline"
			return
		end

		progress = clamp((t - tStart) / holdSeconds, 0, 1)
		ui.barFill.Size = UDim2.new(progress, 0, 1, 0)
		ui.heart.Position = UDim2.new(0, 14 + math.floor(progress * 12), 0.5, math.sin(t * 18) * (1 + progress * 2))

		ui.btnLabel.Text = randomGarbled(cfg.title or "RESET", progress * 0.95)
		ui.btnHint.Text = randomGarbled(cfg.subtitle or "Hold to overwrite timeline", progress * 0.85)

		local ramp = smoothstep(progress)
		local chaos = smoothstep(clamp((progress - 0.20) / 0.80, 0, 1))

		cc.Contrast = lerp(0, 0.70, ramp) + chaos * 0.10
		cc.Saturation = lerp(0, -0.42, ramp) - chaos * 0.20
		cc.Brightness = lerp(0, -0.09, ramp) - chaos * 0.06
		cc.TintColor = Color3.fromRGB(255, math.floor(lerp(255, 175, ramp)), math.floor(lerp(255, 175, ramp)))

		bloom.Intensity = lerp(0, 2.4, ramp) + chaos * 1.0
		blur.Size = lerp(0, 16, ramp) + chaos * 6
		dof.FarIntensity = lerp(0, 0.78, ramp)
		dof.NearIntensity = lerp(0, 0.30, ramp)
		dof.InFocusRadius = lerp(20, 7, ramp)
		rays.Intensity = lerp(0, 0.18, ramp) + chaos * 0.10

		local sep = lerp(0, 14, ramp) + chaos * 10
		ui.chromR.BackgroundTransparency = 0.999 - ramp * 0.06
		ui.chromG.BackgroundTransparency = 0.999 - ramp * 0.03
		ui.chromB.BackgroundTransparency = 0.999 - ramp * 0.06
		ui.chromR.Position = UDim2.new(0, math.floor(sep), 0, 0)
		ui.chromB.Position = UDim2.new(0, -math.floor(sep), 0, 0)

		for _, b in ipairs(ui.tears) do
			b.BackgroundTransparency = 0.98 - ramp * 0.20 + math.random() * 0.04
			b.Position = UDim2.new(0, math.random(-60 - ramp * 260, 60 + ramp * 260), b.Position.Y.Scale, math.random(-10, 10))
			b.Size = UDim2.new(1, math.random(-120 - ramp * 420, 120 + ramp * 420), 0, b.Size.Y.Offset)
		end

		local wobble = (progress > 0.20) and (0.97 + math.sin(t * (20 + progress * 10)) * (0.02 + progress * 0.03)) or 1
		setSounds(sounds, lerp(1, 0.22, ramp), wobble)

		if S then
			if S["SoulEntryRumble"] then
				S["SoulEntryRumble"].Volume = lerp(0.05, 0.48, ramp)
				S["SoulEntryRumble"].PlaybackSpeed = lerp(0.95, 0.80, ramp)
			end
			if S["heartbeat"] then
				S["heartbeat"].Volume = lerp(0.05, 0.36, ramp)
				S["heartbeat"].PlaybackSpeed = lerp(0.90, 1.85, ramp)
			end
			if S["Charge up"] then
				S["Charge up"].PlaybackSpeed = lerp(1.0, 1.45, ramp)
				S["Charge up"].Volume = lerp(0.18, 0.28, ramp)
			end
			if progress > 0.55 then
				if not (S["Glitch"] and S["Glitch"].IsPlaying) then
					sfxPlay(S, "Glitch", 0.18, 1.0, true)
				end
				if S["Glitch"] then
					S["Glitch"].Volume = lerp(0.18, 0.42, chaos)
					S["Glitch"].PlaybackSpeed = lerp(1.0, 0.92, chaos)
				end
			end
		end

		if cam then
			local fovTarget = baseFov + lerp(0, 18, ramp) + chaos * 8
			cam.FieldOfView = lerp(cam.FieldOfView, fovTarget, clamp(dt * 12, 0, 1))

			if progress > 0.25 then
				local s = (progress - 0.25) * (1.8 + chaos)
				if math.random() < (0.02 + chaos * 0.08) then
					local cf = cam.CFrame
					task.defer(function()
						if cam then cam.CFrame = cf end
					end)
				else
					cam.CFrame = cam.CFrame
						* CFrame.new((math.random()-0.5) * 0.03 * s, (math.random()-0.5) * 0.025 * s, 0)
						* CFrame.Angles(0, 0, (math.random()-0.5) * 0.015 * s)
				end
			end
		end

		Lighting.ExposureCompensation = lightingSnap.ExposureCompensation + lerp(0, -0.95, ramp) + math.sin(t * 14) * 0.15 * ramp
		Lighting.Brightness = clamp(lightingSnap.Brightness + lerp(0, -0.7, ramp) + (math.random()-0.5) * 0.3 * chaos, 0.2, 8)
		Lighting.Ambient = lightingSnap.Ambient:Lerp(Color3.fromRGB(120,0,0), ramp * 0.60)
		Lighting.OutdoorAmbient = lightingSnap.OutdoorAmbient:Lerp(Color3.fromRGB(60,0,0), ramp * 0.60)
		Lighting.FogColor = lightingSnap.FogColor:Lerp(Color3.fromRGB(35,0,0), ramp * 0.60)
		Lighting.FogStart = lerp(lightingSnap.FogStart, 0, ramp)
		Lighting.FogEnd = lerp(lightingSnap.FogEnd, 120, ramp)

		if progress >= 1 and state == "holding" then
			armConfirm()
		end
	end)

	while ui.gui and ui.gui.Parent do
		task.wait(0.05)
		if state == "done" then break end
	end

	return triggered
end

return M
