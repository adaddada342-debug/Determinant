-- StarterPlayerScripts/BattleArenaVFX.client.lua
-- Cosmetic-only animation for the battle arena VFX shell.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE = Remotes:WaitForChild("BattleArenaVFXRE")

local ArenaRoot = workspace:WaitForChild("__BattleArenas")

local heartbeatConn: RBXScriptConnection? = nil
local activeFolder: Folder? = nil

-- Optional local-only post FX (subtle, safe)
local cc: ColorCorrectionEffect? = nil
local bloom: BloomEffect? = nil

local function ensurePostFX()
	if cc and cc.Parent then return end

	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "__BattleArenaCC"
	cc.Contrast = 0.05
	cc.Saturation = 0.05
	cc.Brightness = -0.02
	cc.Parent = Lighting

	bloom = Instance.new("BloomEffect")
	bloom.Name = "__BattleArenaBloom"
	bloom.Intensity = 0.25
	bloom.Size = 24
	bloom.Threshold = 1.0
	bloom.Parent = Lighting
end

local function cleanupPostFX()
	if cc then cc:Destroy() cc = nil end
	if bloom then bloom:Destroy() bloom = nil end
end

local function stopAnim()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	activeFolder = nil
	cleanupPostFX()
end

local function startAnim(folder: Folder)
	stopAnim()
	activeFolder = folder

	local vfx = folder:FindFirstChild("VFX")
	if not vfx then return end

	ensurePostFX()

	local t0 = os.clock()

	heartbeatConn = RunService.Heartbeat:Connect(function()
		if not activeFolder or not activeFolder.Parent then
			stopAnim()
			return
		end

		local tt = os.clock() - t0

		-- Smooth pulse 0..1
		local pulse = (math.sin(tt * 2.2) + 1) * 0.5
		local pulse2 = (math.sin(tt * 3.7 + 1.2) + 1) * 0.5

		-- Animate neon parts
		for _, inst in ipairs(vfx:GetChildren()) do
			if inst:IsA("BasePart") then
				if inst.Name:find("Rail") then
					inst.Transparency = 0.10 + 0.12 * pulse
				elseif inst.Name:find("Pillar") then
					inst.Transparency = 0.18 + 0.20 * pulse2
				elseif inst.Name == "RoofGlow" then
					inst.Transparency = 0.68 + 0.18 * pulse
				elseif inst.Name == "FloorGlow" then
					inst.Transparency = 0.78 + 0.14 * pulse2
				elseif inst.Name:find("MidRing") then
					inst.Transparency = 0.55 + 0.20 * pulse
				end
			end
		end

		-- Subtle post FX breathing
		if cc then
			cc.Contrast = 0.04 + 0.03 * pulse
			cc.Saturation = 0.05 + 0.04 * pulse2
		end
		if bloom then
			bloom.Intensity = 0.18 + 0.18 * pulse
		end
	end)
end

RE.OnClientEvent:Connect(function(kind, payload)
	if kind == "ArenaSpawned" then
		local name = payload and payload.arenaFolderName
		if typeof(name) ~= "string" then return end

		local folder = ArenaRoot:FindFirstChild(name)
		if folder and folder:IsA("Folder") then
			startAnim(folder)
		end
		return
	end

	if kind == "ArenaDestroyed" then
		stopAnim()
		return
	end
end)
