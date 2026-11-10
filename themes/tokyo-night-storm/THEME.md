# Tokyo Night Storm — macOS Setup

Replicates the [Tokyo Night Storm](https://github.com/folke/tokyonight.nvim) palette across the entire dev/desktop stack.

## Color Palette

| Role | Hex | 0xARGB |
|------|-----|--------|
| Background | `#24283b` | `0xff24283b` |
| Foreground | `#c0caf5` | `0xffc0caf5` |
| Accent (yellow / gold) | `#e0af68` | `0xffe0af68` |
| Selection BG | `#2e3c64` | `0xff2e3c64` |
| Border / dim | `#414868` | `0xff414868` |
| Red | `#f7768e` | `0xfff7768e` |
| Green | `#9ece6a` | `0xff9ece6a` |
| Yellow | `#e0af68` | `0xffe0af68` |
| Blue | `#7aa2f7` | `0xff7aa2f7` |
| Magenta | `#bb9af7` | `0xffbb9af7` |
| Cyan | `#7dcfff` | `0xff7dcfff` |
| Orange | `#ff9e64` | `0xffff9e64` |

Source-of-truth: `palette.sh` in this directory.

## What's Themed

| Component | Config File | Notes |
|-----------|-------------|-------|
| Ghostty | `~/.config/ghostty/config` | Inline 16-color palette, opacity 85%. See `ghostty-palette` snippet here for raw values. |
| tmux | `~/.tmux.conf` | Status bar, pane borders, popup borders |
| Starship prompt | `~/.config/starship.toml` | Native `[palettes.tokyo_night_storm]` directive |
| btop | `~/.config/btop/themes/tokyo-night-storm.theme` | Activated via `color_theme` in `btop.conf` |
| Atuin | `~/.config/atuin/themes/tokyo-night-storm.toml` | Activated by `[theme] name = "tokyo-night-storm"` in `~/.config/atuin/config.toml`, tracked in `stow/common/atuin` |
| Sketchybar | `~/.config/sketchybar/sketchybarrc` + `plugins/space.sh` + `plugins/wifi.sh` + `plugins/tailscale.sh` | All bar colors, space indicators, status icons |
| JankyBorders | `~/.config/borders/bordersrc` | Yellow active, gray-blue inactive |
| Zed | `~/.config/zed/settings.json` | "Tokyo Night Storm" theme (built-in) |
| fzf | `FZF_DEFAULT_OPTS` in `~/.config/zsh/common.zsh` | Sourced from `palette.sh` via `tn_fzf_colors` helper |
| zsh-autosuggestions | `~/.config/zsh/common.zsh` | `$TN_DIM` (gray-blue) |
| zsh-syntax-highlighting | `~/.config/zsh/common.zsh` | Green commands, yellow strings, red errors, cyan paths |
| eza | `EZA_COLORS` in `~/.config/zsh/common.zsh` | ANSI codes — colors map to TN via terminal palette |
| bat | `stow/common/bat/.config/bat/themes/tokyo-night-storm.tmTheme` + `BAT_THEME=tokyo-night-storm` in `~/.config/zsh/common.zsh` | Hand-rolled tmTheme matching this palette. After edits run `bat cache --build`. |
| Obsidian | (user-installed) | Community "Tokyo Night" theme — install from settings |

## Reference-Based Design

`palette.sh` is the single source of truth:

- **Shell-side** sources it (zsh config) and uses `$TN_*` vars.
- **Starship** uses TOML's native `[palettes.tokyo_night_storm]` directive — same colors, named cleanly.
- **App-side** configs (Atuin, ghostty, tmux conf, btop, sketchybar, borders, zed) hardcode hex values with a comment at the top of each file linking back to `palette.sh`. None of these tools support importing external palettes.

To tweak the theme: edit `palette.sh` first, then propagate hex changes to app-side files.

## Activation Notes

### Atuin

`config.toml` is tracked in `stow/common/atuin` and activates the theme:

```toml
[theme]
name = "tokyo-night-storm"
```

The sync session token lives in `~/.local/share/atuin/`, not in the tracked
config.

### Starship

After a zsh reload, the new prompt appears immediately.

### bat

The TN Storm tmTheme is stowed from this repo into `~/.config/bat/themes/`. After install or any edit to the tmTheme, rebuild bat's theme cache:

```bash
bat cache --build
```

### Obsidian

User-managed. Install the community "Tokyo Night" theme:
- Settings → Appearance → Themes → Manage → search "Tokyo Night" → install → enable.

## Files in this directory

- `palette.sh` — shell exports (source-of-truth)
- `ghostty-palette` — raw Ghostty palette dump (reference)
- `THEME.md` — this file
