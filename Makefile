BINARY_NAME=dfiles
SHELL_NAME=dfiles
ICON_NAME=dev.duxlabs.files
CORE_DIR=core
BUILD_DIR=$(CORE_DIR)/bin
PREFIX ?= /usr/local
DESTDIR ?=
INSTALL_DIR=$(PREFIX)/bin
DATA_DIR=$(PREFIX)/share
ICON_DIR=$(DATA_DIR)/icons/hicolor/scalable/apps
APPLICATIONS_DIR=$(DATA_DIR)/applications
METAINFO_DIR=$(DATA_DIR)/metainfo
DBUS_SERVICES_DIR=$(DATA_DIR)/dbus-1/services
DBUS_SERVICE=$(DESKTOP_ID).FileManager1.service
PORTAL_SERVICE=org.freedesktop.impl.portal.desktop.dfiles.service
PORTALS_DIR=$(DATA_DIR)/xdg-desktop-portal/portals
PORTAL_FILE=dfiles.portal
POLKIT_ACTIONS_DIR ?= /usr/share/polkit-1/actions

USER_HOME := $(if $(SUDO_USER),$(shell getent passwd $(SUDO_USER) | cut -d: -f6),$(HOME))
USER_CONFIG_HOME := $(if $(SUDO_USER),$(USER_HOME)/.config,$(or $(XDG_CONFIG_HOME),$(USER_HOME)/.config))
SYSTEMD_USER_DIR=$(USER_CONFIG_HOME)/systemd/user

SHELL_DIR=quickshell
ASSETS_DIR=assets
DESKTOP_ID=dev.duxlabs.files

.PHONY: install-dbus-activation install-user-unit all build dev run clean test fmt vet lint-qml test-qml appimage flatpak-build flatpak-run flatpak-lint flatpak-modules i18n-extract i18n-local i18n-test i18n-push i18n-sync i18n-check install install-bin install-icon install-desktop install-metainfo install-polkit install-dbus install-portal install-systemd uninstall uninstall-bin uninstall-icon uninstall-desktop uninstall-metainfo uninstall-polkit uninstall-dbus uninstall-portal uninstall-systemd help

FLATPAK_MANIFEST=distro/flatpak/$(DESKTOP_ID).yml

all: build

build:
	@$(MAKE) -C $(CORE_DIR) build

flatpak-build:
	flatpak run org.flatpak.Builder \
		--force-clean --user --install --repo=repo \
		--mirror-screenshots-url=https://dl.flathub.org/media \
		--compose-url-policy=full \
		builddir $(FLATPAK_MANIFEST)

flatpak-run:
	flatpak run $(DESKTOP_ID)

flatpak-lint:
	flatpak run --command=flatpak-builder-lint org.flatpak.Builder \
		manifest $(FLATPAK_MANIFEST)
	flatpak run --command=flatpak-builder-lint org.flatpak.Builder \
		repo repo

flatpak-modules:
	cd $(CORE_DIR) && GOWORK=off go run github.com/dennwc/flatpak-go-mod@latest \
		-dest-pref $(CORE_DIR)/ -out ../distro/flatpak .

dev:
	@$(MAKE) -C $(CORE_DIR) dev

run: dev
	@$(BUILD_DIR)/$(BINARY_NAME) run -c $(CURDIR)/$(SHELL_DIR)

clean:
	@$(MAKE) -C $(CORE_DIR) clean

test:
	@$(MAKE) -C $(CORE_DIR) test

fmt:
	@$(MAKE) -C $(CORE_DIR) fmt

vet:
	@$(MAKE) -C $(CORE_DIR) vet

lint-qml:
	@./$(SHELL_DIR)/scripts/qmllint-entrypoints.sh

test-qml:
	@python3 $(SHELL_DIR)/tests/run-qml.py

appimage:
	@./scripts/build-appimage.sh

i18n-extract:
	@python3 $(SHELL_DIR)/translations/extract_translations.py

i18n-local:
	@python3 $(SHELL_DIR)/scripts/i18nsync.py local

i18n-test:
	@python3 $(SHELL_DIR)/scripts/i18nsync.py test

i18n-push:
	@python3 $(SHELL_DIR)/scripts/i18nsync.py push

i18n-sync:
	@python3 $(SHELL_DIR)/scripts/i18nsync.py sync

i18n-check:
	@python3 $(SHELL_DIR)/scripts/i18nsync.py check

# Fjord installs only its own files. Desktop defaults and portal integration are opt-in.
FJORD_ID=io.github.febsho.fjordfiles
FJORD_LIBEXECDIR=$(PREFIX)/libexec/fjord-files
FJORD_SYSTEMD_DIR=$(DATA_DIR)/systemd/user
FJORD_DBUS_ACTIVATION=$(DBUS_SERVICES_DIR)/io.github.febsho.fjordfiles.FileManager1.service

install: install-bin install-icon install-desktop install-metainfo install-user-unit

