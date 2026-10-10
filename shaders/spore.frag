// Spore Trip (mystery salvage curse): the cave wobbles, the colour channels
// drift apart and the hue cycles. uAmount 0…1 eases the whole effect in/out.
#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uAmount;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float a = uAmount;
  // Slow rolling waves, stronger toward the screen edges.
  float edge = 0.4 + 0.6 * length(uv - 0.5) * 1.4;
  vec2 wave = vec2(
    sin(uv.y * 11.0 + uTime * 2.1) + 0.5 * sin(uv.y * 23.0 - uTime * 3.3),
    cos(uv.x * 9.0 + uTime * 1.7) + 0.5 * cos(uv.x * 19.0 + uTime * 2.6)
  ) * 0.009 * a * edge;
  vec2 q = clamp(uv + wave, 0.0, 1.0);
  // Chromatic split that breathes.
  vec2 split = vec2(0.006 + 0.004 * sin(uTime * 1.3), 0.0) * a;
  vec4 base = texture(uTexture, q);
  float r = texture(uTexture, clamp(q + split, 0.0, 1.0)).r;
  float b = texture(uTexture, clamp(q - split, 0.0, 1.0)).b;
  vec3 col = vec3(r, base.g, b);
  // Psychedelic hue drift (colours are premultiplied, so tint by alpha).
  vec3 tint = 0.5 + 0.5 * cos(uTime * 0.8 + vec3(0.0, 2.1, 4.2) + uv.xyx * 4.0);
  col = mix(col, col * (0.6 + tint * 0.9), 0.35 * a);
  fragColor = vec4(col, base.a);
}
