--!strict
-- The cars that drive down the streets now and then (Services/TrafficService decides, every client
-- draws them: Controllers/TrafficController). Nobody at the wheel: an old rusted sedan comes out of
-- the mist at one end of a street, headlights first, drives the length of it in the right-hand lane
-- and goes back into the mist at the other end, and a moment later (PAIR) another comes the other
-- way in the other lane, so they pass each other. Sometimes (LURK) that second one waits for you
-- instead: it comes the moment someone steps out into the road. Get hit and you're thrown,
-- ragdolled, and everything in your bucket is gone.
-- `pose` is shared so the server's hit check and every client's car are in the same place.

local Traffic = {
	EVERY = { 240, 360 }, -- seconds between cars down a street (the user: "every 5min or sum")
	FIRST = { 60, 150 }, -- seconds before a street's first car
	RETRY = { 20, 45 }, -- a car is due but nobody's on that street: look again in this long
	SPEED = { 60, 72 }, -- studs a second (half as fast again as it was, the user asked: 40-48)
	PAIR = { 0.5, 2 }, -- seconds after the first car that the one the other way comes out of the mist
	-- How often the one the other way waits (from PAIR[1] on) for someone to step into the road, and
	-- comes then; nobody does within `wait` seconds and it comes anyway.
	LURK = { chance = 0.35, wait = 12 },
	LANE = 5.5, -- studs out from the road's centre: the middle of the right-hand lane
	ENDS = 26, -- studs in from each end of the street where it comes out of the mist / goes back in
	FADE = 1.2, -- seconds it takes to come out of the mist and to go back in
	SOLID = 0.6, -- how far out of the mist before it can hit anyone (0..1)
	BODY = { halfWidth = 3.7, halfLength = 8.9, height = 5.6 }, -- the car's box round its pivot (on the road under its middle)
	PAD = 0.8, -- studs round the box that still count (the root part's own size)
	LAG = 0.1, -- seconds: the server sees players this far in the past, so it checks the car that far back too
	KNOCK = { forward = 0.6, up = 34, side = 14 }, -- the throw: share of the car's speed (as hard as before it got faster), then studs/s up and away
	DOWN = 3.2, -- seconds ragdolled
	HORN = { ahead = 90, wide = 6.5, gap = 1.6, most = 2 }, -- it honks at anyone in front of it, this far ahead (about 1.3 s) and this close to its line (the server decides: CarHonk)
}

export type Trip = {
	id: number,
	street: CFrame, -- the street's start: road centre, -Z down the street, +X to the right
	y: number, -- studs from street.Y up to the road's top
	length: number, -- studs, the street's length
	dir: number, -- 1 down the street, -1 back up it toward its gate
	speed: number, -- studs a second
	startAt: number, -- server time (Workspace:GetServerTimeNow()) it comes out of the mist
	seed: number, -- everything left to chance about it (the headlights' flicker, the engine) is this, on every client
}

-- Seconds from coming out of the mist to being gone.
function Traffic.duration(trip: Trip): number
	return (trip.length - 2 * Traffic.ENDS) / trip.speed
end

-- Where the car is `t` seconds into its trip (its pivot: on the road under its middle, facing the
-- way it's going), and how many studs it has driven.
function Traffic.pose(trip: Trip, t: number): (CFrame, number)
	local driven = math.clamp(t, 0, Traffic.duration(trip)) * trip.speed
	local z = if trip.dir > 0 then Traffic.ENDS + driven else trip.length - Traffic.ENDS - driven
	local function point(at: number): Vector3
		return (trip.street * CFrame.new(trip.dir * Traffic.LANE, trip.y, -at)).Position
	end
	local here = point(z)
	return CFrame.lookAt(here, point(z + trip.dir * 2), trip.street.UpVector), driven
end

-- 0..1, how far out of the mist it is: it fades in at one end and away at the other.
function Traffic.presence(trip: Trip, t: number): number
	return math.clamp(math.min(t, Traffic.duration(trip) - t) / Traffic.FADE, 0, 1)
end

return Traffic
