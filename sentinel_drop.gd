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
@onready var resize_handle: Control = $TerminalPanel/ResizeHandle

# --- Internal State ---
var is_open: bool = false
var target_y_closed: float = 0.0
var target_y_open: float = 0.0
var terminal_height: float = 0.0
var command_registry: Dictionary = {}
var command_history: Array[String] = []
var history_index: int = -1
var input_draft: String = ""
var is_wireframe: bool = false

# Dragging states
var is_dragging: bool = false
var max_height_pixels: float = 0.0

func _ready() -> void:
	# 1. Calculate dimensions based on screen size
	var screen_size = get_viewport().get_visible_rect().size
	terminal_height = screen_size.y * default_screen_height_pct
	max_height_pixels = screen_size.y
	
	# Set panel size
	terminal_panel.size.y = terminal_height
	terminal_panel.size.x = screen_size.x
	
	# Position panel completely off-screen at start
	target_y_closed = -terminal_height
	target_y_open = 0.0
	terminal_panel.position.y = target_y_closed
	
	# 2. Connect UI signals
	command_input.focus_exited.connect(_on_focus_exited)
	command_input.gui_input.connect(_on_input_box_gui_input)
	resize_handle.gui_input.connect(_on_resize_handle_input)
	
	# Hide the panel on launch so the bevel is perfectly invisible
	terminal_panel.visible = false
	
	# 3. Register Commands
	register_command("help", _cmd_help, "Lists all available commands.")
	register_command("clear", _cmd_clear, "Clears the terminal screen.")
	register_command("cls", _cmd_clear, "Alias for clear.")
	register_command("bloom", _cmd_bloom, "Toggles environment bloom. Usage: bloom on/off")
	register_command("fov", _cmd_fov, "Sets the active 3D camera Field of View. Usage: fov [value]")
	register_command("fps", _cmd_fps, "Prints the current frames per second.")
	register_command("reload", _cmd_reload, "Reloads the currently active scene.")
	register_command("vsync", _cmd_vsync, "Toggles vertical synchronization. Usage: vsync on/off")
	register_command("wireframe", _cmd_wireframe, "Toggles wireframe overlay mode for 3D/2D debugging.")
	register_command("engine_info", _cmd_engine_info, "Prints engine version, OS, and hardware diagnostics.")
	register_command("shutdown", _cmd_shutdown, "Instantly closes the game client.")
	
	log_text("[color=cyan]SentinelDrop Terminal Initialized. Type 'help' for commands.[/color]")

func _on_input_box_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# 1. Handle Command Submission
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_command_submitted(command_input.text)
			command_input.accept_event()
			return
			
		# 2. Cycle UP through History
		if event.keycode == KEY_UP:
			if command_history.is_empty():
				command_input.accept_event()
				return
				
			# If we are just starting to navigate up, save what the user currently has typed
			if history_index == -1:
				input_draft = command_input.text
				
			# Move backward in time through history array
			if history_index < command_history.size() - 1:
				history_index += 1
				_apply_history_to_input()
				
			command_input.accept_event() # Prevent Godot from moving text caret
			
		# 3. Cycle DOWN through History
		elif event.keycode == KEY_DOWN:
			if history_index == -1:
				command_input.accept_event()
				return
				
			history_index -= 1
			
			if history_index == -1:
				# We are back at the bottom, restore their original draft
				command_input.text = input_draft
				command_input.caret_column = command_input.text.length()
			else:
				_apply_history_to_input()
				
			command_input.accept_event() # Prevent Godot from moving text caret

func _apply_history_to_input() -> void:
	# History is stored sequentially, so the most recent item is at the back of the array
	var target_text = command_history[(command_history.size() - 1) - history_index]
	command_input.text = target_text
	# Move the text cursor to the very end of the string instead of leaving it at the start
	command_input.caret_column = target_text.length()

func _on_focus_exited() -> void:
	#If we are already exiting the tree, don't bother awaiting
	if not is_inside_tree() or get_tree() == null:
		return
		
	await get_tree().process_frame
	
	#If the scene reloaded during the frame wait, abort safely
	if not is_inside_tree() or get_viewport() == null:
		return
		
	var current_focus = get_viewport().gui_get_focus_owner()
	print("Focus lost! New focus owner: ", current_focus)

