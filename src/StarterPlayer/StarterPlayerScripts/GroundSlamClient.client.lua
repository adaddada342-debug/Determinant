-- StarterPlayerScripts/GroundSlamClient
-- Slam: VFX moment = damage moment. Plays impact SFX when VFX starts.

if _G.__GroundSlamClientLoaded then return end
_G.__GroundSlamClientLoaded = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local AbilityRequest = remotes:WaitForChild("AbilityRequest")
local AbilityFX = remotes:WaitForChild("AbilityFX")
local AbilityImpact = remotes:WaitForChild("AbilityImpact") -- ✅ NEW

-- =========================================================
-- CONFIG
-- =========================================================
local CONFIG = {
	TOOL_NAME = "ToughGlove",
	COOLDOWN = 6.0,

	-- Animation
	SLAM_ANIM_ID = "rbxassetid://73164213778121",
	ANIM_FADE_IN = 0.08,
	ANIM_SPEED = 4.0,
	POST_ANIM_DELAY = 0.0,

	-- Minimum local windup before VFX/damage can happen (match server MIN_IMPACT_DELAY)
	MIN_LOCAL_WINDUP = 0.60,

	-- Movement lock during whole animation
	LOCK_WALKSPEED = 0,
	LOCK_JUMPPOWER = 0,
	LOCK_RELEASE_AFTER = 0.18,

	-- Impact frames
	IMPACT_HITSTOP = 0.08,
	SHAKE_TIME = 0.22,
	SHAKE_STRENGTH = 3.1,

	-- Visual scale
	RADIUS = 18,
	CRATER_RADIUS = 9,
	CRATER_LIFETIME = 2.2,

	-- CRAZY knobs
	DEBRIS_COUNT = 18,
	DEBRIS_SPEED = 55,
	DEBRIS_UP = 42,
	DUST_BURST = 120,
	SPIKE_COUNT = 14,
	EXTRA_RINGS = 2,
}

-- ===== Impact sound that plays when VFX starts =====
local IMPACT_SOUND_ID = "rbxassetid://9118617342"

local function playImpactSfxAt(pos: Vector3)
	-- Create a tiny invisible anchor part so the sound has a 3D position
	local anchor = Instance.new("Part")
	anchor.Name = "SlamSoundAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = workspace

	local s = Instance.new("Sound")
	s.SoundId = IMPACT_SOUND_ID
	s.Volume = 0.9
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = 90
	s.RollOffMinDistance = 10
	s.Parent = anchor

	s:Play()

	-- Cleanup
	Debris:AddItem(anchor, 3)
end


-- ===== Sounds (ReplicatedStorage -> SoundService clone) =====
local function ensureClientSounds()
	local existing = SoundService:FindFirstChild("UI_Sounds")
	if existing and existing:IsA("Folder") then return existing end

	local src = ReplicatedStorage:FindFirstChild("UI_Sounds")
	if not (src and src:IsA("Folder")) then
		warn("[GroundSlamClient] UI_Sounds not found in ReplicatedStorage. Slam will be silent.")
		return nil
	end

	local cloned = src:Clone()
	cloned.Name = "UI_Sounds"
	cloned.Parent = SoundService
	return cloned
end

local sounds = ensureClientSounds()
local SND_Impact = sounds and (sounds:FindFirstChild("Select") or sounds:FindFirstChild("TextBlip")) or nil

local function playSound(snd)
	if snd and snd:IsA("Sound") then
		snd:Stop()
		snd.TimePosition = 0
		snd:Play()
	end
end

-- ===== Character helpers =====
local function getChar() return player.Character end
local function getHumanoid(char) return char and char:FindFirstChildOfClass("Humanoid") end
local function getHRP(char) return char and char:FindFirstChild("HumanoidRootPart") end

local function hasToolEquipped(char)
	if not char then return false end
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") and child.Name == CONFIG.TOOL_NAME then
			return true
		end
	end
	return false
end

