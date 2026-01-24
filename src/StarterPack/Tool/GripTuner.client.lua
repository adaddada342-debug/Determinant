-- Tool/GripTuner.client.lua
-- Equip tool, move/rotate Handle in Studio, press G to bake Grip.
-- Works best in Studio Play Solo.

local tool = script.Parent
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local handle = tool:WaitForChild("Handle")

local function getRightArm(char)
	-- R6: "Right Arm", R15: "RightHand"
	return char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
end

local function bakeGrip()
	local char = player.Character
	if not char then return end

	local rightArm = getRightArm(char)
	if not rightArm then
		warn("No Right Arm/RightHand found.")
		return
	end

	-- Desired Grip is the offset from RightArm to Handle
	local gripCF = rightArm.CFrame:ToObjectSpace(handle.CFrame)

	tool.Grip = gripCF

	print("✅ Baked Tool.Grip = ", tool.Grip)
	print("   Position:", tool.Grip.Position)
	local rx, ry, rz = tool.Grip:ToOrientation()
	print(("   Orientation (rad): %.4f, %.4f, %.4f"):format(rx, ry, rz))
end

tool.Equipped:Connect(function()
	print("GripTuner active. Move/rotate the Handle, then press G to bake Grip.")
end)

UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.G then
		bakeGrip()
	end
end)
