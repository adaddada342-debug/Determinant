-- ServerScriptService/00_RemotesBootstrap.server.lua
-- Ensures Remotes + required RemoteEvents exist before anything waits on them.

-- ROJO TEST

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function ensureFolder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function ensureRE(parent, name)
	local re = parent:FindFirstChild(name)
	if not re then
		re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = parent
	end
	return re
end

local Remotes = ensureFolder(ReplicatedStorage, "Remotes")

-- Battle core
ensureRE(Remotes, "BattleRE")
ensureRE(Remotes, "BulletHellRE")
ensureRE(Remotes, "Phase2Enter")
ensureRE(Remotes, "Phase2Exit")

-- Weapon damage (GLOBAL, for all tools)
ensureRE(Remotes, "WeaponDamageRE")

print("[RemotesBootstrap] Ready:", Remotes:GetFullName())
