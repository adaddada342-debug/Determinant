-- ServerScriptService/ToolDestroyTrap.server.lua
local Players = game:GetService("Players")

local function attach(tool: Tool)
	if tool:GetAttribute("__TrapAttached") then return end
	tool:SetAttribute("__TrapAttached", true)

	tool.Destroying:Connect(function()
		warn("=== TOOL Destroying fired:", tool:GetFullName(), "===")
		warn(debug.traceback())
	end)

	tool.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			warn("=== TOOL parent became nil (destroyed):", tool.Name, "===")
		end
	end)
end

Players.PlayerAdded:Connect(function(plr)
	plr.Backpack.ChildAdded:Connect(function(c)
		if c:IsA("Tool") and c.Name == "TheBlade" then
			attach(c)
		end
	end)
	plr.CharacterAdded:Connect(function(char)
		char.ChildAdded:Connect(function(c)
			if c:IsA("Tool") and c.Name == "TheBlade" then
				attach(c)
			end
		end)
	end)
end)
