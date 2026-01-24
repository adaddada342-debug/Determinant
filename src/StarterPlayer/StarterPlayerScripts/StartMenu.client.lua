-- StarterPlayerScripts/StartMenu.client.lua
-- Determinant Start Menu (FULL FIX: fits screen, text renders, settings + music actually work)
-- ✅ DOES NOT touch server pipeline logic (same remotes/handshake)
-- ✅ Fix: Settings now calls MenuAction "SetSettings" (matches your server)
-- ✅ Fix: Settings has REAL controls + autosave debounce (0.35s)
-- ✅ Fix: Music UI text renders + no layered playback
-- ✅ Fix: Responsive layout clamps widths (no off-screen)
-- ✅ Fix: ZIndex sane (text no longer vanishes behind borders)
-- ✅ NEW: Corner-only tunnelling animation that DOES NOT block UI input

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- =========================
-- SINGLETON GUARD
-- =========================
if _G.__DETERMINANT_STARTMENU_RUNNING then
	warn("[StartMenu] Duplicate client detected, abort:", script:GetFullName())
	return
end
_G.__DETERMINANT_STARTMENU_RUNNING = true

-- =========================
-- Remotes (LOGIC UNCHANGED)
-- =========================
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MenuAction  = Remotes:WaitForChild("MenuAction")   -- RemoteEvent
local MenuState   = Remotes:WaitForChild("MenuState")    -- RemoteFunction
local MenuCommand = Remotes:WaitForChild("MenuCommand")  -- RemoteEvent

-- =========================
-- Helpers
-- =========================
local function make(className, props, parent)
	local inst = Instance.new(className)
	for k,v in pairs(props or {}) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function tween(obj, goal, t, style, dir)
	local ti = TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local tw = TweenService:Create(obj, ti, goal)
	tw:Play()
	return tw
end

local function safeCall(tag, fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then warn("[StartMenu:"..tag.."]", res) end
	return ok, res
end

local function now() return os.clock() end

-- pixel-ish snap
local function snap(px, step)
	step = step or 2
	return math.floor((px / step) + 0.5) * step
end

-- Rough border that DOES NOT nuke your text (ZIndex relative to the frame)
local function addRoughBorder(frame, color)
	local z = (frame.ZIndex or 1) + 1
	local t = 2
	local a = 0.12

	local function edge()
		return make("Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = a,
			BorderSizePixel = 0,
			ZIndex = z,
			Active = false,
			Selectable = false,
		}, frame)
	end

	local top = edge()
	local bot = edge()
	local lef = edge()
	local rig = edge()

	top.Size = UDim2.new(1, snap(math.random(-8,8)), 0, t)
	top.Position = UDim2.new(0, snap(math.random(-2,2)), 0, snap(math.random(-2,2)))

	bot.Size = UDim2.new(1, snap(math.random(-8,8)), 0, t)
	bot.Position = UDim2.new(0, snap(math.random(-2,2)), 1, -t + snap(math.random(-2,2)))

	lef.Size = UDim2.new(0, t, 1, snap(math.random(-8,8)))
	lef.Position = UDim2.new(0, snap(math.random(-2,2)), 0, snap(math.random(-2,2)))

	rig.Size = UDim2.new(0, t, 1, snap(math.random(-8,8)))
	rig.Position = UDim2.new(1, -t + snap(math.random(-2,2)), 0, snap(math.random(-2,2)))

	return {top, bot, lef, rig}
end

-- =========================
-- CoreGui limited disable (LOGIC UNCHANGED)
-- =========================
local coreSnapshot = {}
local coreTypes = {
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.EmotesMenu,
}

local function snapshotCore()
	coreSnapshot = {}
	for _, t in ipairs(coreTypes) do
		local ok, cur = pcall(function() return StarterGui:GetCoreGuiEnabled(t) end)
		if ok then coreSnapshot[t] = cur end
	end
	for _, t in ipairs(coreTypes) do
		pcall(function() StarterGui:SetCoreGuiEnabled(t, false) end)
	end
end

local function restoreCore()
	for t, cur in pairs(coreSnapshot) do
		pcall(function() StarterGui:SetCoreGuiEnabled(t, cur) end)
	end
	coreSnapshot = {}
end

-- =========================
-- Menu-only input lock (LOGIC UNCHANGED)
-- =========================
local controls
local inputBlocked = false

local function blockGameplayInputs()
	if inputBlocked then return end
	inputBlocked = true

	local ps = player:WaitForChild("PlayerScripts")
	local pm = ps:FindFirstChild("PlayerModule")
	if pm then
		local ok, mod = pcall(require, pm)
		if ok and mod and mod.GetControls then
			controls = mod:GetControls()
			pcall(function() controls:Disable() end)
		end
	end

	local function sink() return Enum.ContextActionResult.Sink end
	ContextActionService:BindActionAtPriority("__MENU_BLOCK_KEYS__", sink, false, 99999,
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
		Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift,
		Enum.KeyCode.E, Enum.KeyCode.Q, Enum.KeyCode.F, Enum.KeyCode.R,
		Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
		Enum.KeyCode.Tab
	)
end

local function unblockGameplayInputs()
	if not inputBlocked then return end
	inputBlocked = false
	ContextActionService:UnbindAction("__MENU_BLOCK_KEYS__")
	if controls then pcall(function() controls:Enable() end) end
	controls = nil
end

-- =========================
-- Camera handling (LOGIC UNCHANGED)
-- =========================
local function enterMenuCamera()
	local cam = workspace.CurrentCamera
	if not cam then return end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CameraSubject = nil
	cam.CFrame = CFrame.new(0, 20, 60) * CFrame.Angles(0, math.rad(180), 0)
end

local function attachCameraToHumanoid(timeout)
	local cam = workspace.CurrentCamera
	if not cam then return false end
	cam.CameraType = Enum.CameraType.Custom

	local t0 = now()
	while now() - t0 < (timeout or 10) do
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
			return true
		end
		task.wait(0.05)
	end
	return false
end

-- =========================
-- Menu-only post FX (no blur)
-- =========================
local postFolder
local function ensurePostFX()
	if postFolder and postFolder.Parent then return end
	postFolder = Instance.new("Folder")
	postFolder.Name = "__StartMenuPostFX"
	postFolder.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "Bloom"
	bloom.Intensity = 0.45
	bloom.Size = 18
	bloom.Threshold = 0.9
	bloom.Parent = postFolder

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "ColorCorrect"
	cc.Brightness = -0.06
	cc.Contrast = 0.26
	cc.Saturation = -0.20
	cc.TintColor = Color3.fromRGB(255, 215, 160)
	cc.Parent = postFolder

	local blur = Instance.new("BlurEffect")
	blur.Name = "Blur"
	blur.Size = 0
	blur.Parent = postFolder
end

local function clearPostFX()
	if postFolder then
		postFolder:Destroy()
		postFolder = nil
	end
end

-- =========================
-- Audio groups + menu music (LOGIC UNCHANGED, FIXED PLAYBACK)
-- =========================
local function getOrCreateGroup(name)
	local g = SoundService:FindFirstChild(name)
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = 1
		g.Parent = SoundService
	end
	return g
end

local MusicGroup = getOrCreateGroup("Music")
local SFXGroup   = getOrCreateGroup("SFX")

local menuSound = Instance.new("Sound")
menuSound.Name = "__MenuMusic"
menuSound.Looped = false
menuSound.Volume = 1
menuSound.SoundGroup = MusicGroup
menuSound.Parent = SoundService

local menuTracks = {}
local trackIndex = 1
local shuffle = false
local loopOne = false

local function normalizeSoundId(id)
	if typeof(id) ~= "string" then return nil end
	id = id:gsub("%s+", "")
	if id == "" then return nil end
	local num = id:match("rbxassetid://(%d+)") or id:match("id=(%d+)") or id:match("^(%d+)$")
	if not num then return nil end
	return "rbxassetid://" .. num
end

local function findMenuMusicFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local audio = assets and assets:FindFirstChild("Audio")
	local folder = audio and audio:FindFirstChild("MenuMusic")
	if folder and folder:IsA("Folder") then return folder end
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d:IsA("Folder") and d.Name == "MenuMusic" then
			return d
		end
	end
	return nil
end

