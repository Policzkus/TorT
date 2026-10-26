--!strict
-- Health (the user scrapped the three lives for it): everyone has MAX. The Knifer's knife takes
-- Knifer.DAMAGE a stab, so the second one kills you. It doesn't come back by itself (the user): a
-- bandage from the seller does (Config/Items). Down to nothing and you're dead: your bucket's gone
-- and you wake at the spawn with all of it back. (The old out-of-lives rule, half your banked candy,
-- went with the lives.)
return {
	MAX = 100,
	LOW = 35, -- under this the HUD's bar is red and the edges of your view pulse
}
