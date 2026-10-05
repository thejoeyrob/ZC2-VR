extends Node3D

const ZOMBIE_SCRIPT := preload("res://game/zombie.gd")
const MAG_CAPACITY := 30
const MOVE_SPEED := 2.15
const SNAP_DEGREES := 30.0

var xr_interface: XRInterface
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var left_hand: XRController3D
var right_hand: XRController3D

var weapon: Node3D
var muzzle: Marker3D
var support_grip: Marker3D
var magwell: Marker3D
var charging_point: Marker3D
var charging_handle: MeshInstance3D
var weapon_mag: MeshInstance3D
var muzzle_flash: MeshInstance3D

var scope_rear: Marker3D
var scope_camera_mount: Marker3D
var scope_viewport: SubViewport
var scope_camera: Camera3D
var scope_lens: MeshInstance3D
var scope_material: StandardMaterial3D
var scope_fovs := [28.0, 18.0, 11.0]
var scope_index := 1
var scope_active := false

var hud: Label3D
var status_label: Label3D
var wave_label: Label3D

var ammo := MAG_CAPACITY
var reserve_mags := 5
var mag_inserted := true
var needs_charge := false
var held_mag: MeshInstance3D
var held_mag_fresh := false
var removing_mag := false
var charging := false
var charging_start_z := 0.0
var charge_pull := 0.0
var two_hand := false

var prev_trigger := 0.0
var prev_left_grip := 0.0
var prev_a := false
var prev_b := false
var snap_latched := false
var recoil_pitch := 0.0
var muzzle_flash_time := 0.0

var score := 0
var health := 100
var wave := 0
var enemies_alive := 0
var next_wave_pending := false
var game_over := false

func _ready() -> void:
	_build_environment()
	_build_player()
	_build_weapon()
	_build_scope()
	_initialize_openxr()
	_start_next_wave()
	_update_hud()

func _initialize_openxr() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.initialize():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	else:
		get_viewport().use_xr = false
		xr_camera.position = Vector3(0.0, 1.65, 4.0)
		xr_camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.018, 0.014, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.18, 0.35)
	env.ambient_light_energy = 1.3
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

	_add_box(Vector3(18.0, 0.12, 18.0), Vector3(0.0, -0.06, -3.0), Color(0.055, 0.045, 0.075))
	_add_box(Vector3(18.0, 2.4, 0.18), Vector3(0.0, 1.2, -12.0), Color(0.09, 0.045, 0.13))
	_add_box(Vector3(0.18, 2.4, 18.0), Vector3(-9.0, 1.2, -3.0), Color(0.045, 0.055, 0.11))
	_add_box(Vector3(0.18, 2.4, 18.0), Vector3(9.0, 1.2, -3.0), Color(0.045, 0.055, 0.11))

	for i in range(8):
		var x := -7.0 + float(i) * 2.0
		_add_emissive_post(Vector3(x, 1.0, -8.0 - float(i % 2) * 1.8), Color(0.18, 0.75, 1.0) if i % 2 == 0 else Color(0.82, 0.18, 1.0))

	var title := Label3D.new()
	title.text = "ZC2 // VR ARENA"
	title.font_size = 96
	title.outline_size = 10
	title.modulate = Color(0.7, 0.95, 1.0)
	title.position = Vector3(0.0, 3.2, -11.75)
	title.pixel_size = 0.0035
	add_child(title)

