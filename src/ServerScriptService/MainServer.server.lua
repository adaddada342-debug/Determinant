-- ServerScriptService/MainServer

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MemoryService = require(script.Parent.Systems.MemoryService)
local DialogueService = require(script.Parent.Systems.DialogueService)
local ResetService = require(script.Parent.Systems.ResetService)
local WorldPersistenceService = require(script.Parent.Systems.WorldPersistenceService)
local AwakeningService = require(script.Parent.Systems.AwakeningService)


-- ensure remotes exist
local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function ensure(name, className)
	local obj = remotes:FindFirstChild(name)
	if not obj then
		obj = Instance.new(className)
		obj.Name = name
		obj.Parent = remotes
	end
	return obj
end

-- existing
ensure("DialogueRequest", "RemoteFunction")
ensure("DialogueEvent", "RemoteEvent")
ensure("ResetRequest", "RemoteEvent")
ensure("AwakeningEvent", "RemoteEvent")


-- ✅ ability remotes (add these)
ensure("AbilityRequest", "RemoteEvent")
ensure("AbilityImpact", "RemoteEvent")
ensure("AbilityFX", "RemoteEvent")

ensure("AbilityRequest", "RemoteEvent")
ensure("AbilityImpact", "RemoteEvent")
ensure("AbilityFX", "RemoteEvent")

-- NEW
ensure("AbilityCooldown", "RemoteEvent")
ensure("StatusEvent", "RemoteEvent")



-- init services
MemoryService:Init()

DialogueService.MemoryService = MemoryService
DialogueService:BindRemotes()

WorldPersistenceService.MemoryService = MemoryService

ResetService.MemoryService = MemoryService
ResetService.WorldPersistenceService = WorldPersistenceService
ResetService:BindRemotes()

local StatusService = require(script.Parent.Systems.StatusService)
StatusService:Init()
AwakeningService:Init()






game.Players.PlayerAdded:Connect(function(player)
	task.wait(1)
	WorldPersistenceService:ApplyPlayerWorld(player)
end)
