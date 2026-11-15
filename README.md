# Fjord Files

<div align="center">
  <img src="assets/io.github.febsho.fjordfiles.svg" alt="Fjord Files logo" width="144">

### A standalone file manager for Linux

Built with [Quickshell](https://quickshell.org/) and [Go](https://go.dev/)

</div>

Fjord Files is a file manager for Wayland. A Go daemon handles file operations and a Quickshell UI provides the desktop experience. The application uses its own app ID and separate settings. Most features work standalone; optional desktop services such as gvfs, udisks2, and danksearch are used when available.

## Features

- **Tabs and views:** Multiple tabs, a split view with two panes, and list, grid, and column views. Sort order and view can be remembered per folder.
- **Navigation:** Type to jump to a name or filter the current folder, revisit folders you have opened, and restore closed tabs.
- **Search:** Recursive name search with filters. Uses danksearch when it is running and walks the tree otherwise.
- **File operations:** Copy, move, rename, trash, and delete with progress and conflict handling. Most operations can be undone. Retry denied operations as administrator through polkit.
- **Archives:** Browse ZIP, TAR, 7z, RAR, and CPIO archives; extract other supported formats in full. Extract individual files from ZIP, TAR, 7z, and RAR. Create ZIP, tar.gz, tar.xz, and tar.zst archives.
- **Devices and network:** Mount, unmount, and eject drives through udisks2. Connect to network shares through gvfs.
- **Trash, recent files, and bookmarks:** Browse and restore trashed files, revisit recent files, and keep folders in the sidebar.
- **Open and save dialogs:** Can optionally provide the XDG Desktop Portal file chooser to other applications.
- **Desktop integration:** Supports `org.freedesktop.FileManager1` for “Show in Folder”. Registration as the default file manager stays off until enabled in Settings.
- **Previews:** Images, text, audio, and video, with optional PDF and Office previews. Video previews start paused and muted in the sidebar, show a thumbnail before playback, and let you choose nearby clips. Double-click a video to expand it. Availability and codecs depend on installed Qt modules and helper tools.
- **Appearance:** Adjustable glass surfaces, separate window opacity, and compositor blur with a strength control on Umbriel.

## Installation

### AppImage

Download the latest x86_64 AppImage and its checksum from [GitHub Releases](https://github.com/Febsho/Fjord-Files/releases/latest):

```bash
curl -fLO https://github.com/Febsho/Fjord-Files/releases/latest/download/Fjord-Files-x86_64.AppImage
curl -fLO https://github.com/Febsho/Fjord-Files/releases/latest/download/Fjord-Files-x86_64.AppImage.sha256
sha256sum -c Fjord-Files-x86_64.AppImage.sha256
chmod +x Fjord-Files-x86_64.AppImage
./Fjord-Files-x86_64.AppImage
```

The AppImage bundles Qt and the Quickshell UI runtime. It still uses the host Wayland compositor and its blur support.

### From source

Requires Go 1.27.3 or newer and Quickshell with Qt 6. Shared QML components and the Quickshell runtime source are included in the repository. The default launch requires Quickshell with Qt 6 or the compatible `libdux-qt-base0` runtime. Build with `QTBASE=1` to build and embed the included runtime source.

```bash
git clone https://github.com/Febsho/Fjord-Files.git
cd Fjord-Files
make
./run-fjord
```

Install locally:

```bash
make install PREFIX="$HOME/.local"
```

This installs the application, desktop launcher, Fjord icon, and a disabled-by-default systemd user unit under the selected prefix. It does not change default applications or install system-wide D-Bus, portal, or polkit integration. Quickshell must remain on your `PATH`. To uninstall:

```bash
make uninstall PREFIX="$HOME/.local"
```

Use `PREFIX=/usr` for a system installation. Enable or disable the background service when needed:

```bash
systemctl --user enable --now fjord-files.service
systemctl --user disable --now fjord-files.service
```

Build an x86_64 AppImage with `make appimage`. This requires Go, Quickshell, Qt 6 with QML, Multimedia, and PDF modules, `rsvg-convert`, and `curl`. The output is `dist/Fjord-Files-x86_64.AppImage`, accompanied by a SHA-256 checksum file.

### NixOS and Home Manager

The flake provides NixOS and Home Manager modules. Home Manager example:

```nix
{
  inputs.fjord-files.url = "github:Febsho/Fjord-Files";

  imports = [ inputs.fjord-files.homeModules.dux-files ];
  programs.dux-files.enable = true;
}
```

The NixOS module is `nixosModules.dux-files`. Enable systemd startup and the portal with `programs.dux-files.systemd.enable` and `programs.dux-files.portal.enable`. Module options are defined in [flake.nix](flake.nix).

### Arch Linux

The package recipe is in [distro/arch](distro/arch). See its [README](distro/arch/README.md) for build and verification instructions.

### Flatpak

The manifest and build instructions are in [distro/flatpak/README.md](distro/flatpak/README.md). The Flatpak build cannot register the XDG Portal file chooser backend.

## Optional dependencies

These programs are detected on `PATH` at startup:

| Package | Enables |
| --- | --- |
| `bubblewrap` | Sandboxes external thumbnailers and selected preview paths |
| `ffmpegthumbnailer` | Video thumbnails |
| `poppler` (`poppler-utils` on Debian/Ubuntu) | PDF thumbnails |
| `gvfs` | Network shares and trash on removable drives |
| `udisks2` | Drives in the sidebar |
| `danksearch` | Fast search through the running search service |

PNG, JPEG, GIF, BMP, TIFF, and WebP images are decoded directly. Other formats use installed freedesktop thumbnailers. Run `dfiles ipc system.capabilities` to see detected features and their status.

PDF previews require the optional QtQuick.Pdf module. Depending on your distribution, the package may be called `qt6-webengine`, `qt6-qtpdf`, `qt6-pdf-imports`, or `qml6-module-qtquick-pdf`. Office previews also require LibreOffice and bubblewrap. See [Office previews](docs/office-preview.md) for details and limitations. Audio and video codec support depends on the Qt Multimedia runtime; see [audio and video previews](docs/media-preview.md).

## Usage

The application launcher is `fjord-files`; the backend CLI is currently named `dfiles`.

```bash
fjord-files show
fjord-files ~/Downloads
fjord-files open ~/Downloads
fjord-files open --new-window ~/src
fjord-files select ~/Documents/notes.txt
fjord-files properties ~/Documents/notes.txt
```

`open` accepts local paths, `trash:///`, `computer:///`, `network:///`, `admin:///`, and GVFS locations such as `sftp://`, `smb://`, `ftp://`, `davs://`, or `nfs://`.

When started through systemd, closing the window hides it by default. When started directly, the application exits after the last window closes unless the close behavior setting says otherwise.

### CLI

The CLI connects to a running instance or handles the request itself. Use `--json` for machine-readable output.

```bash
dfiles trash put|list|count|restore|empty
dfiles mime query|default|set
dfiles devices list|mount|unmount|eject
dfiles search <folder> <query>
dfiles ipc list
dfiles ipc <method> key=value...
```

### Set as the default file manager

Choosing a default file manager is left to the user. After installation, set Fjord Files as the default with:

```bash
xdg-mime default io.github.febsho.fjordfiles.desktop inode/directory
```

Fjord Files registers `org.freedesktop.FileManager1` when enabled in Settings. Optional D-Bus activation can be installed separately:

```bash
make install-dbus-activation PREFIX="$HOME/.local"
```

See [README-FJORD.md](README-FJORD.md) for development and integration details.

### Open and save dialogs

The portal is not enabled automatically. Turn it on in Settings or with the CLI:

```bash
dfiles portal install
dfiles portal status
dfiles portal uninstall
```

Setup updates the user configuration for `xdg-desktop-portal` and keeps the previous backend as a fallback. The portal service must reload its configuration, which can close dialogs that are already open. Applications that draw their own dialogs are unaffected. See [README-FJORD.md](README-FJORD.md) for details.

## Development

```bash
make build
./run-fjord
make test
make test-qml
make lint-qml
```

`make run` starts the development UI with the local QML tree. For hot reload:

```bash
DFILES_ENABLE_HOTRELOAD=1 core/bin/dfiles run -c quickshell
```

For architecture, setup, and integration details, see [README-FJORD.md](README-FJORD.md) and the [docs](docs/architecture.md). Contribution instructions and project conventions are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Project structure

```text
core/           Go daemon, CLI, file operations, and IPC
quickshell/     Quickshell UI and QML modules
vendor/         Included shared QML components and Quickshell runtime source
assets/         Fjord logo, desktop launcher, and system integration
distro/         Arch, Nix, and Flatpak packaging
docs/           Architecture and feature details
```

## Lizenz

MIT. See [LICENSE](LICENSE) and the notices in `assets/licenses/`.