func _build_player() -> void:
	xr_origin = XROrigin3D.new()
	xr_origin.name = "XROrigin"
	add_child(xr_origin)

	xr_camera = XRCamera3D.new()
	xr_camera.name = "Head"
	xr_camera.current = true
	xr_origin.add_child(xr_camera)

	left_hand = XRController3D.new()
	left_hand.name = "LeftHand"
	left_hand.tracker = &"left_hand"
	left_hand.pose = &"aim"
	xr_origin.add_child(left_hand)

	right_hand = XRController3D.new()
	right_hand.name = "RightHand"
	right_hand.tracker = &"right_hand"
	right_hand.pose = &"aim"
	xr_origin.add_child(right_hand)

	_add_controller_visual(left_hand, Color(0.18, 0.65, 1.0))
	_add_controller_visual(right_hand, Color(0.9, 0.25, 0.72))

	hud = Label3D.new()
	hud.position = Vector3(0.0, -0.28, -1.1)
	hud.font_size = 54
	hud.outline_size = 8
	hud.pixel_size = 0.0024
	hud.modulate = Color(0.92, 0.96, 1.0)
	xr_camera.add_child(hud)

	status_label = Label3D.new()
	status_label.position = Vector3(0.0, -0.40, -1.08)
	status_label.font_size = 34
	status_label.outline_size = 7
	status_label.pixel_size = 0.0024
	status_label.modulate = Color(0.62, 0.95, 0.78)
	xr_camera.add_child(status_label)

	wave_label = Label3D.new()
	wave_label.position = Vector3(0.0, 0.34, -1.35)
	wave_label.font_size = 48
	wave_label.outline_size = 8
	wave_label.pixel_size = 0.0025
	wave_label.modulate = Color(0.95, 0.72, 0.24)
	xr_camera.add_child(wave_label)

func _build_weapon() -> void:
	weapon = Node3D.new()
	weapon.name = "ZC2Rifle"
	add_child(weapon)

	_add_mesh_box(weapon, Vector3(0.095, 0.13, 0.52), Vector3(0.0, -0.025, -0.25), Color(0.08, 0.07, 0.095), 0.2)
	_add_mesh_box(weapon, Vector3(0.075, 0.085, 0.36), Vector3(0.0, 0.055, -0.56), Color(0.12, 0.10, 0.15), 0.1)
	_add_mesh_box(weapon, Vector3(0.055, 0.20, 0.16), Vector3(0.0, -0.12, -0.08), Color(0.07, 0.055, 0.09), 0.1)
	_add_mesh_box(weapon, Vector3(0.055, 0.055, 0.48), Vector3(0.0, 0.0, -0.73), Color(0.05, 0.05, 0.065), 0.1)

	var accent := _add_mesh_box(weapon, Vector3(0.101, 0.025, 0.30), Vector3(0.0, 0.052, -0.29), Color(0.55, 0.10, 0.78), 2.5)
	var accent_mat := accent.material_override as StandardMaterial3D
	accent_mat.emission_enabled = true
	accent_mat.emission = Color(0.38, 0.04, 0.72)
	accent_mat.emission_energy_multiplier = 1.5

	weapon_mag = _add_mesh_box(weapon, Vector3(0.075, 0.22, 0.10), Vector3(0.0, -0.17, -0.22), Color(0.16, 0.14, 0.19), 0.15)
	weapon_mag.rotation_degrees.x = -8.0

	muzzle = Marker3D.new()
	muzzle.position = Vector3(0.0, 0.0, -0.99)
	weapon.add_child(muzzle)

	support_grip = Marker3D.new()
	support_grip.position = Vector3(0.0, -0.055, -0.52)
	weapon.add_child(support_grip)

	magwell = Marker3D.new()
	magwell.position = Vector3(0.0, -0.14, -0.20)
	weapon.add_child(magwell)

	charging_point = Marker3D.new()
	charging_point.position = Vector3(0.075, 0.045, -0.20)
	weapon.add_child(charging_point)

	charging_handle = _add_mesh_box(weapon, Vector3(0.065, 0.025, 0.055), charging_point.position, Color(0.74, 0.55, 0.12), 0.2)

	muzzle_flash = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.045
	flash_mesh.height = 0.09
	muzzle_flash.mesh = flash_mesh
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1.0, 0.63, 0.18)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.35, 0.04)
	flash_mat.emission_energy_multiplier = 4.0
	muzzle_flash.material_override = flash_mat
	muzzle_flash.position = muzzle.position
	muzzle_flash.visible = false
	weapon.add_child(muzzle_flash)

	var logo := Label3D.new()
	logo.text = "ZC2"
	logo.font_size = 64
	logo.pixel_size = 0.0007
	logo.modulate = Color(0.95, 0.78, 0.22)
	logo.position = Vector3(0.051, 0.01, -0.25)
	logo.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	weapon.add_child(logo)

