shader_type canvas_item;
render_mode blend_disabled, unshaded, skip_vertex_transform;

uniform float _contrast = 2.2;
uniform float _exposure = 1.0;
uniform int   _ao_samples = 16;
uniform float _ao_distance = 0.25;
uniform float _ao_sample_bias = 1.4;
uniform float _ao_ray_height = 20.0;
uniform float _ao_strength : hint_range(0.0, 4.0) = 1.0;
uniform float _ao_lod = 1.0;
uniform float _light_shape : hint_range(-1.0, 4.0) = 2.0;
uniform float _2d_view_distortion = -1.0;
uniform float _reflectivity : hint_range(0.0, 1.0) = 1.0;

uniform float _height_scale:  hint_range(0.0, 1.0) = 0.25;

uniform float _mountain_peak_height : hint_range(200, 2000, 50) = 600.0;
uniform float _world_width : hint_range(1000, 40000, 250) = 12000.0;

uniform float _sky_sun_position;
uniform float _sky_sun_height : hint_range(0.1, 1.0);
uniform vec4 _sky_sun_direct_color : hint_color;
uniform vec4 _sky_sun_ambient_color : hint_color;
uniform vec4 _sky_ambient_color : hint_color;
uniform vec4 _sky_background_color : hint_color;

uniform vec4 _water_fog_color : hint_color;
uniform vec4 _water_surface_color : hint_color;
uniform vec4 _water_line_color : hint_color;

uniform sampler2D _height_data;
uniform sampler2D _albedo_roughness;

// -----------------
// Raycast functions
// -----------------

float height_at(vec2 pos, float lod)
{
	return texture(_height_data, pos, lod).r;
}

// Direction: 1 facing the sun, -1 facing away from the sun
vec4 sky_color(float direction)
{
	return mix(mix(_sky_ambient_color.rgba, _sky_background_color.rgba, max(-direction, 0.0)), _sky_sun_ambient_color.rgba, max(pow(direction, 2.0), 0.0));
}

float ray_gather_halfcircle(float zero, vec2 start, vec2 end, float h, int num_rays)
{
	float result = 0.0;
	float current_sample = 0.0;
	for(int i = 0; i < num_rays; i++)
	{
		float f = pow((float(i) + 1.0) / float(num_rays), _ao_sample_bias); // i+1 because we don't need to cast a ray straight up.

		vec3 ray = vec3(mix(start, end, f), h * (f+0.001));
		current_sample = max(current_sample, height_at(ray.xy, _ao_lod) - zero); 
		result += (current_sample - ray.z) / -(ray.z*2.0);
	}
	return max(0.5 + result / float(num_rays), 0.0);
}

float ray_gather_sphere(vec2 pos, float zero, float radius, float h, int num_directions, int num_rays)
{
	float result = 0.0;
	for(int i = 0; i < num_directions; i++)
	{
		float f = (float(i) + 0.5) / float(num_directions);
		vec2 end = pos + vec2(sin(f*6.28), cos(f*6.28))*radius;
		result += ray_gather_halfcircle(zero, pos, end, h, num_rays);
	}
	return clamp(result / float(num_directions), 0.0, 1.0);
}

vec3 calculate_illumination(vec2 pos, float zero, float radius, float h, int num_rays, vec3 normal, float roughness, vec3 view)
{
	float directions[16];
	vec3 global_illumination = vec3(0.0);
	for(int i = 0; i < directions.length(); i++)
	{
		float f = 1.0 - (float(i) / float(directions.length()));
		vec2 end = pos + vec2(sin((f+_sky_sun_position)*6.28), cos((f+_sky_sun_position)*6.28))*radius;
		directions[i] = pow(ray_gather_halfcircle(zero, pos, end, h, num_rays), _light_shape);
		vec4 light_influence = sky_color(f*2.0-1.0) * directions[i];
		global_illumination += light_influence.rgb * light_influence.a;
	}
	global_illumination = global_illumination / float(directions.length());

	vec3 view_reflect = reflect(normal, view);
	vec3 sun_direction = normalize(vec3(sin((_sky_sun_position)*6.28), cos((_sky_sun_position)*6.28), _sky_sun_height));
	float cardial_refl_dir = dot(view_reflect, sun_direction);
	
	float index = (cardial_refl_dir/2.0+0.5)*float(directions.length());
	float refl_occlusion = mix(directions[int(index)], directions[int(index+1.0)%directions.length()], fract(index));
	vec4 global_reflection = sky_color(cardial_refl_dir) * refl_occlusion;

	// 
	vec3 sun_diffuse = smoothstep(0.5, 0.6, directions[0]) * _sky_sun_direct_color.a * _sky_sun_direct_color.rgb * max(dot(normal, sun_direction), 0.0);
	//vec3 sun_specular = _sky_sun_direct_color.a * _sky_sun_direct_color.rgb * clamp(cardial_refl_dir, 0.0, 1.0) * refl_occlusion;

	return global_illumination * _ao_strength + sun_diffuse + global_reflection.rgb * global_reflection.a * roughness * _reflectivity;
}