-- ===== Ground raycast =====
local function getGround(hrp: BasePart)
	local origin = hrp.Position + Vector3.new(0, 2, 0)
	local direction = Vector3.new(0, -120, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { hrp.Parent }

	local res = workspace:Raycast(origin, direction, params)
	if res then
		return res.Position, res.Normal
	end
	return hrp.Position - Vector3.new(0, 3, 0), Vector3.new(0, 1, 0)
end

-- ===== Screen flash + post effects =====
local blur: BlurEffect? = nil
local cc: ColorCorrectionEffect? = nil

local function ensurePostFX()
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Size = 0
		blur.Parent = Lighting
	end
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Contrast = 0
		cc.Saturation = 0
		cc.Brightness = 0
		cc.TintColor = Color3.new(1, 1, 1)
		cc.Parent = Lighting
	end
end

local function flashScreen()
	local pg = player:WaitForChild("PlayerGui")

	local gui = pg:FindFirstChild("SlamFlash")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "SlamFlash"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.Parent = pg
	end

	local frame = gui:FindFirstChild("F")
	if not frame then
		frame = Instance.new("Frame")
		frame.Name = "F"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = gui
	end

	local tIn = TweenService:Create(frame, TweenInfo.new(0.03), { BackgroundTransparency = 0.58 })
	local tOut = TweenService:Create(frame, TweenInfo.new(0.10), { BackgroundTransparency = 1 })
	tIn:Play()
	tIn.Completed:Connect(function() tOut:Play() end)

	ensurePostFX()
	if blur and cc then
		blur.Size = 0
		cc.Contrast = 0
		cc.Saturation = 0
		cc.Brightness = 0.02

		TweenService:Create(blur, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = 10 }):Play()
		TweenService:Create(cc, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Contrast = 0.25, Saturation = -0.2, Brightness = 0.08 }):Play()

		task.delay(0.09, function()
			if blur and cc then
				TweenService:Create(blur, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = 0 }):Play()
				TweenService:Create(cc, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Contrast = 0, Saturation = 0, Brightness = 0.02 }):Play()
			end
		end)
	end
end

-- ===== Camera shake =====
local cam = workspace.CurrentCamera
local shaking = false
local shakeConn: RBXScriptConnection? = nil
local baseCFrame: CFrame? = nil

local function startShake(duration, strength)
	if shaking then return end
	shaking = true
	baseCFrame = cam.CFrame

	local startT = os.clock()
	shakeConn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - startT
		if t >= duration then
			shaking = false
			if shakeConn then shakeConn:Disconnect() end
			shakeConn = nil
			if baseCFrame then cam.CFrame = baseCFrame end
			return
		end

		local jitter = Vector3.new(
			(math.random() - 0.5) * 2,
			(math.random() - 0.5) * 2,
			(math.random() - 0.5) * 2
		) * (strength / 18)

		cam.CFrame = baseCFrame * CFrame.new(jitter)
	end)
end

-- ===== Impact stop =====
local function impactStop(hum: Humanoid)
	local oldWalk = hum.WalkSpeed
	local oldJump = hum.JumpPower

	hum.WalkSpeed = 0
	hum.JumpPower = 0

	local animator = hum:FindFirstChildOfClass("Animator")
	local tracks = animator and animator:GetPlayingAnimationTracks() or {}
	for _, tr in ipairs(tracks) do
		pcall(function() tr:AdjustSpeed(0.05) end)
	end

	task.delay(CONFIG.IMPACT_HITSTOP, function()
		if hum and hum.Parent then
			hum.WalkSpeed = oldWalk
			hum.JumpPower = oldJump
			for _, tr in ipairs(tracks) do
				pcall(function() tr:AdjustSpeed(1) end)
			end
		end
	end)
end