func _build_scope() -> void:
	_add_mesh_box(weapon, Vector3(0.11, 0.09, 0.33), Vector3(0.0, 0.14, -0.38), Color(0.035, 0.035, 0.05), 0.1)

	scope_rear = Marker3D.new()
	scope_rear.position = Vector3(0.0, 0.14, -0.21)
	weapon.add_child(scope_rear)

	scope_camera_mount = Marker3D.new()
	scope_camera_mount.position = Vector3(0.0, 0.14, -0.42)
	weapon.add_child(scope_camera_mount)

	scope_viewport = SubViewport.new()
	scope_viewport.name = "ScopeViewport"
	scope_viewport.size = Vector2i(512, 512)
	scope_viewport.msaa_3d = Viewport.MSAA_2X
	scope_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	scope_viewport.world_3d = get_viewport().world_3d
	add_child(scope_viewport)

	scope_camera = Camera3D.new()
	scope_camera.fov = scope_fovs[scope_index]
	scope_camera.near = 0.04
	scope_camera.far = 120.0
	scope_camera.current = true
	scope_viewport.add_child(scope_camera)

	scope_lens = MeshInstance3D.new()
	var lens_mesh := QuadMesh.new()
	lens_mesh.size = Vector2(0.084, 0.084)
	scope_lens.mesh = lens_mesh
	scope_lens.position = Vector3(0.0, 0.14, -0.205)
	scope_lens.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	scope_material = StandardMaterial3D.new()
	scope_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	scope_material.albedo_color = Color(0.015, 0.025, 0.035)
	scope_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	scope_lens.material_override = scope_material
	weapon.add_child(scope_lens)

	var reticle_layer := CanvasLayer.new()
	scope_viewport.add_child(reticle_layer)
	var h := ColorRect.new()
	h.color = Color(0.9, 0.12, 0.12, 0.9)
	h.position = Vector2(196, 255)
	h.size = Vector2(120, 2)
	reticle_layer.add_child(h)
	var v := ColorRect.new()
	v.color = Color(0.9, 0.12, 0.12, 0.9)
	v.position = Vector2(255, 196)
	v.size = Vector2(2, 120)
	reticle_layer.add_child(v)
	var dot := ColorRect.new()
	dot.color = Color(1.0, 0.72, 0.12, 1.0)
	dot.position = Vector2(252, 252)
	dot.size = Vector2(8, 8)
	reticle_layer.add_child(dot)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.043
	ring.outer_radius = 0.052
	var ring_instance := MeshInstance3D.new()
	ring_instance.mesh = ring
	ring_instance.position = Vector3(0.0, 0.14, -0.202)
	ring_instance.rotation_degrees.x = 90.0
	ring_instance.material_override = _material(Color(0.1, 0.11, 0.14), 0.0)
	weapon.add_child(ring_instance)

func _process(delta: float) -> void:
	_update_locomotion(delta)
	_update_weapon_pose()
	_update_scope()
	_update_reload_interactions()
	_update_weapon_input()
	_update_fx(delta)
	_update_hud()

func _update_locomotion(delta: float) -> void:
	if game_over:
		return
	var stick := left_hand.get_vector2(&"primary")
	if stick.length() > 0.12:
		var forward := -xr_camera.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right_vec := xr_camera.global_transform.basis.x
		right_vec.y = 0.0
		right_vec = right_vec.normalized()
		var move := forward * -stick.y + right_vec * stick.x
		if move.length() > 1.0:
			move = move.normalized()
		xr_origin.global_position += move * MOVE_SPEED * delta

	var turn := right_hand.get_vector2(&"primary")
	if absf(turn.x) > 0.72 and not snap_latched:
		snap_latched = true
		_snap_turn(-SNAP_DEGREES * signf(turn.x))
	elif absf(turn.x) < 0.25:
		snap_latched = false

