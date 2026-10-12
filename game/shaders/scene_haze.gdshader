shader_type canvas_item;
render_mode unshaded, blend_mix;

// Local translucent wisps only: no screen texture, refraction or background blur.
uniform float phase = 0.0;
uniform bool smoke = true;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV;
	float density;
	vec3 tint;
	if (smoke) {
		float rise = 1.0 - p.y;
		float drift = 0.045 * sin(rise * 6.0 - phase * 0.34) + rise * 0.10;
		float width = 0.11 + rise * 0.25;
		float edge = 1.0 - smoothstep(width * 0.2, width, abs(p.x - 0.5 - drift));
		float cloud = noise(vec2(p.x * 5.0 - phase * 0.035, p.y * 5.0 + phase * 0.13));
		cloud = mix(cloud, noise(vec2(p.x * 11.0, p.y * 10.0 + phase * 0.21)), 0.25);
		density = smoothstep(0.28, 0.79, cloud) * edge;
		density *= smoothstep(0.0, 0.17, rise) * (1.0 - smoothstep(0.60, 1.0, rise));
		density *= 0.068;
		tint = vec3(0.33, 0.32, 0.30);
	} else {
		float broad = noise(vec2(p.x * 5.0 - phase * 0.022, p.y * 2.8 + phase * 0.013));
		float detail = noise(vec2(p.x * 12.0 + phase * 0.014, p.y * 5.0));
		density = smoothstep(0.30, 0.83, mix(broad, detail, 0.24));
		// Keep it at ankle level; no opaque band over floor items or gravestones.
		density *= smoothstep(0.06, 0.42, p.y) * (1.0 - smoothstep(0.82, 1.0, p.y));
		density *= smoothstep(0.0, 0.055, p.x) * (1.0 - smoothstep(0.945, 1.0, p.x));
		density *= 0.047;
		tint = vec3(0.34, 0.42, 0.46);
	}
	COLOR = vec4(tint, density);
}
