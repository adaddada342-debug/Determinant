-- ReplicatedStorage/BossBulletHell/Constants.lua
local C = {}

-- Fairness / pacing
C.PHASE_MIN = 5
C.PHASE_MAX = 15

-- Damage + anti-meltdown
C.POST_HIT_IMMUNITY = 0.20 -- prevents multi-hit blender deaths

-- Player hit sphere (server)
C.PLAYER_HIT_RADIUS = 2.2

-- Bullets
C.BULLET_DAMAGE = 18
C.BULLET_RADIUS = 1.0
C.BULLET_LIFE = 3.0

-- Explosions
C.EXPLOSION_DAMAGE = 32

-- Beam
C.BEAM_DAMAGE = 26
C.BEAM_TICK_COOLDOWN = 0.45

return C
