--!strict
-- Lives (PROMPT §V2.2/V2.3): you only die inside open houses. Each death costs a life and your
-- carried bucket. Out of lives: lose half your banked candy, then lives refill.
return {
	MAX = 3,
	REFILL_SECONDS = 20 * 60, -- one life back every 20 minutes (real time) up to MAX
	OUT_OF_LIVES_CANDY_LOSS = 0.5,
}
