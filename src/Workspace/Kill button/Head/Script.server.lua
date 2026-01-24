
script.Parent.ClickDetector.MouseClick:Connect(function(player)
	local humanoid = player.Character:FindFirstChild ("Humanoid")
	humanoid.Health = 0 
end)