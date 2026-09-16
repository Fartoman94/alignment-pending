extends SceneTree

# Rasterizes assets/branding/icon.svg into the PNG sizes the app icon and
# the Windows .ico builder (tools/build_ico.py) need. Run headless:
#   godot4 --headless --script res://tools/render_branding.gd
func _initialize() -> void:
	var svg_path := "res://assets/branding/icon.svg"
	var svg_bytes := FileAccess.get_file_as_bytes(svg_path)
	if svg_bytes.is_empty():
		push_error("render_branding: could not read %s" % svg_path)
		quit(1)
		return
	var sizes := [16, 32, 48, 64, 128, 256]
	for size in sizes:
		var img := Image.new()
		var scale := float(size) / 512.0
		var err := img.load_svg_from_buffer(svg_bytes, scale)
		if err != OK:
			push_error("render_branding: failed to rasterize at size %d (err %d)" % [size, err])
			quit(1)
			return
		if img.get_width() != size:
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		var out_path := "res://assets/branding/icon_%d.png" % size
		var save_err := img.save_png(out_path)
		if save_err != OK:
			push_error("render_branding: failed to save %s (err %d)" % [out_path, save_err])
			quit(1)
			return
		print("wrote ", out_path)
	# Primary app icon (Godot's config/icon expects a single image; 256 is
	# a safe default that Godot itself downsamples for the editor/dock UI).
	var main_img := Image.new()
	main_img.load_svg_from_buffer(svg_bytes, 256.0 / 512.0)
	main_img.save_png("res://assets/branding/icon.png")
	print("wrote res://assets/branding/icon.png")
	quit(0)
