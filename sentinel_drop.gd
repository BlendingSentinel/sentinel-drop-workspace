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
	# Determine dimensions based on screen size
	var screen_size = get_viewport().get_visible_rect().size
	terminal_height = screen_size.y * default_screen_height_pct
	max_height_pixels = screen_size.y
	
	# Set panel size
	terminal_panel.size.y = terminal_height
	terminal_panel.size.x = screen_size.x
	
	# Position panel completely off screen at start
	target_y_closed = -terminal_height
	target_y_open = 0.0
	terminal_panel.position.y = target_y_closed
	
	# UI connect signals
	command_input.focus_exited.connect(_on_focus_exited)
	command_input.gui_input.connect(_on_input_box_gui_input)
	resize_handle.gui_input.connect(_on_resize_handle_input)
	
	# Hide the panel on launch so the bevel is perfectly invisible
	terminal_panel.visible = false
	
	# Index of valid commands
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
	register_command("window_mode", _cmd_window_mode, "Changes display mode. Usage: window_mode [windowed/fullscreen/borderless]")
	register_command("screenshot", _cmd_screenshot, "Captures the screen and saves it as a PNG.")
	register_command("gc", _cmd_gc, "Runs a low-level memory audit and checks for orphan node leaks.")
	register_command("ping", _cmd_ping, "Pings the current server, or a specific domain/IP. Usage: ping [optional_url]")
	register_command("volume", _cmd_volume, "Sets bus volume. Usage: volume [bus_name] [value 0.0-1.0]")
	register_command("timescale", _cmd_timescale, "Adjusts global game processing speed. Usage: timescale [value]")
	register_command("aa", _cmd_aa, "Manages Anti-Aliasing profiles. Usage: aa [type] [value]")
	
	log_text("[color=cyan]SentinelDrop Terminal Initialized. Type 'help' for commands.[/color]")

func _on_input_box_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Handle Command Submission
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_command_submitted(command_input.text)
			command_input.accept_event()
			return
			
		# Cycle UP through History
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
			
		# Cycle DOWN through History
		elif event.keycode == KEY_DOWN:
			if history_index == -1:
				command_input.accept_event()
				return
				
			history_index -= 1
			
			if history_index == -1:
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
	#If we are already exiting the tree, don't bother waiting
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

# --- Open/Close ---
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
	
	# Determine Build/Export Profile
	var build_profile: String = "Production Release Build"
	var profile_color: String = "green"
	
	if OS.has_feature("editor"):
		build_profile = "Debug Mode (Running inside Editor)"
		profile_color = "yellow"
	elif OS.has_feature("debug"):
		build_profile = "Exported Debug Build"
		profile_color = "orange"
	
	# Graphics Pipeline and Backend Diagnostics
	var render_method = RenderingServer.get_current_rendering_method().capitalize()
	var render_driver = RenderingServer.get_current_rendering_driver_name().to_upper()
	var api_version = RenderingServer.get_video_adapter_api_version()
	
	# Calculate Engine Uptime
	var total_msec: int = Time.get_ticks_msec()
	var total_seconds: int = total_msec / 1000
	var seconds: int = total_seconds % 60
	var minutes: int = (total_seconds / 60) % 60
	var hours: int = total_seconds / 3600
	var uptime_str: String = "%02d:%02d:%02d" % [hours, minutes, seconds]
	
	# Clean Scannable Diagnostic Display
	log_text("[color=yellow]--- SentinelDrop Advanced System Summary ---[/color]")
	log_text("Engine Version:   [color=cyan]%s[/color]" % version_str)
	log_text("Build Profile:    [color=%s]%s[/color]" % [profile_color, build_profile])
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

