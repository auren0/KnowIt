# KnowIt

A modern, offline-first flashcard app for Flutter, built around FSRS spaced
repetition, with optional AI generation and Anki interoperability. KnowIt keeps
the original warm yellow design language, now with Nunito and JetBrains Mono
typography, and extends it with a complete study engine.

## Features

### Core learning
- **Collections (decks)**: create, edit, duplicate, delete, nest subcollections,
  descriptions, emoji, accent colours, search, sort, filter, real counts and
  progress.
- **Cards**: basic, reversed and cloze-deletion notes. Rich-text markup
  (`**bold**`, `*italic*`, `__underline__`, `==highlight==`, `` `code` ``), tags,
  image/audio attachments, live preview, deck selection, bulk delete/move/
  duplicate, previews and undo.
- **Independent sibling cards**: a reversed note creates front→back and
  back→front cards with separate FSRS state. Every cloze deletion (`{{c1::…}}`,
  `{{c2::…}}`) becomes its own scheduled card. Editing a note updates all
  siblings without duplicating them; legacy reversed/cloze cards are migrated
  automatically.
- **FSRS scheduling**: official `fsrs` Dart package, Again/Hard/Good/Easy,
  stability/difficulty, learning/relearning steps, daily limits, desired
  retention, timezone-aware day boundaries and persistent review history.
  Practice modes never change scheduling.
- **Study flow**: flip animation, tap/keyboard controls (`Space`, `1–4`, `U`),
  optional swipe rating, interval previews, rating undo, learning-card
  requeueing and a real completion summary.
- **Study modes**: spaced repetition, quick review, cram, random, difficult.
- **Statistics**: real daily activity, heatmap, streaks, retention, rating
  breakdown, study time, deck workload, difficult cards and recent history.
- **Browse/search**: card text, collection names, tags, learning state and due
  windows (`is:due`, `due:today`, `due:week`, `due:overdue`, `#tag`).

### AI flashcards (optional)
- New **Create** tab: paste notes or a topic explanation, choose deck, card
  count, format, source/output language and generate.
- Import PDF, TXT or Markdown study material locally. Empty/scanned PDFs,
  oversized files and extraction failures are handled without uploading.
- Preview and edit every generated card, remove cards, review duplicate
  warnings, then explicitly select and save. Nothing is auto-saved.
- OpenAI-compatible provider architecture with user-supplied base URL, model
  and API key. Keys are stored in platform secure storage, never in Hive,
  backups or logs. No key or provider is bundled.
- Cancellation, timeouts, rate-limit/authentication errors and malformed model
  responses are handled. Generated output is validated with local duplicate
  detection before saving.

### Anki interoperability
- **APKG import**: preview classic Anki packages before committing, preserving
  nested deck names, notes, basic/reversed/cloze cards, tags and media.
  Duplicate detection, corruption/unsupported-format errors, scheduling
  warnings and rollback on failure are implemented. Imported cards start as new
  FSRS cards; Anki SM-2 scheduling is deliberately not converted.
- **APKG export**: classic Anki schema 11 package containing decks, notes,
  basic/reversed/cloze cards, tags and media. Exported cards are intentionally
  new; FSRS scheduling and review history are not transferred. The package is
  validated structurally and by an import round-trip. It has **not** yet been
  verified by opening the generated file in the official Anki desktop app.
- Newer zstd-compressed `collection.anki21b` packages are detected and rejected
  with a clear explanation rather than mis-read.
- Import of a real third-party APKG (41 notes, nested decks, 32 media files)
  was verified during development, including duplicate skipping.

### Data, settings and sync foundations
- Hive persistence, stable IDs, startup migration/repair, tombstone-aware
  deletes, JSON backup/import/restore, timestamped backups and undo.
- Settings: system/light/dark theme, text size, animations, haptics, keyboard
  shortcuts, swipe rating, limits, retention, learning steps, daily goal,
  reminders, file-based backup, Anki import/export, AI provider management.
- Reminders are local to the device and only scheduled when enabled.
- **Cloud sync foundation**: stable ids, `updatedAt` timestamps, deletion
  tombstones, idempotent by-id merges, append-only review-log union and
  conflict-preserving planning (`lib/services/sync/`). There is no transport,
  account or backend, so cloud sync is **not functional** yet; the offline
  database is unaffected.

## Architecture

```
lib/
  models/      typed models + Hive adapters
  services/    persistence, FSRS, queues, stats, backups, media, notifications
  services/ai/ provider abstraction, prompt/validation, duplicate detection
  services/anki/ APKG import/export and HTML conversion
  services/sync/ tombstones and local merge/conflict engine
  screens/     home, collections, study, editors, browse, settings, AI, Anki
  tabs/        deck overview, card list, statistics
  widgets/     deck cards, charts, rich text, empty states
  theme/       KnowIt design system
  utils/       ids, formatting, deck trees
```