func _process(_delta: float) -> void:
	if is_dragging and enable_dragging and is_open:
		var mouse_y = get_viewport().get_mouse_position().y
		var handle_thickness = resize_handle.size.y
		var safe_max_height = max_height_pixels - handle_thickness
		
		var new_height = clamp(mouse_y, min_height_pixels, safe_max_height)
		
		terminal_height = new_height
		terminal_panel.size.y = terminal_height
		
		target_y_closed = -terminal_panel.size.y

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action):
		toggle_terminal()
		get_viewport().set_input_as_handled()
		
	if is_dragging and not is_open:
		is_dragging = false

# --- Open/Close Logic ---
func toggle_terminal() -> void:
	if is_dragging:
		is_dragging = false
		
	is_open = !is_open
	
	target_y_closed = -terminal_panel.size.y
	var target_y = target_y_open if is_open else target_y_closed
	
	history_index = -1
	input_draft = ""
	
	if is_open:
		terminal_panel.visible = true
		command_input.grab_focus()
	else:
		command_input.release_focus()
	
	if slide_duration <= 0.0:
		terminal_panel.position.y = target_y
		if not is_open:
			terminal_panel.visible = false
	else:
		var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(terminal_panel, "position:y", target_y, slide_duration)
		
		if not is_open:
			tween.tween_callback(func(): 
				terminal_panel.visible = false
				if terminal_panel.position.y != target_y_closed:
					terminal_panel.position.y = target_y_closed
			)

# --- Mouse Resizing Drag Logic ---
func _on_resize_handle_input(event: InputEvent) -> void:
	if not enable_dragging:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed

# --- Command System Logic ---
func register_command(command_name: String, callable: Callable, description: String = "") -> void:
	command_registry[command_name] = {
		"callable": callable,
		"description": description
	}

func _on_command_submitted(text: String) -> void:
	var trimmed = text.strip_edges()
	
	history_index = -1
	input_draft = ""
	
	if trimmed.is_empty():
		_force_focus_loop()
		return
		
	if command_history.is_empty() or command_history.back() != text:
		command_history.append(text)
		
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

func _force_focus_loop() -> void:
	# SAFETY CHECK: If the scene reloaded or changed, this node is no longer in the tree.
	# Exit early to prevent null instance crashes.
	if not is_inside_tree() or get_tree() == null:
		return
		
	await get_tree().process_frame
	
	# Double check again after the frame pass to make sure we didn't exit during the wait
	if is_inside_tree() and command_input:
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

func _cmd_bloom(args: Array) -> void:
	if args.is_empty():
		log_text("[color=yellow]Usage: bloom [on/off][/color]")
		return
		
	var world_env: WorldEnvironment = get_tree().root.find_child("WorldEnvironment", true, false)
	if not world_env or not world_env.environment:
		log_text("[color=red]Error: No active WorldEnvironment or Environment Resource found.[/color]")
		return
		
	var switch = args[0].to_lower()
	if switch in ["on", "1", "true"]:
		world_env.environment.glow_enabled = true
		world_env.environment.glow_bloom = 0.5
		log_text("Bloom enabled.")
	elif switch in ["off", "0", "false"]:
		world_env.environment.glow_enabled = false
		log_text("Bloom disabled.")
	else:
		log_text("[color=red]Invalid argument. Use 'on' or 'off'.[/color]")

func _cmd_fov(args: Array) -> void:
	if args.is_empty():
		log_text("[color=yellow]Usage: fov [value] (e.g., fov 90)[/color]")
		return
		
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		log_text("[color=red]Error: No active Camera3D found in the viewport.[/color]")
		return
		
	var new_fov = args[0].to_float()
	new_fov = clamp(new_fov, 30.0, 120.0)
	camera.fov = new_fov
	log_text("Camera FOV set to %d" % new_fov)

