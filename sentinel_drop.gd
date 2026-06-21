extends CanvasLayer

# --- Exported Settings (Configurable in Inspector) ---
@export_category("SentinelDrop Configuration")
@export var slide_duration: float = 0.15
@export_range(0.1, 1.0) var default_screen_height_pct: float = 0.4
@export var toggle_action: String = "toggle_terminal"

@export_subgroup("Mouse Dragging")
@export var enable_dragging: bool = true
@export var min_height_pixels: float = 100.0

# --- Node References ---
@onready var terminal_panel: Panel = $TerminalPanel
@onready var history_log: RichTextLabel = $TerminalPanel/VBoxContainer/HistoryLog
@onready var command_input: LineEdit = $TerminalPanel/VBoxContainer/CommandInput
@onready var resize_handle: Control = $TerminalPanel/ResizeHandle # Our new node!

# --- Internal State ---
var is_open: bool = false
var target_y_closed: float = 0.0
var target_y_open: float = 0.0
var terminal_height: float = 0.0
var command_registry: Dictionary = {}

# Dragging states
var is_dragging: bool = false
var max_height_pixels: float = 0.0

func _ready() -> void:
	# 1. Calculate dimensions based on screen size
	var screen_size = get_viewport().get_visible_rect().size
	terminal_height = screen_size.y * default_screen_height_pct
	max_height_pixels = screen_size.y # Cannot drag past screen height
	
	# Set panel size
	terminal_panel.size.y = terminal_height
	terminal_panel.size.x = screen_size.x
	
	# Position panel completely off-screen at start
	target_y_closed = -terminal_height
	target_y_open = 0.0
	terminal_panel.position.y = target_y_closed
	
	# 2. Connect UI signals
	command_input.text_submitted.connect(_on_command_submitted)
	
	# Connect mouse dragging signals
	resize_handle.gui_input.connect(_on_resize_handle_input)
	
	# 3. Register default built-in commands
	register_command("help", _cmd_help, "Lists all available commands.")
	register_command("clear", _cmd_clear, "Clears the terminal screen.")
	
	log_text("[color=cyan]SentinelDrop Terminal Initialized. Type 'help' for commands.[/color]")
	
	command_input.focus_exited.connect(_on_focus_exited)
	command_input.gui_input.connect(_on_input_box_gui_input)
	
	# Hide the panel on launch so the bevel is perfectly invisible
	terminal_panel.visible = false
	
	log_text("[color=cyan]SentinelDrop Terminal Initialized. Type 'help' for commands.[/color]")
	

func _on_input_box_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			# Manually run our command submission
			_on_command_submitted(command_input.text)
			command_input.accept_event()

func _on_focus_exited() -> void:
	await get_tree().process_frame
	var current_focus = get_viewport().gui_get_focus_owner()
	print("Focus lost! New focus owner: ", current_focus)

func _process(_delta: float) -> void:
	# If we are actively dragging, update the terminal size to track the mouse
	if is_dragging and enable_dragging and is_open:
		var mouse_y = get_viewport().get_mouse_position().y
		
		# FIX: Subtract the handle's thickness so it can never leave the screen boundaries
		var handle_thickness = resize_handle.size.y
		var safe_max_height = max_height_pixels - handle_thickness
		
		# Clamp the height between our minimum size and our new safe maximum boundary
		var new_height = clamp(mouse_y, min_height_pixels, safe_max_height)
		
		terminal_height = new_height
		terminal_panel.size.y = terminal_height
		
		# Recalculate where the closed position is based on the new size
		target_y_closed = -terminal_height

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action):
		toggle_terminal()
		get_viewport().set_input_as_handled()
		
	# Safety check: If the terminal is closed while dragging, stop dragging
	if is_dragging and not is_open:
		is_dragging = false

# --- Open/Close Logic ---
func toggle_terminal() -> void:
	if is_dragging:
		is_dragging = false
		
	is_open = !is_open
	
	var target_y = target_y_open if is_open else target_y_closed
	
	if is_open:
		# CRITICAL: Show the panel right before it starts sliding down
		terminal_panel.visible = true
		command_input.grab_focus()
	else:
		command_input.release_focus()
	
	if slide_duration <= 0.0:
		terminal_panel.position.y = target_y
		# If it's closing instantly, hide it right now
		if not is_open:
			terminal_panel.visible = false
	else:
		var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(terminal_panel, "position:y", target_y, slide_duration)
		
		# If it's closing with an animation, wait for the slide to finish, then hide it
		if not is_open:
			tween.tween_callback(func(): terminal_panel.visible = false)

# --- Mouse Resizing Drag Logic ---
func _on_resize_handle_input(event: InputEvent) -> void:
	if not enable_dragging:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
			else:
				is_dragging = false

# --- Command System Logic ---
func register_command(command_name: String, callable: Callable, description: String = "") -> void:
	command_registry[command_name] = {
		"callable": callable,
		"description": description
	}

func _on_command_submitted(text: String) -> void:
	var trimmed = text.strip_edges()
	if trimmed.is_empty():
		_force_focus_loop()
		return
	
	log_text("> " + trimmed)
	command_input.clear()
	
	var parts = trimmed.split(" ")
	var command_name = parts[0].to_lower()
	var args = parts.slice(1)
	
	if command_registry.has(command_name):
		command_registry[command_name]["callable"].call(args)
	else:
		log_text("[color=red]Error: Unknown command '%s'. Type 'help' for list.[/color]" % command_name)
		
	_force_focus_loop()

# Helper function to completely clear the frame queue before grabbing focus
func _force_focus_loop() -> void:
	await get_tree().process_frame
	command_input.grab_focus()

func log_text(text: String) -> void:
	history_log.append_text(text + "\n")

# --- Core Built-in Commands ---
func _cmd_help(_args: Array) -> void:
	log_text("[color=yellow]--- Available Commands ---[/color]")
	for cmd in command_registry:
		log_text("%s - %s" % [cmd, command_registry[cmd]["description"]])

func _cmd_clear(_args: Array) -> void:
	history_log.clear()
