-- StarterPlayerScripts/AuraDebugSpawner.client.lua
-- Press 1/2/3 to spawn aura stages, 0 to clear.
-- EXTREME DEBUG: prints exactly what's missing or misconfigured.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local TAG = "[AuraDebug]"

-- =========================
-- CONFIG (MATCH YOUR EXPLORER)
-- =========================
local AURAS_PATH = {"Assets","VFX","Auras"}

local AURA_NAME_BY_STAGE = {
	[1] = "RefusalAura_Stage1",
	[2] = "RefusalAura_Stage2",
	[3] = "DeathRefusal_Stage3",
}

local LIVE_NAME = "__AURA_DEBUG_LIVE__"
local VERBOSE_EMITTER_DUMP = true -- set false if spammy

-- =========================
-- LOG HELPERS
-- =========================
local function log(...)
	print(TAG, ...)
end

local function warnlog(...)
	warn(TAG, ...)
end

local function safeName(inst)
	if not inst then return "nil" end
	return inst.Name .. " <" .. inst.ClassName .. ">"
end

local function fullName(inst)
	if not inst then return "nil" end
	local ok, res = pcall(function() return inst:GetFullName() end)
	return ok and res or safeName(inst)
end

-- =========================
-- RESOLVE AURAS FOLDER
-- =========================
local function getAurasFolder()
	local node = ReplicatedStorage
	for _, childName in ipairs(AURAS_PATH) do
		local nextNode = node:FindFirstChild(childName)
		if not nextNode then
			return nil, ("Missing '%s' under %s"):format(childName, fullName(node))
		end
		node = nextNode
	end
	return node
end

-- =========================
-- CHARACTER HELPERS
-- =========================
local function getCharacter()
	local char = player.Character
	if not char then
		log("Waiting for CharacterAdded...")
		char = player.CharacterAdded:Wait()
	end
	return char
end

