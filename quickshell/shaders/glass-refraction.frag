#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 sourceSize;
    float cornerRadius;
    float displacement;
    float refractionOpacity;
    float saturation;
};

layout(binding = 1) uniform sampler2D source;

void main()
{
    vec2 uv = qt_TexCoord0;
    vec2 pixel = uv * sourceSize;
    vec2 halfSize = sourceSize * 0.5;
    float radius = clamp(cornerRadius, 0.0, min(halfSize.x, halfSize.y));
    vec2 q = abs(pixel - halfSize) - (halfSize - vec2(radius));
    float distanceToEdge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    float roundedMask = 1.0 - smoothstep(-0.75, 0.75, distanceToEdge);

    vec2 radial = uv - vec2(0.5);
    vec2 warpedUv = clamp(uv + radial * (dot(radial, radial) * 4.0) * displacement, vec2(0.0), vec2(1.0));
    vec2 dispersion = vec2(0.001, 0.0);
    vec4 center = texture(source, warpedUv);
    float red = texture(source, clamp(warpedUv + dispersion, vec2(0.0), vec2(1.0))).r;
    float blue = texture(source, clamp(warpedUv - dispersion, vec2(0.0), vec2(1.0))).b;

    vec3 refracted = vec3(red, center.g, blue);
    float luminance = dot(refracted, vec3(0.2126, 0.7152, 0.0722));
    refracted = mix(vec3(luminance), refracted, 1.0 + saturation);
    float alpha = roundedMask * refractionOpacity;
    fragColor = vec4(refracted * alpha, center.a * alpha) * qt_Opacity;
}
