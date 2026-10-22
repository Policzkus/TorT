--!strict
-- Costume Line homeowners (PROMPT §3.6). Each personality greets you with one of its lines; pick
-- the answer in the style they like. Wrong options come from the other personalities' pools.
-- Kid-friendly only. Add lines freely; keep each answer short enough for a phone button.

export type Personality = {
	name: string,
	emoji: string,
	likes: string, -- shown in the hint line
	greetings: { string },
	answers: { string },
}

local personalities: { [string]: Personality } = {
	GrumpyGus = {
		name = "Grumpy Gus",
		emoji = "👴",
		likes = "polite kids",
		greetings = {
			"Hmph. Another one. What do YOU want?",
			"It's past my bedtime, kid. Make it quick.",
			"I suppose you want candy. Everybody wants candy.",
			"Wipe your feet first. Now, what is it?",
		},
		answers = {
			"Trick or treat, please! Thank you, sir!",
			"Sorry to bother you. May I please have a treat?",
			"Please and thank you! Have a good night!",
			"Excuse me, sir, may I have one, please?",
			"Thank you so much, I'll only take one!",
			"Pardon me! Trick or treat, please?",
		},
	},
	WitchyWanda = {
		name = "Witchy Wanda",
		emoji = "🧙",
		likes = "rhymes",
		greetings = {
			"Who knocks upon my door so late, hoping for a treat-filled plate?",
			"Speak in rhyme or speak no more, little goblin at my door!",
			"Bubble, bubble, what's the trouble? Say it sweetly, say it double!",
			"My cauldron's warm, my cat is fat. Now tell me, child, what's this and that?",
		},
		answers = {
			"Trick or treat, smell my feet, give me something good to eat!",
			"Candy sweet and candy small, I'd be happy with them all!",
			"Witch so wise and witch so grand, drop a treat into my hand!",
			"By the moon and by the night, may I have a sweet delight?",
			"Your cauldron's hot, your hat is tall, please share some candy with us all!",
			"Abracadabra, hocus pocus, give me sweets so I can focus!",
		},
	},
	CoachCarl = {
		name = "Coach Carl",
		emoji = "🏈",
		likes = "hype",
		greetings = {
			"ALRIGHT CHAMP! Show me that trick-or-treat ENERGY!",
			"Who's ready to WIN at Halloween?!",
			"Hustle, hustle! What've you got for me, rookie?",
			"I want to hear it from the BACK OF THE STADIUM!",
		},
		answers = {
			"LET'S GOOO! Best house on the whole block, Coach!",
			"TRICK OR TREAT! I gave it one hundred and ten percent!",
			"Put me in, Coach! I'm ready for the candy!",
			"WOOO! Team Candy for the WIN!",
			"High five, Coach! Halloween MVP right here!",
			"I ran three streets to get here! GO TEAM!",
		},
	},
	LadyVictoria = {
		name = "Lady Victoria",
		emoji = "👒",
		likes = "fancy manners",
		greetings = {
			"Good evening. One does hope you have been raised properly.",
			"Oh my. A visitor. Do introduce yourself, darling.",
			"Tea is served at nine. Candy, however, must be earned with grace.",
			"Shoulders back, chin up. Now, how may I help you, dear?",
		},
		answers = {
			"Good evening, madam. Might I trouble you for a treat?",
			"A delightful home, my lady. May I kindly have a sweet?",
			"How do you do? It would be an honour to receive a treat.",
			"Your garden is simply marvellous. A treat, if you would?",
			"Lovely evening, isn't it? Might I have a sweet, please?",
			"Charmed, I'm sure! Would you spare a treat for a guest?",
		},
	},
	CountSugula = {
		name = "Count Sugula",
		emoji = "🧛",
		likes = "drama",
		greetings = {
			"Ah-ah-ah! Who dares disturb the Count at this hour?",
			"The night is dark and full of SUGAR! Speak, mortal!",
			"I have waited three hundred years for a worthy visitor...",
			"Bwahaha! Impress me, little one, and the candy is yours!",
		},
		answers = {
			"Behold! I have crossed the darkest night for your candy!",
			"Thunder roars! Lightning strikes! I demand a TREAT!",
			"From the shadows I rise... for one piece of chocolate!",
			"Fear not, great Count! I bring you my most dramatic bow!",
			"The moon is full, my bag is empty... this is my destiny!",
			"Gasp! At last I stand before the legendary Count!",
		},
	},
}

local order = { "GrumpyGus", "WitchyWanda", "CoachCarl", "LadyVictoria", "CountSugula" }

return {
	personalities = personalities,
	ORDER = order, -- stable order for seeded picks
}
