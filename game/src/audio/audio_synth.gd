class_name AudioSynth
extends RefCounted

## Procedural, code-generated audio only (P41) — no imported/downloaded
## SFX or music files ever, mirroring ProceduralMeshFactory's role for
## visuals (see docs/legal/ASSET_PROVENANCE.md). Every clip is synthesized
## at runtime from a waveform type plus a linear attack/decay envelope, so
## every generated SFX cue is click-free by construction: sample 0 always
## starts at silence and the final sample always ends at silence (see
## DataValidator's envelope-fits-duration check on data/sfx_cues.json).

const SAMPLE_RATE: int = 22050

static func generate_tone(waveform: String, freq_hz: float, duration_sec: float, attack_sec: float, decay_sec: float, gain_db: float) -> AudioStreamWAV:
    var frame_count: int = maxi(int(round(duration_sec * SAMPLE_RATE)), 1)
    var attack_frames: int = int(round(attack_sec * SAMPLE_RATE))
    var decay_frames: int = int(round(decay_sec * SAMPLE_RATE))
    var gain: float = db_to_linear(gain_db)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = int(freq_hz * 1000.0) + frame_count

    var data: PackedByteArray = PackedByteArray()
    data.resize(frame_count * 2)
    for i in frame_count:
        var t: float = float(i) / float(SAMPLE_RATE)
        var raw: float = _waveform_sample(waveform, freq_hz, t, rng)
        var env: float = _envelope(i, frame_count, attack_frames, decay_frames)
        var sample: float = clampf(raw * env * gain, -1.0, 1.0)
        data.encode_s16(i * 2, int(round(sample * 32767.0)))

    var stream: AudioStreamWAV = AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = SAMPLE_RATE
    stream.stereo = false
    stream.data = data
    return stream

## A loopable ambient pad: sums a small chord of integer-ratio sine
## partials over an exact whole number of fundamental cycles, so sample 0
## and the sample just past the end land at the same phase for every
## partial — a phase-continuous loop seam with no discontinuity/click,
## without needing a fade-based crossfade at the loop point. chord_ratios
## must be positive integers (e.g. [2, 3, 4]) so ratio * cycles is always
## a whole number of partial-cycles too.
static func generate_pad_loop(root_freq_hz: float, chord_ratios: Array, target_loop_seconds: float, gain_db: float) -> AudioStreamWAV:
    var cycles: int = maxi(int(round(root_freq_hz * target_loop_seconds)), 1)
    var actual_duration: float = float(cycles) / root_freq_hz
    var frame_count: int = maxi(int(round(actual_duration * SAMPLE_RATE)), 1)
    var gain: float = db_to_linear(gain_db)

    var data: PackedByteArray = PackedByteArray()
    data.resize(frame_count * 2)
    for i in frame_count:
        var t: float = float(i) / float(SAMPLE_RATE)
        var sum: float = 0.0
        for ratio: float in chord_ratios:
            sum += sin(TAU * root_freq_hz * ratio * t)
        sum /= float(chord_ratios.size())
        var sample: float = clampf(sum * gain, -1.0, 1.0)
        data.encode_s16(i * 2, int(round(sample * 32767.0)))

    var stream: AudioStreamWAV = AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = SAMPLE_RATE
    stream.stereo = false
    stream.data = data
    stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    stream.loop_begin = 0
    stream.loop_end = frame_count
    return stream

static func _waveform_sample(waveform: String, freq_hz: float, t: float, rng: RandomNumberGenerator) -> float:
    var phase: float = fmod(freq_hz * t, 1.0)
    match waveform:
        "sine":
            return sin(phase * TAU)
        "square":
            return 1.0 if phase < 0.5 else -1.0
        "triangle":
            return 4.0 * absf(phase - 0.5) - 1.0
        "noise":
            return rng.randf_range(-1.0, 1.0)
        _:
            return sin(phase * TAU)

static func _envelope(i: int, frame_count: int, attack_frames: int, decay_frames: int) -> float:
    if attack_frames > 0 and i < attack_frames:
        return float(i) / float(attack_frames)
    var decay_start: int = frame_count - decay_frames
    if decay_frames > 0 and i >= decay_start:
        return float(frame_count - i) / float(decay_frames)
    return 1.0
