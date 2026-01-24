-- ServerScriptService/Systems/SoulService.server.lua
-- Server-authoritative current soul + mid-fight switching

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local SoulSwitchRE = Remotes:FindFirstChild("SoulSwitchRE") or Instance.new("RemoteEvent")
SoulSwitchRE.Name = "SoulSwitchRE"
SoulSwitchRE.Parent = Remotes

local VALID = {
	BRAVERY = true,
	JUSTICE = true,
	KINDNESS = true,
	PATIENCE = true,
	INTEGRITY = true,
	PERSEVERANCE = true,
}

local DEFAULT_SOUL = "PATIENCE"

local function normalize(s: any): string
	s = tostring(s or ""):upper()
	return s
end

local function canSwitch(plr: Player): boolean
	-- You can hard-gate this later (cooldowns, only during Enemy phase, etc.)
	-- For now: allow always if alive.
	local ch = plr.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

local function setSoul(plr: Player, soulKey: string)
	plr:SetAttribute("CurrentSoul", soulKey)
end

Players.PlayerAdded:Connect(function(plr)
	-- ensure it exists
	if type(plr:GetAttribute("CurrentSoul")) ~= "string" then
		setSoul(plr, DEFAULT_SOUL)
	end
end)

SoulSwitchRE.OnServerEvent:Connect(function(plr: Player, requestedSoul: any)
	if not canSwitch(plr) then return end

	local key = normalize(requestedSoul)
	if not VALID[key] then return end

	setSoul(plr, key)
end)

print("[SoulService] Loaded (CurrentSoul attribute + SoulSwitchRE).")