local function loadTracksFromFolder()
	menuTracks = {}
	local folder = findMenuMusicFolder()
	if not folder then
		warn("[StartMenu:Music] Missing MenuMusic folder. Put sounds in ReplicatedStorage/Assets/Audio/MenuMusic")
		return false
	end

	for _, s in ipairs(folder:GetChildren()) do
		if s:IsA("Sound") then
			local sid = normalizeSoundId(s.SoundId) or normalizeSoundId(s:GetAttribute("SoundId"))
			if sid then
				table.insert(menuTracks, {
					name = (s.Name ~= "" and s.Name) or "Untitled",
					soundId = sid,
					artist = s:GetAttribute("Artist"),
				})
			end
		end
	end

	table.sort(menuTracks, function(a,b) return (a.name or "") < (b.name or "") end)
	return #menuTracks > 0
end

local function applyAudioSettings(settings)
	settings = settings or {}
	local master = math.clamp(tonumber(settings.masterVolume) or 0.85, 0, 1)
	local music  = math.clamp(tonumber(settings.musicVolume)  or 0.80, 0, 1)
	local sfx    = math.clamp(tonumber(settings.sfxVolume)    or 0.85, 0, 1)
	MusicGroup.Volume = master * music
	SFXGroup.Volume   = master * sfx
end

local function pickNextIndex()
	if #menuTracks == 0 then return 1 end
	if loopOne then return trackIndex end
	if shuffle then
		if #menuTracks == 1 then return 1 end
		local newIdx = trackIndex
		while newIdx == trackIndex do
			newIdx = math.random(1, #menuTracks)
		end
		return newIdx
	end
	local nxt = trackIndex + 1
	if nxt > #menuTracks then nxt = 1 end
	return nxt
end

local function playTrack(idx)
	if #menuTracks == 0 then return false end
	idx = math.clamp(idx or 1, 1, #menuTracks)
	trackIndex = idx
	local tr = menuTracks[trackIndex]
	if not tr or not tr.soundId then return false end

	-- FIX: no layered audio, ever
	menuSound:Stop()
	menuSound.SoundId = tr.soundId
	menuSound.TimePosition = 0

	pcall(function() ContentProvider:PreloadAsync({menuSound}) end)
	menuSound:Play()

	return true
end

local function togglePlayPause()
	if menuSound.IsPlaying then
		menuSound:Pause()
	else
		if menuSound.SoundId == "" then
			playTrack(trackIndex)
		else
			menuSound:Resume()
		end
	end
end

menuSound.Ended:Connect(function()
	if #menuTracks == 0 then return end
	trackIndex = pickNextIndex()
	playTrack(trackIndex)
end)

local function ensureMenuMusicStarted()
	if #menuTracks == 0 then return end
	if not menuSound.IsPlaying then
		playTrack(trackIndex)
	end
end

-- =========================
-- Settings state (LOGIC UNCHANGED)
-- =========================
local menuState = {
	settings = {
		masterVolume = 0.85,
		musicVolume  = 0.80,
		sfxVolume    = 0.85,
		uiScale = 1.0,
		graphicsQuality = 7,
		cameraShake = true,
		reducedFlashes = false,
		showDamageNumbers = true,
		bloodEffects = true,
	},
	slots = {},
}

local reqCounter = 0
local function nextReqId()
	reqCounter += 1
	return reqCounter
end

-- =========================
-- Runtime GUI root
-- =========================
local GUI_NAME = "__StartMenu_RUNTIME"
local old = playerGui:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999999
gui.Enabled = true
pcall(function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
gui.Parent = playerGui

-- Root fill
local root = make("Frame", {
	Name = "Root",
	Size = UDim2.fromScale(1,1),
	BackgroundColor3 = Color3.fromRGB(0,0,0),
	BorderSizePixel = 0,
	ZIndex = 1,
	Active = false,
}, gui)

-- Theme
local C_BG      = Color3.fromRGB(5, 5, 8)
local C_BG2     = Color3.fromRGB(24, 3, 14)
local C_PANEL   = Color3.fromRGB(10, 10, 14)
local C_PANEL2  = Color3.fromRGB(18, 18, 24)
local C_TEXT    = Color3.fromRGB(245, 245, 245)
local C_MUTED   = Color3.fromRGB(170, 170, 180)
local C_ACCENT  = Color3.fromRGB(255, 220, 140)
local C_DANGER  = Color3.fromRGB(255, 60, 60)
local C_GOOD    = Color3.fromRGB(170, 255, 210)

-- Background stack (FORCE UNDER UI)
local bg = make("Frame", {
	Size = UDim2.fromScale(1,1),
	BackgroundColor3 = C_BG,
	BorderSizePixel = 0,
	ZIndex = 0,
	Active = false,
}, root)
make("UIGradient", {Rotation=18, Color=ColorSequence.new(C_BG, C_BG2)}, bg)

local scanWrap = make("Frame", {
	Size = UDim2.fromScale(1,1),
	BackgroundTransparency = 1,
	ZIndex = 0,
	Active = false,
}, root)

for i = 1, 120 do
	make("Frame", {
		Position = UDim2.new(0,0,(i-1)/120,0),
		Size = UDim2.new(1,0,0,1),
		BackgroundColor3 = Color3.fromRGB(255,255,255),
		BackgroundTransparency = 0.978,
		BorderSizePixel = 0,
		ZIndex = 0,
		Active = false,
	}, scanWrap)
end

local noise = make("Frame", {
	Size = UDim2.fromScale(1,1),
	BackgroundColor3 = Color3.fromRGB(255,255,255),
	BackgroundTransparency = 0.989,
	BorderSizePixel = 0,
	ZIndex = 0,
	Active = false,
}, root)
make("UIGradient", {Rotation=35}, noise)

local glitchLayer = make("Frame", {
	Size = UDim2.fromScale(1,1),
	BackgroundTransparency = 1,
	ZIndex = 0,
	Active = false,
}, root)

local function glitchBurst(intensity)
	if menuState.settings.reducedFlashes then return end
	intensity = intensity or 1
	for i=1, math.random(2, 4) do
		local g = make("Frame", {
			BackgroundColor3 = (math.random() < 0.5) and C_ACCENT or C_DANGER,
			BackgroundTransparency = 0.80,
			BorderSizePixel = 0,
			Size = UDim2.new(math.random(10, 22)/100, 0, 0, snap(math.random(8, 14)*intensity, 2)),
			Position = UDim2.new(math.random(), snap(math.random(-30,30),2), math.random(), snap(math.random(-30,30),2)),
			ZIndex = 0,
			Active = false,
		}, glitchLayer)
		task.delay(0.08, function()
			if g and g.Parent then
				tween(g, {BackgroundTransparency=1}, 0.10)
				task.delay(0.12, function() if g and g.Parent then g:Destroy() end end)
			end
		end)
	end
end

-- Safe padding container (so nothing goes off-screen)
local safe = make("Frame", {
	Name="Safe",
	Size=UDim2.fromScale(1,1),
	BackgroundTransparency=1,
	ZIndex = 2,
}, root)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 18),
	PaddingRight = UDim.new(0, 18),
	PaddingTop = UDim.new(0, 16),
	PaddingBottom = UDim.new(0, 16),
}, safe)

-- Scale = baseScale * uiScaleSetting
local uiScale = make("UIScale", {Scale = 1}, safe)
local function computeBaseScale()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
	return math.clamp(math.min(vp.X/1920, vp.Y/1080), 0.72, 1.05)
end
local function applyUIScale()
	local base = computeBaseScale()
	local userS = math.clamp(tonumber(menuState.settings.uiScale) or 1.0, 0.8, 1.2)
	uiScale.Scale = base * userS
end

-- =========================
-- Corner-only Tunnel Overlay (DOES NOT BLOCK INPUT)
-- =========================
local cornerTunnel = nil

