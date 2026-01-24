--!strict
-- ScytheWalk.client.lua
-- Plays custom scythe walk animation when player is moving

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid: Humanoid = character:WaitForChild("Humanoid")

-- === CONFIG ===
local SCYTHE_WALK_ANIMATION_ID = "rbxassetid://92962656771936"
local WALK_SPEED_THRESHOLD = 0.5 -- how much movement counts as "walking"
local WALK_PRIORITY = Enum.AnimationPriority.Movement

-- === LOAD ANIMATION ===
local animator: Animator = humanoid:WaitForChild("Animator")

local walkAnim = Instance.new("Animation")
walkAnim.AnimationId = SCYTHE_WALK_ANIMATION_ID

local walkTrack = animator:LoadAnimation(walkAnim)
walkTrack.Priority = WALK_PRIORITY
walkTrack.Looped = true

-- Optional: slightly slower playback for HEAVY weapon feel
walkTrack:AdjustSpeed(0.9)

-- === STATE ===
local isWalking = false

-- === UPDATE LOOP ===
RunService.RenderStepped:Connect(function()
	if humanoid.MoveDirection.Magnitude > WALK_SPEED_THRESHOLD then
		if not isWalking then
			isWalking = true
			walkTrack:Play(0.15) -- smooth fade in
		end
	else
		if isWalking then
			isWalking = false
			walkTrack:Stop(0.15) -- smooth fade out
		end
	end
end)

-- === CLEANUP ===
humanoid.Died:Connect(function()
	if walkTrack.IsPlaying then
		walkTrack:Stop()
	end
end)
