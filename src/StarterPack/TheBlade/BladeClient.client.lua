-- StarterPack/TheBlade/BladeClient.client.lua
local Tool = script.Parent
local Players = game:GetService("Players")

local IDLE_ANIM_NAME = "BladeIdle"
local idleTrack: AnimationTrack? = nil
local runningConn: RBXScriptConnection? = nil

local function getHumanoid()
	local player = Players.LocalPlayer
	local char = player.Character or player.CharacterAdded:Wait()
	return char:WaitForChild("Humanoid") :: Humanoid
end

local function getAnimator(h: Humanoid): Animator
	local a = h:FindFirstChildOfClass("Animator")
	if not a then
		a = Instance.new("Animator")
		a.Parent = h
	end
	return a
end

local function playIdle()
	local hum = getHumanoid()
	local animator = getAnimator(hum)

	local anim = Tool:FindFirstChild(IDLE_ANIM_NAME)
	if not anim or not anim:IsA("Animation") then
		warn("Missing Animation named", IDLE_ANIM_NAME, "inside tool")
		return
	end

	-- stop old
	if idleTrack then
		idleTrack:Stop(0.1)
		idleTrack:Destroy()
		idleTrack = nil
	end

	idleTrack = animator:LoadAnimation(anim)
	idleTrack.Priority = Enum.AnimationPriority.Idle
	idleTrack.Looped = true
	idleTrack:Play(0.15)

	-- Optional: pause idle while moving (comment out if you want it always)
	if runningConn then runningConn:Disconnect() end
	runningConn = hum.Running:Connect(function(speed)
		if not idleTrack then return end
		if speed > 0.5 then
			if idleTrack.IsPlaying then idleTrack:Stop(0.1) end
		else
			if not idleTrack.IsPlaying then idleTrack:Play(0.15) end
		end
	end)
end

local function stopIdle()
	if runningConn then runningConn:Disconnect(); runningConn = nil end
	if idleTrack then
		idleTrack:Stop(0.15)
		idleTrack:Destroy()
		idleTrack = nil
	end
end

Tool.Equipped:Connect(playIdle)
Tool.Unequipped:Connect(stopIdle)