local function makeCornerTunnel(parent, opts)
	opts = opts or {}
	local color = opts.color or C_ACCENT
	local sizePx = tonumber(opts.sizePx) or 210
	local layers = tonumber(opts.layers) or 18
	local inset = tonumber(opts.inset) or 7
	local thickness = tonumber(opts.thickness) or 2
	local alpha = tonumber(opts.alpha) or 0.20
	local speed = tonumber(opts.speed) or 16

	local wrap = make("Frame", {
		Name = "__CornerTunnel",
		Size = UDim2.fromScale(1,1),
		BackgroundTransparency = 1,
		ZIndex = 1,          -- below safe/nav/content (those start at 2+)
		Active = false,
		Selectable = false,
	}, parent)

	local function corner(anchor, pos)
		local c = make("Frame", {
			AnchorPoint = anchor,
			Position = pos,
			Size = UDim2.new(0, sizePx, 0, sizePx),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 1,
			Active = false,
			Selectable = false,
		}, wrap)
		return c
	end

	local tl = corner(Vector2.new(0,0), UDim2.new(0,0,0,0))
	local tr = corner(Vector2.new(1,0), UDim2.new(1,0,0,0))
	local bl = corner(Vector2.new(0,1), UDim2.new(0,0,1,0))
	local br = corner(Vector2.new(1,1), UDim2.new(1,0,1,0))

	local corners = {tl=tl, tr=tr, bl=bl, br=br}
	local rects = {tl={}, tr={}, bl={}, br={}}
	local t = 0
	local enabled = true

	local function buildFor(key, holder)
		-- container that we will offset slightly for the "tunnelling" motion
		local inner = make("Frame", {
			Name = "Inner",
			Size = UDim2.fromScale(1,1),
			BackgroundTransparency = 1,
			ZIndex = 1,
			Active = false,
			Selectable = false,
		}, holder)

		rects[key].inner = inner
		rects[key].frames = {}

		for i=1, layers do
			local pad = (i-1) * inset
			local f = make("Frame", {
				BackgroundColor3 = color,
				BackgroundTransparency = alpha,
				BorderSizePixel = 0,
				ZIndex = 1,
				Active = false,
				Selectable = false,
				Size = UDim2.new(1, -pad*2, 1, -pad*2),
				Position = UDim2.new(0, pad, 0, pad),
			}, inner)

			-- outline style via 4 edges (so it looks like a tunnel rather than filled blocks)
			make("Frame", {BackgroundColor3=color, BackgroundTransparency=alpha, BorderSizePixel=0, ZIndex=1, Active=false,
				Size=UDim2.new(1,0,0,thickness), Position=UDim2.new(0,0,0,0)}, f)
			make("Frame", {BackgroundColor3=color, BackgroundTransparency=alpha, BorderSizePixel=0, ZIndex=1, Active=false,
				Size=UDim2.new(1,0,0,thickness), Position=UDim2.new(0,0,1,-thickness)}, f)
			make("Frame", {BackgroundColor3=color, BackgroundTransparency=alpha, BorderSizePixel=0, ZIndex=1, Active=false,
				Size=UDim2.new(0,thickness,1,0), Position=UDim2.new(0,0,0,0)}, f)
			make("Frame", {BackgroundColor3=color, BackgroundTransparency=alpha, BorderSizePixel=0, ZIndex=1, Active=false,
				Size=UDim2.new(0,thickness,1,0), Position=UDim2.new(1,-thickness,0,0)}, f)

			table.insert(rects[key].frames, f)
		end
	end

	buildFor("tl", tl)
	buildFor("tr", tr)
	buildFor("bl", bl)
	buildFor("br", br)

	local function setColor(newColor)
		color = newColor or color
		for _, pack in pairs(rects) do
			for _, f in ipairs(pack.frames or {}) do
				f.BackgroundColor3 = color
				for _, child in ipairs(f:GetChildren()) do
					if child:IsA("Frame") then child.BackgroundColor3 = color end
				end
			end
		end
	end

	local function setEnabled(on)
		enabled = (on == true)
		wrap.Visible = enabled
	end

	local function step(dt)
		if not enabled then return end
		t += dt * speed
		local wob = snap(math.sin(t) * 6, 1)
		local wob2 = snap(math.cos(t*0.9) * 6, 1)

		-- Offset each corner's inner slightly differently so it feels alive
		if rects.tl.inner then rects.tl.inner.Position = UDim2.new(0, wob, 0, wob2) end
		if rects.tr.inner then rects.tr.inner.Position = UDim2.new(0, -wob, 0, wob2) end
		if rects.bl.inner then rects.bl.inner.Position = UDim2.new(0, wob, 0, -wob2) end
		if rects.br.inner then rects.br.inner.Position = UDim2.new(0, -wob, 0, -wob2) end
	end

	return {
		Wrap = wrap,
		SetEnabled = setEnabled,
		SetColor = setColor,
		Step = step,
	}
end

-- =========================
-- Bridge for SoulSelect (LOGIC UNCHANGED)
-- =========================
local BRIDGE_NAME = "__SoulSelectBridge"
local bridge = playerGui:FindFirstChild(BRIDGE_NAME)
if bridge then bridge:Destroy() end
bridge = Instance.new("BindableEvent")
bridge.Name = BRIDGE_NAME
bridge.Parent = playerGui

local chosenSoul = nil
local pendingStartReqId = nil
local pendingStartSlot = nil
local pendingStartMode = nil

-- =========================
-- Header
-- =========================
local header = make("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1,0,0,112),
	ZIndex = 3,
}, safe)

local title = make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0, 0, 0, 0),
	Size=UDim2.new(1,0,0,62),
	Text="DETERMINANT",
	Font=Enum.Font.GothamBlack,
	TextSize=64,
	TextColor3=C_TEXT,
	TextXAlignment=Enum.TextXAlignment.Left,
	ZIndex = 3,
}, header)

local subtitle = make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0, 2, 0, 64),
	Size=UDim2.new(1,0,0,18),
	Text="THE MENU IS WATCHING YOU.",
	Font=Enum.Font.GothamSemibold,
	TextSize=14,
	TextColor3=C_ACCENT,
	TextXAlignment=Enum.TextXAlignment.Left,
	TextTransparency=0.06,
	ZIndex = 3,
}, header)

local status = make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0, 2, 0, 84),
	Size=UDim2.new(1,0,0,18),
	Text="Waiting for server…",
	Font=Enum.Font.Code,
	TextSize=14,
	TextColor3=C_MUTED,
	TextXAlignment=Enum.TextXAlignment.Left,
	TextTransparency=0.10,
	ZIndex = 3,
}, header)

local function setStatus(t) status.Text = t or "" end

-- =========================
-- Main layout (responsive clamp)
-- =========================
local main = make("Frame", {
	BackgroundTransparency=1,
	Position=UDim2.new(0,0,0,120),
	Size=UDim2.new(1,0,1,-120),
	ZIndex = 3,
}, safe)

local NAV_GAP = 14

local nav = make("Frame", {
	BackgroundColor3=C_PANEL,
	BorderSizePixel=0,
	ZIndex=4,
}, main)
addRoughBorder(nav, C_ACCENT)

local content = make("Frame", {
	BackgroundColor3=C_PANEL,
	BorderSizePixel=0,
	ZIndex=4,
}, main)
addRoughBorder(content, C_ACCENT)

local function layoutMain()
	local w = main.AbsoluteSize.X
	local navW = math.clamp(math.floor(w * 0.34 + 0.5), 320, 520)
	nav.Size = UDim2.new(0, navW, 1, 0)
	nav.Position = UDim2.new(0,0,0,0)

	content.Position = UDim2.new(0, navW + NAV_GAP, 0, 0)
	content.Size = UDim2.new(1, -(navW + NAV_GAP), 1, 0)
end
main:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutMain)
task.defer(layoutMain)

-- =========================
-- Nav: strip + buttons
-- =========================
local navStrip = make("Frame", {
	BackgroundColor3=Color3.fromRGB(12,12,16),
	BorderSizePixel=0,
	Size=UDim2.new(1,0,0,54),
	ZIndex=5,
}, nav)
addRoughBorder(navStrip, C_DANGER)

make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0,14,0,10),
	Size=UDim2.new(1,-28,0,18),
	Text="MENU CONTROL",
	Font=Enum.Font.Code,
	TextSize=14,
	TextColor3=C_ACCENT,
	TextXAlignment=Enum.TextXAlignment.Left,
	ZIndex=6,
}, navStrip)

make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0,14,0,28),
	Size=UDim2.new(1,-28,0,18),
	Text="INPUT: MOUSE / KEYS",
	Font=Enum.Font.Code,
	TextSize=12,
	TextColor3=C_MUTED,
	TextXAlignment=Enum.TextXAlignment.Left,
	TextTransparency=0.15,
	ZIndex=6,
}, navStrip)

local navStack = make("Frame", {
	BackgroundTransparency=1,
	Position=UDim2.new(0,0,0,64),
	Size=UDim2.new(1,0,1,-64),
	ZIndex=5,
}, nav)

make("UIListLayout", {
	Padding=UDim.new(0, 10),
	SortOrder=Enum.SortOrder.LayoutOrder,
	HorizontalAlignment=Enum.HorizontalAlignment.Center,
	VerticalAlignment=Enum.VerticalAlignment.Top,
}, navStack)

