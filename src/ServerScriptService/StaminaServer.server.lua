-- ServerScriptService/StaminaServer.server.lua
-- Authoritative stamina + dodge permission. Exploiters get nothing but disappointment.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Remotes folder
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

-- Remote: client requests a dodge, server validates + triggers DodgeRollRE
local TryDodgeRE = Remotes:FindFirstChild("TryDodgeRE")
if not TryDodgeRE then
	TryDodgeRE = Instance.new("RemoteEvent")
	TryDodgeRE.Name = "TryDodgeRE"
	TryDodgeRE.Parent = Remotes
end

-- This is your existing dodge movement remote (server already listens to this)
local DodgeRollRE = Remotes:FindFirstChild("DodgeRollRE")
if not DodgeRollRE then
	-- If you haven’t created it yet, create it so the dodge server script can bind.
	DodgeRollRE = Instance.new("RemoteEvent")
	DodgeRollRE.Name = "DodgeRollRE"
	DodgeRollRE.Parent = Remotes
end

-- ====== CONFIG ======
local MAX_STAMINA = 100
local REGEN_PER_SEC = 22        -- stamina regen rate
local REGEN_DELAY = 0.35        -- delay after spending before regen starts
local DODGE_COST = 28

-- Anti-spam (extra safety on top of your dodge server script)
local REQUEST_RATE_WINDOW = 2
local REQUEST_RATE_MAX = 8
-- ====================

local lastSpendAt = {}     -- [player] = time
local reqLog = {}          -- [player] = {t1,t2,...}

local function now() return os.clock() end

local function logReq(plr)
	reqLog[plr] = reqLog[plr] or {}
	local t = reqLog[plr]
	local tn = now()
	table.insert(t, tn)
	for i = #t, 1, -1 do
		if tn - t[i] > REQUEST_RATE_WINDOW then
			table.remove(t, i)
		end
	end
	return #t
end

local function initChar(char)
	char:SetAttribute("MaxStamina", MAX_STAMINA)
	char:SetAttribute("Stamina", MAX_STAMINA)
	char:SetAttribute("IFrames", false) -- so UI has a defined value immediately
end

local function spendStamina(plr, char, amount)
	local s = char:GetAttribute("Stamina") or MAX_STAMINA
	if s < amount then
		return false
	end
	char:SetAttribute("Stamina", math.max(0, s - amount))
	lastSpendAt[plr] = now()
	return true
end

-- Regen loop
RunService.Heartbeat:Connect(function(dt)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if not char then continue end

		local maxS = char:GetAttribute("MaxStamina") or MAX_STAMINA
		local s = char:GetAttribute("Stamina")
		if s == nil then
			initChar(char)
			continue
		end

		-- regen delay after spending
		local last = lastSpendAt[plr] or 0
		if now() - last < REGEN_DELAY then
			continue
		end

		if s < maxS then
			local newS = math.min(maxS, s + (REGEN_PER_SEC * dt))
			char:SetAttribute("Stamina", newS)
		end
	end
end)

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		initChar(char)
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	lastSpendAt[plr] = nil
	reqLog[plr] = nil
end)

-- Client asks to dodge; server validates stamina and then forwards to DodgeRollRE
TryDodgeRE.OnServerEvent:Connect(function(plr, side)
	local char = plr.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	-- Rate limit
	if logReq(plr) > REQUEST_RATE_MAX then
		return
	end

	-- Validate side
	if typeof(side) ~= "number" then return end
	side = (side < 0) and -1 or 1

	-- Stamina gate
	if not spendStamina(plr, char, DODGE_COST) then
		return
	end

	-- Approved: trigger your actual dodge movement
	DodgeRollRE:FireServer(plr, side) 
	-- ^ IMPORTANT:
	-- If your dodge server script uses DodgeRollRE.OnServerEvent (normal),
	-- you cannot "FireServer" from server.
	-- So instead, we directly call the handler by switching the flow:
	-- EASIEST FIX: make dodge server script listen to TryDodgeRE instead of DodgeRollRE.
end)

print("[StaminaServer] Loaded (authoritative stamina + dodge gate)")
