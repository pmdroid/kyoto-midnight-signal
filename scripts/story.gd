extends RefCounted
## Deterministic opening progression, separate from rendering and input.
enum Phase { GREETING, HOLD_FIRST, FETCH_FIRST, RETURN_FIRST, OFFER_SECOND, HOLD_SECOND, FETCH_SECOND, STUCK, SEARCH, OFFER_ORB, HOLD_ORB, SIGNAL, LEASH, EXIT, COMPLETE }
var phase: Phase = Phase.GREETING
var seconds: float = 0.0
var pets: int = 0
var discoveries: Dictionary = {}

func change(next: Phase) -> void:
	phase = next
	seconds = 0.0

func milestone() -> int:
	if phase >= Phase.COMPLETE: return 5
	if phase >= Phase.EXIT: return 4
	if phase >= Phase.LEASH: return 3
	if phase >= Phase.OFFER_ORB: return 2
	if phase >= Phase.OFFER_SECOND: return 1
	return 0

func snapshot() -> Dictionary:
	var stable: int = phase
	match phase:
		Phase.FETCH_FIRST, Phase.RETURN_FIRST: stable = Phase.OFFER_SECOND
		Phase.FETCH_SECOND, Phase.SEARCH: stable = Phase.STUCK
		Phase.SIGNAL: stable = Phase.HOLD_ORB
	return {"version": 1, "phase": stable, "pets": pets, "discoveries": discoveries}

func restore(data: Dictionary) -> bool:
	if data.get("version") != 1: return false
	var value = data.get("phase", -1)
	if not (value is int or value is float): return false
	if int(value) < 0 or int(value) > Phase.COMPLETE: return false
	phase = int(value) as Phase
	seconds = 0.0
	pets = maxi(0, int(data.get("pets", 0)))
	var found = data.get("discoveries", {})
	discoveries = found if found is Dictionary else {}
	return true