local function navButton(text, desc, order, accent)
	local b = make("TextButton", {
		Size=UDim2.new(1, -26, 0, 72),
		BackgroundColor3=C_PANEL2,
		BorderSizePixel=0,
		AutoButtonColor=false,
		Text="",
		LayoutOrder=order,
		ZIndex=6,
		Active=true,
	}, navStack)
	addRoughBorder(b, accent or C_ACCENT)

	local glow = make("Frame", {
		BackgroundColor3=accent or C_ACCENT,
		BackgroundTransparency=0.92,
		BorderSizePixel=0,
		Size=UDim2.new(1,0,1,0),
		ZIndex=7,
		Visible=false,
		Active=false,
	}, b)

	local t = make("TextLabel", {
		BackgroundTransparency=1,
		Position=UDim2.new(0,16,0,12),
		Size=UDim2.new(1,-32,0,22),
		Text=text,
		Font=Enum.Font.GothamBlack,
		TextSize=18,
		TextColor3=C_TEXT,
		TextXAlignment=Enum.TextXAlignment.Left,
		ZIndex=8,
	}, b)

	local d = make("TextLabel", {
		BackgroundTransparency=1,
		Position=UDim2.new(0,16,0,38),
		Size=UDim2.new(1,-32,0,18),
		Text=desc or "",
		Font=Enum.Font.Gotham,
		TextSize=12,
		TextColor3=C_MUTED,
		TextXAlignment=Enum.TextXAlignment.Left,
		TextTransparency=0.12,
		ZIndex=8,
	}, b)

	local enabled = true
	local function setEnabled(on)
		enabled = on
		t.TextTransparency = enabled and 0 or 0.55
		d.TextTransparency = enabled and 0.12 or 0.80
		glow.Visible = false
	end

	b.MouseEnter:Connect(function()
		if not enabled then return end
		glow.Visible = true
		tween(b, {BackgroundColor3=Color3.fromRGB(28,28,38)}, 0.08)
	end)
	b.MouseLeave:Connect(function()
		if not enabled then return end
		glow.Visible = false
		tween(b, {BackgroundColor3=C_PANEL2}, 0.12)
	end)

	return b, setEnabled
end

local btnContinue, setContinueEnabled = navButton("Continue", "Resume from a save slot.", 1, C_ACCENT)
local btnNewGame = navButton("New Game", "Begin a fresh timeline (soul selection).", 2, C_DANGER)
local btnSettings = navButton("Settings", "Audio, visuals, accessibility.", 3, C_ACCENT)
local btnMusic = navButton("Music", "Playlist + playback.", 4, C_ACCENT)
local btnCredits = navButton("Credits", "Credits + acknowledgements.", 5, C_ACCENT)

btnNewGame = btnNewGame
btnSettings = btnSettings
btnMusic = btnMusic
btnCredits = btnCredits

-- =========================
-- Content header + pages
-- =========================
local contentHeader = make("Frame", {
	BackgroundColor3=Color3.fromRGB(12,12,16),
	BorderSizePixel=0,
	Size=UDim2.new(1,0,0,60),
	ZIndex=5,
}, content)
addRoughBorder(contentHeader, C_ACCENT)

local rcTitle = make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0,16,0,12),
	Size=UDim2.new(1,-32,0,20),
	Text="SAVE SLOTS",
	Font=Enum.Font.GothamBlack,
	TextSize=20,
	TextColor3=C_TEXT,
	TextXAlignment=Enum.TextXAlignment.Left,
	ZIndex=6,
}, contentHeader)

local rcSub = make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0,16,0,34),
	Size=UDim2.new(1,-32,0,18),
	Text="Choose Continue or New Game.",
	Font=Enum.Font.Gotham,
	TextSize=12,
	TextColor3=C_MUTED,
	TextXAlignment=Enum.TextXAlignment.Left,
	TextTransparency=0.12,
	ZIndex=6,
}, contentHeader)

local pageWrap = make("Frame", {
	BackgroundTransparency=1,
	Position=UDim2.new(0,0,0,68),
	Size=UDim2.new(1,0,1,-68),
	ZIndex=5,
}, content)

local pages = {}
local currentPage = "Slots"
local function showPage(name)
	for k,p in pairs(pages) do p.Visible = (k == name) end
	currentPage = name
end
local function setRightHeader(t, s)
	rcTitle.Text = t or ""
	rcSub.Text = s or ""
end

-- =========================
-- Slots page
-- =========================
local slotsPage = make("Frame", {BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Visible=true, ZIndex=5}, pageWrap)
pages.Slots = slotsPage

local slotList = make("ScrollingFrame", {
	BackgroundColor3=Color3.fromRGB(10,10,14),
	BorderSizePixel=0,
	Position=UDim2.new(0,12,0,12),
	Size=UDim2.new(1,-24,1,-24),
	CanvasSize=UDim2.new(0,0,0,0),
	ScrollBarThickness=10,
	ScrollBarImageColor3=C_ACCENT,
	ZIndex=6,
}, slotsPage)
addRoughBorder(slotList, C_ACCENT)

local slotLayout = make("UIListLayout", {
	Padding=UDim.new(0, 12),
	SortOrder=Enum.SortOrder.LayoutOrder,
	HorizontalAlignment=Enum.HorizontalAlignment.Center,
	VerticalAlignment=Enum.VerticalAlignment.Top,
}, slotList)

pcall(function()
	slotList.AutomaticCanvasSize = Enum.AutomaticSize.Y
end)

local function formatTime(ts)
	if type(ts) ~= "number" then return "Never" end
	local d = os.date("*t", ts)
	return string.format("%04d-%02d-%02d %02d:%02d", d.year, d.month, d.day, d.hour, d.min)
end

local slotCards = {}
local function buildSlotCard(i, s)
	local card = make("Frame", {
		Size=UDim2.new(1, -20, 0, 152),
		BackgroundColor3=Color3.fromRGB(12,12,16),
		BorderSizePixel=0,
		LayoutOrder=i,
		ZIndex=7,
	}, slotList)
	addRoughBorder(card, C_ACCENT)

	for n=1, 9 do
		make("Frame", {
			BackgroundColor3=Color3.fromRGB(255,255,255),
			BackgroundTransparency=0.985,
			BorderSizePixel=0,
			Position=UDim2.new(0, 14, 0, 14 + n*13),
			Size=UDim2.new(1, -28, 0, 1),
			ZIndex=7,
			Active=false,
		}, card)
	end

	make("TextLabel", {
		BackgroundTransparency=1,
		Position=UDim2.new(0,14,0,12),
		Size=UDim2.new(1,-28,0,22),
		Text=("SLOT %d"):format(i),
		Font=Enum.Font.GothamBlack,
		TextSize=16,
		TextColor3=C_TEXT,
		TextXAlignment=Enum.TextXAlignment.Left,
		ZIndex=9,
	}, card)

	make("TextLabel", {
		BackgroundTransparency=1,
		Position=UDim2.new(0,14,0,42),
		Size=UDim2.new(1,-28,0,18),
		Text=s.exists and (s.slotName or ("Save "..i)) or "EMPTY",
		Font=Enum.Font.GothamSemibold,
		TextSize=14,
		TextColor3=s.exists and C_ACCENT or C_MUTED,
		TextXAlignment=Enum.TextXAlignment.Left,
		ZIndex=9,
	}, card)

	make("TextLabel", {
		BackgroundTransparency=1,
		Position=UDim2.new(0,14,0,66),
		Size=UDim2.new(1,-28,0,18),
		Text=("Last Played: %s"):format(s.exists and formatTime(s.updatedAt) or "—"),
		Font=Enum.Font.Code,
		TextSize=13,
		TextColor3=C_MUTED,
		TextXAlignment=Enum.TextXAlignment.Left,
		TextTransparency=0.06,
		ZIndex=9,
	}, card)

	return card
end

local function rebuildSlotsUI()
	for _, c in ipairs(slotCards) do c:Destroy() end
	slotCards = {}

	local anySave = false
	for i=1,3 do
		local s = menuState.slots[i] or { exists=false }
		if s.exists then anySave = true end
		table.insert(slotCards, buildSlotCard(i, s))
	end

	setContinueEnabled(anySave)
end

slotLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	if slotList.AutomaticCanvasSize ~= Enum.AutomaticSize.Y then
		slotList.CanvasSize = UDim2.new(0,0,0, slotLayout.AbsoluteContentSize.Y + 18)
	end
end)

