shader_type canvas_item;
render_mode unshaded, blend_add;

// Explicit game time: stopping advance() freezes both flame and embers.
uniform float phase = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float tongue(vec2 p, float center, float height, float seed) {
	float rise = p.y / height;
	float sway = (0.065 * sin(phase * 2.1 + seed + rise * 5.0)
		+ 0.025 * sin(phase * 3.6 + seed * 2.0 + rise * 10.0)) * rise;
	float width = 0.19 * pow(max(1.0 - rise, 0.0), 0.7) + 0.013;
	float shape = 1.0 - smoothstep(width * 0.12, width, abs(p.x - center - sway));
	shape *= smoothstep(0.0, 0.09, p.y) * (1.0 - smoothstep(0.72, 1.0, rise));
	float turbulence = noise(vec2(p.x * 13.0 + seed, p.y * 8.0 - phase * 1.55));
	turbulence += noise(vec2(p.x * 27.0 - seed, p.y * 19.0 - phase * 2.6)) * 0.30;
	return shape * smoothstep(0.28, 0.77, turbulence);
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * 2.0, 1.0 - UV.y - 0.09);
	float flame = tongue(p, -0.18, 0.49, 1.0);
	flame = max(flame, tongue(p, 0.0, 0.75, 4.2));
	flame = max(flame, tongue(p, 0.18, 0.56, 8.4));
	vec3 amber = mix(vec3(1.0, 0.19, 0.025), vec3(1.0, 0.70, 0.16), flame * 0.75);
	float sparks = 0.0;
	for (int i = 0; i < 4; i++) {
		float seed = float(i) * 1.73;
		float life = fract(phase * (0.18 + float(i) * 0.012) + float(i) * 0.29);
		vec2 center = vec2(sin(seed) * 0.20 + sin(life * 4.0 + seed) * life * 0.12,
			0.14 + life * 0.70);
		vec2 distance = (p - center) / vec2(0.009, 0.016);
		float spark = 1.0 - smoothstep(0.2, 1.0, length(distance));
		sparks += spark * smoothstep(0.0, 0.15, life) * (1.0 - smoothstep(0.60, 1.0, life));
	}
	vec3 color = mix(amber, vec3(1.0, 0.65, 0.18), clamp(sparks, 0.0, 1.0));
	COLOR = vec4(color, clamp(flame * 0.40 + sparks * 0.58, 0.0, 0.65));
}
