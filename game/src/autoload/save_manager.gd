extends Node

const SAVE_PATH: String = "user://campaign_01.json"

func save_game() -> Error:
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(JSON.stringify(GameState.to_dict(), "  "))
    file.close()
    return OK

func load_game() -> Error:
    if not FileAccess.file_exists(SAVE_PATH):
        return ERR_FILE_NOT_FOUND
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return FileAccess.get_open_error()
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not parsed is Dictionary:
        return ERR_PARSE_ERROR
    GameState.from_dict(parsed)
    return OK
