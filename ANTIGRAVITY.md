# Antigravity Project Rules & Context

> **Project:** SpudCustoms (Fork) | **Engine:** Godot 4.5 | **Language:** GDScript 2.0

## 1. Project Structure
- **Root**: `godot_project/` (contains `project.godot`)
- **Scripts**: `godot_project/scripts/` (Feature-based organization)
- **Tests**: `godot_project/tests/` (GUT Framework)
- **Assets**: `godot_project/assets/`

## 2. Core Architecture Patterns
- **EventBus**: ALL inter-system communication MUST go through `EventBus` signals. Do NOT direct call across systems.
    - *Source*: `scripts/autoload/EventBus.gd`
- **Managers**: Use Autoloads for global state (e.g., `SteamManager`, `GameStateManager`).
- **Composition**: Prefer small, focused components over large monolithic scripts.

## 3. GDScript Style Guide
- **Type Safety**: ALWAYS use static typing (`var score: int = 0`, `func _ready() -> void:`).
- **Naming**: 
    - Classes: `PascalCase` (`class_name PotatoLogic`)
    - Variables/Functions: `snake_case` (`var potato_count`)
    - Constants: `SCREAMING_SNAKE_CASE` (`const MAX_POTATOES`)
    - Private members: `_underscore_prefix` (`func _internal_logic():`)
- **Node References**: Use `@onready` and Unique Names (`%NodeName`) where possible for robustness.

## 4. Testing (GUT)
- **Location**: `godot_project/tests/unit/` or `godot_project/tests/integration/`
- **Requirement**: New logic SHOULD have accompanying unit tests.
- **Running**: `godot --headless --script godot_project/tests/run_tests.gd`

## 5. Workflow
- **Linting**: Ensure code passes `gdlint` rules (max line length 180, tab indentation).
- **Formatting**: Use `gdformat` before committing.
