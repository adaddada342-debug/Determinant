--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ===== TUNING =====
local WALK_SPEED = 16
local SPRINT_SPEED = 22

local ACCEL_RATE = 12
local DECEL_RATE = 16

local MOVE_DEADZONE = 0.05
local ENABLE_SPRINT = true

-- ===== STATE =====
local humanoid: Humanoid? = nil
local sprinting = false
local currentSpeed = WALK_SPEED

local function expApproach(current: number, target: number, rate: number, dt: number): number
	local a = 1 - math.exp(-rate * dt)
	return current + (target - current) * a
end

local function bindCharacter(char: Instance?)
	if not char or not char:IsA("Model") then
		humanoid = nil
		return
	end

	local h = char:FindFirstChildOfClass("Humanoid")
	if not h then
		humanoid = nil
		return
	end

	humanoid = h
	currentSpeed = h.WalkSpeed
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if not ENABLE_SPRINT then return end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = true
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if not ENABLE_SPRINT then return end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = false
	end
end)

-- Initial character (if already spawned)
bindCharacter(player.Character)

-- Respawns
player.CharacterAdded:Connect(function(char: Model)
	bindCharacter(char)
end)

RunService.RenderStepped:Connect(function(dt: number)
	local h = humanoid
	if not h then return end

	local moving = h.MoveDirection.Magnitude > MOVE_DEADZONE

	local target = WALK_SPEED
	if ENABLE_SPRINT and sprinting and moving then
		target = SPRINT_SPEED
	end

	local rate = (target > currentSpeed) and ACCEL_RATE or DECEL_RATE
	currentSpeed = expApproach(currentSpeed, target, rate, dt)

	h.WalkSpeed = currentSpeed
end)
