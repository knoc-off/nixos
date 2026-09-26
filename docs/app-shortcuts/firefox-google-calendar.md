# Google Calendar — native shortcuts

- **Window match:** class `firefox`, title pattern ` — calendar%.google%.com$`
  (firefox-neo puts the host in the window title, see
  `modules/firefox-neo/chrome/JS/url-in-title.uc.js`)
- **Source:** calendar.google.com `?` dialog, scraped 2026-09-24
- **Status:** documented only, nothing bound

## Navigation

| Action          | Keys      |
| --------------- | --------- |
| Previous period | `p` / `k` |
| Next period     | `n` / `j` |
| Today           | `t`       |
| Go to date      | `g`       |

## Views

| Action   | Keys      |
| -------- | --------- |
| Day      | `1` / `d` |
| Week     | `2` / `w` |
| Month    | `3` / `m` |
| Custom   | `4` / `x` |
| Schedule | `5` / `a` |
| Year     | `6` / `y` |

## Actions

| Action                         | Keys                        |
| ------------------------------ | --------------------------- |
| Create event                   | `c`                         |
| Edit event                     | `e`                         |
| Delete event                   | `backspace` / `delete`      |
| Undo last action (if possible) | `ctrl+z` / `z`              |
| Back to calendar view          | `esc`                       |
| Save event                     | `ctrl+s` / `ctrl+enter`     |

## Application

| Action                               | Keys                          |
| ------------------------------------ | ----------------------------- |
| Search                               | `/`                           |
| Focus "Search for people to meet"    | `shift+=` / `+`               |
| Create dialog (all-day event)        | `q`                           |
| Create dialog (timed event)          | `shift+c`                     |
| Print                                | `ctrl+p`                      |
| Settings                             | `s`                           |
| Shortcut help                        | `ctrl+/` / `?`                |
| Jump to side panel                   | `ctrl+alt+.` / `ctrl+alt+,`   |
| Show person or group info            | `alt+right`                   |

## Screen-reader announcements (opened event)

| Action                   | Keys    |
| ------------------------ | ------- |
| Title                    | `alt+1` |
| Date and time            | `alt+2` |
| Guests                   | `alt+3` |
| Rooms and location       | `alt+4` |
| Description              | `alt+5` |
| Attachments              | `alt+6` |
| Notifications            | `alt+7` |
