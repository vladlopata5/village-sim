extends "res://tests/test_textile_production.gd"
const Recipe=preload("res://scripts/production_recipe.gd")
func run() -> void:
	var place=B.new(&"planner",D.for_type(T.FOOD))
	var stock: RefCounted=place.consumable_stocks[&"fuel"]
	place.resources.add(R.MUSHROOM,2);place.resources.add(R.FLOUR,2)
	check(place.select_production_work().is_empty(),"Zero fuel blocks both otherwise-ready recipes")
	var selected: Dictionary=place.select_production_work("",Callable(),func(_key):return {"resource":R.LOG,"source":null})
	check(selected.get("kind")==&"SUPPLY" and selected.recipe_id==&"fried_mushroom","Generic stock shortage uses current recipe selection")
	var receiver: RefCounted=place.consumable_receivers[&"fuel"]
	receiver.reserve_in(R.LOG,1);receiver.add_reserved(R.LOG,1)
	var cursor: Dictionary=place._recipe_cursors.duplicate()
	check(place.select_production_work().recipe_id==&"fried_mushroom" and place.select_production_work().recipe_id==&"fried_mushroom" and cursor==place._recipe_cursors,"Repeated reads never rotate")
	var first=place.claim_production_work("first")
	check(first!=null and stock.amount==5 and stock.available()==4,"Unpaid process reserves one fuel")
	place.accept_production_batch(first)
	check(first.begin("first") and stock.amount==4,"Start pays once")
	first.release_worker("first")
	place.set_recipe_mode(&"bake_bread",B.ProductionMode.ORDER,2)
	check(place.select_production_work().kind==&"RESUME","Paid resume stays above ORDER")
	check(first.claim("second") and first.begin("second") and stock.amount==4,"Replacement keeps prior payment")
	first.advance("second",30);first.finish("second");place.retire_production_batch(first)
	var next=place.claim_production_work("cook")
	check(next.recipe_id==&"bake_bread","ORDER selected before unlimited mushroom")
	next.cancel();place.retire_production_batch(next)
	place.resources.try_take(R.FLOUR,2)
	selected=place.select_production_work("",func(_resource):return RefCounted.new())
	check(selected.kind==&"SUPPLY" and selected.recipe_id==&"bake_bread" and selected.resource==R.FLOUR,"ORDER SUPPLY stays above lower ready START")
	place.set_recipe_mode(&"bake_bread",B.ProductionMode.MAINTAIN,2)
	check(place.select_production_work().recipe_id==&"fried_mushroom","Unavailable higher recipe does not block runnable lower work")
	# Generic future factory: a recipe without this stock can run even when the stock is empty.
	var plain=Recipe.new({R.FLOUR:1},{R.BREAD:2},30,&"plain")
	place.definition.production_recipes.append(plain)
	place._recipe_settings[plain.id]={"mode":B.ProductionMode.UNLIMITED,"target":0,"produced":0,"revision":0,"order":false}
	place.resources.add(R.FLOUR,1);stock.amount=0
	check(place.select_production_work().recipe_id==&"plain","Fuel-free generic recipe remains runnable")
	place.definition.production_recipes.pop_back();place._recipe_settings.erase(plain.id)
	# One fuel is usable; no arbitrary refilling threshold.
	stock.amount=1
	var calls: Array=[]
	place.resources.try_take(R.MUSHROOM,2)
	selected=place.select_production_work("",func(_resource):return null,func(key):calls.append(key);return {})
	check(selected.kind==&"START" and selected.recipe_id==&"bake_bread" and calls.is_empty(),"One fuel starts ready recipe without self-supply")
	place.resources.add(R.BREAD,9)
	check(not place.can_start_production(&"bake_bread"),"One free output place cannot hold two bread")
	print("Consumable planner: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
