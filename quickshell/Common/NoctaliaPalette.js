.pragma library

// Noctalia's Qt template writes Qt QPalette roles in this fixed order.
function parse(text) {
    const match = /^\s*active_colors\s*=\s*([^\r\n]+)$/m.exec(text || "");
    if (!match)
        return null;
    const colors = match[1].split(",").map(value => value.trim());
    if (colors.length < 21 || colors.some(value => !/^#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?$/.test(value)))
        return null;
    const surface = colors[10];
    const red = parseInt(surface.slice(1, 3), 16);
    const green = parseInt(surface.slice(3, 5), 16);
    const blue = parseInt(surface.slice(5, 7), 16);
    return {
        "light": (red * 299 + green * 587 + blue * 114) / 1000 >= 128,
        "colors": {
            "primary": colors[21] || colors[12],
            "primaryText": colors[13],
            "primaryContainer": colors[12],
            "onPrimaryContainer": colors[13],
            "secondary": colors[14],
            "surface": surface,
            "surfaceText": colors[0],
            "surfaceVariant": colors[16],
            "surfaceVariantText": colors[20],
            "surfaceTint": colors[21] || colors[12],
            "background": colors[9],
            "backgroundText": colors[6],
            "outline": colors[5],
            "surfaceContainer": colors[1],
            "surfaceContainerHigh": colors[16],
            "surfaceContainerHighest": colors[18]
        }
    };
}