local function getHRP(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil, "HumanoidRootPart not found (character not fully loaded yet?)"
	end
	return hrp
end

-- =========================
-- CLEANUP
-- =========================
local function destroyLiveAura(char)
	local existing = char:FindFirstChild(LIVE_NAME)
	if existing then
		log("Destroying existing live aura:", fullName(existing))
		existing:Destroy()
	end
end

-- =========================
-- INSPECTION
-- =========================
local function countDesc(root)
	local parts, emitters, beams, lights, attachments = 0,0,0,0,0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then parts += 1 end
		if d:IsA("ParticleEmitter") then emitters += 1 end
		if d:IsA("Beam") then beams += 1 end
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then lights += 1 end
		if d:IsA("Attachment") then attachments += 1 end
	end
	return parts, emitters, beams, lights, attachments
end

local function dumpEmitterState(root)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			local lifeMin, lifeMax = 0, 0
			local ok = pcall(function()
				lifeMin = d.Lifetime.Min
				lifeMax = d.Lifetime.Max
			end)
			log(("Emitter: %s | Enabled=%s Rate=%.2f Lifetime=%s")
				:format(fullName(d), tostring(d.Enabled), d.Rate, ok and (("%.2f-%.2f"):format(lifeMin, lifeMax)) or "<?>"))
		end
	end
end

-- =========================
-- AURA ATTACH/WELD
-- =========================
local function sanitizeParts(root)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
	end
end

local function enableFX(root, enabled)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Beam") then
			d.Enabled = enabled
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			d.Enabled = enabled
		end
	end
end

local function pickRootPart(aura)
	local named = aura:FindFirstChild("AuraRoot", true)
	if named and named:IsA("BasePart") then
		return named, "Found AuraRoot by name"
	end
	local first = aura:FindFirstChildWhichIsA("BasePart", true)
	if first then
		return first, "No AuraRoot named part, using first BasePart"
	end
	return nil, "No BasePart found inside aura at all"
end

local function ensureWeld(p0, p1)
	local w = Instance.new("WeldConstraint")
	w.Part0 = p0
	w.Part1 = p1
	w.Parent = p0
	return w
end

local function weldAllPartsToRoot(aura, rootPart)
	local welded = 0
	for _, d in ipairs(aura:GetDescendants()) do
		if d:IsA("BasePart") and d ~= rootPart then
			ensureWeld(d, rootPart)
			welded += 1
		end
	end
	return welded
end

-- =========================
-- TEMPLATE RESOLVE
-- =========================
local function getTemplate(stage)
	local aurasFolder, err = getAurasFolder()
	if not aurasFolder then
		return nil, err
	end

	local name = AURA_NAME_BY_STAGE[stage]
	if not name then
		return nil, ("No configured name for stage %d"):format(stage)
	end

	local obj = aurasFolder:FindFirstChild(name)
	if not obj then
		-- print what's actually there
		local children = {}
		for _, c in ipairs(aurasFolder:GetChildren()) do
			table.insert(children, safeName(c))
		end
		return nil, ("Missing template '%s' in %s. Children = [%s]")
			:format(name, fullName(aurasFolder), table.concat(children, ", "))
	end

	return obj, nil
end

-- =========================
-- SPAWN
-- =========================
local function spawnAura(stage)
	log(("--- Spawn stage %d requested ---"):format(stage))

	local template, err = getTemplate(stage)
	if not template then
		warnlog("Template resolve failed:", err)
		return
	end

	log("Template found:", fullName(template))

	local char = getCharacter()
	log("Character:", fullName(char))

	local hrp, hrpErr = getHRP(char)
	if not hrp then
		warnlog("Character not ready:", hrpErr)
		return
	end
	log("HRP:", fullName(hrp), "Pos:", tostring(hrp.Position))

	destroyLiveAura(char)

	local aura = template:Clone()
	aura.Name = LIVE_NAME
	aura.Parent = char
	log("Cloned aura parented to character:", fullName(aura))

	local parts, emitters, beams, lights, attachments = countDesc(aura)
	log(("Aura contents: BaseParts=%d Attachments=%d Emitters=%d Beams=%d Lights=%d")
		:format(parts, attachments, emitters, beams, lights))

	if parts == 0 then
		warnlog("Aura has ZERO BaseParts. If Attachments/Emitters are not under BaseParts, nothing will render.")
	end
	if emitters == 0 and beams == 0 and lights == 0 then
		warnlog("Aura has no ParticleEmitters/Beams/Lights. There's nothing to see even if it attaches.")
	end

	local rootPart, rootMsg = pickRootPart(aura)
	if not rootPart then
		warnlog("RootPart selection failed:", rootMsg)
		aura:Destroy()
		return
	end
	log("RootPart:", fullName(rootPart), "|", rootMsg)

	-- move aura to player
	if aura:IsA("Model") then
		local ok, pivotErr = pcall(function()
			aura:PivotTo(hrp.CFrame)
		end)
		if not ok then
			warnlog("PivotTo failed:", pivotErr)
		else
			log("PivotTo succeeded.")
		end
	else
		rootPart.CFrame = hrp.CFrame
		log("Aura isn't a Model; positioned rootPart to HRP.")
	end

	sanitizeParts(aura)
	log("Sanitized parts (Anchored=false, collisions off, massless).")

	-- weld root to HRP
	ensureWeld(rootPart, hrp)
	log("Welded rootPart -> HRP")

	-- weld all other parts to root
	local weldedCount = weldAllPartsToRoot(aura, rootPart)
	log(("Welded %d additional BaseParts to rootPart"):format(weldedCount))

	enableFX(aura, true)
	log("Enabled all FX components (Emitters/Beams/Lights).")

	if VERBOSE_EMITTER_DUMP and emitters > 0 then
		log("Dumping ParticleEmitter states (Enabled/Rate/Lifetime):")
		dumpEmitterState(aura)
	end

	log(("✅ Spawn stage %d complete. If you still see nothing, it’s emitter settings (Rate=0, Lifetime=0, Transparency) or your aura is invisible by design.")
		:format(stage))
end

local function clearAura()
	local char = getCharacter()
	destroyLiveAura(char)
	log("Cleared live aura.")
end

-- =========================
-- BOOT
-- =========================
log("BOOTED. This must appear in Output or the script is not running.")
do
	local aurasFolder, err = getAurasFolder()
	if not aurasFolder then
		warnlog("Auras folder resolution failed on boot:", err)
	else
		log("Auras folder:", fullName(aurasFolder))
		local children = {}
		for _, c in ipairs(aurasFolder:GetChildren()) do
			table.insert(children, safeName(c))
		end
		log("Auras children:", table.concat(children, ", "))
	end
end

-- =========================
-- INPUT (T / Y / U DEBUG BINDS)
-- =========================
local ContextActionService = game:GetService("ContextActionService")

local function bind(name, stage)
	return function(_, state)
		if state == Enum.UserInputState.Begin then
			print("[AuraDebug] KEY FIRED:", name)
			if stage then
				spawnAura(stage)
			else
				clearAura()
			end
		end
	end
end

ContextActionService:BindAction(
	"AuraStage1_T",
	bind("STAGE 1 (T)", 1),
	false,
	Enum.KeyCode.T
)

ContextActionService:BindAction(
	"AuraStage2_Y",
	bind("STAGE 2 (Y)", 2),
	false,
	Enum.KeyCode.Y
)

ContextActionService:BindAction(
	"AuraStage3_U",
	bind("STAGE 3 (U)", 3),
	false,
	Enum.KeyCode.U
)

ContextActionService:BindAction(
	"AuraClear_G",
	bind("CLEAR (G)", nil),
	false,
	Enum.KeyCode.G
)

print("[AuraDebug] ContextActionService active: T=1, Y=2, U=3, G=clear")



player.CharacterAdded:Connect(function()
	task.wait(0.25)
	clearAura()
end)
