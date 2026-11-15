# Liquid glass rendering

Fjord combines a theme-aware internal surface with optional compositor blur. `GlassSurface.qml` draws a tinted surface, a static top highlight, and a restrained edge. Its appearance follows the light/dark theme and the Subtle, Balanced, or Full material setting. Image and video viewer controls can refract and slightly saturate an application-owned texture beneath their surface; they sample only the visible control area at half resolution. This local effect is separate from desktop backdrop blur.

The Appearance page's Performance mode removes those highlights and client-requested blur, disables optional animation speeds, and turns off texture capture and refraction. Video viewer controls refresh their small source texture as frames arrive while the effect is enabled. Image viewer controls instead request a snapshot when the file, zoom, pan, rotation, or raster size changes, so an idle image does not keep an offscreen render active.

## Backdrop blur

Wayland does not give an application arbitrary access to pixels behind its windows. Fjord requests blur only through `ext-background-effect-v1`, when the compositor advertises that protocol. The current session can be checked with `dfiles blur check`.

Umbriel also has compositor-owned window blur rules. Those rules work independently of the client protocol and are configured by the desktop owner. For Fjord, a matching rule can be added to Umbriel's configuration:

```toml
[[window_rule]]
match.app_id = "^io[.]github[.]febsho[.]fjordfiles$"
blur = true
```

Do not add this when a broader rule already enables blur. Current Umbriel releases may provide blur through window rules without advertising `ext-background-effect-v1`; in that case Fjord leaves blur under compositor control and its Appearance settings explain that limitation.

## Shader limits

Qt 6 `ShaderEffect` uses precompiled `.qsb` packages for the selected RHI backend. Rebuild the checked-in shader package after changing its source with `scripts/compile-glass-shader.sh` (Qt Shader Tools is required for this development step). `ShaderEffectSource` adds an offscreen render and a small GPU texture; Fjord limits that cost to the control strip and disables it in Performance mode.

Wayland does not give an application arbitrary access to pixels behind its windows. Fjord's shader samples only content rendered by Fjord itself; it cannot distort or saturate the desktop behind a Wayland surface. When no application-owned source is available, the normal tinted surface remains readable and compositor blur stays optional.