func _cmd_window_mode(args: Array) -> void:
	if args.is_empty():
		# If no argument is provided, read back the current engine state
		var current_mode = DisplayServer.window_get_mode()
		var mode_name = "Unknown"
		match current_mode:
			DisplayServer.WINDOW_MODE_WINDOWED: mode_name = "Windowed"
			DisplayServer.WINDOW_MODE_FULLSCREEN: mode_name = "Borderless Fullscreen"
			DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN: mode_name = "Exclusive Fullscreen"
			DisplayServer.WINDOW_MODE_MAXIMIZED: mode_name = "Maximized"
			DisplayServer.WINDOW_MODE_MINIMIZED: mode_name = "Minimized"
			
		log_text("Current window mode: [color=yellow]%s[/color]" % mode_name)
		return
		
	var requested_mode = args[0].to_lower()
	match requested_mode:
		"windowed", "window":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			log_text("Window mode set to: [color=green]Windowed[/color]")
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			log_text("Window mode set to: [color=green]Exclusive Fullscreen[/color]")
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			log_text("Window mode set to: [color=green]Borderless Fullscreen[/color]")
		_:
			log_text("[color=red]Invalid mode. Use 'windowed', 'fullscreen', or 'borderless'.[/color]")

func _cmd_screenshot(_args: Array) -> void:
	log_text("[color=yellow]Processing screenshot...[/color]")
	
	# Wait for the current rendering frame to finish drawing completely to avoid graphical tearing
	await RenderingServer.frame_post_draw
	
	# 1. Grab the raw image data from the root viewport
	var image = get_viewport().get_texture().get_image()
	
	# 2. Ensure the "screenshots" directory exists inside the local user folder
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("screenshots"):
		dir.make_dir("screenshots")
		
	# 3. Generate a clean, time-stamped filename
	var time = Time.get_datetime_dict_from_system()
	var filename = "screenshot_%04d-%02d-%02d_%02d-%02d-%02d.png" % [
		time.year, time.month, time.day,
		time.hour, time.minute, time.second
	]
	
	var local_path = "user://screenshots/" + filename
	
	# 4. Save the image to the drive
	var error = image.save_png(local_path)
	
	if error == OK:
		# Convert the user:// path into OS path (C:/Users/ AppData/ /.local/share etc)
		var absolute_path = ProjectSettings.globalize_path(local_path)
		log_text("Screenshot saved successfully to:")
		log_text("[color=cyan]%s[/color]" % absolute_path)
	else:
		log_text("[color=red]Failed to save screenshot. Error code: %d[/color]" % error)

func _cmd_gc(_args: Array) -> void:
	log_text("[color=yellow]Analyzing active engine allocations...[/color]")
	
	# Gather raw memory data from the Performance API
	var static_mem_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
	var static_mem_mb = static_mem_bytes / 1024.0 / 1024.0
	
	# Gather allocation counts
	var total_objects = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var active_resources = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var active_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphan_nodes = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	
	# Print a clean, formatted telemetry display
	log_text("[color=yellow]--- SentinelDrop Memory Diagnostic ---[/color]")
	log_text("Static Memory:   [color=cyan]%.2f MB[/color] (%d bytes)" % [static_mem_mb, static_mem_bytes])
	log_text("Total Objects:   [color=cyan]%d[/color] (Instances, Objects, Structs)" % total_objects)
	log_text("Active Nodes:    [color=cyan]%d[/color] (Inside active scene tree)" % active_nodes)
	log_text("Loaded Resources:[color=cyan]%d[/color] (Textures, Materials, Scripts)" % active_resources)
	
	# Highlight Orphan Nodes aggressively if any leak is detected
	if orphan_nodes > 0:
		log_text("[color=orange]Orphan Nodes:    %d[/color] [color=red]<- ALERT: Nodes leaking outside the Scene Tree![/color]" % orphan_nodes)
	else:
		log_text("Orphan Nodes:    [color=green]0[/color] (Clean teardowns)")

