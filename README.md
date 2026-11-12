# Linkhop

A tiny native macOS link router. Set it as your default browser and every link hops to the right app: by rule, or via a picker at your cursor.

## Install

```sh
make install   # build, copy to ~/Applications, register, launch
make default   # make Linkhop the default browser (macOS asks to confirm)
```

Needs only the Xcode command line tools.

## Picker

| Key | Action |
| --- | --- |
| `1`–`9`, click, `↩` | open in that app |
| `⌘` + any of the above | open, and always use that app for this site |
| arrows / tab | move selection |
| `esc`, click away | cancel |

Hold `⌥` while clicking a link to always get the picker, skipping rules.

## Rules

`~/.config/linkhop/config.json` is re-read on every link, so you don't need to reload after editing it.

```json
{
  "browsers": ["com.brave.Browser", "com.google.Chrome", "com.apple.Safari"],
  "fallback": "com.brave.Browser",
  "rules": [
    { "host": "github.com", "open": "com.google.Chrome" },
    { "host": "*.zoom.us", "pattern": "/j/", "open": "us.zoom.xos" },
    { "from": "com.tinyspeck.slackmacgap", "open": "com.apple.Safari" }
  ]
}
```

- `browsers`: apps shown in the picker, in order. Leave it out to show every app that opens https links.
- `fallback`: the app to use when no rule matches. Leave it out to show the picker instead.
- `rules`: the first match wins, and every field you set has to match.
  - `host`: `github.com` also matches its subdomains, and `*` works as a glob.
  - `from`: the bundle ID of the app where you clicked the link.
  - `pattern`: a regex matched against the full URL.

To find a bundle ID, run `osascript -e 'id of app "Slack"'`. `~/Library/Logs/Linkhop.log` records which app each link came from and which host it went to; it doesn't store full URLs.
