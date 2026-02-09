shader_type canvas_item;

// DRAMATIC Bones Sparkle Shader - Visible energy sparks flying off!
uniform float intensity : hint_range(0.0, 3.0) = 2.0;
uniform vec4 spark_color : source_color = vec4(1.0, 0.9, 0.3, 1.0); // Bright golden
uniform vec4 energy_color : source_color = vec4(1.0, 0.6, 0.1, 1.0); // Orange energy

// Pseudo-random for spark positions
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    vec4 original = texture(TEXTURE, UV);
    float time = TIME * 2.0;
    
    // Base pulsing glow - strong!
    float pulse = 0.7 + 0.3 * sin(time * 5.0);
    
    // Create multiple spark layers
    float sparks = 0.0;
    
    // Layer 1: Fast small sparks
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float angle = fi * 0.785 + time * 3.0; // Rotate around
        float dist = 0.3 + 0.2 * sin(time * 4.0 + fi);
        vec2 spark_pos = vec2(0.5, 0.5) + vec2(cos(angle), sin(angle)) * dist;
        float spark = 1.0 - smoothstep(0.0, 0.08, length(UV - spark_pos));
        spark *= sin(time * 10.0 + fi * 2.0) * 0.5 + 0.5; // Flicker
        sparks += spark;
    }
    
    // Layer 2: Slower larger energy bursts
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float angle = fi * 1.57 + time * 1.5;
        float dist = 0.4 + 0.15 * sin(time * 2.0 + fi * 3.0);
        vec2 burst_pos = vec2(0.5, 0.5) + vec2(cos(angle), sin(angle)) * dist;
        float burst = 1.0 - smoothstep(0.0, 0.12, length(UV - burst_pos));
        burst *= sin(time * 5.0 + fi) * 0.5 + 0.5;
        sparks += burst * 0.7;
    }
    
    // Layer 3: Random sparkle noise
    float noise_spark = hash(UV * 50.0 + vec2(time * 5.0, 0.0));
    noise_spark = pow(noise_spark, 8.0) * 2.0; // Sharp sparkles
    sparks += noise_spark * sin(time * 20.0) * 0.5 + 0.5;
    
    // Energy outline glow
    float edge_glow = 0.0;
    if (original.a > 0.1) {
        // Check nearby pixels for edge
        float edge = 0.0;
        edge += texture(TEXTURE, UV + vec2(0.02, 0.0)).a;
        edge += texture(TEXTURE, UV - vec2(0.02, 0.0)).a;
        edge += texture(TEXTURE, UV + vec2(0.0, 0.02)).a;
        edge += texture(TEXTURE, UV - vec2(0.0, 0.02)).a;
        edge_glow = (4.0 - edge) * 0.5 * original.a;
    }
    
    // Combine effects
    vec4 glow = mix(spark_color, energy_color, sin(time * 3.0) * 0.5 + 0.5);
    
    // Apply sparks where original has content, plus energy around edges
    float spark_mask = sparks * intensity * pulse;
    vec4 spark_effect = glow * spark_mask;
    
    // Strong additive glow
    COLOR = original;
    COLOR.rgb += spark_effect.rgb * original.a * 0.8;
    COLOR.rgb += glow.rgb * edge_glow * pulse * intensity;
    COLOR.rgb += glow.rgb * original.a * pulse * 0.3; // Base glow on whole sprite
    COLOR.a = original.a;
}
