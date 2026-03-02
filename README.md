<img src="Poof.png" alt="Poof" width="256"/>

Poof is a macOS text snippet expander.

- Global snippet expansion via typed triggers
- Two modes:
  - Delimiter mode: expand after trigger + delimiter
  - Immediate mode: expand as soon as trigger is fully typed
- TOML-driven config from a user-selectable directory (keep in your dotfiles)

## Install

📦 [Download latest version](https://github.com/mikker/poof/releases)

or

```sh
$ brew install mikker/tap/poof
```

## TOML config format

Use `[[snippets]]` entries in any `.toml` file:

```toml
[[snippets]]
trigger = ":date"
replace = "{{date}}"
description = "Current date"

[[snippets]]
trigger = ":sig"
replace = "Best regards,\nYour Name{{cursor}}"
case_sensitive = true
```

Supported template tokens:

- `{{date}}` -> `yyyy-MM-dd`
- `{{time}}` -> `HH:mm`
- `{{datetime}}` -> `yyyy-MM-dd HH:mm`
- `{{date:<format>}}` -> custom `DateFormatter` format
- `{{clipboard}}` -> current clipboard text
- `{{uuid}}` -> random UUID
- `{{cursor}}` -> cursor landing position after expansion

## Development

```bash
$ just build
$ just run
$ just test
```

Or use [dude_suite](https://github.com/mikker/dude_suite).

```bash
$ suite
```

## Raycast import

```bash
just import-raycast "/path/to/Snippets.json"
```

## Releases

Local commands:

```bash
just notary-setup
just release 0.1.1
just distribute 0.1.1
```

`just distribute` does all release steps:

- builds + signs + notarizes `Poof.app`
- uploads the zip to a GitHub Release
- prepends `CHANGELOG.md`
- updates Sparkle `appcast.xml`
- updates the `poof` Homebrew cask in your tap (`../homebrew-tap` or `mikker/homebrew-tap`)

## License

MIT
