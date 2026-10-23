--!strict
-- The game's own playable characters (PROMPT §V2.3: nobody plays as their Roblox avatar). Each one
-- is an AI mesh (Roblox Studio generate_mesh, owner's account) generated in six segments;
-- Modules/CharacterRig joins them into a Humanoid rig. Sizes and offsets are in studs after
-- scaling; an offset is the segment's centre relative to the point between the feet, with the
-- character facing -Z. eye = eye height (default: 60% up the head segment; set it when a hat makes
-- the head segment tall).

export type Segment = { mesh: number, texture: number, size: { number }, offset: { number } }
export type Character = { segments: { [string]: Segment }, eye: number? }

local characters: { [string]: Character } = {
	-- Starter kids ----------------------------------------------------------------------------------
	-- Skinny kid, messy brown hair, oversized blue hoodie.
	Kid_Milo = {
		eye = 3.8,
		segments = {
			Head = {
				mesh = 75213827872370,
				texture = 96082268006171,
				size = { 1.741, 1.519, 1.846 },
				offset = { -0.005, 3.841, -0.018 },
			},
			LeftArm = {
				mesh = 126842007591126,
				texture = 126111741177638,
				size = { 0.857, 1.829, 0.702 },
				offset = { -0.596, 2.107, -0.013 },
			},
			LeftLeg = {
				mesh = 105087091476145,
				texture = 93214259339308,
				size = { 0.704, 1.826, 1.011 },
				offset = { -0.389, 0.913, -0.143 },
			},
			RightArm = {
				mesh = 80980647619650,
				texture = 98307009928562,
				size = { 0.855, 1.829, 0.702 },
				offset = { 0.597, 2.109, -0.014 },
			},
			RightLeg = {
				mesh = 110401558353046,
				texture = 86589916844852,
				size = { 0.706, 1.825, 1.024 },
				offset = { 0.392, 0.913, -0.143 },
			},
			Torso = {
				mesh = 79894604115879,
				texture = 140495576578374,
				size = { 1.317, 1.816, 1.638 },
				offset = { 0.005, 2.356, 0.122 },
			},
		},
	},
	-- Mustard beanie, olive raincoat, rubber boots.
	Kid_Ivy = {
		eye = 3.6,
		segments = {
			Head = {
				mesh = 134059159507083,
				texture = 136667540271525,
				size = { 1.933, 1.799, 1.932 },
				offset = { -0.002, 3.701, 0 },
			},
			LeftArm = {
				mesh = 137704495838602,
				texture = 116649952306693,
				size = { 0.76, 1.351, 0.694 },
				offset = { -0.705, 1.965, -0.036 },
			},
			LeftLeg = {
				mesh = 122432220394232,
				texture = 85745256605379,
				size = { 0.528, 1.32, 0.928 },
				offset = { -0.353, 0.66, -0.183 },
			},
			RightArm = {
				mesh = 74076449978935,
				texture = 97506821075772,
				size = { 0.761, 1.348, 0.699 },
				offset = { 0.704, 1.965, -0.035 },
			},
			RightLeg = {
				mesh = 95093945467930,
				texture = 107341558388243,
				size = { 0.523, 1.319, 0.923 },
				offset = { 0.351, 0.66, -0.181 },
			},
			Torso = {
				mesh = 85771389510610,
				texture = 136604981128202,
				size = { 1.601, 1.878, 1.714 },
				offset = { -0.001, 1.995, 0.021 },
			},
		},
	},
	-- Chubby kid, yellow rain hat, round glasses, striped sweater.
	Kid_Theo = {
		eye = 3.55,
		segments = {
			Head = {
				mesh = 79237757788031,
				texture = 102525495693227,
				size = { 2.176, 1.676, 2.156 },
				offset = { 0, 3.662, 0 },
			},
			LeftArm = {
				mesh = 71032734078144,
				texture = 131288323949863,
				size = { 0.776, 1.727, 0.655 },
				offset = { -0.777, 1.953, -0.008 },
			},
			LeftLeg = {
				mesh = 123378507516446,
				texture = 109784120883345,
				size = { 0.737, 1.667, 1.036 },
				offset = { -0.403, 0.834, -0.149 },
			},
			RightArm = {
				mesh = 79835422527042,
				texture = 117142956580741,
				size = { 0.777, 1.726, 0.652 },
				offset = { 0.776, 1.951, -0.01 },
			},
			RightLeg = {
				mesh = 127355990884025,
				texture = 83932569320549,
				size = { 0.736, 1.665, 1.032 },
				offset = { 0.403, 0.833, -0.146 },
			},
			Torso = {
				mesh = 121804099545513,
				texture = 128492303146169,
				size = { 1.563, 1.984, 1.511 },
				offset = { 0.006, 2.081, 0.01 },
			},
		},
	},
	-- Freckles, backwards red cap, flannel and overalls.
	Kid_Nell = {
		eye = 3.25,
		segments = {
			Head = {
				mesh = 91992189214665,
				texture = 80169307451381,
				size = { 2.084, 2.137, 2.366 },
				offset = { 0, 3.332, 0 },
			},
			LeftArm = {
				mesh = 75203402218975,
				texture = 120473312907002,
				size = { 0.759, 1.629, 0.67 },
				offset = { -0.647, 1.655, 0.141 },
			},
			LeftLeg = {
				mesh = 128934700793241,
				texture = 76615733550609,
				size = { 0.771, 1.688, 1.249 },
				offset = { -0.37, 0.844, 0.05 },
			},
			RightArm = {
				mesh = 125411469838418,
				texture = 118490898143262,
				size = { 0.768, 1.632, 0.67 },
				offset = { 0.647, 1.657, 0.143 },
			},
			RightLeg = {
				mesh = 90178641748637,
				texture = 86254612394505,
				size = { 0.774, 1.688, 1.243 },
				offset = { 0.367, 0.845, 0.052 },
			},
			Torso = {
				mesh = 91069899101924,
				texture = 138117843459117,
				size = { 1.242, 0.934, 1.138 },
				offset = { -0.001, 2.065, 0.099 },
			},
		},
	},

	-- Costumes --------------------------------------------------------------------------------------
	-- Dirty bed sheet with eye holes; the sheet is the "head" segment, so it sways as one piece.
	Costume_GhostSheet = {
		eye = 3.9,
		segments = {
			Head = {
				mesh = 126684551881466,
				texture = 78289907495288,
				size = { 1.961, 3.916, 1.767 },
				offset = { 0.004, 2.642, 0.031 },
			},
			LeftArm = {
				mesh = 72448769341484,
				texture = 108564588766444,
				size = { 0.823, 1.904, 1.15 },
				offset = { -0.901, 2.331, 0.03 },
			},
			LeftLeg = {
				mesh = 88563143721083,
				texture = 95881804375891,
				size = { 0.673, 1.868, 1.14 },
				offset = { -0.405, 0.935, -0.344 },
			},
			RightArm = {
				mesh = 123073874267452,
				texture = 87038493174483,
				size = { 0.818, 1.912, 1.151 },
				offset = { 0.903, 2.329, 0.034 },
			},
			RightLeg = {
				mesh = 101164303174795,
				texture = 139639004088114,
				size = { 0.676, 1.87, 1.14 },
				offset = { 0.405, 0.935, -0.343 },
			},
			Torso = {
				mesh = 137337877980325,
				texture = 76094717741476,
				size = { 1.967, 2.588, 1.762 },
				offset = { 0.001, 1.979, 0.028 },
			},
		},
	},
	-- Carved jack-o'-lantern over the head, patched corduroy jacket, gardening gloves.
	Costume_PumpkinHead = {
		eye = 3.95,
		segments = {
			Head = {
				mesh = 123757647604184,
				texture = 88921178065741,
				size = { 1.756, 1.568, 1.721 },
				offset = { -0.001, 4.016, 0 },
			},
			LeftArm = {
				mesh = 122880108517660,
				texture = 126634184288315,
				size = { 0.807, 1.795, 0.739 },
				offset = { -0.703, 2.283, -0.016 },
			},
			LeftLeg = {
				mesh = 88142282944222,
				texture = 131722852652901,
				size = { 0.847, 2.114, 1.151 },
				offset = { -0.381, 1.058, -0.171 },
			},
			RightArm = {
				mesh = 83568039022893,
				texture = 134821051945051,
				size = { 0.807, 1.798, 0.746 },
				offset = { 0.703, 2.282, -0.015 },
			},
			RightLeg = {
				mesh = 91856390490005,
				texture = 74042713105298,
				size = { 0.852, 2.113, 1.15 },
				offset = { 0.377, 1.056, -0.174 },
			},
			Torso = {
				mesh = 129567523789737,
				texture = 114920772646483,
				size = { 1.32, 1.828, 1.213 },
				offset = { 0.003, 2.638, 0.018 },
			},
		},
	},
	-- Little witch: crooked hat, ragged black dress, striped stockings.
	Costume_Witch = {
		eye = 3.3,
		segments = {
			Head = {
				mesh = 126615365535591,
				texture = 111790567527374,
				size = { 2.817, 2.825, 2.79 },
				offset = { 0, 3.688, 0 },
			},
			LeftArm = {
				mesh = 125226548846884,
				texture = 76145680596042,
				size = { 0.829, 1.266, 0.585 },
				offset = { -0.687, 1.92, 0.002 },
			},
			LeftLeg = {
				mesh = 71200375762511,
				texture = 132800158004983,
				size = { 0.552, 1.266, 0.645 },
				offset = { -0.289, 0.633, -0.123 },
			},
			RightArm = {
				mesh = 89104056392056,
				texture = 71246169789648,
				size = { 0.83, 1.264, 0.591 },
				offset = { 0.688, 1.921, 0.004 },
			},
			RightLeg = {
				mesh = 72014007491257,
				texture = 127137328504140,
				size = { 0.544, 1.265, 0.643 },
				offset = { 0.29, 0.633, -0.122 },
			},
			Torso = {
				mesh = 107141737646659,
				texture = 86084946085908,
				size = { 1.36, 1.701, 1.327 },
				offset = { 0, 1.647, 0.004 },
			},
		},
	},
	-- Black cat mascot suit: big ears, whiskers, curled tail.
	Costume_BlackCat = {
		eye = 3.55,
		segments = {
			Head = {
				mesh = 137688621012957,
				texture = 94254164912031,
				size = { 1.983, 1.997, 1.761 },
				offset = { 0.029, 3.801, -0.231 },
			},
			LeftArm = {
				mesh = 134051818900784,
				texture = 127886486644463,
				size = { 0.796, 1.606, 0.631 },
				offset = { -0.648, 2.098, -0.289 },
			},
			LeftLeg = {
				mesh = 120083595058647,
				texture = 100527841059161,
				size = { 0.734, 1.858, 0.954 },
				offset = { -0.342, 0.929, -0.332 },
			},
			RightArm = {
				mesh = 94747466585200,
				texture = 92285018897671,
				size = { 0.819, 1.608, 0.628 },
				offset = { 0.689, 2.1, -0.288 },
			},
			RightLeg = {
				mesh = 80841496922934,
				texture = 122794035676610,
				size = { 0.768, 1.862, 0.952 },
				offset = { 0.38, 0.932, -0.337 },
			},
			Torso = {
				mesh = 138758289563210,
				texture = 136015422802317,
				size = { 1.809, 2.206, 2.049 },
				offset = { -0.195, 1.877, 0.087 },
			},
		},
	},
	-- Little vampire: slicked hair, waistcoat, red-lined cape.
	Costume_Vampire = {
		eye = 3.75,
		segments = {
			Head = {
				mesh = 133762386698097,
				texture = 90046138619200,
				size = { 1.901, 1.713, 1.91 },
				offset = { 0, 3.844, -0.206 },
			},
			LeftArm = {
				mesh = 103961965745849,
				texture = 129464731494596,
				size = { 0.835, 1.603, 0.79 },
				offset = { -0.731, 1.952, -0.198 },
			},
			LeftLeg = {
				mesh = 113432359455332,
				texture = 93979385569226,
				size = { 0.725, 1.754, 0.899 },
				offset = { -0.38, 0.877, -0.265 },
			},
			RightArm = {
				mesh = 119716425191805,
				texture = 121276529939149,
				size = { 0.835, 1.61, 0.78 },
				offset = { 0.735, 1.951, -0.194 },
			},
			RightLeg = {
				mesh = 127368241057079,
				texture = 138928136103331,
				size = { 0.718, 1.754, 0.902 },
				offset = { 0.383, 0.877, -0.264 },
			},
			Torso = {
				mesh = 131928789609936,
				texture = 129495721963764,
				size = { 2.906, 2.913, 2.016 },
				offset = { 0, 1.837, 0.153 },
			},
		},
	},
	-- Skeleton bodysuit and a big cracked skull mask.
	Costume_Skeleton = {
		segments = {
			Head = {
				mesh = 120305539583716,
				texture = 138175936022481,
				size = { 2.148, 2.025, 2.163 },
				offset = { 0, 3.488, 0 },
			},
			LeftArm = {
				mesh = 124242256225977,
				texture = 118636128052493,
				size = { 1.003, 1.706, 0.764 },
				offset = { -0.955, 1.596, -0.053 },
			},
			LeftLeg = {
				mesh = 97465681346623,
				texture = 72525191894834,
				size = { 0.686, 1.347, 0.91 },
				offset = { -0.516, 0.674, -0.177 },
			},
			RightArm = {
				mesh = 130561368605829,
				texture = 106927115752026,
				size = { 1.008, 1.703, 0.767 },
				offset = { 0.953, 1.596, -0.053 },
			},
			RightLeg = {
				mesh = 114865731205745,
				texture = 72661740754604,
				size = { 0.682, 1.348, 0.906 },
				offset = { 0.514, 0.674, -0.176 },
			},
			Torso = {
				mesh = 132199006507509,
				texture = 118222182900775,
				size = { 1.632, 1.807, 1.608 },
				offset = { -0.001, 1.67, -0.028 },
			},
		},
	},
	-- Homeowners (client-side puppets, HomeownerController; Config/Homeowners pools them) ------------
	-- Gaunt, grey, wide fixed grin; tank top and suspenders.
	Owner_TankTop = {
		segments = {
			Head = {
				mesh = 96927304743348,
				texture = 76527226488503,
				size = { 2.238, 2.115, 1.836 },
				offset = { -0.003, 6.143, -0.024 },
			},
			LeftArm = {
				mesh = 92413082275970,
				texture = 126273855231495,
				size = { 1.283, 3.179, 1 },
				offset = { -1.003, 3.771, 0.277 },
			},
			LeftLeg = {
				mesh = 121521961358580,
				texture = 96036214643203,
				size = { 1.058, 3.346, 1.34 },
				offset = { -0.607, 1.673, -0.072 },
			},
			RightArm = {
				mesh = 101020066095802,
				texture = 70627798008510,
				size = { 1.293, 3.178, 0.999 },
				offset = { 0.998, 3.774, 0.276 },
			},
			RightLeg = {
				mesh = 107736345987000,
				texture = 133889123267000,
				size = { 1.061, 3.346, 1.341 },
				offset = { 0.6, 1.674, -0.074 },
			},
			Torso = {
				mesh = 134496562133359,
				texture = 106901161150623,
				size = { 1.507, 2.611, 1.443 },
				offset = { -0.005, 4.171, 0.22 },
			},
		},
	},
	-- Grandma in curlers and a floral housecoat, eyes too far apart.
	Owner_Curlers = {
		segments = {
			Head = {
				mesh = 86082328373212,
				texture = 75277827707497,
				size = { 2.196, 1.886, 2.417 },
				offset = { 0.007, 5.457, 0.031 },
			},
			LeftArm = {
				mesh = 70828604521615,
				texture = 121784132011768,
				size = { 0.961, 2.854, 1.293 },
				offset = { -1.56, 3.123, -0.008 },
			},
			LeftLeg = {
				mesh = 118892267405669,
				texture = 117103768455468,
				size = { 0.809, 1.061, 1.506 },
				offset = { -0.618, 0.531, -0.24 },
			},
			RightArm = {
				mesh = 70369123244970,
				texture = 73133701319927,
				size = { 0.958, 2.857, 1.296 },
				offset = { 1.561, 3.126, -0.004 },
			},
			RightLeg = {
				mesh = 70997136854827,
				texture = 103619226007954,
				size = { 0.823, 1.073, 1.502 },
				offset = { 0.62, 0.536, -0.238 },
			},
			Torso = {
				mesh = 104438646190883,
				texture = 93533600925758,
				size = { 3.015, 3.911, 2.662 },
				offset = { 0.002, 2.866, 0 },
			},
		},
	},
	-- Suburban dad, sweater vest, frozen grin, blank white eyes.
	Owner_SweaterVest = {
		segments = {
			Head = {
				mesh = 105542667871630,
				texture = 131411331474040,
				size = { 1.945, 2.052, 1.456 },
				offset = { -0.003, 6.374, 0.086 },
			},
			LeftArm = {
				mesh = 89889828218128,
				texture = 105749628800971,
				size = { 0.889, 2.994, 0.991 },
				offset = { -1.024, 3.797, 0.289 },
			},
			LeftLeg = {
				mesh = 103482558537095,
				texture = 136972827201963,
				size = { 0.772, 3.243, 1.431 },
				offset = { -0.446, 1.622, -0.212 },
			},
			RightArm = {
				mesh = 74378789567628,
				texture = 137948464527979,
				size = { 0.898, 2.997, 0.997 },
				offset = { 1.019, 3.796, 0.289 },
			},
			RightLeg = {
				mesh = 128849982338732,
				texture = 107673177575232,
				size = { 0.781, 3.241, 1.427 },
				offset = { 0.446, 1.621, -0.214 },
			},
			Torso = {
				mesh = 112295418933774,
				texture = 132102021024826,
				size = { 1.713, 2.67, 1.488 },
				offset = { -0.003, 4.429, 0.184 },
			},
		},
	},
	-- Porcelain-doll mother in a pastel apron (cute until she's seven studs tall and staring).
	Owner_Porcelain = {
		segments = {
			Head = {
				mesh = 104958993018837,
				texture = 71278882171449,
				size = { 3.652, 3.26, 3.712 },
				offset = { 0, 5.37, 0 },
			},
			LeftArm = {
				mesh = 110749841805422,
				texture = 73775461371615,
				size = { 1.341, 1.863, 0.843 },
				offset = { -1.12, 2.984, -0.025 },
			},
			LeftLeg = {
				mesh = 71130348538802,
				texture = 74368976385162,
				size = { 0.825, 1.259, 1.109 },
				offset = { -0.506, 0.63, -0.142 },
			},
			RightArm = {
				mesh = 123543190366510,
				texture = 104658756290541,
				size = { 1.351, 1.857, 0.844 },
				offset = { 1.136, 2.986, -0.023 },
			},
			RightLeg = {
				mesh = 137721741413418,
				texture = 112224228950265,
				size = { 0.837, 1.256, 1.107 },
				offset = { 0.522, 0.629, -0.143 },
			},
			Torso = {
				mesh = 91002167636443,
				texture = 118234033689624,
				size = { 3.341, 3.252, 3.36 },
				offset = { 0.003, 2.459, -0.022 },
			},
		},
	},
	-- Farmer with a stitched-smile burlap sack over his head.
	Owner_SackMask = {
		segments = {
			Head = {
				mesh = 105359789720848,
				texture = 77373882859376,
				size = { 1.995, 2.465, 2.078 },
				offset = { 0.001, 6.168, -0.022 },
			},
			LeftArm = {
				mesh = 88576839300805,
				texture = 80101832520321,
				size = { 1.87, 3.17, 1.417 },
				offset = { -1.459, 3.539, 0.014 },
			},
			LeftLeg = {
				mesh = 96609772083734,
				texture = 99839943364468,
				size = { 1.306, 3.559, 1.936 },
				offset = { -0.711, 1.779, -0.323 },
			},
			RightArm = {
				mesh = 95146457443273,
				texture = 109072782469680,
				size = { 1.874, 3.166, 1.416 },
				offset = { 1.456, 3.54, 0.018 },
			},
			RightLeg = {
				mesh = 131396305012145,
				texture = 103221292479402,
				size = { 1.311, 3.556, 1.94 },
				offset = { 0.71, 1.778, -0.328 },
			},
			Torso = {
				mesh = 122812084678709,
				texture = 71457627720093,
				size = { 2.59, 2.983, 2.572 },
				offset = { 0, 3.766, 0.013 },
			},
		},
	},
	-- Tall man in a funeral suit with a pale rotting jack-o'-lantern for a head.
	Owner_PumpkinSuit = {
		segments = {
			Head = {
				mesh = 95694271530851,
				texture = 134826226799668,
				size = { 2.754, 2.692, 2.792 },
				offset = { 0.007, 6.454, 0 },
			},
			LeftArm = {
				mesh = 136431682326805,
				texture = 71492688672043,
				size = { 1.164, 3.404, 1.116 },
				offset = { -1.353, 3.257, 0.054 },
			},
			LeftLeg = {
				mesh = 114289200693753,
				texture = 106666392147516,
				size = { 0.926, 2.443, 1.518 },
				offset = { -0.533, 1.222, -0.265 },
			},
			RightArm = {
				mesh = 122483700758947,
				texture = 92389267581650,
				size = { 1.152, 3.409, 1.115 },
				offset = { 1.359, 3.263, 0.058 },
			},
			RightLeg = {
				mesh = 114144296945236,
				texture = 70479603918428,
				size = { 0.931, 2.444, 1.527 },
				offset = { 0.534, 1.222, -0.265 },
			},
			Torso = {
				mesh = 128512953455585,
				texture = 92329933359203,
				size = { 1.925, 2.75, 1.592 },
				offset = { 0.003, 3.812, -0.067 },
			},
		},
	},
}

return characters
