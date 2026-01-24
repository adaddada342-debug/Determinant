-- StarterPlayerScripts/DodgeRollDoubleTap.client.lua
-- ✅ AMENDED: Double-tap A/D triggers SERVER dodge roll (no client physics, no dt errors)
-- ✅ Plays animation locally for responsiveness
-- Requires ServerScriptService/DodgeRollServer.server.lua (your AlignPosition version)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DodgeRollRE = Remotes:WaitForChild("DodgeRollRE")

-- ========= ANIMATION IDS =========
local DODGE_LEFT_ID  = "rbxassetid://112907811601429"
local DODGE_RIGHT_ID = "rbxassetid://115917163099925"
-- ================================

-- ========= TUNING =========
local DOUBLE_TAP_WINDOW = 0.25
local COOLDOWN = 0.70
-- =========================

local lastDodgeTime = 0
local lastTapA, lastTapD = -1, -1
local trackCache = {} -- [humanoid] = { [animId] = AnimationTrack }

local function now() return os.clock() end

local function getChar()
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	return char, hum
end

local function getAnimator(hum)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	return animator
end

local function getCachedTrack(hum, animId)
	trackCache[hum] = trackCache[hum] or {}
	local existing = trackCache[hum][animId]
	if existing and existing.Parent then
		return existing
	end

	local animator = getAnimator(hum)
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	trackCache[hum][animId] = track
	return track
end

local function isDoubleTap(lastTapTime)
	return lastTapTime > 0 and (now() - lastTapTime) <= DOUBLE_TAP_WINDOW
end

local function tryRoll(side) -- -1 left, +1 right
	if (now() - lastDodgeTime) < COOLDOWN then return end
	lastDodgeTime = now()

	local char, hum = getChar()
	if not char then return end

	-- play animation instantly
	local animId = (side < 0) and DODGE_LEFT_ID or DODGE_RIGHT_ID
	local track = getCachedTrack(hum, animId)
	if track.IsPlaying then track:Stop(0) end
	track:Play(0, 1, 1)
	track:AdjustWeight(1, 0)

	-- ask server to perform the actual dodge movement + iframes
	DodgeRollRE:FireServer(side)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.A then
		if isDoubleTap(lastTapA) then
			lastTapA = -1
			tryRoll(-1)
		else
			lastTapA = now()
		end
	elseif input.KeyCode == Enum.KeyCode.D then
		if isDoubleTap(lastTapD) then
			lastTapD = -1
			tryRoll(1)
		else
			lastTapD = now()
		end
	end
end)

print("[DodgeRollDoubleTap] Loaded (server-authoritative dodge, fixed).")
