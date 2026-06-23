# SentinelDrop

An agnostic, zero-dependency developer runtime console and hardware diagnostics suite for Godot 4. 

SentinelDrop is a lightweight, drop-in utility that gives you complete oversight over your game's rendering pipelines, audio structures, low-level memory allocation, asynchronous networking, and engine execution loops. It requires zero project dependencies and works out of the box for any project.

## Feature set

* **Zero-Leak Memory Auditing:** Single-line garbage collection (`gc`) that forces reference cycles and targets orphaned node leaks.
* **Asynchronous Networking:** Non-blocking, thread-safe `ping` utility using low-level background threads.
* **Auto-Discovering Audio Matrix:** Logarithmic decibel calculations (`volume`) that dynamically map and track your project's active mixer buses and mute states.
* **Unified Pipeline Routers:** Master controllers for Anti-Aliasing (`aa`), frame capping (`fps`), and environment toggles over a single clean syntax layout.

## Installation

### 1. Using the Sandbox Demo
This repository is hosted as a complete Godot 4 project. Clone the repo and open it directly in the Godot Editor to explore the interactive testing grounds!

### 2. Adding to Your Own Project
To implement SentinelDrop into your own game:
1. Copy the contents of the `addons/sentinel_drop/` directory into your project's `addons/` folder.
2. Go to **Project -> Project Settings -> Plugins** and check **Enable** next to SentinelDrop.
3. In the AutoLoad tab in the **Project Settings** window, load the path **sentinel_drop/sentinel_drop.tscn**, set the node name SentinelDrop and clock **Add**.
4. In the **Input Map** section of the **Project Settings**, add an input called "toggle_terminal" and set the **`~` (Tilde)** key as the input for the "toggle_terminal" input command.
5. Run your game and press the **`~` (Tilde)** key to open the console!

## The Command Index

| Command | Syntax / Usage | Description |
| :--- | :--- | :--- |
| `help` | `help` | Lists all available console commands. |
| `clear` / `cls` | `clear` | Clears the terminal text buffer history. |
| `engine_info` | `engine_info` | Prints engine version, OS, build profile, and hardware diagnostics. |
| `fps` | `fps` | Prints the current real-time frames per second. |
| `gc` | `gc` | Runs a low-level memory audit and hunts down orphan node leaks. |
| `aa` | `aa [type] [value]` | Interactive query/setter for MSAA 2D/3D, Screen Space AA, and TAA. |
| `volume` | `volume [bus] [value]` | Queries the mixer matrix or sets bus volumes logarithmically (0.0 - 1.0). |
| `vsync` | `vsync [on/off/adaptive]`| Adjusts display server vertical synchronization states on the fly. |
| `timescale` | `timescale [value]` | Modifies global engine execution speeds (0.0 to 5.0). |
| `ping` | `ping [optional_url]` | Asynchronously checks connection stability via background threads. |
| `screenshot` | `screenshot` | Captures the active viewport and saves it as a local timestamped PNG. |
| `wireframe` | `wireframe` | Toggles the debug hardware wireframe overlay mode. |
| `bloom` | `bloom [on/off]` | Directly toggles the active WorldEnvironment bloom state. |
| `fov` | `fov [value]` | Modifies the active 3D camera Field of View safely. |
| `reload` | `reload` | Re-buffers and restarts the active gameplay scene file. |
| `window_mode` | `window_mode [mode]` | Shifts display parameters between Windowed, Fullscreen, and Borderless. |
| `shutdown` | `shutdown` | Instantly terminates the running game client execution loop. |

## License
This project is open-source and available under the [MIT License](LICENSE).