-- =========================
-- Settings autosave (0.35s)
-- =========================
local settingsDirty = false
local settingsDirtyAt = 0
local settingsAutosaveConn = nil

local function queueSettingsAutosave()
	settingsDirty = true
	settingsDirtyAt = now()
	setRightHeader("SETTINGS", "Changes apply instantly. Autosaves in 0.35s.")
	if settingsAutosaveConn then return end

	settingsAutosaveConn = RunService.Heartbeat:Connect(function()
		if not settingsDirty then return end
		if now() - settingsDirtyAt < 0.35 then return end

		settingsDirty = false
		if settingsAutosaveConn then settingsAutosaveConn:Disconnect(); settingsAutosaveConn = nil end

		local reqId = nextReqId()
		local payload = {}
		for k,v in pairs(menuState.settings) do payload[k] = v end
		payload.reqId = reqId

		-- ✅ FIX: server expects "SetSettings"
		MenuAction:FireServer("SetSettings", payload)
		setStatus("Settings autosaved.")
	end)
end

-- =========================
-- Apply all local settings
-- =========================
local function applyAllSettingsLocal()
	applyAudioSettings(menuState.settings)
	applyUIScale()
	scanWrap.Visible = (menuState.settings.reducedFlashes ~= true)

	-- Corner tunnel respects Reduced Flashes
	if cornerTunnel then
		cornerTunnel:SetEnabled(menuState.settings.reducedFlashes ~= true)
	end
end

-- =========================
-- Settings page (REAL CONTROLS)
-- =========================
local settingsPage = make("Frame", {BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Visible=false, ZIndex=5}, pageWrap)
pages.Settings = settingsPage

local settingsScroll = make("ScrollingFrame", {
	BackgroundColor3=Color3.fromRGB(10,10,14),
	BorderSizePixel=0,
	Position=UDim2.new(0,12,0,12),
	Size=UDim2.new(1,-24,1,-24),
	CanvasSize=UDim2.new(0,0,0,0),
	ScrollBarThickness=10,
	ScrollBarImageColor3=C_ACCENT,
	ZIndex=6,
}, settingsPage)
addRoughBorder(settingsScroll, C_ACCENT)

local settingsLayout = make("UIListLayout", {Padding=UDim.new(0,12), SortOrder=Enum.SortOrder.LayoutOrder}, settingsScroll)
pcall(function() settingsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y end)

local function sectionHeader(text)
	local h = make("Frame", {
		Size=UDim2.new(1,-20,0,34),
		BackgroundTransparency=1,
		LayoutOrder=0,
		ZIndex=7,
	}, settingsScroll)

	make("TextLabel", {
		BackgroundTransparency=1,
		Position=UDim2.new(0,10,0,6),
		Size=UDim2.new(1,-20,0,22),
		Text=text,
		Font=Enum.Font.GothamBlack,
		TextSize=16,
		TextColor3=C_TEXT,
		TextXAlignment=Enum.TextXAlignment.Left,
		ZIndex=9,
	}, h)

	make("Frame", {
		BackgroundColor3=C_DANGER,
		BackgroundTransparency=0.85,
		BorderSizePixel=0,
		Position=UDim2.new(0,10,1,-2),
		Size=UDim2.new(1,-20,0,2),
		ZIndex=8,
		Active=false,
	}, h)
end

local function mkRow(height)
	local row = make("Frame", {
		Size=UDim2.new(1,-20,0,height),
		BackgroundColor3=C_PANEL2,
		BorderSizePixel=0,
		ZIndex=7,
	}, settingsScroll)
	addRoughBorder(row, C_ACCENT)
	return row
end

local function sliderRow(labelText, get, set, minV, maxV, step, fmt)
	local row = mkRow(74)

	make("TextLabel", {
		BackgroundTransparency=1,
		Position=UDim2.new(0,12,0,8),
		Size=UDim2.new(1,-140,0,20),
		Text=labelText,
		Font=Enum.Font.GothamSemibold,
		TextSize=14,
		TextColor3=C_TEXT,
		TextXAlignment=Enum.TextXAlignment.Left,
		ZIndex=9,
	}, row)

	local val = make("TextLabel", {
		BackgroundTransparency=1,
		Position=UDim2.new(1,-120,0,8),
		Size=UDim2.new(0,108,0,20),
		Text="",
		Font=Enum.Font.Code,
		TextSize=14,
		TextColor3=C_ACCENT,
		TextXAlignment=Enum.TextXAlignment.Right,
		ZIndex=9,
	}, row)

	local bar = make("Frame", {
		Position=UDim2.new(0,12,0,38),
		Size=UDim2.new(1,-24,0,16),
		BackgroundColor3=Color3.fromRGB(14,14,18),
		BorderSizePixel=0,
		ZIndex=8,
		Active=false,
	}, row)
	addRoughBorder(bar, C_ACCENT)

	local fill = make("Frame", {
		BackgroundColor3=C_ACCENT,
		BorderSizePixel=0,
		Size=UDim2.new(0,0,1,0),
		ZIndex=9,
		Active=false,
	}, bar)

	local hit = make("TextButton", {
		BackgroundTransparency=1,
		Size=UDim2.fromScale(1,1),
		Text="",
		AutoButtonColor=false,
		ZIndex=10,
	}, bar)

	local dragging = false

	local function clampSnap(v)
		v = math.clamp(v, minV, maxV)
		if step and step > 0 then
			v = math.floor((v/step) + 0.5) * step
			v = math.clamp(v, minV, maxV)
		end
		return v
	end

	local function render()
		local v = clampSnap(get())
		local alpha2 = (v - minV) / math.max(0.0001, (maxV - minV))
		fill.Size = UDim2.new(alpha2, 0, 1, 0)
		val.Text = fmt and fmt(v) or tostring(v)
	end

	local function setFromX(x)
		local ax = bar.AbsolutePosition.X
		local aw = bar.AbsoluteSize.X
		if aw <= 0 then return end
		local tt = (x - ax) / aw
		tt = math.clamp(tt, 0, 1)
		local v = minV + (maxV - minV) * tt
		v = clampSnap(v)
		set(v)
		render()
		applyAllSettingsLocal()
		queueSettingsAutosave()
	end

	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromX(UserInputService:GetMouseLocation().X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(UserInputService:GetMouseLocation().X)
		end
	end)

	render()
	return render
end

local function toggleRow(labelText, get, set)
	local row = mkRow(52)

	make("TextLabel", {
		BackgroundTransparency=1,
		Position=UDim2.new(0,12,0,0),
		Size=UDim2.new(1,-160,1,0),
		Text=labelText,
		Font=Enum.Font.GothamSemibold,
		TextSize=14,
		TextColor3=C_TEXT,
		TextXAlignment=Enum.TextXAlignment.Left,
		ZIndex=9,
	}, row)

	local state = make("TextLabel", {
		BackgroundTransparency=1,
		Position=UDim2.new(1,-130,0,0),
		Size=UDim2.new(0,118,1,0),
		Text="",
		Font=Enum.Font.Code,
		TextSize=14,
		TextColor3=C_ACCENT,
		TextXAlignment=Enum.TextXAlignment.Right,
		ZIndex=9,
	}, row)

	local dot = make("Frame", {
		AnchorPoint=Vector2.new(0.5,0.5),
		Position=UDim2.new(1,-146,0.5,0),
		Size=UDim2.new(0,10,0,10),
		BackgroundColor3=C_DANGER,
		BorderSizePixel=0,
		ZIndex=9,
		Active=false,
	}, row)

	local button = make("TextButton", {
		BackgroundTransparency=1,
		Size=UDim2.fromScale(1,1),
		Text="",
		AutoButtonColor=false,
		ZIndex=10,
	}, row)

	local function render()
		local on = (get() == true)
		state.Text = on and "ON" or "OFF"
		state.TextColor3 = on and C_GOOD or C_DANGER
		dot.BackgroundColor3 = on and C_GOOD or C_DANGER
	end

	button.MouseButton1Click:Connect(function()
		set(not (get() == true))
		render()
		applyAllSettingsLocal()
		queueSettingsAutosave()
	end)

	render()
	return render
end

sectionHeader("AUDIO")
local renderMaster = sliderRow("Master Volume",
	function() return tonumber(menuState.settings.masterVolume) or 0.85 end,
	function(v) menuState.settings.masterVolume = v end,
	0, 1, 0.01,
	function(v) return string.format("%d%%", math.floor(v*100+0.5)) end
)

