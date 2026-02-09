shader_type canvas_item;

// Flame Burst Shader - INSTA-KILL effect with fiery dissolve
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flame_color_inner : source_color = vec4(1.0, 0.95, 0.6, 1.0); // Bright yellow core
uniform vec4 flame_color_mid : source_color = vec4(1.0, 0.6, 0.1, 1.0); // Orange
uniform vec4 flame_color_outer : source_color = vec4(0.9, 0.2, 0.1, 1.0); // Red edge

// Simple pseudo-random function
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // Smoothstep
    
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
    vec4 original = texture(TEXTURE, UV);
    
    // Create flame-like noise pattern
    float time = TIME * 3.0;
    vec2 flame_uv = UV;
    flame_uv.y -= progress * 0.5; // Flames rise upward
    
    // Multi-octave noise for flame shape
    float n = noise(flame_uv * 8.0 + vec2(0.0, time));
    n += noise(flame_uv * 16.0 + vec2(0.0, time * 1.5)) * 0.5;
    n += noise(flame_uv * 32.0 + vec2(0.0, time * 2.0)) * 0.25;
    n = n / 1.75;
    
    // Dissolve threshold based on progress
    float dissolve_edge = progress * 1.5;
    float burn_width = 0.15;
    
    // Create burn edge
    float burn = smoothstep(dissolve_edge - burn_width, dissolve_edge, n);
    float alpha_mask = step(n, dissolve_edge);
    
    // Flame color gradient based on distance from burn edge
    float edge_dist = abs(n - dissolve_edge) / burn_width;
    vec4 flame = mix(flame_color_inner, flame_color_mid, edge_dist);
    flame = mix(flame, flame_color_outer, smoothstep(0.3, 1.0, edge_dist));
    
    // Combine: show original with flame overlay, then dissolve
    vec4 result = original;
    
    // Add flame glow near burn edge
    float glow = (1.0 - edge_dist) * burn * (1.0 - alpha_mask);
    result = mix(result, flame, glow * 2.0);
    
    // Apply dissolve
    result.a = original.a * alpha_mask;
    
    // Add bright edge at dissolve line
    float edge_glow = smoothstep(0.0, burn_width * 0.5, burn_width - abs(n - dissolve_edge));
    result.rgb += flame_color_inner.rgb * edge_glow * (1.0 - alpha_mask) * 2.0;
    
    COLOR = result;
}
