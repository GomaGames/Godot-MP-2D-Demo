extends KinematicBody2D

const PlayerHurtSound = preload("res://Player/PlayerHurtSound.tscn")

export onready var ACCELERATION = 500
export onready var MAX_SPEED = 80
export onready var ROLL_SPEED = 120
export onready var FRICTION = 500

enum {
	MOVE,
	ROLL,
	ATTACK
}

var state = MOVE
var velocity = Vector2.ZERO
var roll_vector = Vector2.DOWN
var stats = PlayerStats

var last_position := Vector2.ZERO
var last_motion := Vector2.ZERO
var last_rotation := Vector2.ZERO
var last_input := Vector2.ZERO
# from network
var next_position := Vector2.ZERO
var next_rotation := Vector2.ZERO
var next_input := Vector2.ZERO
var move_speed := 0

export var username := "User"
export var user_id := ""

onready var animationPlayer = $AnimationPlayer
onready var animationTree = $AnimationTree
onready var animationState = animationTree.get("parameters/playback")
onready var swordHitbox = $HitboxPivot/SwordHitbox
onready var hurtbox = $Hurtbox
onready var blinkAnimationPlayer = $BlinkAnimationPlayer
onready var tween = $Tween


func _ready():
	randomize()
	stats.connect("no_health", self, "queue_free")
	animationTree.active = true
	swordHitbox.knockback_vector = roll_vector

func _physics_process(delta):
	match state:
		MOVE:
			move_state(delta)

		ROLL:
			roll_state()

		ATTACK:
			attack_state()

func is_local_player() -> bool:
	return user_id == Network.get_user_id()

# from network
func update_state() -> void:
	if last_position != next_position:
		tween.interpolate_method(self, "do_state_update_move", position, next_position, 0.12)
		tween.start()

	last_position = next_position

	# not in use
	# if last_input != next_input:
	# 	pass
	# last_input = next_input


# uses network send_position_update tranform
func do_state_update_move(new_position: Vector2) -> void:
	position = new_position

func despawn() -> void:
	queue_free()

func move_state(delta):
	if !is_local_player():
		return

	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input_vector.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	input_vector = input_vector.normalized()

	if input_vector != Vector2.ZERO:
		roll_vector = input_vector
		swordHitbox.knockback_vector = input_vector
		animationTree.set("parameters/Idle/blend_position", input_vector)
		animationTree.set("parameters/Run/blend_position", input_vector)
		animationTree.set("parameters/Attack/blend_position", input_vector)
		animationTree.set("parameters/Roll/blend_position", input_vector)
		animationState.travel("Run")
		velocity = velocity.move_toward(input_vector * MAX_SPEED, ACCELERATION * delta)
	else:
		animationState.travel("Idle")
		# velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		velocity = Vector2.ZERO

	# not in use
	# if last_motion != input_vector:
	# 	Network.send_input_update(input_vector, MAX_SPEED)
	# last_motion = input_vector

	if last_position != position:
		Network.send_position_update(position)
	last_position = position

	move()

	if Input.is_action_just_pressed("roll"):
		state = ROLL

	if Input.is_action_just_pressed("attack"):
		state = ATTACK

func roll_state():
	velocity = roll_vector * ROLL_SPEED
	animationState.travel("Roll")
	move()

func attack_state():
	velocity = Vector2.ZERO
	animationState.travel("Attack")

func move():
	velocity = move_and_slide(velocity)

func roll_animation_finished():
	velocity = velocity * 0.8
	state = MOVE

func attack_animation_finished():
	state = MOVE

func _on_Hurtbox_area_entered(area):
	stats.health -= area.damage
	hurtbox.start_invincibility(0.6)
	hurtbox.create_hit_effect()
	var playerHurtSound = PlayerHurtSound.instance()
	get_tree().current_scene.add_child(playerHurtSound)

func _on_Hurtbox_invincibility_started():
	blinkAnimationPlayer.play("Start")

func _on_Hurtbox_invincibility_ended():
	blinkAnimationPlayer.play("Stop")