local renderMusic = sliderRow("Music Volume",
	function() return tonumber(menuState.settings.musicVolume) or 0.80 end,
	function(v) menuState.settings.musicVolume = v end,
	0, 1, 0.01,
	function(v) return string.format("%d%%", math.floor(v*100+0.5)) end
)

local renderSFX = sliderRow("SFX Volume",
	function() return tonumber(menuState.settings.sfxVolume) or 0.85 end,
	function(v) menuState.settings.sfxVolume = v end,
	0, 1, 0.01,
	function(v) return string.format("%d%%", math.floor(v*100+0.5)) end
)

sectionHeader("UI / GRAPHICS")
local renderUIScale = sliderRow("UI Scale",
	function() return tonumber(menuState.settings.uiScale) or 1.0 end,
	function(v) menuState.settings.uiScale = v end,
	0.8, 1.2, 0.01,
	function(v) return string.format("%.2fx", v) end
)

local renderGfx = sliderRow("Graphics Quality",
	function() return tonumber(menuState.settings.graphicsQuality) or 7 end,
	function(v) menuState.settings.graphicsQuality = v end,
	1, 10, 1,
	function(v) return tostring(math.floor(v+0.5)) end
)

sectionHeader("ACCESSIBILITY")
local renderReduced = toggleRow("Reduced Flashes",
	function() return menuState.settings.reducedFlashes end,
	function(v) menuState.settings.reducedFlashes = v end
)

local renderShake = toggleRow("Camera Shake",
	function() return menuState.settings.cameraShake end,
	function(v) menuState.settings.cameraShake = v end
)

sectionHeader("GAMEPLAY")
local renderDmgNums = toggleRow("Show Damage Numbers",
	function() return menuState.settings.showDamageNumbers end,
	function(v) menuState.settings.showDamageNumbers = v end
)

local renderBlood = toggleRow("Blood Effects",
	function() return menuState.settings.bloodEffects end,
	function(v) menuState.settings.bloodEffects = v end
)

settingsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	if settingsScroll.AutomaticCanvasSize ~= Enum.AutomaticSize.Y then
		settingsScroll.CanvasSize = UDim2.new(0,0,0, settingsLayout.AbsoluteContentSize.Y + 24)
	end
end)

-- =========================
-- Music page (TEXT RENDERS + WORKS)
-- =========================
local musicPage = make("Frame", {BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Visible=false, ZIndex=5}, pageWrap)
pages.Music = musicPage

local musicBox = make("Frame", {
	BackgroundColor3=Color3.fromRGB(10,10,14),
	BorderSizePixel=0,
	Position=UDim2.new(0,12,0,12),
	Size=UDim2.new(1,-24,1,-24),
	ZIndex=6,
}, musicPage)
addRoughBorder(musicBox, C_ACCENT)

local nowPlaying = make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0,14,0,12),
	Size=UDim2.new(1,-28,0,20),
	Text="Now: —",
	Font=Enum.Font.Code,
	TextSize=14,
	TextColor3=C_ACCENT,
	TextXAlignment=Enum.TextXAlignment.Left,
	ZIndex=9,
}, musicBox)

local trackList = make("ScrollingFrame", {
	Position=UDim2.new(0,14,0,42),
	Size=UDim2.new(1,-28,1,-154),
	BackgroundColor3=Color3.fromRGB(18,18,24),
	BorderSizePixel=0,
	CanvasSize=UDim2.new(0,0,0,0),
	ScrollBarThickness=10,
	ScrollBarImageColor3=C_ACCENT,
	ZIndex=7,
}, musicBox)
addRoughBorder(trackList, C_ACCENT)

local trackLayout = make("UIListLayout", {Padding=UDim.new(0,8), SortOrder=Enum.SortOrder.LayoutOrder}, trackList)
pcall(function() trackList.AutomaticCanvasSize = Enum.AutomaticSize.Y end)

local function refreshNowPlaying()
	local tr = menuTracks[trackIndex]
	if not tr then
		nowPlaying.Text = "Now: — (no tracks)"
		return
	end
	local artist = tr.artist and (" | " .. tostring(tr.artist)) or ""
	local icon = menuSound.IsPlaying and "▶" or "❚❚"
	nowPlaying.Text = string.format("%s %s%s", icon, tr.name or "Untitled", artist)
end

local function rebuildTrackList()
	for _, c in ipairs(trackList:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end

	if #menuTracks == 0 then
		make("TextLabel", {
			BackgroundTransparency=1,
			Size=UDim2.new(1,-10,0,60),
			Text="No menu tracks found.\nPut Sounds in ReplicatedStorage/Assets/Audio/MenuMusic",
			Font=Enum.Font.Code,
			TextSize=14,
			TextColor3=C_MUTED,
			TextWrapped=true,
			TextXAlignment=Enum.TextXAlignment.Left,
			TextYAlignment=Enum.TextYAlignment.Top,
			ZIndex=9,
		}, trackList)
		return
	end

	for i, tr in ipairs(menuTracks) do
		local row = make("TextButton", {
			Size=UDim2.new(1,-10,0,48),
			BackgroundColor3=Color3.fromRGB(18,18,24),
			BorderSizePixel=0,
			AutoButtonColor=false,
			Text="",
			ZIndex=8,
		}, trackList)
		addRoughBorder(row, (i==trackIndex and C_DANGER or C_ACCENT))

		make("TextLabel", {
			BackgroundTransparency=1,
			Position=UDim2.new(0,10,0,6),
			Size=UDim2.new(1,-20,0,18),
			Text=tr.name or ("Track "..i),
			Font=Enum.Font.GothamSemibold,
			TextSize=14,
			TextColor3=C_TEXT,
			TextXAlignment=Enum.TextXAlignment.Left,
			ZIndex=10,
		}, row)

		make("TextLabel", {
			BackgroundTransparency=1,
			Position=UDim2.new(0,10,0,26),
			Size=UDim2.new(1,-20,0,16),
			Text=(tr.artist and tostring(tr.artist) or "Unknown Artist"),
			Font=Enum.Font.Code,
			TextSize=12,
			TextColor3=C_MUTED,
			TextXAlignment=Enum.TextXAlignment.Left,
			TextTransparency=0.12,
			ZIndex=10,
		}, row)

		row.MouseButton1Click:Connect(function()
			playTrack(i)
			refreshNowPlaying()
			rebuildTrackList()
		end)
	end
end

trackLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	if trackList.AutomaticCanvasSize ~= Enum.AutomaticSize.Y then
		trackList.CanvasSize = UDim2.new(0,0,0, trackLayout.AbsoluteContentSize.Y + 16)
	end
end)

local controlsRow = make("Frame", {
	BackgroundTransparency=1,
	AnchorPoint=Vector2.new(0,1),
	Position=UDim2.new(0,14,1,-12),
	Size=UDim2.new(1,-28,0,120),
	ZIndex=9,
}, musicBox)

make("UIListLayout", {
	FillDirection=Enum.FillDirection.Horizontal,
	Padding=UDim.new(0,10),
	HorizontalAlignment=Enum.HorizontalAlignment.Left,
	VerticalAlignment=Enum.VerticalAlignment.Center,
	SortOrder=Enum.SortOrder.LayoutOrder,
}, controlsRow)

local function ctrlBtn(text, color)
	local b = make("TextButton", {
		Size=UDim2.new(0,160,0,52),
		BackgroundColor3=C_PANEL2,
		BorderSizePixel=0,
		AutoButtonColor=false,
		Text=text,
		Font=Enum.Font.GothamBlack,
		TextSize=16,
		TextColor3=C_TEXT,
		ZIndex=10,
	}, controlsRow)
	addRoughBorder(b, color or C_ACCENT)
	return b
end

local bPrev = ctrlBtn("Prev", C_ACCENT)
local bPlay = ctrlBtn("Play/Pause", C_GOOD)
local bNext = ctrlBtn("Next", C_ACCENT)
local bShuffle = ctrlBtn("Shuffle: OFF", C_DANGER)
local bLoop = ctrlBtn("Loop One: OFF", C_DANGER)

bPrev.MouseButton1Click:Connect(function()
	if #menuTracks == 0 then return end
	trackIndex -= 1
	if trackIndex < 1 then trackIndex = #menuTracks end
	playTrack(trackIndex)
	refreshNowPlaying()
	rebuildTrackList()
end)

bNext.MouseButton1Click:Connect(function()
	if #menuTracks == 0 then return end
	trackIndex = pickNextIndex()
	playTrack(trackIndex)
	refreshNowPlaying()
	rebuildTrackList()
end)

