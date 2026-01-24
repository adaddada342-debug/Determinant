-- ServerScriptService/Boot/ResetBoot.server.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Ensure Remotes + ResetRequest exist (early fail = obvious)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ResetRequest = Remotes:WaitForChild("ResetRequest")
assert(ResetRequest:IsA("RemoteEvent"), "[ResetBoot] Remotes.ResetRequest must be a RemoteEvent")

-- Your module
local ResetService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("ResetService"))

-- REQUIRE THESE FROM WHEREVER THEY ACTUALLY LIVE IN YOUR PROJECT:
-- (Change the paths below to match your hierarchy)
local MemoryService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("MemoryService"))
local WorldPersistenceService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("WorldPersistenceService"))

-- Inject dependencies
ResetService.MemoryService = MemoryService
ResetService.WorldPersistenceService = WorldPersistenceService

-- Bind remotes
ResetService:BindRemotes()

print("[ResetBoot] ResetService wired and ResetRequest bound.")