func _snap_turn(degrees: float) -> void:
	var before := xr_camera.global_position
	xr_origin.rotate_y(deg_to_rad(degrees))
	var after := xr_camera.global_position
	xr_origin.global_position += before - after

func _update_weapon_pose() -> void:
	if not right_hand.get_is_active():
		return
	weapon.global_transform = right_hand.global_transform
	if two_hand and left_hand.get_is_active() and weapon.global_position.distance_to(left_hand.global_position) > 0.08:
		weapon.look_at(left_hand.global_position, Vector3.UP)

	if recoil_pitch > 0.001:
		weapon.rotate_object_local(Vector3.RIGHT, deg_to_rad(-recoil_pitch))

func _update_weapon_input() -> void:
	var trigger := right_hand.get_float(&"trigger")
	var a_pressed := right_hand.is_button_pressed(&"ax_button")
	var b_pressed := right_hand.is_button_pressed(&"by_button")

	if game_over:
		if b_pressed and not prev_b:
			_restart_game()
		prev_trigger = trigger
		prev_a = a_pressed
		prev_b = b_pressed
		return

	if trigger > 0.72 and prev_trigger <= 0.72:
		_fire()

	if a_pressed and not prev_a:
		scope_index = (scope_index + 1) % scope_fovs.size()
		scope_camera.fov = scope_fovs[scope_index]
		right_hand.trigger_haptic_pulse(&"haptic", 0.0, 0.35, 0.035, 0.0)

	prev_trigger = trigger
	prev_a = a_pressed
	prev_b = b_pressed

func _fire() -> void:
	if not mag_inserted:
		_status_pulse("NO MAG — GRAB ONE AT LEFT HIP")
		return
	if needs_charge:
		_status_pulse("RACK CHARGING HANDLE")
		return
	if ammo <= 0:
		_status_pulse("MAG EMPTY — PULL IT OUT")
		return

	ammo -= 1
	recoil_pitch = 2.2 if two_hand else 4.4
	muzzle_flash_time = 0.045
	muzzle_flash.visible = true
	right_hand.trigger_haptic_pulse(&"haptic", 0.0, 0.72 if two_hand else 0.9, 0.055, 0.0)

	var from := muzzle.global_position
	var direction := -muzzle.global_transform.basis.z
	var to := from + direction * 85.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider = hit.get("collider")
		if collider and collider.has_method("take_damage"):
			collider.take_damage(2 if two_hand else 1)
			score += 15
			_status_pulse("HIT +15")

func _update_reload_interactions() -> void:
	var grip := left_hand.get_float(&"grip")
	var just_pressed := grip > 0.62 and prev_left_grip <= 0.62
	var just_released := grip < 0.35 and prev_left_grip >= 0.35

	if just_pressed and left_hand.get_is_active():
		_begin_left_hand_interaction()

	if removing_mag and grip > 0.35:
		if left_hand.global_position.distance_to(magwell.global_position) > 0.14:
			removing_mag = false
			mag_inserted = false
			ammo = 0
			weapon_mag.visible = false
			_make_held_mag(false)
			left_hand.trigger_haptic_pulse(&"haptic", 0.0, 0.6, 0.045, 0.0)
			_status_pulse("EMPTY MAG REMOVED")

	if charging and grip > 0.35:
		var local_hand := weapon.to_local(left_hand.global_position)
		charge_pull = maxf(0.0, local_hand.z - charging_start_z)
		charging_handle.position.z = charging_point.position.z + clampf(charge_pull, 0.0, 0.09)

	if just_released:
		if held_mag:
			_finish_mag_hold()
		if charging:
			_finish_charge()
		removing_mag = false
		two_hand = false

	prev_left_grip = grip

