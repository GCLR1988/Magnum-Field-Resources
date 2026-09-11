# Training Depot

A simple iOS app for foremen: pick a program, then pick a PDF or video walkthrough for it.

Programs can either sync live from a Dropbox folder (add a PDF or video
there and it shows up in the app automatically) or use files bundled
directly into the app. Files are cached locally once viewed, so everything
stays available in the field even without a signal. Supported file types:
`.pdf`, `.mp4`, `.mov`, `.m4v`.

A few extras on top of the basics:

- **Wi-Fi-only video downloads.** On by default (Settings, gear icon on the
  home screen) so background syncing never eats cellular data on a big
  video. PDFs always download regardless, since they're tiny. Opening a
  video that isn't cached yet while off Wi-Fi shows a "Download Anyway"
  option to override it just that once.
- **"New" badges + last-synced time.** Any walkthrough that showed up
  since a program's list was last viewed gets a small "NEW" tag, and the
  home screen shows one "Last Synced" line for how long ago it last
  checked Dropbox.
- **In-PDF search and page thumbnails.** While viewing a PDF, the
  magnifying-glass button searches its text with next/previous jump
  buttons, and the grid button opens a page-thumbnail strip for jumping
  straight to a page in a long document.
- **Per-program logos.** Drop a `logo.png` (or `.jpg`/`.jpeg`) into a
  program's Dropbox folder, next to its PDFs and videos, and its home
  screen tile automatically shows that logo instead of the generic folder
  icon -- no rebuild needed, same as adding a new walkthrough.
- **Folders within a program.** A program's Dropbox folder can organize
  its PDFs and videos into subfolders (e.g. "Estimating", "Scheduling")
  instead of one long flat list -- open the program and tap into a folder
  the same way you'd tap into a walkthrough. Folders can nest to any depth.
- **Fast reopen + a "New Content Available" banner.** The very first time
  the app is opened, everything currently in Dropbox downloads right away
  so it's all available offline from the start. Every time after that,
  opening the app just checks what's changed (fast) instead of
  re-downloading it -- if anything new or updated is found, a "New Content
  Available! / Download Now" banner appears in the bottom-right corner to
  fetch it on demand.

## Setting up live Dropbox sync

See **DROPBOX_SETUP.md** for the full walkthrough (creating the Dropbox
app, permissions, and config). Short version:

1. Create an app at dropbox.com/developers/apps with "App folder" access.
2. Fill in `MagnumFieldTraining/Sync/DropboxConfig.swift` with your app
   key, app secret, and refresh token.
3. Point each program at its folder in `MagnumFieldTraining/Data/ProgramData.swift`.

## Using bundled files instead (no Dropbox)

For a program you'd rather keep fully offline and edit by hand:

1. Put your PDF or video files in `MagnumFieldTraining/PDFs/`.
2. In `Data/ProgramData.swift`, change that program's `source` to
   `.local([...])` and list its files there, e.g.:
   ```swift
   Program(name: "Procore", source: .local([
       WalkthroughResource(title: "Getting Started", location: .bundled(filename: "Procore - Getting Started.pdf")),
       WalkthroughResource(title: "Site Walkthrough", location: .bundled(filename: "Procore - Site Walkthrough.mp4")),
   ]))
   ```

## Project structure

- `MagnumFieldTrainingApp.swift` -- app entry point
- `ContentView.swift` -- home screen: pinned, program list, "New Content Available" banner
- `Views/SplashView.swift` -- full-screen Magnum logo shown until the first sync finishes, fades out instead of flashing "No Programs Yet"
- `Models/Program.swift` -- data model (Program, WalkthroughResource)
- `Models/WalkthroughFolder.swift` -- a program's folder tree (root + nested subfolders)
- `Models/CatalogStore.swift` -- live document/folder list per program (local + synced), first-sync-vs-returning-user download behavior
- `Models/PinnedStore.swift` -- on-device pins
- `Data/ProgramData.swift` -- the list of programs and where their files come from (edit this)
- `Sync/` -- Dropbox sync layer (auth, listing, downloading, caching)
- `Views/ProgramDetailView.swift` -- list of walkthroughs for a program
- `Views/WalkthroughDetailView.swift` -- PDF viewer (PDFKit, with search + thumbnails) or video player (AVKit), depending on file type
- `Views/PDFKitRepresentedView.swift` -- SwiftUI wrapper around PDFKit's PDFView
- `Views/PDFThumbnailBar.swift` -- SwiftUI wrapper around PDFKit's page-thumbnail strip
- `Views/SettingsView.swift` -- the Wi-Fi-only-for-videos toggle
- `Models/SeenStore.swift` -- tracks which walkthroughs have been seen, for "New" badges
- `Models/SettingsStore.swift` -- persisted app preferences (Wi-Fi-only for videos)
- `Sync/NetworkMonitor.swift` -- tracks whether the device is on Wi-Fi
- `PDFs/` -- drop bundled (offline-only) PDF/video files here
