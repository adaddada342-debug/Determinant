-- StarterPlayerScripts/DeterminantCombat/PlayerDodgeController.client.lua
-- Client handles dodge feel (impulse), server decides if it’s allowed + sets i-frames.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local plr = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("DeterminantCombat"):WaitForChild("Remotes")
local CombatRE = remotes:WaitForChild("CombatRE")
local DodgeRE = remotes:WaitForChild("DodgeRE")

local pending = false
local lastDir = Vector3.new(0, 0, -1)

local function getChar()
	return plr.Character
end

local function getHRP()
	local ch = getChar()
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function getHum()
	local ch = getChar()
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function getMoveDir()
	-- Uses Humanoid.MoveDirection (works with default Roblox controls)
	local hum = getHum()
	if hum and hum.MoveDirection.Magnitude > 0.05 then
		local v = hum.MoveDirection
		return Vector3.new(v.X, 0, v.Z).Unit
	end
	-- If not moving, roll forward relative to camera
	local cam = workspace.CurrentCamera
	if cam then
		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.05 then
			return flat.Unit
		end
	end
	return lastDir
end

local function applyImpulse(duration, impulse, dir)
	local hrp = getHRP()
	local hum = getHum()
	if not (hrp and hum) then return end

	-- Temporary LinearVelocity for a smooth burst
	local att = hrp:FindFirstChild("DodgeAttachment") or Instance.new("Attachment")
	att.Name = "DodgeAttachment"
	att.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DodgeLV"
	lv.Attachment0 = att
	lv.MaxForce = math.huge
	lv.VectorVelocity = dir * impulse
	lv.Parent = hrp

	-- Briefly reduce control conflicts
	local oldAutoRotate = hum.AutoRotate
	hum.AutoRotate = false

	task.delay(duration, function()
		if lv.Parent then lv:Destroy() end
		if hum.Parent then hum.AutoRotate = oldAutoRotate end
	end)
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode ~= Enum.KeyCode.Q then return end
	if pending then return end

	local dir = getMoveDir()
	lastDir = dir
	pending = true

	-- Ask server for permission (stamina + cooldown). Server acks.
	DodgeRE:FireServer({ dir = dir })
end)

CombatRE.OnClientEvent:Connect(function(msg, data)
	if msg ~= "DodgeAck" then return end
	pending = false
	data = data or {}

	if not data.ok then
		-- Denied: do nothing (you can add a small sound later)
		return
	end

	applyImpulse(data.duration or 0.25, data.impulse or 80, lastDir)
end)
