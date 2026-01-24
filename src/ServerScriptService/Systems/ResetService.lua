-- ServerScriptService/Systems/ResetService
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResetService = {}
ResetService.MemoryService = nil
ResetService.WorldPersistenceService = nil

function ResetService:BindRemotes()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ResetRequest = remotes:WaitForChild("ResetRequest")

	ResetRequest.OnServerEvent:Connect(function(player)
		self:DoReset(player)
	end)
end

function ResetService:DoReset(player)
	-- HARD GUARDS so this can't nuke your server
	if not self.MemoryService then
		warn("[ResetService] MemoryService is nil. Reset aborted for", player.Name)
		return
	end
	if not self.WorldPersistenceService then
		warn("[ResetService] WorldPersistenceService is nil. Reset aborted for", player.Name)
		return
	end

	-- Safe update (create missing fields)
	local okUpdate, errUpdate = pcall(function()
		self.MemoryService:Update(player, function(m)
			m = m or {}

			m.resets = (m.resets or 0) + 1

			m.anomalies = m.anomalies or {}
			m.anomalies.dialogueDesyncCount = m.anomalies.dialogueDesyncCount or 0

			if (m.resets % 2) == 0 then
				m.anomalies.dialogueDesyncCount += 1
			end

			return m
		end)
	end)
	if not okUpdate then
		warn("[ResetService] Memory update failed:", errUpdate)
	end

	-- Respawn-ish: move to spawn
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local spawn = workspace:FindFirstChild("SpawnLocation")
	if hrp and spawn then
		hrp.CFrame = spawn.CFrame + Vector3.new(0, 3, 0)
	end

	-- Re-apply world scars (safe)
	local okApply, errApply = pcall(function()
		self.WorldPersistenceService:ApplyPlayerWorld(player)
	end)
	if not okApply then
		warn("[ResetService] ApplyPlayerWorld failed:", errApply)
	end

	-- Save immediately after reset (safe)
	local okSave, errSave = pcall(function()
		self.MemoryService:Save(player)
	end)
	if not okSave then
		warn("[ResetService] Save failed:", errSave)
	end
end

return ResetService