-- ===== FX Folder =====
local function fxFolder()
	local f = workspace:FindFirstChild("FX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "FX"
		f.Parent = workspace
	end
	return f
end

-- ===== Disc helper =====
local function makeDiscPart(name, pos: Vector3, thickness: number, diameter: number)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(thickness, diameter, diameter)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	return p
end

-- ===== VFX =====
local function spawnCraterAndScorch(pos: Vector3)
	local fx = fxFolder()

	local crater = makeDiscPart("Crater", pos + Vector3.new(0, 0.02, 0), 0.16, 0.2)
	crater.Material = Enum.Material.Slate
	crater.Color = Color3.fromRGB(28, 28, 28)
	crater.Transparency = 0.05
	crater.Parent = fx

	local scorch = makeDiscPart("Scorch", pos + Vector3.new(0, 0.015, 0), 0.06, 0.2)
	scorch.Material = Enum.Material.SmoothPlastic
	scorch.Color = Color3.fromRGB(10, 10, 10)
	scorch.Transparency = 0.35
	scorch.Parent = fx

	TweenService:Create(crater, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.16, CONFIG.CRATER_RADIUS * 2, CONFIG.CRATER_RADIUS * 2)
	}):Play()

	TweenService:Create(scorch, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.06, (CONFIG.CRATER_RADIUS * 2.6), (CONFIG.CRATER_RADIUS * 2.6)),
		Transparency = 0.55
	}):Play()

	task.delay(CONFIG.CRATER_LIFETIME, function()
		if crater.Parent then
			local fade = TweenService:Create(crater, TweenInfo.new(0.40, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
			fade:Play()
			fade.Completed:Connect(function() if crater.Parent then crater:Destroy() end end)
		end
		if scorch.Parent then
			local fade2 = TweenService:Create(scorch, TweenInfo.new(0.40, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
			fade2:Play()
			fade2.Completed:Connect(function() if scorch.Parent then scorch:Destroy() end end)
		end
	end)
end

local function spawnShockwaveMega(pos: Vector3, radius: number)
	local fx = fxFolder()

	local disc = makeDiscPart("SlamDisc", pos + Vector3.new(0, 0.03, 0), 0.08, 0.2)
	disc.Material = Enum.Material.Neon
	disc.Color = Color3.new(1, 1, 1)
	disc.Transparency = 0.82
	disc.Parent = fx

	local ring = makeDiscPart("SlamRing", pos + Vector3.new(0, 0.035, 0), 0.12, 0.2)
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.new(1, 1, 1)
	ring.Transparency = 0.25
	ring.Parent = fx

	local tDisc = TweenService:Create(disc, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, radius * 2.1, radius * 2.1),
		Transparency = 1
	})
	local tRing = TweenService:Create(ring, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, radius * 2.8, radius * 2.8),
		Transparency = 1
	})
	tDisc:Play(); tRing:Play()
	tDisc.Completed:Connect(function() if disc.Parent then disc:Destroy() end end)
	tRing.Completed:Connect(function() if ring.Parent then ring:Destroy() end end)

	for i = 1, CONFIG.EXTRA_RINGS do
		task.delay(0.06 * i, function()
			local r = makeDiscPart("AfterRing", pos + Vector3.new(0, 0.04 + (i * 0.002), 0), 0.10, 0.2)
			r.Material = Enum.Material.Neon
			r.Color = Color3.new(1, 1, 1)
			r.Transparency = 0.45
			r.Parent = fx

			local target = radius * (2.3 + 0.4 * i)
			local tw = TweenService:Create(r, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.10, target * 2, target * 2),
				Transparency = 1
			})
			tw:Play()
			tw.Completed:Connect(function() if r.Parent then r:Destroy() end end)
		end)
	end
end

local function spawnDust(pos: Vector3)
	local fx = fxFolder()

	local emitterPart = Instance.new("Part")
	emitterPart.Name = "DustEmitter"
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(1, 1, 1)
	emitterPart.CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0))
	emitterPart.Parent = fx

	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(0.35, 0.7)
	pe.Speed = NumberRange.new(18, 36)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-120, 120)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 4
	pe.LightInfluence = 0
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1)
	})
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.8),
		NumberSequenceKeypoint.new(1, 4.5)
	})
	pe.Color = ColorSequence.new(Color3.fromRGB(140, 140, 140))
	pe.Parent = emitterPart
	pe:Emit(CONFIG.DUST_BURST)

	Debris:AddItem(emitterPart, 1.2)
end

local function spawnSpikes(pos: Vector3, radius: number)
	local fx = fxFolder()
	for i = 1, CONFIG.SPIKE_COUNT do
		local angle = (math.pi * 2) * (i / CONFIG.SPIKE_COUNT)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local length = radius * (1.2 + math.random() * 0.5)

		local spike = Instance.new("Part")
		spike.Name = "Spike"
		spike.Anchored = true
		spike.CanCollide = false
		spike.CanQuery = false
		spike.CanTouch = false
		spike.Material = Enum.Material.Neon
		spike.Color = Color3.new(1, 1, 1)
		spike.Transparency = 0.35
		spike.Size = Vector3.new(0.18, 0.18, length)
		spike.CFrame = CFrame.new(pos + Vector3.new(0, 0.12, 0), pos + dir * 10) * CFrame.new(0, 0, -length / 2)
		spike.Parent = fx

		local tw = TweenService:Create(spike, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.05, 0.05, length * 1.05)
		})
		tw:Play()
		tw.Completed:Connect(function() if spike.Parent then spike:Destroy() end end)
	end
end

