extends Node

## Central scene navigation with fade transitions and error-safe loading.
## Autoloads persist across change_scene_to_packed(), so this never
## re-registers EventBus/GameState/SaveManager.

signal transition_started(target_path: String)
signal transition_finished(target_path: String)

const FADE_DURATION: float = 0.35

var _fade_rect: ColorRect
var _fade_layer: CanvasLayer
var _busy: bool = false

func _ready() -> void:
    _fade_layer = CanvasLayer.new()
    _fade_layer.layer = 100
    _fade_rect = ColorRect.new()
    _fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
    _fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    _fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _fade_layer.add_child(_fade_rect)
    get_tree().root.add_child.call_deferred(_fade_layer)

func is_busy() -> bool:
    return _busy

## Loads and switches to the scene at scene_path with a fade-out/fade-in.
## Returns OK, or an Error code if the scene is missing/invalid/busy.
## Never crashes the tree on a bad path.
func go_to(scene_path: String) -> Error:
    if _busy:
        push_warning("SceneRouter busy, ignoring go_to(%s)" % scene_path)
        return ERR_BUSY
    if not ResourceLoader.exists(scene_path, "PackedScene"):
        push_error("SceneRouter: scene does not exist: %s" % scene_path)
        return ERR_FILE_NOT_FOUND
    var packed: Resource = ResourceLoader.load(scene_path, "PackedScene")
    if packed == null or not (packed is PackedScene):
        push_error("SceneRouter: failed to load scene: %s" % scene_path)
        return ERR_CANT_OPEN

    _busy = true
    transition_started.emit(scene_path)
    if _fade_rect != null and is_inside_tree():
        await _fade(1.0)
    var err: Error = get_tree().change_scene_to_packed(packed)
    if err != OK:
        push_error("SceneRouter: change_scene_to_packed(%s) failed: %s" % [scene_path, err])
        _busy = false
        if _fade_rect != null and is_inside_tree():
            await _fade(0.0)
        return err
    await get_tree().process_frame
    if _fade_rect != null and is_inside_tree():
        await _fade(0.0)
    _busy = false
    transition_finished.emit(scene_path)
    return OK

func _fade(target_alpha: float) -> void:
    if SettingsManager.reduced_motion:
        _fade_rect.color.a = target_alpha
        return
    var tween: Tween = create_tween()
    tween.tween_property(_fade_rect, "color:a", target_alpha, FADE_DURATION)
    await tween.finished
