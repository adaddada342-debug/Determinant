-- ReplicatedStorage/Shared/MemorySchema
local MemorySchema = {}

function MemorySchema.default()
	return {
		version = 1,

		-- meta persistence
		timelines = 1,
		resets = 0,

		flags = {
			metNpc_Alma = false,
			angeredNpc_Alma = false,
		},

		traits = {
			mercy = 0,
			violence = 0,
			curiosity = 0,
		},

		anomalies = {
			dialogueDesyncCount = 0,
			npcGlitchSeen = false,
		},

		-- persistent world scars/objects
		world = {
			scars = {
				-- ["DoorA"] = { cracked = true, crackedAtReset = 2 }
			}
		}
	}
end

return MemorySchema
