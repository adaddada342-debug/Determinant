-- StarterPlayerScripts/ImpactFrameSnitch.client.lua
-- Logs whenever anything disables your Laser1/Laser2 post effects.

local Lighting = game:GetService("Lighting")

local function watchFolder(folderName: string)
	local folder = Lighting:WaitForChild(folderName)
	print("[Snitch] Watching", folder:GetFullName())

	for _, inst in ipairs(folder:GetDescendants()) do
		if inst:IsA("PostEffect") then
			print("[Snitch] Hooked", inst:GetFullName())

			inst:GetPropertyChangedSignal("Enabled"):Connect(function()
				print(string.format(
					"[Snitch] %s Enabled -> %s\n%s",
					inst:GetFullName(),
					tostring(inst.Enabled),
					debug.traceback("Traceback (who triggered this change?)", 2)
					))
			end)
		end
	end
end

watchFolder("Laser1")
watchFolder("Laser2")
