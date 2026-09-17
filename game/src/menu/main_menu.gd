extends Control

## Reworked per the "ULTIMATE_IMPLEMENTATION_BUNDLE"'s visual-target
## reference: a stronger title lockup (icon + wordmark), a left-aligned
## stacked menu (now including Credits, previously only reachable from
## nowhere despite credits.tscn already existing), and a decorative
## "terminal" flavor panel on the right for atmosphere/personality — a
## real, original Godot UI construction, not an attempt to reproduce the
## reference's painted illustration style (out of reach without a 2D
## illustration pipeline this project doesn't have).

const CURSOR_BLINK_INTERVAL_SEC: float = 0.55

@onready var _continue_button: Button = $MenuBox/ContinueButton
@onready var _new_button: Button = $MenuBox/NewCampaignButton
@onready var _settings_button: Button = $MenuBox/SettingsButton
@onready var _credits_button: Button = $MenuBox/CreditsButton
@onready var _quit_button: Button = $MenuBox/QuitButton
@onready var _terminal_cursor: Label = $Terminal/Margin/VBox/TerminalCursor
var _cursor_timer: float = 0.0
var _cursor_visible: bool = true

func _ready() -> void:
    LocalizationManager.localize_control_tree(self)
    _continue_button.disabled = not SaveManager.has_any_save()
    _new_button.pressed.connect(_on_new_campaign_pressed)
    _continue_button.pressed.connect(_on_continue_pressed)
    _settings_button.pressed.connect(_on_settings_pressed)
    _credits_button.pressed.connect(_on_credits_pressed)
    _quit_button.pressed.connect(_on_quit_pressed)
    # P43: controller/keyboard parity from the very first screen — nothing
    # is focused by default, so ui_accept would have no target otherwise.
    (_continue_button if not _continue_button.disabled else _new_button).grab_focus()
    set_process(not SettingsManager.reduced_motion)

## A blinking terminal cursor — the one purely decorative animation on this
## screen, skipped outright under reduced-motion (same accessibility gate
## P42 already applies to every other non-essential animation).
func _process(delta: float) -> void:
    _cursor_timer += delta
    if _cursor_timer >= CURSOR_BLINK_INTERVAL_SEC:
        _cursor_timer = 0.0
        _cursor_visible = not _cursor_visible
        _terminal_cursor.modulate.a = 1.0 if _cursor_visible else 0.0

func _on_credits_pressed() -> void:
    await SceneRouter.go_to("res://scenes/credits.tscn")

## Visual-target pass ("Start in a garage with three employees and a
## model called PotatoLM" — landing page contract): a fresh campaign now
## really does start with 3 hired staff and a real, weak starting model,
## not an empty roster. This seeding lives here, not in GameState.reset_
## to_defaults() itself — that function stays a true blank slate, since
## most of tools/bootstrap.sh's smoke tests call it directly and build
## their own scenario on top of an empty staff/models array.
const STARTING_STAFF_COUNT: int = 3

func _on_new_campaign_pressed() -> void:
    GameState.reset_to_defaults()
    SimClock.reset_rng_streams()
    RivalManager.generate_rival()
    WorldStateManager.generate()
    StaffManager.refresh_candidates()
    for i in STARTING_STAFF_COUNT:
        StaffManager.hire(0)
    ModelManager.seed_starting_model()
    _seed_starting_workstations()
    await SceneRouter.go_to("res://scenes/campaign.tscn")

## Garage vertical-slice recovery pass: a brand-new campaign used to start
## in a genuinely empty room — no desks, no monitors, 3 staff with nothing
## to do but wander (campaign.gd's own visual-overhaul-pass comment called
## this deliberate at the time, matching the Art Bible's "cheap converted
## office" framing literally). Confirmed by a real screenshot of the
## actual running build that this reads as an unconvincing blockout, not
## a "humble start" — every visual-target reference has always shown the
## garage already staffed and working on day one. Seeds 3 real desk
## buildings and assigns each of the 3 starting hires to a real
## research_sprint work order at their own desk, using the exact same
## GameState.buildings/TaskManager plumbing a save/load restore or a
## player-driven build+assign already goes through — Campaign._spawn_
## staff_agent()'s existing "resume an in-progress task on load" path
## picks this up with no further changes. Desk cells sit in build grid
## row 1 (row 3 is the reserved east-west route, never usable).
const STARTING_DESK_CELLS: Array[Vector2i] = [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)]
func _seed_starting_workstations() -> void:
    var desk_ids: Array[String] = []
    for i in STARTING_DESK_CELLS.size():
        var desk_id: String = "garage_desk_%d" % (i + 1)
        GameState.buildings.append({
            "id": desk_id, "buildable_id": "desk",
            "cell_x": STARTING_DESK_CELLS[i].x, "cell_y": STARTING_DESK_CELLS[i].y,
            "rotated": false,
        })
        desk_ids.append(desk_id)
    for i in GameState.staff.size():
        if i >= desk_ids.size():
            break
        var staff_id: String = String((GameState.staff[i] as Dictionary).get("id", ""))
        TaskManager.assign(staff_id, "research_sprint", desk_ids[i])

func _on_continue_pressed() -> void:
    var err: Error = SaveManager.load_newest_autosave()
    if err != OK:
        push_warning("MainMenu: continue failed to load an autosave (error %s)" % err)
    await SceneRouter.go_to("res://scenes/campaign.tscn")

func _on_settings_pressed() -> void:
    await SceneRouter.go_to("res://scenes/settings.tscn")

func _on_quit_pressed() -> void:
    get_tree().quit()
