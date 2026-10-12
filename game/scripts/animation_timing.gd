extends RefCounted
## Only ambient loops are retimed. Scripted actions retain their original frame clock.

const NEUTRAL_HOLD := {
	"devil": 2.35, "abbot": 2.65, "alchemist": 2.25,
	"inquisitor": 2.85, "mon": 2.40, "monk": 2.55,
}


static func duration(sheet: String, animation: int, index: int, base: float) -> float:
	if sheet == "cow":
		return base * 1.55
	if sheet == "mon" and animation == 4:
		return base * 2.2 # Slow breathing while asleep; getting up remains responsive.
	if animation == 0 and index == 0 and NEUTRAL_HOLD.has(sheet):
		return NEUTRAL_HOLD[sheet]
	return base
