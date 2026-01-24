-- StarterPlayerScripts/SpawnExplosionPillar_GroundSnap_WithManualOffset.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PLAYER = Players.LocalPlayer
local KEY = Enum.KeyCode.L

-- ========= CONFIG =========
local TEMPLATE_NAME = "Explosion_Pillar"

local REPLACE_PREVIOUS = true

-- If your model is rotated wrong around Y, fix it here:
local YAW_OFFSET_DEG = 0

-- Spawn in front of player a bit (optional)
local FORWARD_OFFSET = 0

-- This is the manual nudge you want:
-- Positive = higher, Negative = lower
local MANUAL_Y_OFFSET = -100

-- Raycast settings
local RAY_UP = 10
local RAY_DOWN = 500
-- ==========================

local activeModel: Model? = nil

local function findTemplate(): Model?
	local m = ReplicatedStorage:FindFirstChild(TEMPLATE_NAME)
	if m and m:IsA("Model") then return m end
	m = Workspace:FindFirstChild(TEMPLATE_NAME)
	if m and m:IsA("Model") then return m end
	return nil
end

local function ensurePrimaryPart(model: Model)
	local pivot = model:FindFirstChild("Pivot")
	if pivot and pivot:IsA("BasePart") then
		model.PrimaryPart = pivot
		return
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return
	end
	local any = model:FindFirstChildWhichIsA("BasePart", true)
	if any then model.PrimaryPart = any end
end

local function getGroundYUnder(character: Model, origin: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local rayOrigin = origin + Vector3.new(0, RAY_UP, 0)
	local rayDir = Vector3.new(0, -(RAY_UP + RAY_DOWN), 0)

	local hit = Workspace:Raycast(rayOrigin, rayDir, params)
	if hit then
		return hit.Position.Y
	end
	return origin.Y
end

local function bottomOffsetY(model: Model): number
	local pivotCF = model:GetPivot()
	local bbCF, bbSize = model:GetBoundingBox()
	local centerInPivot = pivotCF:PointToObjectSpace(bbCF.Position)
	return centerInPivot.Y - (bbSize.Y * 0.5)
end

local function spawn()
	local character = PLAYER.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return end

	local template = findTemplate()
	if not template then
		warn(("[Spawn] Missing '%s' in ReplicatedStorage/workspace."):format(TEMPLATE_NAME))
		return
	end

	if REPLACE_PREVIOUS and activeModel and activeModel.Parent then
		activeModel:Destroy()
		activeModel = nil
	end

	local clone = template:Clone()
	clone.Name = "ExplosionPillar_Runtime"
	clone.Parent = Workspace
	activeModel = clone

	ensurePrimaryPart(clone)

	-- Compute bottom from bounding box (automatic)
	local bottomY = bottomOffsetY(clone)

	-- Facing
	local _, yaw, _ = hrp.CFrame:ToOrientation()
	yaw += math.rad(YAW_OFFSET_DEG)

	-- Position (XZ) + forward offset
	local forward = hrp.CFrame.LookVector * FORWARD_OFFSET
	local baseXZ = Vector3.new(hrp.Position.X + forward.X, hrp.Position.Y, hrp.Position.Z + forward.Z)

	-- Ground snap
	local groundY = getGroundYUnder(character, baseXZ)

	-- Pivot Y so the model bottom sits on the ground, plus your manual nudge
	local pivotY = (groundY - bottomY) + MANUAL_Y_OFFSET
	local pivotPos = Vector3.new(baseXZ.X, pivotY, baseXZ.Z)

	clone:PivotTo(CFrame.new(pivotPos) * CFrame.Angles(0, yaw, 0))

	-- Anchor everything
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == KEY then
		spawn()
	end
end)
