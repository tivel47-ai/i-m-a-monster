# Focused recovery regressions; production guard implementation is unchanged.
extends "res://tests/simulation_map_validation.gd"

var guards: Array[Node]=[]

func fixture() -> void:
	seed(4405)
	map=load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	units=get_nodes_in_group("player_units")
	reset_units(Vector2(100,100))
	for unit in units:
		unit.get_node("AggroArea").monitoring=false
		unit.aggro_candidates.clear()
	guards.clear()
	for actor in map.villagers:
		actor.autonomous_movement_enabled=actor.guard_patrol!=null
		if actor.guard_patrol!=null:
			actor.threat_detection.detection_enabled=false
			guards.append(actor)
	for index in range(59): map.get_node("ActivityZones").get_child(index)._random.seed=440500+index
	await frames(5)

func wait_for_state(mode: int, excluded_id: int=0, seconds: int=600) -> Node:
	for tick in range(seconds*2):
		for actor in guards:
			if is_instance_valid(actor) and actor.get_instance_id()!=excluded_id and actor.is_available_for_infection() and actor.guard_patrol.state==mode: return actor
		await frames(30)
	return null

func run() -> void:
	for interruption in ["death","conversion","combat","incoming_death"]:
		await fixture()
		var stationed: Node=await wait_for_state(4,0,30)
		check(stationed!=null,"Initial actual sentry reaches post: "+interruption)
		if stationed==null:
			map.queue_free()
			await frames(3)
			continue
		var victim: Node=stationed
		if interruption=="incoming_death":
			victim=await wait_for_state(3)
			check(victim!=null,"A real relief physically starts its post approach")
			if victim==null:
				map.queue_free()
				await frames(3)
				continue
			# The incumbent may have changed while waiting for a completed patrol circuit.
			stationed=await wait_for_state(4,0,2)
		var victim_id: int=victim.get_instance_id()
		var visit_baseline := {}
		for actor in guards: visit_baseline[actor.get_instance_id()]=actor.guard_patrol.post_visits
		if interruption in ["death","incoming_death"]:
			victim.take_damage(1000)
		else:
			var enemy=load("res://scenes/zombie.tscn").instantiate()
			enemy.position=victim.position+Vector2(20,0)
			map.add_child(enemy)
			enemy.set_physics_process(false)
			enemy.navigation_agent.avoidance_enabled=false
			victim.begin_encounter(Color.GREEN,enemy)
			if interruption=="conversion": victim.receive_zombie_attack(20,1.0,enemy)
			await frames(60)
			check(victim.guard_patrol.state==0 and not victim.has_destination,"Unavailable sentry releases its duty state: "+interruption)
			victim.leave_encounter(enemy)
			enemy.queue_free()
			if interruption=="conversion":
				await frames(150)
				# The newly converted playable zombie must not attack the next sentry.
				units=get_nodes_in_group("player_units")
				reset_units(Vector2(100,100))
				for unit in units:
					unit.get_node("AggroArea").monitoring=false
					unit.aggro_candidates.clear()
		if interruption=="incoming_death":
			await frames(60)
			check(is_instance_valid(stationed) and stationed.guard_patrol.state==4,"Death of incoming relief does not dismiss the incumbent")
		var recovered: Node=await wait_for_state(4,victim_id)
		check(recovered!=null,"Another living guard occupies post after interruption: "+interruption)
		var rotated:=false
		var peak:=0
		for tick in range(1200): # At most another 600 s, until a new actual duty arrival.
			var near:=0
			var new_arrival:=false
			for actor in guards:
				if not is_instance_valid(actor) or not actor.is_available_for_infection(): continue
				if actor.guard_patrol.is_near_post(): near+=1
				new_arrival=new_arrival or actor.guard_patrol.post_visits>visit_baseline[actor.get_instance_id()]
			peak=maxi(peak,near)
			if new_arrival:
				rotated=true
				break
			await frames(30)
		check(rotated and peak<=2,"Actual relief rotation recovers without a permanent claim or clustering: "+interruption+" peak="+str(peak))
		if interruption=="conversion": check(map.infected_residents==1,"Duty sentry conversion keeps single mission accounting")
		map.queue_free()
		await frames(3)
	print("Guard duty recovery validation failures: ",failures)
	quit(1 if failures else 0)