vec3 ray_light(vec3 col, vec3 light_dir, vec2 normal, float h, vec2 pos)
{
	return ray_gather_halfcircle(h, pos, pos+light_dir.xy*0.05, light_dir.z, 1) * clamp(dot(normalize(light_dir.xy), normal), 0.0, 1.0) * col;
}

// ------------
// Tonemapping
// ------------

vec3 aces_tonemap(vec3 color){	
	mat3 m1 = mat3(
        vec3(0.59719, 0.07600, 0.02840),
        vec3(0.35458, 0.90834, 0.13383),
        vec3(0.04823, 0.01566, 0.83777)
	);
	mat3 m2 = mat3(
        vec3(1.60475, -0.10208, -0.00327),
        vec3(-0.53108,  1.10813, -0.07276),
        vec3(-0.07367, -0.00605,  1.07602)
	);
	vec3 v = m1 * color;    
	vec3 a = v * (v + 0.0245786) - 0.000090537;
	vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
	return pow(clamp(m2 * (a / b), 0.0, 1.0), vec3(1.0 / 2.2));	
}

// -------------
// Main function
// -------------

varying vec2 world_coords;

void vertex()
{
	VERTEX = (EXTRA_MATRIX * (WORLD_MATRIX * vec4(VERTEX, 0.0, 1.0))).xy;
	world_coords = VERTEX;
}

void fragment()
{
	vec4 rgbr = texture(_albedo_roughness, UV);
	float height = height_at(UV, 0.0);
	vec3 VIEW = normalize(vec3((SCREEN_UV.xy * 2.0 - 1.0) * _2d_view_distortion, 4.0));

	vec3 point = vec3(UV, height);
	vec3 tangent = vec3((UV + vec2(0.01, 0.0)), height_at(UV+vec2(0.01, 0.0), 0.0)) - point;
	vec3 bitangent = vec3((UV + vec2(0.0, 0.01)), height_at(UV+vec2(0.0, 0.01), 0.0)) - point;
	vec3 normal = normalize(cross(tangent * vec3(1, 1, _height_scale), bitangent * vec3(1, 1, _height_scale)));
	
	vec3 light = calculate_illumination(UV, height, _ao_distance, _ao_ray_height * _sky_sun_height, _ao_samples, normal, rgbr.a, VIEW);
	//vec3 light  = vec3(pow(ray_gather_sphere(UV, height, 0.50, 4.0, 4, 4), 2.2)) * 0.5;
	//light += vec3(pow(ray_gather_sphere(UV, height, 0.05, 1.0, 4, 4), 1.2)) * 0.5;
	//light += ray_light(vec3(1.0, 1.0, 1.0), vec3(1.0, 0.5, 64.0), normal, height, UV) * 0.25;
	//vec3 light = vec3(smoothstep(0.0, 4.0, height)/2.0+0.5);

	float water_height = 1.0 + sin(world_coords.x/500.0*4.0+TIME) * 0.025;
	float water_depth = max(water_height - height + sin(TIME) * 0.05, 0.0);

	COLOR = vec4(rgbr.rgb * mix(light, _water_fog_color.rgb, min(water_depth * _water_fog_color.a, 1.0)), 1.0);
	COLOR.rgb = mix(COLOR.rgb, _water_surface_color.rgb * mix(light, vec3(1.0), 0.5), min(water_depth * _water_surface_color.a * 4.0, 1.0));
	COLOR.rgb = mix(COLOR.rgb, _water_fog_color.rgb, min(water_depth * _water_fog_color.a, 1.0));
	//COLOR.rgb = mix(COLOR.rgb, _water_line_color.rgb * light, _water_line_color.a * (0.75 + sin(TIME) * 0.25) * smoothstep(0.1, 0.0, abs(water_height - height - 0.15 + sin(TIME) * 0.05)));
	COLOR.rgb = aces_tonemap(pow(COLOR.rgb * _exposure, vec3(_contrast)));
}