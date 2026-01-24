local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- tuning
local MAX_ROLL = math.rad(6)      -- degrees of roll sway
local MAX_YAW  = math.rad(2)      -- subtle left/right yaw
local SMOOTHNESS = 14             -- higher = snappier
local RETURN_SPEED = 18

local roll = 0
local yaw = 0

local function expLerp(current: number, target: number, speed: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-speed * dt))
end

RunService:BindToRenderStep("CameraSway", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local mouseDelta = UserInputService:GetMouseDelta()

	-- target sway from input
	local targetRoll = math.clamp(-mouseDelta.X * 0.0025, -MAX_ROLL, MAX_ROLL)
	local targetYaw  = math.clamp(-mouseDelta.X * 0.0015, -MAX_YAW,  MAX_YAW)

	-- smooth toward targets
	roll = expLerp(roll, targetRoll, SMOOTHNESS, dt)
	yaw  = expLerp(yaw,  targetYaw,  SMOOTHNESS, dt)

	-- softly return to neutral when mouse stops
	if mouseDelta.Magnitude < 0.01 then
		roll = expLerp(roll, 0, RETURN_SPEED, dt)
		yaw  = expLerp(yaw,  0, RETURN_SPEED, dt)
	end

	-- apply sway WITHOUT accumulating error
	local baseCFrame = camera.CFrame
	camera.CFrame =
		baseCFrame
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(0, 0, roll)
end)
