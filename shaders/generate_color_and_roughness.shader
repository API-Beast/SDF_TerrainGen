shader_type canvas_item;
render_mode blend_disabled, unshaded;

// Inputs
uniform sampler2D _base_data;
uniform sampler2D _slope_data;

// _base_data R - height without slopes (unused)
// _base_data G - <0 sea floor influence, >0 surface influence
// _base_data B - <0 beach influence, >0 mountain influence
// _base_data A - reserved (vegetation influence?)
// _slope_data R - height with slopes (unused)
// _slope_data G - grass influence
// _slope_data B - sand influence
// _slope_data A - snow influence

// RGBR - Red, Green, Blue, Roughness
uniform sampler2D _cliffs_rgbr;
uniform sampler2D _surface_rgbr;
uniform sampler2D _mountain_rgbr;
uniform sampler2D _seafloor_rgbr;

// -------------
// Main function
// -------------

varying vec2 world_coords;
varying vec2 world_uv;

void vertex()
{
	world_coords = VERTEX;
	world_uv = world_coords / 1500.0;
}

void fragment()
{
	vec4 data = texture(_base_data, UV);

	float biome_influences_a = data.g;
	float biome_influences_b = data.b;
	//float biome_influences_c = unpack_snorm(data.a);

	float influence_floor    = max(-biome_influences_a, 0.0);
	float influence_surface  = max( biome_influences_a, 0.0);
	float influence_mountain = max(-biome_influences_b, 0.0);
	float influence_beach    = max( biome_influences_b, 0.0);
	// float influence_vegetation = ...
	
	vec4 cliffs   = texture(_cliffs_rgbr, world_uv);
	vec4 seafloor = texture(_seafloor_rgbr, world_uv);
	vec4 surface  = texture(_surface_rgbr, world_uv);
	vec4 mountain = texture(_mountain_rgbr, world_uv);

	COLOR = mix(cliffs, seafloor, influence_floor);
	COLOR = mix(COLOR, surface,  influence_surface);
	COLOR = mix(COLOR, mountain, influence_mountain);
}