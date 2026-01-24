-- ServerScriptService/ArenaTeleport.server.lua
-- Server-authoritative arena teleporter with stable return storage.

local Players = game:GetService("Players")

local ARENA_Y = 9000
local ARENA_SPACING = 300

local function computeArenaCenter(plr: Player)
	return Vector3.new((plr.UserId % 50) * ARENA_SPACING, ARENA_Y, 0)
end

local function getHRP(plr: Player)
	local ch = plr.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function getReturnValue(plr: Player)
	local v = plr:FindFirstChild("__BattleReturnCFrame")
	if not v then
		v = Instance.new("CFrameValue")
		v.Name = "__BattleReturnCFrame"
		v.Parent = plr
	end
	return v
end

local function enter(plr: Player)
	local hrp = getHRP(plr)
	if not hrp then return false end

	local ret = getReturnValue(plr)
	if ret.Value == CFrame.new() then
		ret.Value = hrp.CFrame
	end

	local center = computeArenaCenter(plr)
	local spawnCF = CFrame.new(center + Vector3.new(0, 3, 16), center + Vector3.new(0, 3, -18))

	hrp.CFrame = spawnCF
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	return true
end

local function exit(plr: Player)
	local hrp = getHRP(plr)
	if not hrp then return false end

	local ret = getReturnValue(plr)
	if ret.Value ~= CFrame.new() then
		hrp.CFrame = ret.Value
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end

	ret.Value = CFrame.new()
	return true
end

_G.ArenaTeleport = _G.ArenaTeleport or {}
_G.ArenaTeleport.Enter = enter
_G.ArenaTeleport.Exit = exit

Players.PlayerRemoving:Connect(function(plr)
	pcall(function() exit(plr) end)
end)

print("[ArenaTeleport] Loaded.")
