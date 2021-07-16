shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D _base_data;

// _base_data R - height without slopes
// _base_data G - <0 sea floor influence, >0 surface influence
// _base_data B - <0 beach influence, >0 mountain influence
// _base_data A - reserved (vegetation influence?)

uniform sampler2D _slope_heights;

uniform float _deep_sea_line = -4.0;
uniform float _beach_line = 1.5;
uniform float _grass_line = 4.0;
uniform float _snow_line = 5.0;

uniform float _height_scale = 0.25;
uniform float _lod = 2.0;

void fragment()
{
	vec4 data = texture(_base_data, UV);
	float height = data.r;

	vec3 point = vec3(UV, height);
	vec3 tangent = vec3((UV + vec2(0.01, 0.0)), textureLod(_base_data, UV+vec2(0.01, 0.0), _lod).r) - point;
	vec3 bitangent = vec3((UV + vec2(0.0, 0.01)), textureLod(_base_data, UV+vec2(0.0, 0.01), _lod).r) - point;
	vec3 normal = normalize(cross(tangent * vec3(1, 1, _height_scale), bitangent * vec3(1, 1, _height_scale)));
	float slope = 1.0 - normal.z;

	COLOR = vec4(mix(vec3(slope), normal, step(0.5, SCREEN_UV.x)), 1.0);
	COLOR.r = height;
}