install-bin:
	@test -f $(BUILD_DIR)/dfiles || { echo "Build first with make build"; exit 1; }
	@install -D -m 755 $(BUILD_DIR)/dfiles $(DESTDIR)$(FJORD_LIBEXECDIR)/fjord-files
	@install -d $(DESTDIR)$(INSTALL_DIR)
	@printf '%s\n' '#!/bin/sh' 'export DFILES_QS_CHILD=1' 'exec "$(FJORD_LIBEXECDIR)/fjord-files" "$$@"' > $(DESTDIR)$(INSTALL_DIR)/fjord-files
	@chmod 755 $(DESTDIR)$(INSTALL_DIR)/fjord-files

install-icon:
	@install -D -m 644 $(ASSETS_DIR)/$(FJORD_ID).svg $(DESTDIR)$(ICON_DIR)/$(FJORD_ID).svg

install-desktop:
	@install -D -m 644 $(ASSETS_DIR)/$(FJORD_ID).desktop $(DESTDIR)$(APPLICATIONS_DIR)/$(FJORD_ID).desktop

install-metainfo:
	@install -D -m 644 $(ASSETS_DIR)/$(FJORD_ID).metainfo.xml $(DESTDIR)$(METAINFO_DIR)/$(FJORD_ID).metainfo.xml

# Explicit opt-in only. Never overwrite an existing activation file.
install-dbus-activation:
	@install -d $(DESTDIR)$(DBUS_SERVICES_DIR)
	@(set -C; sed 's|@BINDIR@|$(INSTALL_DIR)|g' $(ASSETS_DIR)/dbus/io.github.febsho.fjordfiles.FileManager1.service.in > $(DESTDIR)$(FJORD_DBUS_ACTIVATION)) || { echo "Activation file already exists or could not be written; nothing overwritten" >&2; exit 1; }
	@chmod 644 $(DESTDIR)$(FJORD_DBUS_ACTIVATION)

install-user-unit:
	@install -d $(DESTDIR)$(FJORD_SYSTEMD_DIR)
	@sed 's|@BINDIR@|$(INSTALL_DIR)|g' $(ASSETS_DIR)/systemd/fjord-files.service.in > $(DESTDIR)$(FJORD_SYSTEMD_DIR)/fjord-files.service
	@chmod 644 $(DESTDIR)$(FJORD_SYSTEMD_DIR)/fjord-files.service

uninstall:
	@rm -f $(DESTDIR)$(FJORD_SYSTEMD_DIR)/fjord-files.service
	@rm -f $(DESTDIR)$(INSTALL_DIR)/fjord-files $(DESTDIR)$(FJORD_LIBEXECDIR)/fjord-files
	@rm -f $(DESTDIR)$(ICON_DIR)/$(FJORD_ID).svg $(DESTDIR)$(APPLICATIONS_DIR)/$(FJORD_ID).desktop $(DESTDIR)$(METAINFO_DIR)/$(FJORD_ID).metainfo.xml

help:
	@echo "Build:"
	@echo "  build              - Build the dfiles binary (release flags, UI embedded)"
	@echo "  dev                - Fast development build"
	@echo "  run                - Build and run against the in-repo quickshell config"
	@echo "  clean / test / fmt / vet"
	@echo "  lint-qml           - qmllint shell.qml through the Quickshell tooling VFS (needs quickshell/.qmlls.ini)"
	@echo "  test-qml           - Run the shell logic tests and the offscreen QML fixtures"
	@echo "  appimage           - Build and smoke-check an x86_64 AppImage (Arch Qt 6 runtime required)"
	@echo "  i18n-extract       - Regenerate translations/en.json from I18n.tr() calls"
	@echo "  i18n-local         - Re-extract and show added/removed terms (no POEditor)"
	@echo "  i18n-test          - Extract and validate, no POEditor calls"
	@echo "  i18n-push          - Force-upload all source terms (needs POEDITOR_API_TOKEN + DFILES_POEDITOR_PROJECT_ID)"
	@echo "  i18n-sync          - Upload changed source terms + download translations (needs POEDITOR_API_TOKEN + DFILES_POEDITOR_PROJECT_ID)"
	@echo "  i18n-check         - Fail if local i18n is out of sync with POEditor"
	@echo ""
	@echo "Install (PREFIX=$(PREFIX)):"
	@echo "  install            - Install Fjord Files, its launcher, icon, desktop entry and optional user unit"
	@echo "  install-dbus-activation - Explicitly install FileManager1 bus activation (may take precedence over other file managers)"
	@echo "  uninstall          - Remove Fjord Files installation files"
	@echo ""
	@echo "Flatpak:"
	@echo "  flatpak-build      - Build and install the Flatpak locally (org.flatpak.Builder)"
	@echo "  flatpak-run        - Run the installed Flatpak"
	@echo "  flatpak-lint       - Lint the manifest and built repo"
	@echo "  flatpak-modules    - Regenerate distro/flatpak/go.mod.yml + modules.txt from core/go.mod"
