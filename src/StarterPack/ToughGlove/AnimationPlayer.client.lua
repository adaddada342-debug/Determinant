-- Tool LocalScript (ToughGlove Animations)
-- FIXED:
--  - No Animator creation (prevents stacking / track leaks with other systems)
--  - Idle/Walk priority set to Movement (won't stomp dodge)
--  - Respects character:GetAttribute("Dodging") so dodge animations don't get cut off
--  - Caches tracks per humanoid safely

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local tool = script.Parent

-- ======================
-- ANIMATION IDS
-- ======================
local IDLE_ID = 107085846799909
local WALK_ID = 112457855869927

-- ======================
-- TUNING
-- ======================
local BASE_WALKSPEED = 16
local BASE_ANIM_SPEED = 1.35

local ROTATE_DEGREES_ON_STOP = -90
local ROTATE_SMOOTHNESS = 12

-- ======================
-- STATE
-- ======================
local humanoid
local rootPart
local character

local updateConn
local equipped = false

local wasMoving = false
local turning = false
local turnStartCF = CFrame.new()
local turnGoalCF = CFrame.new()
local turnT = 1

-- Cache tracks per humanoid to avoid LoadAnimation spam across re-equips
local trackCache = {} -- [humanoid] = { idleTrack = AnimationTrack, walkTrack = AnimationTrack }

local idleAnim = Instance.new("Animation")
idleAnim.AnimationId = ("rbxassetid://%d"):format(IDLE_ID)

local walkAnim = Instance.new("Animation")
walkAnim.AnimationId = ("rbxassetid://%d"):format(WALK_ID)

local function getOrCreateTracks(hum)
	local cached = trackCache[hum]
	if cached and cached.idleTrack and cached.walkTrack then
		return cached.idleTrack, cached.walkTrack
	end

	-- IMPORTANT: use the existing Animator (do not create a new one)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		-- If Animator doesn't exist yet, wait briefly for Roblox to create it
		animator = hum:WaitForChild("Animator", 2)
	end
	if not animator then
		return nil, nil
	end

	local idleTrack = animator:LoadAnimation(idleAnim)
	idleTrack.Priority = Enum.AnimationPriority.Movement
	idleTrack.Looped = true

	local walkTrack = animator:LoadAnimation(walkAnim)
	walkTrack.Priority = Enum.AnimationPriority.Movement
	walkTrack.Looped = true

	trackCache[hum] = { idleTrack = idleTrack, walkTrack = walkTrack }
	return idleTrack, walkTrack
end

local function playTrack(track, fade)
	if track and not track.IsPlaying then
		track:Play(fade or 0.1)
	end
end

local function stopTrack(track, fade)
	if track and track.IsPlaying then
		track:Stop(fade or 0.1)
	end
end

local function startTurn()
	if not rootPart then return end
	turning = true
	turnT = 0
	turnStartCF = rootPart.CFrame

	local yaw = math.rad(ROTATE_DEGREES_ON_STOP)
	local pos = rootPart.Position
	local rot = CFrame.Angles(0, yaw, 0)
	turnGoalCF = CFrame.new(pos) * (turnStartCF - turnStartCF.Position) * rot
end

local function stepTurn(dt)
	if not turning or not rootPart then return end
	local alpha = 1 - math.exp(-ROTATE_SMOOTHNESS * dt)
	turnT = math.clamp(turnT + alpha, 0, 1)

	rootPart.CFrame = turnStartCF:Lerp(turnGoalCF, turnT)
	if turnT >= 0.999 then
		turning = false
	end
end

local idleTrack, walkTrack

local function update(dt)
	if not humanoid or not rootPart or not character then return end

	-- IMPORTANT: don't touch locomotion animations while dodging
	if character:GetAttribute("Dodging") then
		-- Let dodge script own AutoRotate; we just keep our tracks quiet
		stopTrack(idleTrack, 0.05)
		stopTrack(walkTrack, 0.05)
		turning = false
		wasMoving = false
		return
	end

	local moving = humanoid.MoveDirection.Magnitude > 0.01

	if moving then
		humanoid.AutoRotate = true
		turning = false

		stopTrack(idleTrack, 0.15)
		playTrack(walkTrack, 0.05)

		if walkTrack then
			local speedScale = humanoid.WalkSpeed / BASE_WALKSPEED
			walkTrack:AdjustSpeed(BASE_ANIM_SPEED * speedScale)
		end
	else
		-- Your rotate-on-stop behavior
		humanoid.AutoRotate = false

		stopTrack(walkTrack, 0.15)
		playTrack(idleTrack, 0.10)

		if wasMoving then
			startTurn()
		end

		stepTurn(dt)
	end

	wasMoving = moving
end

local function bindCharacter()
	character = player.Character
	if not character then return false end

	humanoid = character:FindFirstChildOfClass("Humanoid")
	rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return false end

	idleTrack, walkTrack = getOrCreateTracks(humanoid)
	if not idleTrack or not walkTrack then return false end

	return true
end

local function onEquipped()
	if equipped then return end
	equipped = true

	if not bindCharacter() then
		equipped = false
		return
	end

	playTrack(idleTrack, 0.1)

	if not updateConn then
		updateConn = RunService.RenderStepped:Connect(update)
	end
end

local function onUnequipped()
	if not equipped then return end
	equipped = false

	if updateConn then
		updateConn:Disconnect()
		updateConn = nil
	end

	-- Restore default behavior
	if humanoid then
		humanoid.AutoRotate = true
	end

	stopTrack(idleTrack, 0.1)
	stopTrack(walkTrack, 0.1)

	turning = false
	wasMoving = false
end

tool.Equipped:Connect(onEquipped)
tool.Unequipped:Connect(onUnequipped)

player.CharacterAdded:Connect(function()
	-- reset references; cache is per-humanoid anyway
	humanoid = nil
	rootPart = nil
	character = nil
	idleTrack = nil
	walkTrack = nil
	turning = false
	wasMoving = false
end)