func _cmd_ping(args: Array) -> void:
	# BEHAVIOR 1: Ping current game server
	if args.is_empty():
		log_text("Checking connectivity to game server...")
		
		# Hook into Godot's high-level multiplayer API if active
		if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			# Note: Actual RTT tracking depends on your network setup (e.g., ENetPacketPeer provides peer.get_statistic())
			log_text("Connected to server. Peer ID: [color=cyan]%d[/color]" % multiplayer.get_unique_id())
		else:
			log_text("[color=yellow]No active multiplayer server connection detected.[/color]")
		return

	# BEHAVIOR 2: Ping a specific domain or IP address
	var target_url = args[0]
	if not target_url.begins_with("http://") and not target_url.begins_with("https://"):
		target_url = "https://" + target_url
		
	log_text("Pinging address [color=cyan]%s[/color]..." % target_url)
	
	# Create a temporary HTTPRequest node dynamically
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Track the exact hardware millisecond tick when the request leaves
	var start_time = Time.get_ticks_msec()
	
	# Define an inline lambda function to handle the response asynchronously
	var on_completed = func(result, response_code, _headers, _body):
		var duration = Time.get_ticks_msec() - start_time
		
		if result == HTTPRequest.RESULT_SUCCESS:
			log_text("Reply from %s: bytes=~32 [color=green]time=%dms[/color] Status=%d" % [args[0], duration, response_code])
		else:
			log_text("[color=red]Ping request failed. Destination host unreachable or timed out.[/color]")
			
		# Clean up the temporary node immediately so we don't leak memory
		http_request.queue_free()
		
	# Connect our lambda listener to the request completion signal
	http_request.request_completed.connect(on_completed)
	
	# Send out the web request
	var err = http_request.request(target_url)
	if err != OK:
		log_text("[color=red]Failed to initialize network connection socket.[/color]")
		http_request.queue_free()

func _cmd_volume(args: Array) -> void:
	if args.is_empty() or args[0] == "":
		log_text("[color=yellow]--- SentinelDrop Audio Mixer Matrix ---[/color]")
		
		var bus_count = AudioServer.bus_count
		for i in range(bus_count):
			var bus_name = AudioServer.get_bus_name(i)
			var current_db = AudioServer.get_bus_volume_db(i)
			var current_pct = int(db_to_linear(current_db) * 100)
			var is_muted = AudioServer.is_bus_mute(i)
			var mute_status = " [color=red](MUTED)[/color]" if is_muted else ""
			
			log_text("  Bus [%d]: [color=cyan]%-12s[/color] Volume: [color=green]%3d%%[/color] (%.1f dB)%s" % [
				i, bus_name, current_pct, current_db, mute_status
			])
		return
		
	if args.size() < 2:
		log_text("[color=red]Usage: volume [bus_name] [value 0.0 - 1.0][/color]")
		return

func _cmd_timescale(args: Array) -> void:
	if args.is_empty() or args[0] == "":
		log_text("Current Engine Timescale: [color=yellow]%.2f[/color]" % Engine.time_scale)
		return
		
	var target_scale = args[0].to_float()
	
	# Clamp to safe boundaries (0.0 freezes execution, anything above 5.0 can break physics steps)
	Engine.time_scale = clamp(target_scale, 0.0, 5.0)
	log_text("Global Engine Timescale set to: [color=green]%.2f[/color]" % Engine.time_scale)

