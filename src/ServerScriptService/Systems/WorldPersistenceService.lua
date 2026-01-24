-- ServerScriptService/Systems/WorldPersistenceService
local CollectionService = game:GetService("CollectionService")

local WorldPersistenceService = {}
WorldPersistenceService.MemoryService = nil

local TAG = "PersistentObject"

function WorldPersistenceService:ApplyPlayerWorld(player)
	local mem = self.MemoryService:Get(player)
	if not mem then return end

	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		local pid = inst:GetAttribute("PersistentId")
		if typeof(pid) ~= "string" or pid == "" then
			continue
		end

		local scar = mem.world.scars[pid]
		if scar then
			-- Apply known fields safely
			if scar.cracked ~= nil then
				inst:SetAttribute("Cracked", scar.cracked)
			end
		end
	end
end

function WorldPersistenceService:RecordScar(player, persistentId, scarTable)
	self.MemoryService:Update(player, function(m)
		m.world.scars[persistentId] = m.world.scars[persistentId] or {}
		for k,v in pairs(scarTable) do
			m.world.scars[persistentId][k] = v
		end
	end)
end

return WorldPersistenceService
