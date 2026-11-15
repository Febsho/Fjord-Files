package blur

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-files/core/internal/atomicfile"
)

const (
	umbrielBlurStart = "# BEGIN Fjord Files managed Umbriel blur"
	umbrielBlurEnd   = "# END Fjord Files managed Umbriel blur"
)

var umbrielConfigMu sync.Mutex

type umbrielBlurState struct {
	Enabled         string `json:"enabled"`
	Radius          string `json:"radius"`
	EnabledPresent  bool   `json:"enabled_present"`
	RadiusPresent   bool   `json:"radius_present"`
	BlurTableExists bool   `json:"blur_table_exists"`
	ConfigExists    bool   `json:"config_exists"`
	TrailingNewline int    `json:"trailing_newline_count"`
}

func ConfigureUmbriel(enabled bool, radius int) error {
	if radius < 0 || radius > 100 {
		return fmt.Errorf("blur radius must be between 0 and 100")
	}
	configHome, err := os.UserConfigDir()
	if err != nil {
		return err
	}
	if value := os.Getenv("XDG_CONFIG_HOME"); value != "" {
		configHome = value
	}
	stateHome, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	stateHome = filepath.Join(stateHome, ".local", "state")
	if value := os.Getenv("XDG_STATE_HOME"); value != "" {
		stateHome = value
	}

	return configureUmbrielFiles(
		filepath.Join(configHome, "umbriel", "config.toml"),
		filepath.Join(stateHome, "fjord-files", "umbriel-blur.json"),
		enabled,
		radius,
	)
}

func configureUmbrielFiles(configPath, statePath string, enabled bool, radius int) error {
	umbrielConfigMu.Lock()
	defer umbrielConfigMu.Unlock()
	if info, err := os.Lstat(configPath); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("refusing to replace symlinked Umbriel config %s", configPath)
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}

	original, err := os.ReadFile(configPath)
	configExists := err == nil
	if errors.Is(err, os.ErrNotExist) {
		original = nil
	} else if err != nil {
		return err
	}
	mode := os.FileMode(0600)
	if info, statErr := os.Stat(configPath); statErr == nil {
		mode = info.Mode().Perm()
	}

	var state umbrielBlurState
	stateData, stateErr := os.ReadFile(statePath)
	stateExists := stateErr == nil
	if stateErr != nil && !errors.Is(stateErr, os.ErrNotExist) {
		return stateErr
	}
	if stateExists {
		if err := json.Unmarshal(stateData, &state); err != nil {
			return fmt.Errorf("read Fjord Files Umbriel blur state: %w", err)
		}
	}

	updated := original
	if enabled {
		if !stateExists {
			state.Enabled, state.EnabledPresent = tableValue(original, "appearance.blur", "enabled")
			state.Radius, state.RadiusPresent = tableValue(original, "appearance.blur", "radius")
			_, _, state.BlurTableExists = tableBounds(strings.Split(string(original), "\n"), "appearance.blur")
			state.ConfigExists = configExists
			state.TrailingNewline = len(original) - len(bytes.TrimRight(original, "\n"))
		}
		updated, err = setTableValue(updated, "appearance.blur", "enabled", "true")
		if err != nil {
			return err
		}
		updated, err = setTableValue(updated, "appearance.blur", "radius", fmt.Sprint(radius))
		if err != nil {
			return err
		}
		updated = setUmbrielWindowRule(updated, true)
	} else {
		updated = setUmbrielWindowRule(updated, false)
		if stateExists {
			updated, err = restoreTableValue(updated, "appearance.blur", "enabled", state.Enabled, state.EnabledPresent)
			if err != nil {
				return err
			}
			updated, err = restoreTableValue(updated, "appearance.blur", "radius", state.Radius, state.RadiusPresent)
			if err != nil {
				return err
			}
			updated = withTrailingNewlines(updated, state.TrailingNewline)
			if !state.BlurTableExists {
				updated = removeEmptyTable(updated, "appearance.blur")
			}
			if !state.ConfigExists && onlyCommentsAndWhitespace(updated) {
				updated = nil
			}
		}
		if bytesEqual(updated, original) && !stateExists {
			return nil
		}
	}

	if bytesEqual(updated, original) && enabled && stateExists {
		return nil
	}
	if enabled && !stateExists {
		data, err := json.Marshal(state)
		if err != nil {
			return err
		}
		if err := atomicfile.WriteFileMkdir(statePath, data, 0600, 0700); err != nil {
			return fmt.Errorf("save original Umbriel blur settings: %w", err)
		}
	}
	if err := atomicfile.WriteFileMkdir(configPath, updated, mode, 0700); err != nil {
		if enabled && !stateExists {
			_ = os.Remove(statePath)
		}
		return fmt.Errorf("write Umbriel config: %w", err)
	}
	if err := runUmbriel("config", "validate", "-c", configPath); err != nil {
		rollbackUmbrielConfig(configPath, original, mode, statePath, enabled && !stateExists)
		return err
	}
	if err := runUmbriel("msg", "config-reload"); err != nil {
		rollbackUmbrielConfig(configPath, original, mode, statePath, enabled && !stateExists)
		_ = runUmbriel("msg", "config-reload")
		return err
	}
	if !enabled && stateExists {
		if err := os.Remove(statePath); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("remove saved Umbriel blur settings: %w", err)
		}
	}
	return nil
}