func _cmd_aa(args: Array) -> void:
	var vp = get_viewport()
	
	# Helper parameter maps to turn cryptic engine integers into clean text labels
	var get_msaa_str = func(val): 
		match val:
			Viewport.MSAA_DISABLED: return "Off"
			Viewport.MSAA_2X: return "2x"
			Viewport.MSAA_4X: return "4x"
			Viewport.MSAA_8X: return "8x"
			_: return "Unknown"
			
	var get_ssaa_str = func(val):
		match val:
			Viewport.SCREEN_SPACE_AA_DISABLED: return "Off"
			Viewport.SCREEN_SPACE_AA_FXAA: return "FXAA"
			Viewport.SCREEN_SPACE_AA_SMAA: return "SMAA"
			_: return "Unknown"
	
	# ==========================================
	# CASE 1: No arguments provided -> Show full matrix
	# ==========================================
	if args.is_empty() or args[0] == "":
		log_text("[color=yellow]--- SentinelDrop Anti-Aliasing Dashboard ---[/color]")
		log_text("  msaa2d: [color=cyan]%s[/color]" % get_msaa_str.call(vp.msaa_2d))
		log_text("  msaa3d: [color=cyan]%s[/color]" % get_msaa_str.call(vp.msaa_3d))
		log_text("  screen: [color=cyan]%s[/color]" % get_ssaa_str.call(vp.screen_space_aa))
		log_text("  taa:    [color=cyan]%s[/color]" % ("Enabled" if vp.use_taa else "Disabled"))
		log_text("Usage: [color=yellow]aa [type] [optional_value][/color] (Valid types: msaa2d, msaa3d, screen, taa)")
		return
	
	var target_pipe = args[0].to_lower()
	
	# ==========================================
	# CASE 2: 1 Argument -> Query specific pipeline status & options
	# ==========================================
	if args.size() < 2 or args[1] == "":
		match target_pipe:
			"msaa2d":
				log_text("Current MSAA 2D setting: [color=cyan]%s[/color]" % get_msaa_str.call(vp.msaa_2d))
				log_text("Valid argument values: [color=yellow]off, 2x, 4x, 8x[/color]")
			"msaa3d":
				log_text("Current MSAA 3D setting: [color=cyan]%s[/color]" % get_msaa_str.call(vp.msaa_3d))
				log_text("Valid argument values: [color=yellow]off, 2x, 4x, 8x[/color]")
			"screen":
				log_text("Current Screen Space AA setting: [color=cyan]%s[/color]" % get_ssaa_str.call(vp.screen_space_aa))
				log_text("Valid argument values: [color=yellow]off, fxaa, smaa[/color]")
			"taa":
				log_text("Current TAA setting: [color=cyan]%s[/color]" % ("Enabled" if vp.use_taa else "Disabled"))
				log_text("Valid argument values: [color=yellow]on, off[/color]")
			_:
				log_text("[color=red]Unknown pipeline. Use 'msaa2d', 'msaa3d', 'screen', or 'taa'.[/color]")
		return
	
	# ==========================================
	# CASE 3: 2 Arguments -> Actively write values
	# ==========================================
	var write_val = args[1].to_lower()
	match target_pipe:
		"msaa2d", "msaa3d":
			var target_enum = Viewport.MSAA_DISABLED
			match write_val:
				"off", "disabled": target_enum = Viewport.MSAA_DISABLED
				"2x": target_enum = Viewport.MSAA_2X
				"4x": target_enum = Viewport.MSAA_4X
				"8x": target_enum = Viewport.MSAA_8X
				_:
					log_text("[color=red]Invalid value. Valid inputs: off, 2x, 4x, 8x[/color]")
					return
					
			if target_pipe == "msaa2d":
				vp.msaa_2d = target_enum
				log_text("MSAA 2D pipeline updated to: [color=green]%s[/color]" % get_msaa_str.call(vp.msaa_2d))
			else:
				vp.msaa_3d = target_enum
				log_text("MSAA 3D pipeline updated to: [color=green]%s[/color]" % get_msaa_str.call(vp.msaa_3d))

		"screen":
			var target_enum = Viewport.SCREEN_SPACE_AA_DISABLED
			match write_val:
				"off", "disabled": target_enum = Viewport.SCREEN_SPACE_AA_DISABLED
				"fxaa": target_enum = Viewport.SCREEN_SPACE_AA_FXAA
				"smaa": target_enum = Viewport.SCREEN_SPACE_AA_SMAA
				_:
					log_text("[color=red]Invalid value. Valid inputs: off, fxaa, smaa[/color]")
					return
			vp.screen_space_aa = target_enum
			log_text("Screen Space AA pipeline updated to: [color=green]%s[/color]" % get_ssaa_str.call(vp.screen_space_aa))
	
		"taa":
			match write_val:
				"on", "enabled", "true":
					vp.use_taa = true
				"off", "disabled", "false":
					vp.use_taa = false
				_:
					log_text("[color=red]Invalid value. Valid inputs: on, off[/color]")
					return
			log_text("TAA pipeline updated to: [color=green]%s[/color]" % ("Enabled" if vp.use_taa else "Disabled"))
			
		_:
			log_text("[color=red]Unknown pipeline string. Use 'msaa2d', 'msaa3d', 'screen', or 'taa'.[/color]")
