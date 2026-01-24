-- ServerScriptService/Systems/DialogueService (ModuleScript)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogueDB = require(ReplicatedStorage.Shared.DialogueDB)

local DialogueService = {}
DialogueService.MemoryService = nil

-- Studio/dev fallback memory (per-player, non-persistent)
local _devMemByUserId: {[number]: any} = {}

local function getDevMem(player)
	local uid = player.UserId
	local mem = _devMemByUserId[uid]
	if not mem then
		mem = {
			resets = 0,
			flags = {},
			traits = { mercy = 0, violence = 0, curiosity = 0 },
			anomalies = { dialogueDesyncCount = 0 },
		}
		_devMemByUserId[uid] = mem
	end
	return mem
end

function DialogueService:_getMem(player)
	-- If MemoryService is wired, use it
	if self.MemoryService and type(self.MemoryService.Get) == "function" then
		local mem = self.MemoryService:Get(player)
		if mem then
			return mem, true -- true = persistent
		end
		warn("[DialogueService] Memory missing for", player.Name, "falling back to dev memory (non-persistent).")
		return getDevMem(player), false
	end

	warn("[DialogueService] MemoryService not set; using dev memory (non-persistent) for", player.Name)
	return getDevMem(player), false
end

function DialogueService:_applyEffects(player, effectsFn, persistent)
	if type(effectsFn) ~= "function" then return end

	if persistent and self.MemoryService and type(self.MemoryService.Update) == "function" then
		self.MemoryService:Update(player, function(m)
			effectsFn(m)
		end)
	else
		effectsFn(getDevMem(player))
	end
end

function DialogueService:BindRemotes()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local DialogueRequest = remotes:WaitForChild("DialogueRequest")

	-- MUST be RemoteFunction
	if not DialogueRequest:IsA("RemoteFunction") then
		warn("[DialogueService] Remotes/DialogueRequest must be a RemoteFunction, not:", DialogueRequest.ClassName)
		return
	end

	-- Bind exactly once
	if DialogueRequest.OnServerInvoke ~= nil then
		warn("[DialogueService] DialogueRequest.OnServerInvoke already bound; skipping rebind.")
		return
	end

	print("[DialogueService] Binding DialogueRequest.OnServerInvoke")

	DialogueRequest.OnServerInvoke = function(player, npcId, nodeId)
		print("[DialogueService] Invoke from:", player.Name, "npcId:", npcId, "nodeId:", nodeId)

		if typeof(npcId) ~= "string" or npcId == "" then
			warn("[DialogueService] Invalid npcId from", player.Name, npcId)
			return nil
		end

		local mem, persistent = self:_getMem(player)

		local npc = DialogueDB.NPCS[npcId]
		if not npc then
			local keys = {}
			for k in pairs(DialogueDB.NPCS) do table.insert(keys, k) end
			table.sort(keys)
			warn("[DialogueService] Unknown npcId:", npcId, "Available NPCs:", table.concat(keys, ", "))
			return nil
		end

		local nodeKey = (typeof(nodeId) == "string" and nodeId ~= "") and nodeId or "start"
		local nodeFn = npc[nodeKey]
		if type(nodeFn) ~= "function" then
			nodeFn = npc.start
		end

		local packet = nodeFn(mem)
		if packet and packet.effects then
			self:_applyEffects(player, packet.effects, persistent)
		end

		if packet then packet.effects = nil end
		return packet
	end
end

return DialogueService
