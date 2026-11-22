extends RefCounted
## Map coordinates are independent of the follow camera. Full maps never fit onscreen.
const TEXTURES = {
	"apartment": preload("res://assets/rooms/apartment.png"),
	"hallway": preload("res://assets/rooms/hallway.png"),
	"courtyard": preload("res://assets/rooms/courtyard.png")
}
const LABELS = {"apartment": "HOME / AFTER HOURS", "hallway": "THE SHARED HALL", "courtyard": "THE SLEEPING GARDEN"}
const APARTMENT_START = Vector2(540, 500)
const FIRST_FETCH = Vector2(952, 650)
const LOST_BALL = Vector2(386, 388)
const MONITOR = Vector2(474, 396)
const LEASH = Vector2(1420, 603)
const HOME_DOOR = Vector2(1370, 603)
const HALL_HOME = Vector2(237, 444)
const HALL_EXIT = Vector2(1346, 463)
const CART = Vector2(1152, 445)
const GARDEN_HOME = Vector2(177, 571)
const GREENHOUSE = Vector2(1145, 398)
const WORKBENCH = Vector2(1275, 320)

static func walkable(room: String, p: Vector2) -> bool:
	match room:
		"apartment":
			var inside := Rect2(145, 386, 1300, 500).has_point(p) or Rect2(556, 322, 400, 100).has_point(p) or Rect2(1219, 310, 200, 55).has_point(p) or Rect2(1219, 345, 25, 100).has_point(p)
			if not inside: return false
			for obstacle in [Rect2(90, 438, 249, 325), Rect2(195, 720, 177, 109), Rect2(74, 701, 129, 136), Rect2(953, 260, 257, 149), Rect2(1248, 341, 270, 224), Rect2(1117, 671, 371, 145), Rect2(337, 343, 108, 53)]:
				if obstacle.has_point(p): return false
			return true
		"hallway":
			if not Rect2(97, 416, 1360, 482).has_point(p): return false
			return not Rect2(60, 542, 310, 294).has_point(p) and not Rect2(1120, 615, 306, 221).has_point(p)
		"courtyard":
			var inside := Rect2(306, 370, 1125, 568).has_point(p) or Rect2(145, 523, 260, 82).has_point(p) or Rect2(423, 346, 250, 60).has_point(p) or Rect2(733, 249, 136, 155).has_point(p) or Rect2(185, 781, 220, 125).has_point(p)
			if not inside: return false
			for obstacle in [Rect2(557, 392, 436, 207), Rect2(1174, 500, 337, 324), Rect2(95, 608, 345, 170), Rect2(1000, 70, 445, 290)]:
				if obstacle.has_point(p): return false
			return true
	return false

static func objects(room: String) -> Array[Dictionary]:
	match room:
		"apartment": return [
			{"id":"moon_home","p":Vector2(1265,843),"verb":"Open the chest","type":"moon","hidden":false},
			{"id":"toy","p":Vector2(415,828),"verb":"Wind the little robot","type":"secret","hidden":false},
			{"id":"photo","p":Vector2(374,675),"verb":"Look under the blanket","type":"secret","hidden":true},
			{"id":"cell","p":WORKBENCH,"verb":"Search the workbench","type":"cell","hidden":false},
			{"id":"cup","p":Vector2(907,362),"verb":"Make a warm drink","type":"secret","hidden":false}
		]
		"hallway": return [
			{"id":"moon_hall","p":Vector2(1435,854),"verb":"Take the moon piece","type":"moon","hidden":true},
			{"id":"cassette","p":Vector2(825,435),"verb":"Check the washing machine","type":"secret","hidden":true},
			{"id":"mail","p":Vector2(526,434),"verb":"Open the old mailbox","type":"secret","hidden":false},
			{"id":"toolbox","p":Vector2(279,853),"verb":"Open the toolbox","type":"secret","hidden":false}
		]
		"courtyard": return [
			{"id":"moon_garden","p":Vector2(459,366),"verb":"Turn the sundial","type":"moon","hidden":false},
			{"id":"nest","p":Vector2(263,843),"verb":"Look behind the ivy","type":"secret","hidden":true},
			{"id":"seeds","p":Vector2(1335,845),"verb":"Open the garden box","type":"secret","hidden":false},
			{"id":"arch","p":Vector2(793,275),"verb":"Listen beyond the arch","type":"secret","hidden":false}
		]
	return []