func _begin_left_hand_interaction() -> void:
	var hand_pos := left_hand.global_position
	if mag_inserted and hand_pos.distance_to(magwell.global_position) < 0.16:
		removing_mag = true
		two_hand = false
		_status_pulse("PULL MAG DOWN")
		return

	if needs_charge and hand_pos.distance_to(charging_point.global_position) < 0.16:
		charging = true
		charging_start_z = weapon.to_local(hand_pos).z
		charge_pull = 0.0
		two_hand = false
		_status_pulse("PULL HANDLE BACK")
		return

	if not mag_inserted and reserve_mags > 0 and hand_pos.distance_to(_mag_pouch_position()) < 0.24:
		reserve_mags -= 1
		_make_held_mag(true)
		_status_pulse("FRESH MAG — INSERT INTO RIFLE")
		return

	if hand_pos.distance_to(support_grip.global_position) < 0.28:
		two_hand = true
		left_hand.trigger_haptic_pulse(&"haptic", 0.0, 0.28, 0.03, 0.0)
		_status_pulse("TWO-HAND STABILIZED")

func _make_held_mag(fresh: bool) -> void:
	if held_mag:
		held_mag.queue_free()
	held_mag_fresh = fresh
	held_mag = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.07, 0.20, 0.10)
	held_mag.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.16, 0.22) if fresh else Color(0.08, 0.07, 0.09)
	if fresh:
		mat.emission_enabled = true
		mat.emission = Color(0.12, 0.35, 0.75)
		mat.emission_energy_multiplier = 0.8
	held_mag.material_override = mat
	left_hand.add_child(held_mag)
	held_mag.position = Vector3(0.0, -0.04, -0.075)
	held_mag.rotation_degrees.x = -12.0

func _finish_mag_hold() -> void:
	var close_to_well := held_mag_fresh and not mag_inserted and left_hand.global_position.distance_to(magwell.global_position) < 0.14
	if close_to_well:
		mag_inserted = true
		ammo = MAG_CAPACITY
		needs_charge = true
		weapon_mag.visible = true
		left_hand.trigger_haptic_pulse(&"haptic", 0.0, 0.75, 0.06, 0.0)
		_status_pulse("MAG SEATED — RACK HANDLE")
	else:
		_status_pulse("MAG DROPPED")
	held_mag.queue_free()
	held_mag = null
	held_mag_fresh = false

func _finish_charge() -> void:
	charging = false
	charging_handle.position = charging_point.position
	if charge_pull >= 0.065 and mag_inserted and ammo > 0:
		needs_charge = false
		left_hand.trigger_haptic_pulse(&"haptic", 0.0, 0.85, 0.055, 0.0)
		_status_pulse("CHAMBERED")
	else:
		_status_pulse("PULL HANDLE FURTHER")
	charge_pull = 0.0

func _mag_pouch_position() -> Vector3:
	var side := -xr_camera.global_transform.basis.x.normalized() * 0.22
	var forward := -xr_camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() > 0.01:
		forward = forward.normalized() * 0.10
	return xr_camera.global_position + side + forward + Vector3(0.0, -0.50, 0.0)

func _update_scope() -> void:
	if scope_camera == null:
		return
	scope_camera.global_transform = scope_camera_mount.global_transform

	var to_head := xr_camera.global_position - scope_rear.global_position
	var distance := to_head.length()
	var rear_axis := scope_rear.global_transform.basis.z.normalized()
	var alignment := 0.0
	if distance > 0.001:
		alignment = rear_axis.dot(to_head.normalized())

	var should_activate := distance > 0.055 and distance < 0.27 and alignment > 0.82
	if should_activate != scope_active:
		scope_active = should_activate
		if scope_active:
			scope_material.albedo_texture = scope_viewport.get_texture()
			scope_material.albedo_color = Color.WHITE
			scope_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		else:
			scope_material.albedo_texture = null
			scope_material.albedo_color = Color(0.005, 0.008, 0.012)
			scope_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _update_fx(delta: float) -> void:
	recoil_pitch = move_toward(recoil_pitch, 0.0, delta * 28.0)
	if muzzle_flash_time > 0.0:
		muzzle_flash_time -= delta
		if muzzle_flash_time <= 0.0:
			muzzle_flash.visible = false

