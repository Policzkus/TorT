--!strict
-- Health (the user scrapped the three lives for it): everyone has MAX. The Knifer's knife takes
-- Knifer.DAMAGE a stab, so the second one kills you. A while after you were last hurt (REGEN.delay
-- seconds) it starts coming back, REGEN.rate a second. Down to nothing and you're dead: your bucket's
-- gone and you wake at the spawn with all of it back. (The old out-of-lives rule, half your banked
-- candy, went with the lives.)
return {
	MAX = 100,
	REGEN = { delay = 12, rate = 2.5 }, -- a stab's worth back in 20 s, from 12 s after it
	LOW = 35, -- under this the HUD's bar is red and the edges of your view pulse
}