UI consumes Hive `ValueListenable` boxes, business logic lives in services, and
the FSRS scheduler is independent of UI and persistence.

## Setup and verification

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build windows --release
```

## Windows Release & Installer

### Prerequisites
- **Flutter SDK** (configured with Windows desktop support: `flutter config --enable-windows-desktop`).
- **Visual Studio 2022** with the "Desktop development with C++" workload installed.
- **Inno Setup 6** (available from [jrsoftware.org/isdl.php](https://jrsoftware.org/isdl.php)). Ensure `ISCC.exe` is either in your system `PATH` or installed to the default location (`%LOCALAPPDATA%\Programs\Inno Setup 6` or `C:\Program Files (x86)\Inno Setup 6`).

### Building the Windows Installer
Run the automated PowerShell build script:
```powershell
.\build_installer.ps1
```

The script will:
1. Extract the application version from `pubspec.yaml`.
2. Compile the Flutter Windows release (`flutter build windows --release`).
3. Locate the Inno Setup compiler (`ISCC.exe`).
4. Compile `installer.iss` using LZMA2 solid compression.
5. Produce the standalone installer at `build\installer\KnowIt-Setup.exe`.

If the Flutter Windows release is already compiled, use `-SkipFlutterBuild` to package the installer directly:
```powershell
.\build_installer.ps1 -SkipFlutterBuild
```

Alternatively, compile `installer.iss` using the Inno Setup CLI or IDE:
```cmd
iscc /DMyAppVersion=1.0.0 installer.iss
```

### Installer Configuration & Output
- **Output File:** `build\installer\KnowIt-Setup.exe`
- **Installation Mode:** Modern per-user installation without requiring administrator privileges (`PrivilegesRequired=lowest`).
- **Default Installation Path:** `%LOCALAPPDATA%\Programs\KnowIt`
- **Supported Languages:** English and Russian (matches system locale or user selection).
- **Shortcuts:** Start Menu shortcut and optional Desktop shortcut.
- **Compression:** Solid LZMA2 max compression.
- **Code Signing:** The generated installer is unsigned. On fresh Windows installations, Windows SmartScreen may present an informational notice until signed with an EV certificate or reputation is established.

### Updates and Uninstall Behavior
- **In-Place Updates:** Uses a persistent `AppId` (`{{B3A9B267-8F12-4C9D-9F77-4D9A0C3C9102}`). Running an updated installer cleanly replaces application binaries without duplicate entries.
- **Running Instance Handling:** The installer detects running KnowIt instances (`CloseApplications=yes`) and safely requests closure before overwriting binaries.
- **User Data Protection:** User flashcards, collections, Hive databases, audio/image media files, and study histories are stored in the user application support directory (`%APPDATA%` / `%LOCALAPPDATA%`), completely separated from the installation folder. Installing, updating, or uninstalling KnowIt will **never** delete, overwrite, or modify persistent user study data.

Last verified in this development session:

- `flutter analyze`: no issues.
- `flutter test`: **82 tests passed** (FSRS, queues, limits, statistics, Hive
  CRUD/migration/undo, backup/import, sibling notes, AI parsing/provider errors/
  duplicate detection, PDF/TXT/Markdown extraction, APKG import/export round-trip,
  sync conflict logic, study persistence/undo, restart persistence, editor flows).
- `flutter build apk --debug`: successful.
- Real Anki APKG preview + commit verified with a third-party package.

AI generation itself was not run against a live provider because no credentials
were supplied; provider request/response handling is covered with mock HTTP
tests. Physical-device notification delivery and iOS/Windows builds were not
re-verified in this session.

## Known limitations and unverified areas

- **AI needs configuration.** Add an OpenAI-compatible base URL, model and your
  own API key in Settings → AI features. Client-side keys can be extracted from
  a device; for shared/commercial use use an authenticated backend proxy with
  usage limits. No provider is bundled and no generation is fabricated.
- **APKG export compatibility is not proven in Anki itself.** It is structurally
  validated and round-trips through the importer, but real Anki desktop import
  must still be tested before claiming full compatibility.
- **APKG scheduling is not transferred** in either direction. Import/export
  cards start as new to avoid inventing FSRS/SM-2 mappings.
- **Cloud sync is foundation-only.** No account, backend, transport, retry or
  multi-device test; do not treat it as working sync.
- iOS/Android notification delivery depends on OS permissions and power
  settings. Android builds; runtime delivery was not tested on a device.
- Document extraction uses Syncfusion PDF (subject to its community/commercial
  license terms). OCR for scanned PDFs is not implemented.
- Media is limited to one image and one audio attachment per note; extra Anki
  media references are reported and skipped.
- Android build was verified. iOS, macOS, Linux and Windows builds were not
  re-run here; the added plugins support those platforms but should be built
  and smoke-tested before release.