bPlay.MouseButton1Click:Connect(function()
	togglePlayPause()
	refreshNowPlaying()
end)

bShuffle.MouseButton1Click:Connect(function()
	shuffle = not shuffle
	bShuffle.Text = shuffle and "Shuffle: ON" or "Shuffle: OFF"
end)

bLoop.MouseButton1Click:Connect(function()
	loopOne = not loopOne
	bLoop.Text = loopOne and "Loop One: ON" or "Loop One: OFF"
end)

-- =========================
-- Credits page
-- =========================
local creditsPage = make("Frame", {BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Visible=false, ZIndex=5}, pageWrap)
pages.Credits = creditsPage

local creditsBox = make("Frame", {
	BackgroundColor3=Color3.fromRGB(10,10,14),
	BorderSizePixel=0,
	Position=UDim2.new(0,12,0,12),
	Size=UDim2.new(1,-24,1,-24),
	ZIndex=6,
}, creditsPage)
addRoughBorder(creditsBox, C_ACCENT)

make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0,16,0,14),
	Size=UDim2.new(1,-32,1,-28),
	Text="CREDITS\n\nAdd your list.\n\nThe UI still doesn’t magically create the humans for you.",
	Font=Enum.Font.Gotham,
	TextSize=18,
	TextColor3=C_TEXT,
	TextWrapped=true,
	TextXAlignment=Enum.TextXAlignment.Left,
	TextYAlignment=Enum.TextYAlignment.Top,
	ZIndex=9,
}, creditsBox)

-- =========================
-- Loading overlay (LOGIC UNCHANGED)
-- =========================
local loadingOverlay = make("Frame", {
	Visible=false, Active=false,
	Size=UDim2.fromScale(1,1),
	BackgroundColor3=Color3.fromRGB(0,0,0),
	BackgroundTransparency=1,
	ZIndex=50,
}, root)

local loadingCard = make("Frame", {
	AnchorPoint=Vector2.new(0.5,0.5),
	Position=UDim2.fromScale(0.5,0.5),
	Size=UDim2.new(0,860,0,140),
	BackgroundColor3=C_PANEL,
	BackgroundTransparency=0.08,
	BorderSizePixel=0,
	ZIndex=51,
}, loadingOverlay)
addRoughBorder(loadingCard, C_ACCENT)

local loadingText = make("TextLabel", {
	BackgroundTransparency=1,
	AnchorPoint=Vector2.new(0.5,0.5),
	Position=UDim2.fromScale(0.5,0.5),
	Size=UDim2.new(1,-40,0,48),
	Text="Loading…",
	Font=Enum.Font.GothamBlack,
	TextSize=28,
	TextColor3=C_TEXT,
	ZIndex=52,
}, loadingCard)

local function setLoading(on, text)
	loadingOverlay.Visible = on
	loadingOverlay.Active = on
	if text then loadingText.Text = text end
	if on then
		loadingOverlay.BackgroundTransparency = 1
		tween(loadingOverlay, {BackgroundTransparency=0.32}, 0.12)
	else
		tween(loadingOverlay, {BackgroundTransparency=1}, 0.10)
	end
end

-- =========================
-- Modal for slot picker (LOGIC UNCHANGED)
-- =========================
local modalOverlay = make("Frame", {
	Visible=false, Active=false,
	Size=UDim2.fromScale(1,1),
	BackgroundColor3=Color3.fromRGB(0,0,0),
	BackgroundTransparency=1,
	ZIndex=60,
}, root)

local modalBlock = make("TextButton", {
	Size=UDim2.fromScale(1,1),
	BackgroundTransparency=1,
	Text="",
	AutoButtonColor=false,
	ZIndex=61,
}, modalOverlay)

local modalCard = make("Frame", {
	AnchorPoint=Vector2.new(0.5,0.5),
	Position=UDim2.fromScale(0.5,0.5),
	Size=UDim2.new(0, 900, 0, 620),
	BackgroundColor3=C_PANEL,
	BackgroundTransparency=0.02,
	BorderSizePixel=0,
	ZIndex=62,
}, modalOverlay)
addRoughBorder(modalCard, C_ACCENT)

local modalTitle = make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0,24,0,16),
	Size=UDim2.new(1,-48,0,30),
	TextXAlignment=Enum.TextXAlignment.Left,
	Font=Enum.Font.GothamBlack,
	TextSize=24,
	TextColor3=C_TEXT,
	Text="Modal",
	ZIndex=63,
}, modalCard)

local modalBody = make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0,24,0,58),
	Size=UDim2.new(1,-48,1,-162),
	TextXAlignment=Enum.TextXAlignment.Left,
	TextYAlignment=Enum.TextYAlignment.Top,
	Font=Enum.Font.Code,
	TextSize=15,
	TextColor3=Color3.fromRGB(235,235,235),
	TextWrapped=true,
	RichText=true,
	Text="",
	ZIndex=63,
}, modalCard)

local modalButtons = make("Frame", {
	BackgroundTransparency=1,
	AnchorPoint=Vector2.new(0.5,1),
	Position=UDim2.new(0.5,0,1,-18),
	Size=UDim2.new(1,-48,0,56),
	ZIndex=63,
}, modalCard)

make("UIListLayout", {
	Padding=UDim.new(0,10),
	FillDirection=Enum.FillDirection.Horizontal,
	HorizontalAlignment=Enum.HorizontalAlignment.Right,
	VerticalAlignment=Enum.VerticalAlignment.Center,
	SortOrder=Enum.SortOrder.LayoutOrder,
}, modalButtons)