func _cmd_fps(args: Array) -> void:
	if args.is_empty():
		# Just print the current FPS and whatever the current limit is
		var current_fps = Engine.get_frames_per_second()
		var max_fps = Engine.max_fps
		var limit_text = "Uncapped" if max_fps == 0 else str(max_fps)
		log_text("Current FPS: [color=green]%d[/color] (Limit: %s)" % [current_fps, limit_text])
		return
		
	# Handle the "set NUM" arguments
	if args[0].to_lower() == "set" and args.size() > 1:
		var target_fps = args[1].to_int()
		
		if target_fps < 0:
			log_text("[color=red]Error: FPS limit cannot be negative.[/color]")
			return
			
		# Apply the cap to the engine
		Engine.max_fps = target_fps
		
		if target_fps == 0:
			log_text("FPS limit removed (Uncapped).")
		else:
			log_text("FPS locked to %d." % target_fps)
	else:
		log_text("[color=yellow]Usage: fps OR fps set [number] (use 0 to uncap)[/color]")

func _cmd_reload(_args: Array) -> void:
	log_text("[color=yellow]Reloading current scene...[/color]")
	# Flashes the screen clear right before reloading so the transition feels immediate
	history_log.clear() 
	get_tree().reload_current_scene()

func _cmd_vsync(args: Array) -> void:
	if args.is_empty():
		var current_mode = DisplayServer.window_get_vsync_mode()
		var mode_str = "ON" if current_mode == DisplayServer.VSYNC_ENABLED else "OFF"
		log_text("VSync is currently: [color=yellow]%s[/color]" % mode_str)
		return
		
	var switch = args[0].to_lower()
	if switch in ["on", "1", "true"]:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		log_text("VSync enabled.")
	elif switch in ["off", "0", "false"]:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		log_text("VSync disabled (Uncapped / Fast).")
	else:
		log_text("[color=red]Invalid argument. Use 'on' or 'off'.[/color]")

func _cmd_wireframe(_args: Array) -> void:
	is_wireframe = !is_wireframe
	var vp_rid = get_viewport().get_viewport_rid()
	
	if is_wireframe:
		RenderingServer.viewport_set_debug_draw(vp_rid, RenderingServer.VIEWPORT_DEBUG_DRAW_WIREFRAME)
		log_text("Rendering mode set to [color=magenta]WIREFRAME[/color].")
	else:
		RenderingServer.viewport_set_debug_draw(vp_rid, RenderingServer.VIEWPORT_DEBUG_DRAW_DISABLED)
		log_text("Rendering mode restored to [color=green]NORMAL[/color].")

func _cmd_engine_info(_args: Array) -> void:
	# Core Hardware & Platform Info
	var version_str = Engine.get_version_info()["string"]
	var os_name = OS.get_name()
	var adapter_name = RenderingServer.get_video_adapter_name()
	var adapter_vendor = RenderingServer.get_video_adapter_vendor()
	
	# Graphics Pipeline & Backend Backend Diagnostics
	var render_method = RenderingServer.get_current_rendering_method().capitalize() # e.g. "Forward Plus" or "Gl Compatibility"
	var render_driver = RenderingServer.get_current_rendering_driver_name().to_upper() # e.g. "VULKAN" or "OPENGL3"
	var api_version = RenderingServer.get_video_adapter_api_version() # Specific API implementation version string
	
	# Calculate Engine Uptime (Converts ms into HH:MM:SS formatting)
	var total_msec: int = Time.get_ticks_msec()
	var total_seconds: int = total_msec / 1000
	var seconds: int = total_seconds % 60
	var minutes: int = (total_seconds / 60) % 60
	var hours: int = total_seconds / 3600
	var uptime_str: String = "%02d:%02d:%02d" % [hours, minutes, seconds]
	
	# Clean Scannable Diagnostic Display
	log_text("[color=yellow]--- SentinelDrop Advanced System Summary ---[/color]")
	log_text("Engine Version:   [color=cyan]%s[/color]" % version_str)
	log_text("Operating System: [color=cyan]%s[/color]" % os_name)
	log_text("Graphics Card:    [color=cyan]%s (%s)[/color]" % [adapter_name, adapter_vendor])
	log_text("Render Profile:   [color=magenta]%s[/color]" % render_method)
	log_text("Graphics Backend: [color=magenta]%s (v%s)[/color]" % [render_driver, api_version])
	log_text("Engine Uptime:    [color=green]%s[/color] (including load cycles)" % uptime_str)

func _cmd_shutdown(_args: Array) -> void:
	log_text("[color=red]Shutting down game client...[/color]")
	
	# Give the engine a microsecond to process the log text render before killing the process
	await get_tree().process_frame
	
	get_tree().quit()
