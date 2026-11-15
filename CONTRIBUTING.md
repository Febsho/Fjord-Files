# Contributing

Contributions are welcome and encouraged.

To contribute fork this repository, make your changes, and open a pull request.

## Setup

Clone the repository normally. Shared QML components and the Quickshell runtime source are included under `vendor/`:

```bash
git clone https://github.com/Febsho/Fjord-Files.git
cd Fjord-Files
```

Install [prek](https://prek.j178.dev/) then activate pre-commit hooks:

```bash
prek install
```

The hooks run `gofmt -s`, `go vet`, `go mod tidy`, and the Go test suite for changes under `core/`, plus generic whitespace/YAML checks.

## Running

```bash
make run
# or with hot reload of the QML tree
DFILES_ENABLE_HOTRELOAD=1 core/bin/dfiles run -c quickshell
```

`dfiles ipc list` prints every IPC method the daemon exposes.

### Quickshell runtime (dux-qt-base)

`dfiles qs` runs the UI on `libdux-qt-base.so.0`. By default `make build` does not embed it, and `dfiles` loads the first one it finds:

1. the copy embedded in `dfiles`, if it was built with `QTBASE=1`
2. `libdux-qt-base.so.0` next to `dfiles`, or in `../lib/dfiles/` relative to it
3. the system library dirs (`LD_LIBRARY_PATH`, `ld.so.conf`, `/usr/lib64`, `/usr/lib`, `/lib64`, `/lib`, `/usr/local/lib64`, `/usr/local/lib`)

Without one, `dfiles run` refuses to start. `dfiles run --qs-child`, or `DFILES_QS_CHILD=1`, runs the UI on upstream `qs` from `PATH` instead. That path is unsupported: fork-only features degrade to warnings.

To build and install the vendored runtime:

```bash
cd vendor/fjord-quickshell-runtime
just release        # configures RelWithDebInfo into build/, prefix /usr/local
sudo just install
```

To embed it in `dfiles` instead, run `make QTBASE=1`. An embedded copy always wins over an installed one. Runtime source updates are committed in `vendor/fjord-quickshell-runtime/`; keep its upstream license and notices with the source.

## Shared widgets

Shared components live in `vendor/fjord-qml-common/` and are linked into the app at `quickshell/DCommon/`. Edit either path, run the QML checks, and commit the change in this repository. Preserve the upstream license and copyright notices when changing vendored files. The original widget project includes a gallery that can be launched with `qs -p vendor/fjord-qml-common`.

## Translations

See `quickshell/translations/README.md`.

## Generative AI

Using an LLM to help write code is fine. Submitting its output unread is not.

- You are responsible for every line you submit. You have read it, tested it, and can explain it in review.
- Say in the PR when a meaningful part of the code was AI generated.
- Write PR descriptions, issues, and comments yourself. No AI-written or AI-rewritten text. A few plain sentences in your own words beat a page of generated summary. PRs and issues with AI-written text get closed without review.
- Do not file issues or leave comments you have not verified yourself. Reports that do not reproduce get closed.
- PRs that read like unreviewed output, with narrating comments, invented APIs, or style that ignores the file they are in, get closed without review.
