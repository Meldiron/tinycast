# Screenshots

A palette screen for the screenshots and screen recordings macOS saves: browse them by day, paste or
copy one into the app the palette covered, keep the ones worth keeping, and clear the rest in bulk or
on a schedule. **Paste Latest Screenshot** does the most common errand without opening anything.

## Invariants

- **Only what macOS saved, only where it saves.** The scanner lists the folder `com.apple.screencapture`
  names (Screenshot ▸ Options ▸ Save to, else the Desktop), non-recursively, and admits a file only when
  it carries `kMDItemIsScreenCapture` or `kMDItemScreenCaptureType` — the attributes `screencapture`
  writes. A Spotlight-wide query would also list captures the user filed into project folders, and
  bulk or automatic removal must never reach those.
- **Removal always goes to the Trash.** Nothing in the feature deletes a file outright; every path is
  `FileManager.trashItem`, so every removal can be put back.
- **A kept capture never leaves in bulk.** `ScreenshotCleanupPolicy.removable` filters every bulk and
  automatic removal; only the single-capture Move to Trash can take one. Kept is the
  `com.tinycast.screenshot.kept` extended attribute on the file itself, so it survives a rename, a
  move within the volume and a reinstall, and needs no store.
- **One capture moves without asking; several confirm.** Trashing one is undoable, as File Search's
  delete is. A bulk removal states the count, the space it frees and how many kept captures stay.
- **The board never names a file on its way to the Trash.** With "After pasting or copying" set to
  Move It to the Trash, the board is written from an APFS clone in
  `Caches/<bundle id>/Screenshots/`, so a receiver that reads the file late still finds it. Clones older
  than a day are pruned on the next stage.
- **Automatic clean-up is off by default and never travels.** `screenshotAutoDelete`,
  `screenshotAfterUse` and `screenshotTextSearchEnabled` are excluded from backups — an import must not
  arrive carrying an instruction to trash files, turn a paste into a deletion, or start background OCR.
  Text search has no settings.json key either: it is a processing choice, like the clipboard's.
- **Live only while looked at.** The folder is watched with FSEvents and its text recognised only while
  the screen is visible; `ScreenshotBrowsing` follows `PaletteState.isVisible`, because an ordered-out
  palette keeps its SwiftUI tree. The hourly clean-up sweep runs its own scan.
- **`Model/` stays Foundation-only.** `ScreenshotTests` compiles it verbatim, and
  `ScreenshotScannerTests` compiles the scanner against a temporary folder.

## Layout

| Path | Role |
| --- | --- |
| `Model/ScreenCapture.swift` | One saved capture: URL, kind, date, size, kept |
| `Model/ScreenshotSection.swift` | Day sections and their titles: Today, Yesterday, weekday, then date |
| `Model/ScreenshotQuery.swift` | Every typed word must match the name, day, kind or recognised text |
| `Model/ScreenshotFilter.swift` | The header filter: all, screenshots, recordings, kept |
| `Model/ScreenshotCleanupPolicy.swift` | What a bulk or automatic removal takes |
| `Model/ScreenshotAutoDelete.swift`, `Model/ScreenshotAfterUse.swift` | The two clean-up preferences |
| `Service/ScreenshotScanner.swift` | The folder, the capture attributes and the kept marker |
| `Service/ScreenshotIndex.swift` | The observable list, rescanned off-main and watched while shown |
| `Service/ScreenshotTextStore.swift` | Recognised text per file, via `ClipboardTextHelper` |
| `Service/ScreenshotPasteboard.swift` | Pixels plus file URL on the board, and the staged clone |
| `UI/ScreenshotsScreen.swift` | The palette screen and its ⌘K menu |
| `UI/ScreenshotGridView.swift`, `UI/ScreenshotPreview.swift` | The grid and the preview beside it |
| `UI/ScreenshotsCoordinator.swift` | Every action, Paste Latest Screenshot and the hourly sweep |
| `Settings/ScreenshotsSettingsView.swift` | Settings ▸ Screenshots |

## The screen

The grid sits left of a preview, two thumbnails to a row under day headers that carry the count and
the space the day takes. ↑/↓ move by visual row through `EmojiGridGeometry`, the same flat-index
navigation the emoji grid uses. The preview reuses `FileSearchSurface`, so a recording plays where a
screenshot shows, and lists the capture's details and, with text search on, the text Vision read.

| Key | Action |
| --- | --- |
| ↵ | Paste into the app the palette covered, then keep or trash the file as Settings says |
| ⌘↵ | Copy to the clipboard, with the same after-use rule |
| ⌃⌘↵ | Paste with the other after-use choice, so both stay one chord away |
| ⌥↵ | Paste and keep the palette open, for several captures in one visit |
| ⌘O · ⌘F | Open in its default app · Show in Finder |
| ⇧⌘C · ⌃⌘C · ⇧⌘T | Copy the file · its path · its recognised text |
| ⌘. | Keep, or stop keeping |
| ⌃X · ⌃⇧X | Move to Trash · move every shown capture to the Trash |
| ⌘P | The kind filter |

⌘K also offers Move All from a day, Move Everything Before a day, Share…, the folder and the pane.
A drag copies the file out, as every row drag does.

## Search

Words are folded for case, width and diacritics (`snimek` finds Czech `Snímek obrazovky`) and must all
appear, in any order, in the file name, the day's title, the kind's name, "Kept", or the recognised
text. Recognition is opt-in: one helper at a time, newest first, at most 200 captures a pass, cached in
`screenshot-text.json` against each file's size and date, and dropped with the setting.