func rollbackUmbrielConfig(configPath string, original []byte, mode os.FileMode, statePath string, removeState bool) {
	if len(original) == 0 {
		_ = os.Remove(configPath)
	} else {
		_ = atomicfile.WriteFile(configPath, original, mode)
	}
	if removeState {
		_ = os.Remove(statePath)
	}
}

func runUmbriel(args ...string) error {
	path, err := exec.LookPath("umbriel")
	if err != nil {
		return fmt.Errorf("umbriel blur settings require the umbriel command: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	output, err := exec.CommandContext(ctx, path, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("umbriel %s: %w: %s", args[0], err, strings.TrimSpace(string(output)))
	}
	return nil
}

func setUmbrielWindowRule(data []byte, enabled bool) []byte {
	lines := removeUmbrielWindowRule(strings.Split(string(data), "\n"))
	if !enabled {
		return []byte(strings.Join(lines, "\n"))
	}
	for len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) == "" {
		lines = lines[:len(lines)-1]
	}
	lines = append(lines,
		"",
		umbrielBlurStart,
		"[[window_rule]]",
		`match.app_id = "^io[.]github[.]febsho[.]fjordfiles$"`,
		"blur = true",
		umbrielBlurEnd,
		"",
	)
	return []byte(strings.Join(lines, "\n"))
}

func removeUmbrielWindowRule(lines []string) []string {
	start := -1
	end := -1
	for index, line := range lines {
		switch strings.TrimSpace(line) {
		case umbrielBlurStart:
			start = index
		case umbrielBlurEnd:
			if start >= 0 {
				end = index
			}
		}
	}
	if start < 0 || end < start {
		return lines
	}
	out := make([]string, 0, len(lines))
	out = append(out, lines[:start]...)
	out = append(out, lines[end+1:]...)
	return out
}

func tableValue(data []byte, table, key string) (string, bool) {
	lines := strings.Split(string(data), "\n")
	start, end, found := tableBounds(lines, table)
	if !found {
		return "", false
	}
	for _, line := range lines[start+1 : end] {
		name, value, ok := parseKeyValue(line)
		if ok && name == key {
			return value, true
		}
	}
	return "", false
}

func setTableValue(data []byte, table, key, value string) ([]byte, error) {
	lines := strings.Split(string(data), "\n")
	start, end, found := tableBounds(lines, table)
	if !found {
		if len(lines) > 0 && lines[len(lines)-1] != "" {
			lines = append(lines, "")
		}
		lines = append(lines, "["+table+"]", key+" = "+value)
		return []byte(strings.Join(lines, "\n")), nil
	}
	for i := start + 1; i < end; i++ {
		name, _, ok := parseKeyValue(lines[i])
		if !ok || name != key {
			continue
		}
		lines[i] = replaceKeyValue(lines[i], key, value)
		return []byte(strings.Join(lines, "\n")), nil
	}
	lines = append(lines[:end], append([]string{key + " = " + value}, lines[end:]...)...)
	return []byte(strings.Join(lines, "\n")), nil
}

func restoreTableValue(data []byte, table, key, value string, present bool) ([]byte, error) {
	if present {
		return setTableValue(data, table, key, value)
	}
	lines := strings.Split(string(data), "\n")
	start, end, found := tableBounds(lines, table)
	if !found {
		return data, nil
	}
	out := append([]string{}, lines[:start+1]...)
	for _, line := range lines[start+1 : end] {
		name, _, ok := parseKeyValue(line)
		if !ok || name != key {
			out = append(out, line)
		}
	}
	out = append(out, lines[end:]...)
	return []byte(strings.Join(out, "\n")), nil
}

func removeEmptyTable(data []byte, table string) []byte {
	lines := strings.Split(string(data), "\n")
	start, end, found := tableBounds(lines, table)
	if !found {
		return data
	}
	for _, line := range lines[start+1 : end] {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" && !strings.HasPrefix(trimmed, "#") {
			return data
		}
	}
	return []byte(strings.Join(append(lines[:start], lines[end:]...), "\n"))
}

func onlyCommentsAndWhitespace(data []byte) bool {
	for _, line := range strings.Split(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" && !strings.HasPrefix(trimmed, "#") {
			return false
		}
	}
	return true
}

func withTrailingNewlines(data []byte, count int) []byte {
	return append(bytes.TrimRight(data, "\n"), bytes.Repeat([]byte("\n"), count)...)
}

func tableBounds(lines []string, table string) (int, int, bool) {
	start := -1
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "[") && strings.HasSuffix(trimmed, "]") {
			if start >= 0 {
				return start, i, true
			}
			if !strings.HasPrefix(trimmed, "[[") && trimmed == "["+table+"]" {
				start = i
			}
		}
	}
	if start >= 0 {
		return start, len(lines), true
	}
	return 0, 0, false
}

func parseKeyValue(line string) (string, string, bool) {
	content := line
	if comment := strings.Index(content, "#"); comment >= 0 {
		content = content[:comment]
	}
	key, value, ok := strings.Cut(content, "=")
	if !ok {
		return "", "", false
	}
	key = strings.TrimSpace(key)
	if key == "" {
		return "", "", false
	}
	return key, strings.TrimSpace(value), true
}

func replaceKeyValue(line, key, value string) string {
	comment := ""
	if index := strings.Index(line, "#"); index >= 0 {
		comment = " " + strings.TrimSpace(line[index:])
	}
	indent := line[:len(line)-len(strings.TrimLeft(line, " \t"))]
	return indent + key + " = " + value + comment
}

func bytesEqual(a, b []byte) bool {
	return string(a) == string(b)
}
