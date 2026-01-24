-- ServerScriptService/Systems/StatusService
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StatusService = {}

-- [humanoid] = { [statusName] = { expiresAt = number, data = table? }, base = {WalkSpeed, JumpPower} }
local state = {}

local function now()
	return os.clock()
end

local function ensureBase(hum: Humanoid)
	local s = state[hum]
	if not s then
		s = { statuses = {}, base = nil }
		state[hum] = s
	end
	if not s.base then
		s.base = {
			WalkSpeed = hum.WalkSpeed,
			JumpPower = hum.JumpPower,
		}
	end
	return s
end

local function compute(hum: Humanoid)
	local s = state[hum]
	if not s or not s.base then return end

	local t = now()

	-- purge expired
	for name, info in pairs(s.statuses) do
		if info.expiresAt <= t then
			s.statuses[name] = nil
		end
	end

	-- default to base
	local ws = s.base.WalkSpeed
	local jp = s.base.JumpPower

	-- apply modifiers
	local stunned = s.statuses.Stun ~= nil
	if stunned then
		ws = 0
		jp = 0
	end

	local slow = s.statuses.Slow
	if slow and not stunned then
		local mult = tonumber(slow.data and slow.data.mult) or 0.5
		ws = math.max(0, ws * mult)
	end

	-- write back
	hum.WalkSpeed = ws
	hum.JumpPower = jp
end

function StatusService:Apply(hum: Humanoid, statusName: string, duration: number, data: table?)
	if not hum or hum.Health <= 0 then return end
	if typeof(statusName) ~= "string" then return end
	duration = tonumber(duration) or 0
	if duration <= 0 then return end

	local s = ensureBase(hum)
	s.statuses[statusName] = {
		expiresAt = now() + duration,
		data = data,
	}

	compute(hum)

	-- replicate minimal info (optional UI hooks)
	if self.StatusEvent then
		local packet = {}
		for name, info in pairs(s.statuses) do
			packet[name] = math.max(0, info.expiresAt - now())
		end
		self.StatusEvent:FireAllClients(hum, packet)
	end
end

function StatusService:Clear(hum: Humanoid, statusName: string)
	local s = state[hum]
	if not s then return end
	s.statuses[statusName] = nil
	compute(hum)
end

function StatusService:Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	self.StatusEvent = remotes:WaitForChild("StatusEvent")

	-- keep statuses updated even if nobody reapplies them
	RunService.Heartbeat:Connect(function()
		for hum, _ in pairs(state) do
			if hum.Parent == nil then
				state[hum] = nil
			else
				compute(hum)
			end
		end
	end)
end

return StatusService
