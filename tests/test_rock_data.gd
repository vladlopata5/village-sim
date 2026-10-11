extends SceneTree
const Rock = preload("res://scripts/rock_data.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var rock := Rock.new(&"test",Vector2.ZERO)
	check(rock.stock==10 and rock.initial_stock==10 and rock.work_required==60,"Default finite stock and work")
	check(rock.claim(&"a") and not rock.claim(&"b"),"Exclusive claim")
	check(rock.add_work(&"b",60)==0 and rock.work_done==0,"Nonowner cannot work")
	check(rock.add_work(&"a",17)==0 and rock.work_done==17,"Partial work produces no receipt")
	rock.release(&"b")
	check(rock.reservation_owner_id==&"a","Nonowner cannot release")
	rock.release(&"a")
	check(rock.work_done==17 and rock.claim(&"b"),"Partial survives release and transfer")
	check(rock.add_work(&"b",42)==0 and rock.work_done==59,"59 minutes is incomplete")
	check(rock.add_work(&"b",1)==1 and rock.stock==9 and rock.work_done==0 and rock.reservation_owner_id.is_empty(),"First receipt resets cycle and releases claim")
	check(rock.add_work(&"b",60)==0 and rock.stock==9,"Repeated completion cannot yield")
	for cycle in range(2,11):
		check(rock.claim(&"a") and rock.add_work(&"a",60)==cycle,"Unique receipt for each finite cycle")
	check(rock.stock==0 and rock.completed_cycles==10 and not rock.claim(&"a") and rock.add_work(&"a",60)==0,"Eleventh cycle forbidden")
	print("Rock data: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
