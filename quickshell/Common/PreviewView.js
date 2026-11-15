.pragma library

const minZoom = 0.25;
const maxZoom = 8;
const zoomStep = 1.25;

function kindFor(mime) {
    if (!mime)
        return "";
    switch (mime) {
    case "application/pdf":
        return "pdf";
    case "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
    case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":
    case "application/vnd.openxmlformats-officedocument.presentationml.presentation":
    case "application/vnd.oasis.opendocument.text":
    case "application/vnd.oasis.opendocument.spreadsheet":
    case "application/vnd.oasis.opendocument.presentation":
        return "office";
    case "application/json":
    case "application/xml":
    case "application/javascript":
    case "application/x-shellscript":
    case "application/yaml":
        return "text";
    }
    if (mime.startsWith("audio/") || mime.startsWith("video/"))
        return "media";
    if (mime.startsWith("image/"))
        return "image";
    return mime.startsWith("text/") || mime.endsWith("+xml") || mime.endsWith("+json") ? "text" : "";
}

function clampZoom(zoom) {
    return Math.min(maxZoom, Math.max(minZoom, zoom));
}

function steppedZoom(zoom, direction) {
    return clampZoom(direction > 0 ? zoom * zoomStep : zoom / zoomStep);
}

function normalizeAngle(angle) {
    return ((angle % 360) + 360) % 360;
}

function panLimit(extent, crossExtent, zoom, angle, imageExtent = extent, imageCrossExtent = crossExtent) {
    const turned = normalizeAngle(angle) % 180 !== 0;
    return Math.max(0, ((turned ? imageCrossExtent : imageExtent) * zoom - extent) / 2);
}

function clampPan(value, limit) {
    return Math.min(limit, Math.max(-limit, value));
}
