extends CharacterBody3D

signal died(points: int)

var target: Node3D
var health: int = 3
var speed: float = 0.8
var attack_distance: float = 1.25
var attack_damage: int = 8
var score_value: int = 100
var damage_callback: Callable
var attack_timer: float = 0.0
var dead := false

func setup(p_target: Node3D, p_health: int, p_speed: float, p_damage: int, p_points: int, p_callback: Callable) -> void:
	target = p_target
	health = p_health
	speed = p_speed
	attack_damage = p_damage
	score_value = p_points
	damage_callback = p_callback

func _physics_process(delta: float) -> void:
	if dead or target == null:
		return
	attack_timer = maxf(0.0, attack_timer - delta)
	var offset := target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance > attack_distance:
		if distance > 0.001:
			velocity = offset.normalized() * speed
			move_and_slide()
			var look_target := target.global_position
			look_target.y = global_position.y
			if global_position.distance_to(look_target) > 0.05:
				look_at(look_target, Vector3.UP)
	else:
		velocity = Vector3.ZERO
		if attack_timer <= 0.0:
			attack_timer = 1.15
			if damage_callback.is_valid():
				damage_callback.call(attack_damage)

func take_damage(amount: int) -> void:
	if dead:
		return
	health -= amount
	_flash_hit()
	if health <= 0:
		dead = true
		died.emit(score_value)
		queue_free()

func _flash_hit() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.material_override:
				var material := mesh_instance.material_override as StandardMaterial3D
				if material:
					material.emission_enabled = true
					material.emission = Color(1.0, 0.16, 0.08)
					material.emission_energy_multiplier = 2.2
	var timer := get_tree().create_timer(0.06)
	timer.timeout.connect(_clear_flash)

func _clear_flash() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.material_override:
				var material := mesh_instance.material_override as StandardMaterial3D
				if material:
					material.emission_enabled = false
