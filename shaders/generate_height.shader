shader_type canvas_item;
render_mode blend_disabled, unshaded;


// Dynamic inputs
uniform sampler2D _islands;
uniform int _num_islands;
// 3 pixels per island:
// - RGBA first two points of bezier
// - RGBA other two points of bezier
// - R seed, G min-size cell, B max-size cell, A reserved
// Total: 3x_num_islands width, 1 height
uniform highp float _world_seed;
// Static inputs
uniform sampler2D _material_heights;

// Outputs
// R - height
// G - <0 sea floor influence, >0 surface influence
// B - <0 beach influence, >0 mountain influence
// A - reserved (vegetation influence?)

// ----------------
// Helper functions
// ----------------

float ndot(vec2 a, vec2 b)
{
	return a.x*b.x - a.y*b.y;
}

float rand(highp float n)
{
	return fract(sin(n) * 43758.5453123);
}

float noise(highp float p)
{
	highp float fl = floor(p);
	highp float fc = fract(p);
	return mix(rand(fl), rand(fl + 1.0), fc);
}

float rand2D(vec2 n)
{ 
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float noise2D(vec2 n)
{
	const vec2 d = vec2(0.0, 1.0);
	vec2 b = floor(n), f = smoothstep(vec2(0.0), vec2(1.0), fract(n));
	return mix(mix(rand2D(b), rand2D(b + d.yx), f.x), mix(rand2D(b + d.xy), rand2D(b + d.yy), f.x), f.y);
}

mat2 rotation2d(float angle)
{
	float s = sin(angle);
	float c = cos(angle);
	return mat2(vec2(c, -s), vec2(s, c));
}

vec2 quadratic_bezier(float f, vec2 p1, vec2 p2, vec2 p3)
{
	float f1 = 1.0 - f;
	float f2 = f;
	vec2 l1 = p1 * f1 + p2 * f2;
	vec2 l2 = p2 * f1 + p3 * f2;
	return l1 * f1 + l2 * f2;
}

vec2 cubic_bezier(float f, vec2 p1, vec2 p2, vec2 p3, vec2 p4)
{
	float f1 = 1.0 - f;
	float f2 = f;
	vec2 l1 = p1 * f1 + p2 * f2;
	vec2 l2 = p2 * f1 + p3 * f2;
	vec2 l3 = p3 * f1 + p4 * f2;
	return quadratic_bezier(f, l1, l2, l3);
}

float smin(float d1, float d2, float k)
{
	float h = clamp(0.5 + 0.5*(d2 - d1)/k, 0.0, 1.0);
	return mix(d2, d1, h) - k * h * (1.0-h);
}

float smax(float a, float b, float k)
{
	float x = exp(k * a);
	float y = exp(k * b);
	return max((a * x + b * y) / (x + y), a);
}

float pack_snorm(float f)
{
	uint i = uint(clamp(f, -1.0, 1.0) * 32767.0);
	return uintBitsToFloat(i);
}

float unpack_snorm(float f)
{
	uint i = floatBitsToUint(f);
	return float(clamp(float(f)/32727.0, -1.0, 1.0));
}

float easeInQuad(float x)
{
	return x * min(x, 1.0);
}

float easeOutQuad(float x)
{
	return 1.0 - (1.0 - x) * max(1.0 - x, 1.0);
}

float easeInOutQuad(float x)
{
	return x < 0.5 ? 2.0 * x * x : 1.0 - pow(-2.0 * x + 2.0, 2.0) / 2.0;
}

float lowp_interpol(float x, float start, float end, float a, float b)
{
	return mix(a, b, easeInQuad(max((x - start) / (end - start),  0.0)));
}

float highp_interpol(float x, float start, float end, float a, float b)
{
	return mix(a, b, min((x - start) / (end - start), 1.0));
}

float interpolate(float x, float start, float end, float a, float b)
{
	return mix(a, b, easeInOutQuad(clamp((x - start) / (end - start), 0.0, 1.0)));
}



// --------------
// SDF-Generation
// --------------

float sdfRhombus( in vec2 p, in vec2 b ) 
{
	vec2 q = abs(p);
	float h = clamp((-2.0*ndot(q,b)+ndot(b,b))/dot(b,b),-1.0,1.0);
	float d = length( q - 0.5*b*vec2(1.0-h,1.0+h) );
	return d * sign( q.x*b.y + q.y*b.x - b.x*b.y );
}

float sdfBeveledRotatedRhombus(in vec2 p, in vec2 q, float rotation)
{
	vec2 bounding_box = q*vec2(1.0, 1.0);
	return max(sdfRhombus(rotation2d(rotation*3.14*2.0)*p, q*0.3) - max(q.x, q.y)*0.7, sdfRhombus(rotation2d((rotation+0.125)*3.14*2.0)*p, q.xy*0.3) - max(q.x, q.y)*0.7);
}

float sdfIslandCell(float seed, vec2 p, int i, int max_i, float cell_size_min, float cell_size_max)
{
	float cell_seed = seed + 1.3452 * float(i);
	float f = (float(i)+0.5) / float(max_i);
	float close_to_center = pow(1.0-abs(f - 0.5)*2.0, 2.0);

	vec2 cell_size = vec2(1.0);
	cell_size.x = cell_size_min + mix(noise(cell_seed + 6.34326) * close_to_center, 1.0, close_to_center) * (cell_size_max-cell_size_min);
	cell_size.y = cell_size_min + noise(cell_seed + 22.4523) * (cell_size_max-cell_size_min);
	vec2 offset = cell_size * noise2D(vec2(cell_seed+234.234, cell_seed+456.234));

	return sdfBeveledRotatedRhombus(p-offset*0.75, cell_size, noise(cell_seed));
}

float sdfIsland(float seed, vec2 pos, vec2 A, vec2 B, vec2 C, vec2 D, float cell_size_min, float cell_size_max, int num_cells)
{
	float result = 999999.0;
	for(int i = 0; i < num_cells; i++)
	{
		vec2 p = cubic_bezier((float(i)+0.5) / float(num_cells), pos-A, pos-B, pos-C, pos-D);
		result = min(result, sdfIslandCell(seed, p, i, num_cells, cell_size_min, cell_size_max));
	}
	return result;
}

// Normalized to 0 - 1 range, 0.0 is outer edge, 1.0 is point closest to center, multiplied by a factor and added together
float randomizedUnormIsland(float seed, vec2 pos, vec2 A, vec2 B, vec2 C, vec2 D, float cell_size_min, float cell_size_max, int num_cells,
							float intensity_seed)
{
	float result = 0.0;
	for(int i = 0; i < num_cells; i++)
	{
		vec2 p = cubic_bezier((float(i)+0.5) / float(num_cells), pos-A, pos-B, pos-C, pos-D);
		float intensity = noise(intensity_seed + 2.4452 * float(i));
		float cell = sdfIslandCell(seed, p, i, num_cells, cell_size_min, cell_size_max);
		//cell /= sdfIslandCell(seed, vec2(0.0, 0.0), i, num_cells, cell_size_min, cell_size_max);
		cell /= -cell_size_max;
		cell *= intensity;
		cell = clamp(cell, 0.0, 1.0);
		result += cell;
	}
	return result;
}

vec4 isolines(float d, float line_distance)
{
	vec3 col = vec3(0.576471, 0.647059, 0.827451);
	if(sign(d) < 0.0)
		col = vec3(0.470588, 0.560784, 0.392157);
	//col *=;
	col *= 0.9 + cos(line_distance*d/3.14) * (exp(-abs(d/(line_distance*50.0))) * 0.2);
	col = mix(col, vec3(1.0), 1.0-smoothstep(0.0, line_distance*2.0, abs(d)));
	return vec4(col, 1.0);
}

// -------------------
// Heightmap functions
// -------------------

float merge_heightmap(float height, float material_height, float merge_height)
{
	float factor = smoothstep(height, height+merge_height, material_height);
	return factor;
}

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
	// Generate SDF
	float   island_shape = 99.99e+8;
	float mountain_cells = 0.0;

	for(int i = 0; i < _num_islands; i++)
	{
		vec4 AB = texelFetch(_islands, ivec2(i*3+0, 0), 0);
		vec4 CD = texelFetch(_islands, ivec2(i*3+1, 0), 0);
		vec4 props    = texelFetch(_islands, ivec2(i*3+2, 0), 0);

		island_shape   = min(island_shape, sdfIsland(_world_seed + props.r, world_coords, AB.rg, AB.ba, CD.rg, CD.ba, props.g, props.b, 12));
		mountain_cells = max(mountain_cells, randomizedUnormIsland(_world_seed + props.r, world_coords, AB.rg, AB.ba, CD.rg, CD.ba, props.g, props.b, 12, _world_seed + 632.6573 + props.r * 1.25645) * 1.5);
	}

	// Generate heightmap from SDF
	float   floor_inner_r = 0.0;
	float   floor_outer_r = 8000.0;

	float   cliff_center = -100.0;
	float   cliff_r = 150.0 * 2.0;

	float surface_center = -450.0;
	float surface_r = 350.0 * 2.0;

	float     floor_base_height = -10.0;
	float     cliff_base_height =  1.0;
	float   surface_base_height =  5.0;

	float   floor_height  = interpolate(island_shape, floor_inner_r, floor_outer_r, -2.0, -10.0);
	        floor_height += highp_interpol(island_shape, floor_inner_r, floor_outer_r, 0.0, -0.5);
	float   cliff_height  = lowp_interpol(island_shape, cliff_center - cliff_r, cliff_center + cliff_r, cliff_base_height, 0.0);
	float surface_height  = lowp_interpol(island_shape, surface_center - surface_r, surface_center + surface_r, surface_base_height, -1.0);

	// Outputs
	float influence_cliff    = 0.0;
	float influence_surface  = 0.0;
	float influence_mountain = 0.0;
	float influence_beach    = 0.0;
	float height = 0.0;

	vec4 materials = texture(_material_heights, world_uv);
	// materials.r - Cliffs
	// materials.g - Sea Floor
	// materials.b - Mountains
	// materials.a - Surface

	float mountain_height = surface_height + materials.b * mountain_cells * 4.0;
	cliff_height += materials.r * 2.0;
	floor_height += materials.g * 1.4 * 2.0;
	surface_height += materials.a * 4.0;

	height = floor_height;
	influence_cliff = merge_heightmap(height, cliff_height, 3.00);
	height = mix(height, cliff_height, influence_cliff);
	influence_surface = merge_heightmap(height, surface_height, 1.00);
	height = mix(height, surface_height, influence_surface);
	influence_mountain = merge_heightmap(height, mountain_height, 4.00);
	height = mix(height, mountain_height, influence_mountain);

	float influence_floor = 1.0 - influence_cliff;
	COLOR.r = height;
	COLOR.g = influence_surface  - influence_floor;
	COLOR.b = influence_beach - influence_mountain;
	COLOR.a = 1.0; // Reservered for two more biomes

	//COLOR = vec4(vec3(smoothstep(-8.0, 8.0, height)), 1.0);
	//COLOR = vec4(vec3(mountain_cells), 1.0);
	//COLOR = vec4(vec3(smoothstep(-2.0, 2.0, floor_height), smoothstep(-2.0, 2.0, cliff_height), smoothstep(0.0, 1.0, cliff_height-floor_height)), 1.0);
}

