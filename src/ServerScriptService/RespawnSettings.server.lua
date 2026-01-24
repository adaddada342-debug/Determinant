-- ServerScriptService/RespawnSettings.server.lua
local Players = game:GetService("Players")

-- Full control: Roblox will NOT auto spawn/respawn characters.
Players.CharacterAutoLoads = false

-- RespawnTime irrelevant when CharacterAutoLoads = false, keep sane anyway
Players.RespawnTime = 5

print("[RespawnSettings] CharacterAutoLoads =", Players.CharacterAutoLoads, "RespawnTime =", Players.RespawnTime)
