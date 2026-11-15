# Changelog

## [0.3.0] - 2026-11-16

### Added

- Video thumbnails and a clip selector in the sidebar, with previous and next video navigation in both sidebar and full preview.
- Double-click video previews to expand them to fullscreen.
- A background blur strength slider for Umbriel, which applies blur to Fjord Files through a managed window rule.

### Improved

- Video previews now wait for Play and start muted in the sidebar; the mute control can be switched on for sound.
- Keep the video thumbnail visible until playback starts, including after hiding and reopening the sidebar.
- Removed the foreground-layers setting and fixed the solid pane appearance as the default.
- Unified the search and path bars and restored mouse caret placement in text fields.
- Updated the README with the release AppImage download and checksum instructions.

## [0.2.0] - 2026-11-15

### Added

- Adjustable liquid-glass surfaces with shader refraction across the toolbar, buttons, menus, dialogs, sidebars, tabs, and viewer controls.
- A live glass appearance preview, independent glass strength and opacity controls, and an optional compositor-managed background blur setting.
- A close control for the settings window when native title bars are disabled.

### Improved

- Refined the settings layout and removed remaining Dux branding from user-facing About content.
- Cleaned up tab overview cards by removing overlapping file-name labels and enlarging the folder preview icon.
- Made the leading icon and padding in search fields clickable, placing the caret at the start of the query.
- Added glass rendering benchmarks and QML coverage for the new material components.

### Notes

- Background blur depends on compositor support and configuration. On Umbriel, blur remains controlled by its window rules.
- Glass strength controls material highlights and refraction; window opacity remains a separate setting.
