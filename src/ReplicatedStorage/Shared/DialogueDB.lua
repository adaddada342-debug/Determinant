-- ReplicatedStorage/Shared/DialogueDB
local DialogueDB = {}

local function clamp(n, a, b)
	if n < a then return a end
	if n > b then return b end
	return n
end

function DialogueDB.getAwareness(mem)
	local awareness = 0
	if (mem.resets or 0) >= 1 then awareness += 1 end
	if (mem.resets or 0) >= 3 then awareness += 1 end
	if (mem.anomalies and (mem.anomalies.dialogueDesyncCount or 0) >= 3) then awareness += 1 end
	return clamp(awareness, 0, 3)
end

DialogueDB.NPCS = {
	Alma = {
		start = function(mem)
			local awareness = DialogueDB.getAwareness(mem)
			local resets = mem.resets or 0
			local met = mem.flags and mem.flags.metNpc_Alma

			if not met then
				return {
					name = "Alma",
					text = "You look lost. Thats normal here.",
					choices = {
						{ id = "who", text = "Who are you?" },
						{ id = "howProgress", text = "How does progression work?" },
						{ id = "whatNext", text = "What should I do next?" },
						{ id = "leave", text = "Leave." },
					},
					effects = function(m)
						m.flags = m.flags or {}
						m.flags.metNpc_Alma = true
						m.traits = m.traits or { mercy = 0, violence = 0, curiosity = 0 }
						m.traits.curiosity = (m.traits.curiosity or 0) + 1
					end,
				}
			end

			if resets >= 5 then
				return {
					name = "Alma",
					text = "You have done it a lot.\nResetting does not erase what you changed.\nIt just hides it for a moment.",
					choices = {
						{ id = "howProgress", text = "Explain progression." },
						{ id = "whatNext", text = "What should I do next?" },
						{ id = "leave", text = "Leave." },
					},
					effects = function(m)
						m.anomalies = m.anomalies or { dialogueDesyncCount = 0 }
						m.anomalies.dialogueDesyncCount = (m.anomalies.dialogueDesyncCount or 0) + 1
					end,
				}
			end

			if resets >= 3 then
				return {
					name = "Alma",
					text = "Back again.\nYou are not starting over.\nYou are looping.",
					choices = {
						{ id = "howProgress", text = "How does progression work?" },
						{ id = "whatNext", text = "What should I do next?" },
						{ id = "leave", text = "Leave." },
					},
					effects = function(m)
						m.anomalies = m.anomalies or { dialogueDesyncCount = 0 }
						m.anomalies.dialogueDesyncCount = (m.anomalies.dialogueDesyncCount or 0) + 1
					end,
				}
			end

			if resets >= 1 then
				return {
					name = "Alma",
					text = "Back already. The place has a way of pulling people in.",
					choices = {
						{ id = "askRules", text = "Any rules around here?" },
						{ id = "howProgress", text = "How does progression work?" },
						{ id = "whatNext", text = "What should I do next?" },
						{ id = "leave", text = "Leave." },
					},
				}
			end

			return {
				name = "Alma",
				text = "If you want answers, pay attention to what changes.\nSmall things matter here.",
				choices = {
					{ id = "askRules", text = "Any rules around here?" },
					{ id = "howProgress", text = "How does progression work?" },
					{ id = "whatNext", text = "What should I do next?" },
					{ id = "leave", text = "Leave." },
				},
			}
		end,

		who = function(mem)
			return {
				name = "Alma",
				text = "Im Alma.\nI watch for patterns.\nThis place has a lot of them.",
				choices = {
					{ id = "howProgress", text = "How does progression work?" },
					{ id = "whatNext", text = "What should I do next?" },
					{ id = "leave", text = "Leave." },
				},
			}
		end,

		askRules = function(mem)
			local awareness = DialogueDB.getAwareness(mem)

			if awareness >= 1 then
				return {
					name = "Alma",
					text = "Rule one:\nDo not pretend resets erase consequences.\nThey just rearrange them.",
					choices = {
						{ id = "howProgress", text = "So what carries over?" },
						{ id = "leave", text = "Leave." },
					},
				}
			end

			return {
				name = "Alma",
				text = "Do not touch things you cannot put back.\nIf you do, own it.",
				choices = {
					{ id = "howProgress", text = "What do you mean?" },
					{ id = "leave", text = "Leave." },
				},
			}
		end,

		howProgress = function(mem)
			local awareness = DialogueDB.getAwareness(mem)

			if awareness >= 2 then
				return {
					name = "Alma",
					text =
						"Progression is memory.\n\n" ..
						"1) The world keeps scars.\n" ..
						"2) People keep impressions.\n" ..
						"3) Resets raise awareness.\n\n" ..
						"The more you reset, the more the world pushes back.",
					choices = {
						{ id = "whatCarries", text = "What exactly carries over?" },
						{ id = "whatNext", text = "What should I do next?" },
						{ id = "leave", text = "Leave." },
					},
				}
			end

			return {
				name = "Alma",
				text =
					"Progression is not levels.\n" ..
					"It is consequences.\n\n" ..
					"The game remembers what you change.",
				choices = {
					{ id = "whatCarries", text = "What carries over?" },
					{ id = "whatNext", text = "What should I do next?" },
					{ id = "leave", text = "Leave." },
				},
			}
		end,

		whatCarries = function(mem)
			return {
				name = "Alma",
				text =
					"These usually carry over:\n\n" ..
					"1) Your reset count\n" ..
					"2) Key choices you make\n" ..
					"3) Changes to the world\n\n" ..
					"These usually do not:\n\n" ..
					"1) Temporary tasks\n" ..
					"2) Small surface details\n\n" ..
					"If something feels permanent, it probably is.",
				choices = {
					{ id = "whatNext", text = "What should I do next?" },
					{ id = "leave", text = "Leave." },
				},
			}
		end,

		whatNext = function(mem)
			local resets = mem.resets or 0

			if resets == 0 then
				return {
					name = "Alma",
					text =
						"Start small.\n" ..
						"Find something that can change.\n" ..
						"A door. A switch. A mark.\n" ..
						"Then come back and tell me what happened.",
					choices = {
						{ id = "leave", text = "Leave." },
					},
				}
			end

			if resets < 3 then
				return {
					name = "Alma",
					text =
						"Test the rules.\n" ..
						"Change one thing, reset once, and check if it stayed.\n" ..
						"If it did, that is progression.",
					choices = {
						{ id = "leave", text = "Leave." },
					},
				}
			end

			return {
				name = "Alma",
				text =
					"Now look for contradictions.\n" ..
					"Find something that should reset but does not.\n" ..
					"That is where the real path is.",
				choices = {
					{ id = "leave", text = "Leave." },
				},
			}
		end,
	},

	----------------------------------------------------------------
	-- NEW NPC: Wise Innkeeper (friend)
	-- NPC ID (attribute on model): "FoxyInnkeeper"
	----------------------------------------------------------------
	FoxyInnkeeper = {
		start = function(mem)
			local awareness = DialogueDB.getAwareness(mem)
			local resets = mem.resets or 0

			mem.flags = mem.flags or {}
			local met = mem.flags.metNpc_FoxyInnkeeper == true

			if not met then
				return {
					name = "the_foxyto1",
					text = "Welcome.\nThe door only opens for people who still have questions.\nSit. You look like you ran here from tomorrow.",
					choices = {
						{ id = "who", text = "Who are you?" },
						{ id = "inn", text = "What is this place?" },
						{ id = "advice", text = "Any advice?" },
						{ id = "leave", text = "Leave." },
					},
					effects = function(m)
						m.flags = m.flags or {}
						m.flags.metNpc_FoxyInnkeeper = true
						m.traits = m.traits or { mercy = 0, violence = 0, curiosity = 0 }
						m.traits.curiosity = (m.traits.curiosity or 0) + 1
					end,
				}
			end

			if awareness >= 2 and resets >= 3 then
				return {
					name = "the_foxyto1",
					text = "You came back with the same eyes.\nNot the same person.\nThat difference matters more than your victories.",
					choices = {
						{ id = "resets", text = "You noticed the resets?" },
						{ id = "remember", text = "What does the world remember?" },
						{ id = "advice", text = "So what do I do?" },
						{ id = "leave", text = "Leave." },
					},
				}
			end

			if resets >= 1 then
				return {
					name = "the_foxyto1",
					text = "Back again.\nThe inn stays. People don't.\nTry not to confuse comfort with safety.",
					choices = {
						{ id = "inn", text = "What is this place?" },
						{ id = "buy", text = "What can I get here?" },
						{ id = "advice", text = "Any advice?" },
						{ id = "leave", text = "Leave." },
					},
				}
			end

			return {
				name = "the_foxyto1",
				text = "Sit.\nWarmth is rare out there.\nDon't waste it by sprinting past it.",
				choices = {
					{ id = "inn", text = "What is this place?" },
					{ id = "buy", text = "What can I get here?" },
					{ id = "advice", text = "Any advice?" },
					{ id = "leave", text = "Leave." },
				},
			}
		end,

		who = function(mem)
			return {
				name = "the_foxyto1",
				text = "Just an innkeeper.\nA witness, if you prefer dramatic words.\nI keep drinks warm and stories from rotting.",
				choices = {
					{ id = "inn", text = "What is this place?" },
					{ id = "advice", text = "Any advice?" },
					{ id = "leave", text = "Leave." },
				},
			}
		end,

		inn = function(mem)
			local awareness = DialogueDB.getAwareness(mem)
			if awareness >= 1 then
				return {
					name = "the_foxyto1",
					text = "An inn, technically.\nA seam in the world, practically.\nThings slip through seams. So do people.",
					choices = {
						{ id = "remember", text = "What does the world remember?" },
						{ id = "buy", text = "What can I get here?" },
						{ id = "leave", text = "Leave." },
					},
				}
			end

			return {
				name = "the_foxyto1",
				text = "A place that doesn't ask you to fight to deserve silence.\nStay as long as you can stand yourself.",
				choices = {
					{ id = "buy", text = "What can I get here?" },
					{ id = "advice", text = "Any advice?" },
					{ id = "leave", text = "Leave." },
				},
			}
		end,

		buy = function(mem)
			return {
				name = "the_foxyto1",
				text = "Food. Rest. Tools.\nNot miracles.\nIf you're looking for salvation, wrong counter.",
				choices = {
					{ id = "advice", text = "Then what should I do?" },
					{ id = "leave", text = "Leave." },
				},
			}
		end,

		advice = function(mem)
			local awareness = DialogueDB.getAwareness(mem)
			if awareness >= 2 then
				return {
					name = "the_foxyto1",
					text = "Don't chase power like it's a cure.\nPower just makes your choices louder.\nIf you want the world to soften, stop hitting it and calling it progress.",
					choices = {
						{ id = "remember", text = "What does the world remember?" },
						{ id = "leave", text = "Leave." },
					},
				}
			end

			return {
				name = "the_foxyto1",
				text = "Pick one thing.\nChange it on purpose.\nThen watch what changes back.",
				choices = {
					{ id = "leave", text = "Leave." },
				},
			}
		end,

		resets = function(mem)
			return {
				name = "the_foxyto1",
				text = "You think time is a line.\nIt isn't.\nIt's a habit.\nAnd you've been indulging.",
				choices = {
					{ id = "remember", text = "So what carries over?" },
					{ id = "leave", text = "Leave." },
				},
			}
		end,

		remember = function(mem)
			return {
				name = "the_foxyto1",
				text = "The world remembers patterns.\nPeople remember feelings.\nAnd you...\nYou remember the parts you try hardest to forget.",
				choices = {
					{ id = "leave", text = "Leave." },
				},
			}
		end,
	},
}

return DialogueDB