func _start_next_wave() -> void:
	if game_over:
		return
	wave += 1
	next_wave_pending = false
	var boss_wave := wave % 5 == 0
	if boss_wave:
		_spawn_zombie(Vector3(0.0, 0.0, -9.5), true, 0)
	else:
		var count := mini(3 + wave, 9)
		for i in range(count):
			var spread := float(i) - float(count - 1) * 0.5
			var z := -7.0 - float((i + wave) % 3) * 1.35
			_spawn_zombie(Vector3(spread * 1.35, 0.0, z), false, i)
	wave_label.text = "WAVE %d%s" % [wave, " // DR MANTIS" if boss_wave else ""]

func _spawn_zombie(pos: Vector3, boss: bool, variant: int) -> void:
	var zombie = CharacterBody3D.new()
	zombie.set_script(ZOMBIE_SCRIPT)
	zombie.position = pos
	add_child(zombie)

	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34 if not boss else 0.55
	shape.height = 1.55 if not boss else 2.15
	collider.shape = shape
	collider.position.y = 0.82 if not boss else 1.08
	zombie.add_child(collider)

	var palette := [
		Color(0.22, 0.62, 0.22),
		Color(0.42, 0.20, 0.55),
		Color(0.16, 0.48, 0.42),
		Color(0.50, 0.31, 0.16)
	]
	var body_color: Color = Color(0.16, 0.72, 0.25) if boss else palette[variant % palette.size()]
	_add_mesh_box(zombie, Vector3(0.55, 0.78, 0.30) if not boss else Vector3(0.85, 1.05, 0.44), Vector3(0.0, 0.88 if not boss else 1.2, 0.0), body_color, 0.1)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.25 if not boss else 0.38
	head_mesh.height = 0.48 if not boss else 0.72
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.48 if not boss else 2.05, 0.0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = body_color.lightened(0.08)
	head.material_override = head_mat
	zombie.add_child(head)

	for eye_x in [-0.085, 0.085]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.035 if not boss else 0.052
		eye_mesh.height = 0.065 if not boss else 0.095
		eye.mesh = eye_mesh
		eye.position = Vector3(eye_x * (1.3 if boss else 1.0), 1.53 if not boss else 2.12, -0.225 if not boss else -0.34)
		var eye_mat := StandardMaterial3D.new()
		eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		eye_mat.albedo_color = Color(0.86, 0.12, 1.0) if not boss else Color(1.0, 0.82, 0.08)
		eye_mat.emission_enabled = true
		eye_mat.emission = eye_mat.albedo_color
		eye_mat.emission_energy_multiplier = 2.5
		eye.material_override = eye_mat
		zombie.add_child(eye)

	if boss:
		var nameplate := Label3D.new()
		nameplate.text = "DR MANTIS // STAGE 1"
		nameplate.font_size = 48
		nameplate.outline_size = 8
		nameplate.pixel_size = 0.002
		nameplate.position = Vector3(0.0, 2.65, 0.0)
		nameplate.modulate = Color(0.75, 1.0, 0.18)
		zombie.add_child(nameplate)
		for spike_x in [-0.28, 0.0, 0.28]:
			var spike := MeshInstance3D.new()
			var spike_mesh := CylinderMesh.new()
			spike_mesh.top_radius = 0.0
			spike_mesh.bottom_radius = 0.06
			spike_mesh.height = 0.32
			spike.mesh = spike_mesh
			spike.position = Vector3(spike_x, 2.48, 0.0)
			spike.material_override = _material(Color(0.78, 0.92, 0.14), 1.2)
			zombie.add_child(spike)

	enemies_alive += 1
	zombie.died.connect(_on_zombie_died)
	var hp := 18 + wave * 2 if boss else 2 + int(wave / 3)
	var enemy_speed := 0.46 + minf(float(wave) * 0.045, 0.48)
	zombie.setup(xr_camera, hp, enemy_speed if not boss else enemy_speed * 0.72, 14 if boss else 7, 1200 if boss else 100, Callable(self, "_player_hit"))

