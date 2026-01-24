-- StarterPack/ToughGlove/CombatClient.client.lua
-- ✅ Animations stay
-- ✅ Sends WeaponDamageRE (global)
-- ✅ Server enforces Phase2-only damage

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local tool = script.Parent

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local WeaponDamageRE = Remotes:WaitForChild("WeaponDamageRE")

-- === DAMAGE (server will use BattleData.Weapons anyway) ===
local TOOL_NAME = tool.Name

-- === ANIMS ===
local M1_ANIMS = {
	[1] = 79459011221889,
	[2] = 114470546309665,
	[3] = 121708346907794,
	[4] = 92239466022048,
}

local COMBO_MAX = 4
local CLICK_COOLDOWN = 0.12
local COMBO_RESET_TIME = 0.9
local ANIM_SPEED = 1.0
local FINISHER_COOLDOWN = 0.9

local equipped = false
local combo = 0
local lastClick = 0
local lastComboTime = 0
local lockedUntil = 0

local humanoid: Humanoid? = nil
local animator: Animator? = nil
local tracks: {[number]: AnimationTrack} = {}

local function getHumanoid()
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function getAnimator(h: Humanoid)
	local a = h:FindFirstChildOfClass("Animator")
	if not a then
		a = Instance.new("Animator")
		a.Parent = h
	end
	return a
end

local function loadTracks()
	humanoid = getHumanoid()
	if not humanoid then return end
	animator = getAnimator(humanoid)

	tracks = {}
	for i = 1, COMBO_MAX do
		local anim = Instance.new("Animation")
		anim.AnimationId = ("rbxassetid://%d"):format(M1_ANIMS[i])
		local ok, tr = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and tr then
			tr.Priority = Enum.AnimationPriority.Action
			tr.Looped = false
			tracks[i] = tr
		end
	end
end

local function stopAll()
	for _, t in pairs(tracks) do
		pcall(function()
			if t and t.IsPlaying then t:Stop(0.05) end
		end)
	end
end

local function fireWeaponHit()
	WeaponDamageRE:FireServer({
		toolName = TOOL_NAME,
		attack = "M1",
	})
end

local function swing()
	local now = os.clock()
	if now < lockedUntil then return end
	if (now - lastClick) < CLICK_COOLDOWN then return end
	if not equipped then return end

	lastClick = now

	if now - lastComboTime > COMBO_RESET_TIME then
		combo = 0
	end
	lastComboTime = now

	combo += 1
	if combo > COMBO_MAX then combo = 1 end

	stopAll()
	local tr = tracks[combo]
	if tr then
		pcall(function()
			tr:Play(0.05, 1, ANIM_SPEED)
		end)
	end

	fireWeaponHit()

	if combo == 4 then
		lockedUntil = math.max(lockedUntil, now + FINISHER_COOLDOWN)
		combo = 0
		lastComboTime = 0
	end
end

tool.Equipped:Connect(function()
	equipped = true
	combo = 0
	lastClick = 0
	lastComboTime = 0
	lockedUntil = 0
	loadTracks()
end)

tool.Unequipped:Connect(function()
	equipped = false
	stopAll()
end)

tool.Activated:Connect(swing)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if not equipped then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		swing()
	end
end)