local function spawnDebris(pos: Vector3, radius: number)
	local fx = fxFolder()

	for i = 1, CONFIG.DEBRIS_COUNT do
		local angle = math.random() * math.pi * 2
		local dist = math.random() * (radius * 0.35)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * dist

		local rock = Instance.new("Part")
		rock.Name = "Rock"
		rock.Size = Vector3.new(
			0.35 + math.random() * 0.8,
			0.35 + math.random() * 1.0,
			0.35 + math.random() * 0.8
		)
		rock.Material = Enum.Material.Slate
		rock.Color = Color3.fromRGB(60, 60, 60)
		rock.CanCollide = false
		rock.CanQuery = false
		rock.CanTouch = false
		rock.CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0) + offset) * CFrame.Angles(
			math.rad(math.random(0, 360)),
			math.rad(math.random(0, 360)),
			math.rad(math.random(0, 360))
		)
		rock.Parent = fx

		local dir = (offset.Magnitude > 0.01) and offset.Unit or Vector3.new(1, 0, 0)
		rock.AssemblyLinearVelocity =
			dir * (CONFIG.DEBRIS_SPEED * (0.7 + math.random() * 0.6)) +
			Vector3.new(0, CONFIG.DEBRIS_UP * (0.7 + math.random() * 0.6), 0)

		rock.AssemblyAngularVelocity = Vector3.new(
			math.random(-10, 10),
			math.random(-10, 10),
			math.random(-10, 10)
		)

		task.delay(0.65 + math.random() * 0.35, function()
			if rock.Parent then
				TweenService:Create(rock, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			end
		end)

		Debris:AddItem(rock, 1.4)
	end
end

local function slamVFX(pos: Vector3, radius: number)
	spawnCraterAndScorch(pos)
	spawnSpikes(pos, radius)
	spawnDust(pos)
	spawnShockwaveMega(pos, radius)
	spawnDebris(pos, radius)
end

-- ===== Animation =====
local slamAnim = Instance.new("Animation")
slamAnim.AnimationId = CONFIG.SLAM_ANIM_ID

local function playSlamAnimation(hum: Humanoid)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local track = animator:LoadAnimation(slamAnim)
	track:Play(CONFIG.ANIM_FADE_IN, 1, CONFIG.ANIM_SPEED)
	return track
end

-- ===== Slam logic =====
local lastCast = 0
local casting = false

local function doSlam()
	if casting then return end

	local t = os.clock()
	if t - lastCast < CONFIG.COOLDOWN then return end

	local char = getChar()
	local hum = getHumanoid(char)
	local hrp = getHRP(char)
	if not char or not hum or not hrp then return end
	if hum.Health <= 0 then return end
	if not hasToolEquipped(char) then return end
	if hum.FloorMaterial == Enum.Material.Air then return end

	casting = true
	lastCast = t

	local oldWalk = hum.WalkSpeed
	local oldJump = hum.JumpPower
	hum.WalkSpeed = CONFIG.LOCK_WALKSPEED
	hum.JumpPower = CONFIG.LOCK_JUMPPOWER

	AbilityRequest:FireServer({ ability = "GroundSlam" })

	local track = playSlamAnimation(hum)

	task.spawn(function()
		-- Wait for animation to "actually start" a bit; if it never starts, still enforce MIN_LOCAL_WINDUP
		local startTime = os.clock()

		local advanced = false
		if track then
			for _ = 1, 20 do
				if track.TimePosition > 0.05 then
					advanced = true
					break
				end
				task.wait(0.05)
			end
			if advanced then
				track.Stopped:Wait()
			end
		end

		-- Always enforce minimum windup before VFX/damage
		local elapsed = os.clock() - startTime
		if elapsed < CONFIG.MIN_LOCAL_WINDUP then
			task.wait(CONFIG.MIN_LOCAL_WINDUP - elapsed)
		end

		if CONFIG.POST_ANIM_DELAY > 0 then
			task.wait(CONFIG.POST_ANIM_DELAY)
		end

		-- VFX moment = damage moment
		local char2 = getChar()
		local hum2 = getHumanoid(char2)
		local hrp2 = getHRP(char2)
		if hum2 and hrp2 then
			local hitPos = select(1, getGround(hrp2))

			-- Your impact sound + (optional) UI sound
			playImpactSfxAt(hitPos)
			playSound(SND_Impact)

			flashScreen()
			impactStop(hum2)
			startShake(CONFIG.SHAKE_TIME, CONFIG.SHAKE_STRENGTH)

			slamVFX(hitPos, CONFIG.RADIUS)

			-- Tell server to apply damage NOW
			AbilityImpact:FireServer({ ability = "GroundSlam" })

			task.delay(CONFIG.LOCK_RELEASE_AFTER, function()
				if hum2 and hum2.Parent then
					hum2.WalkSpeed = oldWalk
					hum2.JumpPower = oldJump
				end
				casting = false
			end)
		else
			if hum and hum.Parent then
				hum.WalkSpeed = oldWalk
				hum.JumpPower = oldJump
			end
			casting = false
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.F then
		doSlam()
	end
end)

-- Ignore server echo for our own cast (prevents double VFX)
AbilityFX.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	if data.ability ~= "GroundSlam" then return end
	if typeof(data.origin) ~= "Vector3" then return end

	if data.casterUserId == player.UserId then
		return
	end

	local radius = tonumber(data.radius) or CONFIG.RADIUS
	slamVFX(data.origin, radius)
end)