local function clearModalButtons()
	for _, c in ipairs(modalButtons:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
end

local function modalButton(text, order, width, colorAccent)
	local b = make("TextButton", {
		Size=UDim2.new(0,width or 170,0,46),
		BackgroundColor3=C_PANEL2,
		BorderSizePixel=0,
		AutoButtonColor=false,
		Text=text,
		Font=Enum.Font.GothamBlack,
		TextSize=18,
		TextColor3=C_TEXT,
		LayoutOrder=order or 1,
		Active=true,
		ZIndex=64,
	}, modalButtons)
	addRoughBorder(b, colorAccent or C_DANGER)
	return b
end

local function openModal(titleText, bodyText)
	modalTitle.Text = titleText or "Modal"
	modalBody.Text = (bodyText and tostring(bodyText) ~= "" and bodyText) or "<i>…</i>"
	modalOverlay.Visible = true
	modalOverlay.Active = true
	modalBlock.Active = true
	modalOverlay.BackgroundTransparency = 1
	tween(modalOverlay, {BackgroundTransparency = 0.40}, 0.14)
end

local function closeModal()
	tween(modalOverlay, {BackgroundTransparency=1}, 0.12)
	task.delay(0.13, function()
		modalOverlay.Visible = false
		modalOverlay.Active = false
		modalBlock.Active = false
	end)
end

modalBlock.MouseButton1Click:Connect(function() end)

-- =========================
-- Slot picker (LOGIC PRESERVED)
-- =========================
local function openSlotPicker(titleText, mode) -- "NewGame" | "Continue"
	clearModalButtons()
	openModal(titleText, "")

	local lines = {}
	if mode == "NewGame" then
		table.insert(lines, string.format("<b>SOUL LOCKED:</b> <font color='rgb(255,220,140)'>%s</font>\n", tostring(chosenSoul or "UNKNOWN")))
	end

	for i=1,3 do
		local s = menuState.slots[i] or { exists=false }
		if s.exists then
			table.insert(lines, string.format("Slot %d: <b>%s</b>\nLast Played: %s", i, s.slotName or ("Save "..i), formatTime(s.updatedAt)))
		else
			table.insert(lines, string.format("Slot %d: <i>Empty</i>", i))
		end
	end

	local body = table.concat(lines, "\n\n")
	if body == "" then body = "<i>No slot data received.</i>" end
	modalBody.Text = body

	local cancel = modalButton("Cancel", 1, 140, C_ACCENT)
	cancel.MouseButton1Click:Connect(closeModal)

	for i = 3, 1, -1 do
		local b = modalButton(("Slot %d"):format(i), 2 + (3 - i), 140, C_DANGER)
		b.MouseButton1Click:Connect(function()
			closeModal()

			local reqId = nextReqId()
			pendingStartReqId = reqId
			pendingStartSlot = i
			pendingStartMode = mode

			setLoading(true, (mode == "Continue") and ("Requesting continue (slot %d)…"):format(i) or ("Requesting new game (slot %d)…"):format(i))

			local payload = { slot = i, reqId = reqId }
			MenuAction:FireServer(mode, payload)
		end)
	end
end

-- =========================
-- Page open
-- =========================
local function openSlotsPage()
	setRightHeader("SAVE SLOTS", "Choose Continue or New Game.")
	showPage("Slots")
	rebuildSlotsUI()
end

local function openSettingsPage()
	setRightHeader("SETTINGS", "Changes apply instantly. Autosaves in 0.35s.")
	showPage("Settings")
	renderMaster(); renderMusic(); renderSFX()
	renderUIScale(); renderGfx()
	renderReduced(); renderShake()
	renderDmgNums(); renderBlood()
end

local function openMusicPage()
	setRightHeader("MUSIC", "Playlist + playback controls.")
	showPage("Music")
	refreshNowPlaying()
	rebuildTrackList()
end

local function openCreditsPage()
	setRightHeader("CREDITS", "Who to blame.")
	showPage("Credits")
end

-- =========================
-- Menu lifecycle (LOGIC UNCHANGED)
-- =========================
local inMenu = false
local drift = 0
local cineConn

local function startCinematic()
	if cineConn then cineConn:Disconnect() end
	cineConn = RunService.RenderStepped:Connect(function(dt)
		if not inMenu then return end

		drift += dt * 10
		if menuState.settings.reducedFlashes then
			noise.BackgroundTransparency = 0.993
		else
			if math.random() < 0.25 then
				noise.BackgroundTransparency = 0.987 + (math.random()*0.006)
			end
			if math.random() < 0.05 then glitchBurst(1) end
		end

		if not menuState.settings.reducedFlashes then
			scanWrap.Position = UDim2.new(0,0,0, snap(drift % 3, 1))
			scanWrap.Visible = true
		else
			scanWrap.Visible = false
		end

		-- Corner tunnel step (only if enabled)
		if cornerTunnel and (menuState.settings.reducedFlashes ~= true) then
			cornerTunnel:Step(dt)
		end
	end)
end

local function stopCinematic()
	if cineConn then cineConn:Disconnect(); cineConn = nil end
end

local function enterMenuMode()
	if inMenu then return end
	inMenu = true
	snapshotCore()
	blockGameplayInputs()
	enterMenuCamera()
	ensurePostFX()

	-- Build corner tunnel once
	if not cornerTunnel then
		cornerTunnel = makeCornerTunnel(root, {
			color = C_ACCENT,
			sizePx = 210,
			layers = 18,
			inset = 7,
			thickness = 2,
			alpha = 0.20,
			speed = 16,
		})
	end

	gui.Enabled = true
	setLoading(false)
	setStatus("Menu ready.")
	openSlotsPage()
	startCinematic()
	applyAllSettingsLocal()
	ensureMenuMusicStarted()
end

local function leaveMenuMode()
	inMenu = false
	stopCinematic()
	closeModal()
	setLoading(false)
	clearPostFX()
	unblockGameplayInputs()
	restoreCore()
	gui.Enabled = false
end

-- =========================
-- Button wiring (LOGIC UNCHANGED)
-- =========================
btnNewGame.MouseButton1Click:Connect(function()
	if not inMenu then return end
	chosenSoul = nil
	setStatus("New Game: choosing soul…")
	bridge:Fire("Open")
end)

btnContinue.MouseButton1Click:Connect(function()
	if not inMenu then return end
	openSlotPicker("Continue: Choose Slot", "Continue")
end)

btnSettings.MouseButton1Click:Connect(function()
	if not inMenu then return end
	openSettingsPage()
end)

btnMusic.MouseButton1Click:Connect(function()
	if not inMenu then return end
	openMusicPage()
end)

btnCredits.MouseButton1Click:Connect(function()
	if not inMenu then return end
	openCreditsPage()
end)

-- =========================
-- Receive from SoulSelect (LOGIC UNCHANGED)
-- =========================
bridge.Event:Connect(function(kind, a)
	if kind == "Chosen" then
		chosenSoul = tostring(a)
		setStatus(("Soul locked: %s"):format(chosenSoul))
		return
	end
	if kind == "Mode" then
		if a == "NewGame" then
			openSlotPicker("New Game: Choose Slot", "NewGame")
		end
		return
	end
end)

-- =========================
-- Server -> client commands (LOGIC UNCHANGED + SetSoul before ready)
-- =========================
MenuCommand.OnClientEvent:Connect(function(cmd, data)
	data = data or {}
	local reqId = tonumber(data.reqId)

	if cmd == "EnterMenu" then
		if type(data.settings) == "table" then menuState.settings = data.settings end
		if type(data.slots) == "table" then menuState.slots = data.slots end
		applyAllSettingsLocal()
		enterMenuMode()
		return
	end

	if cmd == "State" then
		if type(data.slots) == "table" then
			menuState.slots = data.slots
			if currentPage == "Slots" then rebuildSlotsUI() end
		end
		return
	end

	if cmd == "Settings" then
		if type(data.settings) == "table" then
			menuState.settings = data.settings
			applyAllSettingsLocal()
			if currentPage == "Settings" then openSettingsPage() end
		end
		return
	end

	if cmd == "ConfirmOverwrite" then
		setLoading(false)
		clearModalButtons()
		openModal(data.title or "Overwrite?", data.body or "Overwrite?")
		local cancel = modalButton("Cancel", 1, 140, C_ACCENT)
		local overwrite = modalButton("Overwrite", 2, 160, C_DANGER)
		cancel.MouseButton1Click:Connect(closeModal)
		overwrite.MouseButton1Click:Connect(function()
			closeModal()
			local newReq = nextReqId()
			pendingStartReqId = newReq
			pendingStartSlot = tonumber(data.slot)
			pendingStartMode = "NewGame"
			setLoading(true, ("Overwriting slot %d…"):format(tonumber(data.slot) or 0))
			MenuAction:FireServer("OverwriteSlot", { slot = data.slot, reqId = newReq })
		end)
		return
	end

	if cmd == "Toast" then
		setLoading(false)
		clearModalButtons()
		openModal("Notice", data.text or "…")
		local close = modalButton("Close", 1, 140, C_ACCENT)
		close.MouseButton1Click:Connect(closeModal)
		return
	end

	if cmd == "StartLoading" then
		local slot = tonumber(data.slot) or pendingStartSlot or 1
		local mode = tostring(data.mode or pendingStartMode or "")

		setLoading(true, ("Loading gameplay (slot %d)…"):format(slot))

		-- ✅ Server expects SetSoul BEFORE ClientGameplayReady (NewGame only)
		if mode == "NewGame" and chosenSoul and reqId then
			MenuAction:FireServer("SetSoul", {
				reqId = reqId,
				slot = slot,
				soulType = tostring(chosenSoul),
			})
		end

		MenuAction:FireServer("ClientGameplayReady", { reqId = reqId })
		return
	end

	if cmd == "BeginGame" then
		setStatus("Entering game…")

		local fade = Instance.new("Frame")
		fade.BackgroundColor3 = Color3.new(0,0,0)
		fade.BackgroundTransparency = 1
		fade.Size = UDim2.fromScale(1,1)
		fade.ZIndex = 999999
		fade.Parent = root

		tween(fade, {BackgroundTransparency = 0}, 0.22)
		task.wait(0.22)

		setLoading(true, "Spawning…")
		attachCameraToHumanoid(10)

		menuSound:Stop()
		leaveMenuMode()

		task.delay(0.2, function()
			if fade and fade.Parent then fade:Destroy() end
		end)
		return
	end
end)

-- =========================
-- Bootstrap (LOGIC UNCHANGED)
-- =========================
setLoading(true, "Waiting for server…")
setStatus("Requesting menu state…")

loadTracksFromFolder()
applyAllSettingsLocal()
ensureMenuMusicStarted()

MenuAction:FireServer("RequestEnterMenu")

task.spawn(function()
	local ok, st = safeCall("MenuState", function()
		return MenuState:InvokeServer()
	end)
	if ok and type(st) == "table" then
		menuState.settings = st.settings or menuState.settings
		menuState.slots = st.slots or menuState.slots
		applyAllSettingsLocal()
		setLoading(false)
		enterMenuMode()
	else
		setLoading(false)
		setStatus("MenuState failed. Entering menu with defaults.")
		enterMenuMode()
	end
end)

print("[StartMenu] Loaded (corner tunnel, input-safe, settings autosave, music UI, pipeline intact).")
