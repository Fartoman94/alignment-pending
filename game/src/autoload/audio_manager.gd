extends Node

## Adaptive music state machine + procedurally-generated SFX playback
## (P41). Every sound in the game — SFX cues and the two music beds alike
## — is synthesized at runtime by AudioSynth from data/sfx_cues.json;
## nothing is ever imported or downloaded (see
## docs/legal/ASSET_PROVENANCE.md). Bus-level volume (the player's
## Master/Music/SFX/UI sliders) stays SettingsManager's job; this
## autoload only ever adjusts individual AudioStreamPlayer.volume_db —
## the two knobs compose additively in dB without stomping each other.

const SFX_VOICE_POOL_SIZE: int = 6
const MUSIC_CROSSFADE_SECONDS: float = 2.0
const MUSIC_SILENT_DB: float = -40.0
const DUCK_DB: float = -8.0
const DUCK_ATTACK_SECONDS: float = 0.15
const DUCK_RELEASE_SECONDS: float = 1.2

var _sfx_streams: Dictionary = {}  # cue_id -> AudioStreamWAV, built lazily
var _sfx_voices: Array[AudioStreamPlayer] = []
var _next_voice_index: int = 0

var _music_calm: AudioStreamPlayer
var _music_tense: AudioStreamPlayer
var _music_state: String = "calm"
var _music_tween: Tween
var _duck_tween: Tween

func _ready() -> void:
    _build_sfx_voice_pool()
    _build_music_players()
    EventBus.incident_raised.connect(_on_incident_raised)
    EventBus.incident_resolved.connect(_on_incident_resolved)
    EventBus.day_advanced.connect(_on_day_advanced)
    EventBus.simulation_pause_changed.connect(_on_pause_changed)
    EventBus.research_unlocked.connect(func(_id: String) -> void: play_sfx("research_unlocked"))
    EventBus.model_created.connect(func(_id: String) -> void: play_sfx("model_trained"))
    # Unconditional, unlike _refresh_music_state()'s change-only crossfade
    # below: on boot there is no "previous" state to fade from, so the
    # initial bed just needs to start audible immediately.
    _crossfade_to(_music_state)

func _build_sfx_voice_pool() -> void:
    for i in SFX_VOICE_POOL_SIZE:
        var voice: AudioStreamPlayer = AudioStreamPlayer.new()
        voice.name = "SfxVoice%d" % i
        add_child(voice)
        _sfx_voices.append(voice)

func _build_music_players() -> void:
    _music_calm = AudioStreamPlayer.new()
    _music_calm.name = "MusicCalm"
    _music_calm.bus = "Music"
    _music_calm.stream = AudioSynth.generate_pad_loop(110.0, [2, 3, 4], 4.0, -14.0)
    _music_calm.volume_db = MUSIC_SILENT_DB
    add_child(_music_calm)

    _music_tense = AudioStreamPlayer.new()
    _music_tense.name = "MusicTense"
    _music_tense.bus = "Music"
    _music_tense.stream = AudioSynth.generate_pad_loop(146.83, [2, 3, 5], 2.0, -12.0)
    _music_tense.volume_db = MUSIC_SILENT_DB
    add_child(_music_tense)

## Cached, generated on first use per cue id — a JSON-defined placeholder
## SFX library with no imported audio files.
func _get_or_build_stream(cue_id: String) -> AudioStreamWAV:
    if _sfx_streams.has(cue_id):
        return _sfx_streams[cue_id]
    var def: Dictionary = SfxCueCatalog.get_def(cue_id)
    if def.is_empty():
        return null
    var stream: AudioStreamWAV = AudioSynth.generate_tone(
        String(def.get("waveform", "sine")),
        float(def.get("base_freq", 440.0)),
        float(def.get("duration_sec", 0.1)),
        float(def.get("attack_sec", 0.0)),
        float(def.get("decay_sec", 0.0)),
        float(def.get("gain_db", -6.0)),
    )
    _sfx_streams[cue_id] = stream
    return stream

## Plays a data-driven SFX cue on its catalog bus via a round-robin voice
## pool (so several cues can overlap without cutting each other off).
func play_sfx(cue_id: String) -> void:
    var stream: AudioStreamWAV = _get_or_build_stream(cue_id)
    if stream == null:
        return
    var def: Dictionary = SfxCueCatalog.get_def(cue_id)
    var voice: AudioStreamPlayer = _sfx_voices[_next_voice_index]
    _next_voice_index = (_next_voice_index + 1) % _sfx_voices.size()
    voice.bus = String(def.get("bus", "SFX"))
    voice.stream = stream
    voice.volume_db = 0.0
    voice.play()

## The pure decision function behind the adaptive state machine: TENSE
## whenever there's something the player urgently needs to deal with
## (a pending incident awaiting a choice, or an active bankruptcy
## countdown); CALM otherwise. Deterministic from GameState alone.
static func compute_music_state(state: Node) -> String:
    if state.pending_incidents.size() > 0:
        return "tense"
    if float(state.bankruptcy_day) >= 0.0:
        return "tense"
    return "calm"

func _refresh_music_state() -> void:
    var target: String = compute_music_state(GameState)
    if target == _music_state:
        return
    _music_state = target
    _crossfade_to(target)

func _crossfade_to(target_state: String) -> void:
    if _music_tween != null and _music_tween.is_valid():
        _music_tween.kill()
    var fade_in: AudioStreamPlayer = _music_tense if target_state == "tense" else _music_calm
    var fade_out: AudioStreamPlayer = _music_calm if target_state == "tense" else _music_tense
    if not fade_in.playing:
        fade_in.play()
    _music_tween = create_tween().set_parallel(true)
    _music_tween.tween_property(fade_in, "volume_db", 0.0, MUSIC_CROSSFADE_SECONDS)
    _music_tween.tween_property(fade_out, "volume_db", MUSIC_SILENT_DB, MUSIC_CROSSFADE_SECONDS)

## A short "sting" duck on every newly raised incident: attenuates the
## Music BUS (not either player's own volume_db), so it always applies to
## whichever bed(s) are currently audible — including mid-crossfade — and
## can never race with _crossfade_to()'s independent per-player tweens.
## Reads the resting level fresh from SettingsManager every time, so it
## always recovers to the player's actual current volume preference
## rather than a value snapshotted once at boot.
func _duck_music() -> void:
    if _duck_tween != null and _duck_tween.is_valid():
        _duck_tween.kill()
    var bus_idx: int = AudioServer.get_bus_index("Music")
    if bus_idx == -1:
        return
    var resting_db: float = linear_to_db(clampf(SettingsManager.music_volume, 0.0001, 1.0))
    _duck_tween = create_tween()
    _duck_tween.tween_method(func(db: float) -> void: AudioServer.set_bus_volume_db(bus_idx, db), resting_db, resting_db + DUCK_DB, DUCK_ATTACK_SECONDS)
    _duck_tween.tween_method(func(db: float) -> void: AudioServer.set_bus_volume_db(bus_idx, db), resting_db + DUCK_DB, resting_db, DUCK_RELEASE_SECONDS)

func _on_incident_raised(_incident_id: StringName) -> void:
    play_sfx("incident_alert")
    _duck_music()
    _refresh_music_state()

func _on_incident_resolved(_incident_id: String, _choice_id: String) -> void:
    _refresh_music_state()

func _on_day_advanced(_day: int) -> void:
    _refresh_music_state()

func _on_pause_changed(_paused: bool) -> void:
    _refresh_music_state()
