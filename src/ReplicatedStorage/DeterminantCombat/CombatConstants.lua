-- ReplicatedStorage/DeterminantCombat/Modules/CombatConstants.lua
local C = {}

-- Player stats
C.MAX_HEALTH = 100
C.MAX_STAMINA = 100
C.STAMINA_REGEN_PER_SEC = 22

-- Dodge (Soulslike pacing: short, readable, punish spamming)
C.DODGE_COST = 28
C.DODGE_COOLDOWN = 0.55
C.DODGE_DURATION = 0.28
C.DODGE_IMPULSE = 85 -- studs/sec-ish feel via LinearVelocity
C.DODGE_IFRAMES = 0.22

-- Hit fairness
C.POST_HIT_IMMUNITY = 0.22 -- prevents multi-hit melts from beams/bullets

-- Bullet hell defaults
C.PLAYER_HIT_RADIUS = 2.2

C.BULLET_DAMAGE = 18
C.BULLET_RADIUS = 1.0
C.BULLET_LIFE = 3.2

C.EXPLOSION_DAMAGE = 32
C.BEAM_DAMAGE = 26
C.BEAM_TICK_COOLDOWN = 0.45

return C
