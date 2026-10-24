--!strict
-- What the homeowners say (PROMPT §3.6, the user's 1023.mp4 look: DialogController's speech bubble).
-- Each house gets a personality every Night. They say a `hello` line when they open the door, a
-- `pleased` or `displeased` one after your mini-game, and in Costume Line they ask one of their
-- `greetings`: answer in the style they like (the greeting gives it away), from `answers`; the
-- wrong options come from the other personalities. Never shown: their name. Eerie, never gory:
-- Roblox's audience is young. Keep lines short enough for the bubble (about 60 letters).

export type Personality = {
	name: string, -- for us only; players never see it
	likes: string, -- the answer style they want (for us; the greeting has to give it away)
	voice: number, -- pitch of their voice blips (1 = normal; lower is deeper)
	greetings: { string },
	answers: { string },
	hello: { string },
	pleased: { string },
	displeased: { string },
}

local personalities: { [string]: Personality } = {
	Host = {
		name = "The Host",
		likes = "manners",
		voice = 0.8,
		greetings = {
			"You're very late. The others were so polite.",
			"Manners, child. In this house we always say please.",
			"Wipe your feet. We only just cleaned the floor... again.",
			"Well? Don't just stand there breathing. Ask nicely.",
		},
		answers = {
			"Sorry to bother you. May I please have a treat?",
			"Good evening. Trick or treat, if you please.",
			"Excuse me, sir. May I have one, please?",
			"Thank you so much. I'll only take one.",
			"Pardon me. Might I trouble you for a sweet?",
			"Please and thank you. Have a lovely night.",
		},
		hello = {
			"Good evening. We've been expecting you.",
			"Ah. Another little guest. Do come closer.",
			"You knocked. Most people don't knock anymore.",
		},
		pleased = { "Such good manners...", "Come back soon. We'll keep a light on.", "Take it. Take it, and go." },
		displeased = { "That's not how you knock.", "Rude. The last rude one never left.", "We'll remember you." },
	},
	Rhymer = {
		name = "The Rhymer",
		likes = "rhymes",
		voice = 1.1,
		greetings = {
			"Knock, knock, knock... who walks at midnight? Rhyme for me, or lose your light.",
			"Round and round the candles go. Say it sweet and say it slow.",
			"Little feet upon my stair, speak in rhyme if you dare.",
			"Moon is high and wind is cold. Rhyme me something, sweet and bold.",
		},
		answers = {
			"Trick or treat, smell my feet, give me something good to eat!",
			"Candy sweet and candy small, I'd be happy with them all!",
			"By the moon and by the night, may I have a sweet delight?",
			"Open wide your creaky door, I'll take one and ask no more!",
			"Candles flicker, shadows creep, one more sweet and then I'll sleep!",
			"Bats above and cats below, give a treat and I will go!",
		},
		hello = {
			"Who's this knocking, small and sweet? Have you come for something to eat?",
			"Tap, tap, tap upon my door... I've been waiting here before.",
			"Ah, a guest beneath the moon. You arrived a bit too soon.",
		},
		pleased = { "Sweet and neat, a proper treat.", "Off you go into the night. Don't look back. Not even right." },
		displeased = { "Clumsy feet and clumsy tongue...", "Wrong, wrong, wrong. You won't last long." },
	},
	Child = {
		name = "The Child",
		likes = "playing along",
		voice = 1.45,
		greetings = {
			"Do you want to play with me? Nobody ever plays with me.",
			"Mommy says I can't go outside. Will you play in here?",
			"Let's play a game! If you win, you get candy. If you lose...",
			"I'm not supposed to open the door. Do you wanna play?",
		},
		answers = {
			"Okay, let's play! Tag, you're it! Now can I have a treat?",
			"I love games! Hide and seek? Then trick or treat!",
			"Sure! I'll play with you! Do I get candy if I win?",
			"Pinky promise I'll come back to play! Trick or treat?",
			"Let's play pretend! You're the candy shop and I'm buying!",
			"Okay! Simon says... give me a treat!",
		},
		hello = {
			"Hi! Hi! Are you my new friend?",
			"Shhh. Mommy's asleep. You can stay as long as you want.",
			"You came back! You came back to play!",
		},
		pleased = { "Yay! Come play again tomorrow. And the day after. Forever.", "You're my best friend now." },
		displeased = { "You're not fun. I'm telling Mommy.", "That was a bad game. Let's play again. Now." },
	},
	Whisperer = {
		name = "The Whisperer",
		likes = "whispering",
		voice = 0.9,
		greetings = {
			"shhh... they're asleep upstairs. whisper.",
			"not so loud... it can hear you...",
			"quiet. quiet. tell me what you want. quietly.",
			"keep your voice down... the walls listen here...",
		},
		answers = {
			"(whispering) trick or treat... please...",
			"shh... just one sweet... then i'll go...",
			"sorry... sorry... may i have a treat... quietly...",
			"i'll be very quiet... one candy... please...",
			"tiptoe... tiptoe... trick or treat...",
			"(very softly) is there any candy left...?",
		},
		hello = {
			"...you shouldn't knock so loud.",
			"shh. come closer. closer.",
			"...did anyone see you come here?",
		},
		pleased = { "good... good... now go. softly.", "nobody heard. nobody will." },
		displeased = { "TOO LOUD.", "...it heard you. run along now." },
	},
	Collector = {
		name = "The Collector",
		likes = "compliments",
		voice = 1.0,
		greetings = {
			"Do you like my dolls? I made every one of them.",
			"Look at my house. Isn't it beautiful? Say it.",
			"I collect pretty things. Are you a pretty thing?",
			"My porch, my door, my lovely glass eyes. Tell me what you see.",
		},
		answers = {
			"Your house is the most beautiful one on the street!",
			"What lovely dolls! May I please have a treat?",
			"Wow, your porch is amazing! Trick or treat!",
			"Your door is so fancy! Can I have a sweet?",
			"I love your decorations, they're the best! Treat, please?",
			"This is the coolest house I've ever seen!",
		},
		hello = {
			"Oh... you'd look wonderful on my shelf.",
			"Another visitor for my collection. Come in. No? Pity.",
			"Hold still. Let me look at you.",
		},
		pleased = { "Charming. Simply charming. I'll think of you.", "Come back when you're ready to stay." },
		displeased = { "Ugly words from such a pretty face.", "I don't collect rude things. Usually." },
	},
	OldMan = {
		name = "The Old Man",
		likes = "bravery",
		voice = 0.65,
		greetings = {
			"Aren't you scared of me? Everyone is scared of me.",
			"Kids run away when they see me. Why haven't you run?",
			"Look at my face. Look. Do you still want candy?",
			"Most children cry at my door. Are you going to cry?",
		},
		answers = {
			"I'm not scared of anything! Trick or treat!",
			"Boo to you too! Now hand over the candy!",
			"Scared? Me? I've walked past way scarier houses!",
			"I'm the bravest kid on this street! Treat, please!",
			"I didn't run and I won't run! Candy time!",
			"You don't scare me, mister! Trick or treat!",
		},
		hello = {
			"...You're standing very close to my door.",
			"Another one. They never learn.",
			"Hmm. You smell like candy.",
		},
		pleased = { "Brave. Brave. That won't help you.", "Fine. Take it. Before I change my mind." },
		displeased = { "I can hear your heart. It's so fast.", "Run home. Run home now." },
	},
}

local order = { "Host", "Rhymer", "Child", "Whisperer", "Collector", "OldMan" }

return {
	personalities = personalities,
	ORDER = order, -- stable order for seeded picks
}