func _on_zombie_died(points: int) -> void:
	score += points
	enemies_alive = maxi(0, enemies_alive - 1)
	if enemies_alive == 0 and not next_wave_pending and not game_over:
		next_wave_pending = true
		wave_label.text = "WAVE CLEAR"
		var timer := get_tree().create_timer(2.0)
		timer.timeout.connect(_start_next_wave)

func _player_hit(damage: int) -> void:
	if game_over:
		return
	health = maxi(0, health - damage)
	left_hand.trigger_haptic_pulse(&"haptic", 0.0, 0.55, 0.06, 0.0)
	right_hand.trigger_haptic_pulse(&"haptic", 0.0, 0.55, 0.06, 0.0)
	_status_pulse("HIT -%d HP" % damage)
	if health <= 0:
		game_over = true
		wave_label.text = "ZC2 DOWN // PRESS B TO RESTART"

func _restart_game() -> void:
	for child in get_children():
		if child is CharacterBody3D and child.get_script() == ZOMBIE_SCRIPT:
			child.queue_free()
	score = 0
	health = 100
	wave = 0
	enemies_alive = 0
	game_over = false
	next_wave_pending = false
	ammo = MAG_CAPACITY
	reserve_mags = 5
	mag_inserted = true
	needs_charge = false
	weapon_mag.visible = true
	_start_next_wave()

func _update_hud() -> void:
	hud.text = "HP %03d   SCORE %06d   AMMO %02d/%02d   MAGS %d" % [health, score, ammo, MAG_CAPACITY, reserve_mags]
	if game_over:
		status_label.text = "B = RESTART"
	elif not mag_inserted:
		status_label.text = "RELOAD: GRAB FRESH MAG FROM LEFT HIP"
	elif needs_charge:
		status_label.text = "RELOAD: GRIP + PULL CHARGING HANDLE"
	elif ammo == 0:
		status_label.text = "EMPTY: GRIP MAG + PULL IT OUT"
	elif two_hand:
		status_label.text = "TWO-HAND GRIP // A: SCOPE %sx" % _scope_text()
	else:
		status_label.text = "LEFT GRIP FORE-END TO STABILIZE // A: SCOPE %sx" % _scope_text()

func _scope_text() -> String:
	return ["2", "4", "6"][scope_index]

func _status_pulse(message: String) -> void:
	status_label.text = message

func _add_controller_visual(parent: Node3D, color: Color) -> void:
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.055, 0.10, 0.14)
	body.mesh = mesh
	body.position = Vector3(0.0, -0.035, -0.04)
	body.material_override = _material(color, 0.25)
	parent.add_child(body)

func _add_box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color, 0.05)
	body.add_child(mesh_instance)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	return mesh_instance

func _add_emissive_post(pos: Vector3, color: Color) -> void:
	var post := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 2.0, 0.08)
	post.mesh = mesh
	post.position = pos
	var mat := _material(color, 2.0)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.8
	post.material_override = mat
	add_child(post)

func _add_mesh_box(parent: Node, size: Vector3, pos: Vector3, color: Color, emission_strength: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = _material(color, emission_strength)
	parent.add_child(instance)
	return instance

func _material(color: Color, emission_strength: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.12
	mat.roughness = 0.48
	if emission_strength > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission_strength
	return mat
