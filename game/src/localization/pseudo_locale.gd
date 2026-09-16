class_name PseudoLocale
extends RefCounted

## Pure, deterministic pseudo-localization transform (P45): accents every
## recognized Latin letter and pads the result so it is always at least
## ~35% longer than the source — a standard QA technique for proving a UI
## survives string expansion without needing real translation content.
## Digits, symbols and any character outside ACCENT_MAP pass through
## unchanged (so currency amounts, percentages, etc. stay readable).

const EXPANSION_FACTOR: float = 1.35
const FILLER: String = " ¡únïçødé!"

const ACCENT_MAP: Dictionary = {
    "a": "á", "e": "é", "i": "í", "o": "ó", "u": "ü", "n": "ñ", "c": "ç", "s": "š",
    "A": "Á", "E": "É", "I": "Í", "O": "Ó", "U": "Ü", "N": "Ñ", "C": "Ç", "S": "Š",
}

static func pseudo_localize(source: String) -> String:
    if source.is_empty():
        return source
    var accented: String = _accent_text(source)
    var target_len: int = int(ceil(source.length() * EXPANSION_FACTOR))
    var result: String = accented
    var f: int = 0
    while result.length() < target_len:
        result += FILLER[f % FILLER.length()]
        f += 1
    return "[%s]" % result

static func _accent_text(text: String) -> String:
    var out: String = ""
    for i in text.length():
        var ch: String = text[i]
        out += ACCENT_MAP.get(ch, ch)
    return out
