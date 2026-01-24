-- ReplicatedStorage/BattleData.lua
-- Encounter data: enemies, acts, dialogue, attacks.

local BattleData = {}

BattleData.Enemies = {
	Froggit = {
		id = "Froggit",
		name = "Froggit",
		maxHP = 30,
		atk = 5,
		def = 0,

		-- Put a Model named "Froggit" inside ReplicatedStorage/Enemies (recommended).
		modelName = "Froggit",

		-- text lines
		intro = "* Froggit hopped close!",
		idleLines = {
			"* Froggit is wondering what to do.",
			"* Froggit doesn't seem to know why it's here.",
			"* Froggit hops closer. Menacingly.",
		},
		attackLines = {
			"* Froggit attacks!",
			"* Froggit croaks threateningly!",
		},

		-- ACT menu options
		acts = {
			{ key="Check",      label="Check",      text="* FROGGIT  ATK 5  DEF 0\n* Life is difficult for this enemy." },
			{ key="Compliment", label="Compliment", text="* You compliment Froggit.\n* It didn't understand, but it appreciated the effort." },
			{ key="Threaten",   label="Threaten",   text="* You threaten Froggit.\n* It is too confused to be properly afraid." },
		},

		-- Mercy conditions
		spare = {
			-- spare becomes available after any ACT once
			requireAct = true,
		},

		attack = {
			mode = "BulletHell3D",
			duration = 6,
		},

		fight = {
			base = 6,
			perfectBonus = 8,
		},
	},

	
	TheBugged = {
		id = "TheBugged",
		name = "The Bugged",
		maxHP = 42,
		atk = 7,
		def = 1,

		-- Put a Model named "TheBugged" inside ReplicatedStorage/Enemies
		modelName = "TheBugged",

		intro = "* Something stutters into existence.",

		idleLines = {
			"* It twitches in place.",
			"* Its outline can't agree with reality.",
			"* The air around it crackles with mistakes.",
		},

		attackLines = {
			"* The Bugged spasms violently!",
			"* The Bugged desyncs the air around you!",
			"* Frames tear as it lurches forward!",
		},

		acts = {
			{
				key = "Check",
				label = "Check",
				text = "* THE BUGGED  ATK 7  DEF 1\n* A resident stitched together by errors.\n* It hurts just to remain loaded.",
			},
			{
				key = "Talk",
				label = "DEBUG",
				text = "* You speak softly, like you're reading logs.\n* The Bugged stabilizes for a breath.\n* Then it remembers it's broken.",
			},
			{
				key = "Threaten",
				label = "PATCH",
				text = "* You force a \"fix\" onto corrupted code.\n* It flinches, resisting the overwrite.\n* Something inside it cracks louder.",
			},
			{
				key = "Spare Plea",
				label = "REBOOT?",
				text = "* You offer it a clean restart.\n* It trembles.\n* It doesn't believe it deserves one.",
			},
		},

		spare = {
			-- spare becomes available after any ACT once
			requireAct = true,
		},

		attack = {
			mode = "BulletHell3D",
			duration = 7,

			-- Optional fields (safe if unused by your current BulletHell pipeline):
			pattern = "GlitchBurst",
			params = {
				burstEvery = 0.55,
				burstCount = 4,
				laneShiftChance = 0.35,
				jitterPx = 10,
			},
		},

		fight = {
			base = 7,
			perfectBonus = 9,
		},
	},

}

BattleData.Weapons = BattleData.Weapons or {}
BattleData.Weapons.ToughGlove = { baseDamage = 12, range = 10 }


return BattleData
