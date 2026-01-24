-- StarterPlayerScripts/Modules/CameraShake.lua
-- Simple additive camera shake (no external libs).
-- Works with Scriptable/Custom cameras; respects current camera CFrame.

local RunService = game:GetService("RunService")

local Shake = {}
Shake.__index = Shake

function Shake.new()
	return setmetatable({
		_amp = 0,
		_freq = 18,
		_decay = 10,
		_rotAmp = 0,
		_seed = 0,
		_conn = nil,
	}, Shake)
end

local function noise(t, seed)
	-- cheap pseudo-noise without math.noise dependency
	return math.sin(t*12.9898 + seed*78.233) * 43758.5453 % 1
end

function Shake:Start(camera)
	if self._conn then return end
	self._conn = RunService.RenderStepped:Connect(function(dt)
		if not camera then return end
		if self._amp <= 0.0001 and self._rotAmp <= 0.0001 then
			return
		end

		-- Exponential decay
		local decay = math.exp(-self._decay * dt)
		self._amp *= decay
		self._rotAmp *= decay

		self._seed += dt * self._freq
		local t = self._seed

		local nx = (noise(t, 1) - 0.5) * 2
		local ny = (noise(t, 2) - 0.5) * 2
		local nz = (noise(t, 3) - 0.5) * 2

		local rx = (noise(t, 4) - 0.5) * 2
		local ry = (noise(t, 5) - 0.5) * 2
		local rz = (noise(t, 6) - 0.5) * 2

		local posOffset = Vector3.new(nx, ny, nz) * self._amp
		local rotOffset = CFrame.Angles(rx * self._rotAmp, ry * self._rotAmp, rz * self._rotAmp)

		-- Apply as additive offset
		camera.CFrame = camera.CFrame * CFrame.new(posOffset) * rotOffset
	end)
end

function Shake:Burst(posAmp, rotAmp, freq, decay)
	self._amp = math.max(self._amp, posAmp or 0)
	self._rotAmp = math.max(self._rotAmp, rotAmp or 0)
	if freq then self._freq = freq end
	if decay then self._decay = decay end
end

function Shake:Stop()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self._amp = 0
	self._rotAmp = 0
end

return Shake
