-- ServerScriptService/Systems/MemoryService
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local MemorySchema = require(game.ReplicatedStorage.Shared.MemorySchema)

local STORE_NAME = "PlayerMemoryV1"
local store = DataStoreService:GetDataStore(STORE_NAME)

local MemoryService = {}
MemoryService._cache = {} -- [userId] = data
MemoryService._dirty = {} -- [userId] = true/false
MemoryService._locks = {} -- [userId] = true while saving/loading

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k,v in pairs(t) do
		out[k] = deepCopy(v)
	end
	return out
end

local function mergeDefaults(defaults, loaded)
	-- keep loaded values, fill missing with defaults
	if type(defaults) ~= "table" then return loaded end
	loaded = (type(loaded) == "table") and loaded or {}
	for k, dv in pairs(defaults) do
		if loaded[k] == nil then
			loaded[k] = deepCopy(dv)
		elseif type(dv) == "table" then
			loaded[k] = mergeDefaults(dv, loaded[k])
		end
	end
	return loaded
end

local function try(times, fn)
	local lastErr
	for i = 1, times do
		local ok, result = pcall(fn)
		if ok then return true, result end
		lastErr = result
		task.wait(0.6 * i)
	end
	return false, lastErr
end

function MemoryService:Get(player)
	local userId = player.UserId
	return self._cache[userId]
end

function MemoryService:MarkDirty(player)
	self._dirty[player.UserId] = true
end

function MemoryService:Update(player, mutatorFn)
	local data = self:Get(player)
	if not data then return end
	mutatorFn(data)
	self:MarkDirty(player)
end

function MemoryService:Load(player)
	local userId = player.UserId
	if self._locks[userId] then return end
	self._locks[userId] = true

	local ok, loaded = try(5, function()
		return store:GetAsync(tostring(userId))
	end)

	local data = mergeDefaults(MemorySchema.default(), ok and loaded or nil)
	self._cache[userId] = data
	self._dirty[userId] = false
	self._locks[userId] = nil

	return data
end

function MemoryService:Save(player)
	local userId = player.UserId
	if self._locks[userId] then return end
	if not self._dirty[userId] then return end
	local data = self._cache[userId]
	if not data then return end

	self._locks[userId] = true

	local ok, err = try(5, function()
		return store:UpdateAsync(tostring(userId), function(old)
			-- last-write wins with defaults merged, but keep existing if server missed something
			local merged = mergeDefaults(MemorySchema.default(), old)
			-- overwrite with our cache
			return data
		end)
	end)

	if ok then
		self._dirty[userId] = false
	else
		warn("[MemoryService] Save failed:", err)
	end

	self._locks[userId] = nil
end

function MemoryService:Init()
	Players.PlayerAdded:Connect(function(player)
		self:Load(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:Save(player)
		self._cache[player.UserId] = nil
		self._dirty[player.UserId] = nil
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			self:Save(player)
		end
	end)
end

return MemoryService
