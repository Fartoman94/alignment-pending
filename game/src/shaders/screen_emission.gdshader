shader_type spatial;
uniform vec4 screen_color : source_color = vec4(0.05,0.65,1.0,1.0);
uniform float emission_strength = 2.0;
void fragment() {
    ALBEDO = screen_color.rgb * 0.12;
    EMISSION = screen_color.rgb * emission_strength;
    ROUGHNESS = 0.25;
}
