# marki-media

Renders ` ```media ` blocks as images or audio. The file is uploaded to Anki's
media collection under a name derived from its content, so two cards that use
the same file share one copy.

## Syntax

The block body is TOML:

````markdown
```media
src = "flags/jm"
size = 300
alt = "Flag of Jamaica"
```
````

| Field      | Type                               | Default  | Applies to |
| ---------- | ---------------------------------- | -------- | ---------- |
| `src`      | string, required                   |          | all        |
| `size`     | integer, max width in px           | `200`    | images     |
| `alt`      | string                             | `""`     | all        |
| `controls` | bool                               | `true`   | audio      |
| `loop`     | bool                               | `false`  | audio      |
| `autoplay` | bool                               | `false`  | audio      |
| `preload`  | `"none"`, `"metadata"` or `"auto"` | `"auto"` | audio      |

An unknown field is an error.

## Resolving `src`

- `src = "flags/jm"`: `flags` is the name of a configured source, and marki
  looks for `jm.<ext>` inside it.
- `src = "flags/de/by"`: looks for `de/by.<ext>` inside `flags`.
- `src = "jm"`: searches every source in order and uses the first match.
- Without an extension, marki tries `svg`, `png`, `webp`, `jpg`, `jpeg`, `gif`,
  `mp3`, `ogg`, `m4a` and `wav`, in that order. You can also write the
  extension yourself: `src = "diagrams/foo.png"`.
- Image extensions render as `<img>`, audio as `<audio>`.

Sources are searched in this order: `.marki/media/`, then `[media_sources]`
from the config, then `--media-dir`:

```toml
[media_sources]
flags = "${HAYLEOX_FLAGS}/share/hayleox-flags"
```

If none of these sources exist, the media renderer isn't registered and
` ```media ` blocks are shown as highlighted TOML.

## Audio example

````markdown
```media
src = "audio/bonjour.mp3"
autoplay = true
```
````

The HTML output is wrapped in `div.marki-media.marki-image` or
`div.marki-media.marki-audio`, which you can target in a model's CSS.
