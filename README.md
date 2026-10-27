# AI-ML Refresher

A macOS widget and companion app, a Windows app and an Android app with a home-screen widget, for a 15-minute daily reading habit in AI & ML.

Every day after **12:00 local time** it collects what's popular or trending across GitHub, Hugging Face, Hacker News, Reddit and a set of research blogs. It ranks everything with a fixed, deterministic formula and keeps the **top 15**.

- **Widget** (medium or large): today's top 5. Click an item to open it, click the bookmark to save it, click **Expand** to open the app.
- **App window**: today's items on the left and your **collection** on the right. Drag items across to save them. Saved items keep tags, notes and read/unread state forever. The ‹ › arrows browse past days.
- **Background helper**: a small invisible helper inside the app builds the brief after 12:00 and keeps the widget current, even with the app closed. The app itself behaves like any Mac app: it bounces in the Dock when launched and quits when you close its window.
- **Notifications** (optional, bell button): "Most recent AI & ML trends for you" every day at 12:05.

- **Sync** (optional, official releases): sign in with Google on each device to keep your collection the same on your Mac, PC and phone.

No AI summaries and no API keys. The same inputs always produce the same list.

## Install

### macOS

Requires macOS 15 or later on Apple silicon.

1. Download **[AI-ML-Refresher-macOS.dmg](https://github.com/MMFreitas1/AI-ML-refresher/releases/latest/download/AI-ML-Refresher-macOS.dmg)**.
2. Open it and drag the app onto **Applications**.
3. Open the app from Applications. The first time, macOS blocks it because the app isn't notarized by Apple: go to **System Settings → Privacy & Security**, click **Open Anyway** and confirm. You only need to do this once.
4. Add the widget: right-click the desktop → **Edit Widgets** → search for the app's name → pick medium or large.

The background helper turns on by itself. If macOS asks, allow it under **System Settings → General → Login Items**.

### Windows

Requires Windows 10 or 11, 64-bit.

1. Download **[AI-ML-Refresher-Windows.exe](https://github.com/MMFreitas1/AI-ML-refresher/releases/latest/download/AI-ML-Refresher-Windows.exe)**. It's a single file and doesn't need .NET or an installer.
2. Move it somewhere permanent, for example a `Programs` folder in your user folder. *Start with Windows* (on by default) launches it from where it is, so don't run it from Downloads and then delete it.
3. Double-click it. The first time, Windows may say "Windows protected your PC" because the app isn't code-signed: click **More info → Run anyway**.
4. The app lives in the notification area (the icons by the clock; it may be under the **^** arrow). Closing the window keeps it running there; use **Quit** in its menu to stop it.

To uninstall, turn off *Settings → Start with Windows* in the app, quit it from its menu and delete the file. Your data is in `%APPDATA%\Refresher`; delete that folder too if you don't want to keep your collection.

### Android

Requires Android 8.0 or later.

1. On your phone, download **[AI-ML-Refresher-Android.apk](https://github.com/MMFreitas1/AI-ML-refresher/releases/latest/download/AI-ML-Refresher-Android.apk)**.
2. Open the downloaded file. The first time, Android asks you to allow installs from your browser (or file manager): allow it, go back and tap **Install**. The app isn't on Google Play, so Play Protect may also ask you to confirm.
3. Add the widget: long-press the home screen → **Widgets** → find the app → drag *Today's top 5* to the home screen. Or use *⋮ → Settings → Add widget to home screen* in the app.

To update, install a newer `.apk` over it: your collection is kept. To uninstall, long-press the app icon → **Uninstall** (this deletes your collection).

All versions are on the [Releases](https://github.com/MMFreitas1/AI-ML-refresher/releases) page.

## Sources

| Source | Signal used for ranking |
|---|---|
| GitHub Trending (all + Python), AI repos only | stars today |
| New GitHub repos (≤14 days) in topics `llm`, `machine-learning`, `deep-learning`, `computer-vision`, `reinforcement-learning`, `robotics`, `ai-agents` | stars per day since creation |
| Hugging Face Daily Papers (successor of Papers with Code) | community upvotes, previous full day |
| Hugging Face trending models | HF trending score |
| Hugging Face trending Spaces | HF trending score |
| Hacker News, last 24h, AI stories only | points |
| r/MachineLearning, r/LocalLLaMA (daily top) | rank in Reddit's top list |
| Import AI, Latent Space, Interconnects, Ahead of AI, Last Week in AI, Simon Willison, Google DeepMind, OpenAI, Hugging Face, BAIR, NVIDIA, The Robot Report, The Transmitter | new post in the last 48h |

Blogs and feeds are listed in `BlogSource.defaultFeeds` (`Sources/BriefCore/Sources.swift`), so they're easy to change.

## How ranking works

See `Sources/BriefCore/Ranker.swift`:

1. Items shown on any of the previous 7 days are dropped, so you don't see the same repo again tomorrow.
2. Duplicates (same canonical URL) are merged.
3. Within each source, `score = weight × log(1 + signal) / log(1 + best signal in that source)`, so each source's #1 scores exactly its weight. Weights range from 1.0 for GitHub Trending and HF Papers down to 0.7 for HF Spaces.
4. Items are sorted by score and picked greedily, with at most **3 per source** and **4 per field**, so no single source or topic can take over the list.

Fields (LLMs & NLP, Agents, Vision, Video & 3D, Audio & Speech, Robotics, Reinforcement Learning, Neuroscience, Systems & Infra) come from keyword rules in `Categorizer.swift`.

## Build & run

To install a ready-made build, see [Install](#install). The app is signed with a development certificate, not notarized: notarizing removes the *Open Anyway* step, but it requires the paid Apple Developer Program.

### Build & install (app + widget)

Requires Xcode and macOS 15 or later. Xcode doesn't need to be open.

```bash
./scripts/install.sh     # generates the project, builds a signed Release, installs to /Applications
./scripts/make-dmg.sh    # same build, packaged as a .dmg in dist/ (drag to Applications)
```

1. Add the widget: right-click the desktop → **Edit Widgets** → search for the app's name → pick medium or large.
2. The background helper is enabled automatically (*Settings → Refresh in the background*). If macOS asks, allow it under System Settings → General → Login Items.

Open the app from Applications, Spotlight, the widget's **Expand** button or a notification. Run the script again after any code change.

The signing team is set in `project.yml` (`DEVELOPMENT_TEAM`). The Xcode project is generated from that file and is git-ignored, so make target or entitlement changes there. To work in Xcode, run `./scripts/make-xcode-project.sh` and open `Refresher.xcodeproj`.

### Without Xcode (app window only, no widget)

```bash
swift run Refresher        # the two-pane app (no widget, helper or notifications)
swift run brief-cli fetch  # build today's brief now and print it
swift run brief-cli show   # print the latest saved brief
swift test                 # unit tests (needs Xcode's toolchain)
```

## Windows

The Windows app (`windows/`, C# and [Avalonia](https://avaloniaui.net)) uses the same sources, ranking formula and data format as the Mac app:

- **Window**: the same two panes. Today's items are on the left and your collection is on the right. Drag items across or click the bookmark to save them. Tags, notes and read state are kept, and the ‹ › arrows browse past days. Closing the window keeps the app running.
- **Notification area** (tray icon): it starts with Windows and builds the brief after 12:00. Its menu lists today's top 5, and each one can be opened or saved. There's no Windows widget.
- **Notifications** (optional, bell button): a Windows notification when the day's brief is ready. Clicking it opens the window.

To install a ready-made build, see [Install](#install).

Data lives in `%APPDATA%\Refresher` (*Settings → Open Folder*). The `briefs/` and `collection.json` files use the same format as the Mac app's, so you can copy them between the two.

### Build

Requires the [.NET 10 SDK](https://dotnet.microsoft.com/download). It builds on Windows, macOS or Linux.

```bash
./scripts/make-exe.sh          # dist/AI-ML-Refresher-<version>-windows.exe (x64; pass arm64 for ARM)
cd windows
dotnet test                    # core tests (ranking, categorization, parsers, schedule, store)
dotnet run --project Refresher.Cli -- fetch   # build today's brief now and print it
dotnet run --project Refresher.App            # run the app (also works on a Mac, for previewing)
```

On Windows without Git Bash, run the publish command from `scripts/make-exe.sh` directly, or open `windows/Refresher.sln` in Visual Studio or Rider. Notifications and *Start with Windows* only work in Windows builds. A preview run on a Mac stores its data in `~/Library/Application Support/Refresher (Windows preview)`.

## Android

The Android app (`android/`, Kotlin and Jetpack Compose) uses the same sources, ranking formula and data format:

- **App**: today's items and your collection, as two tabs on phones and side by side on tablets. Tap an item to open it and the bookmark to save it. Tap a saved item to edit its tags and note or mark it read. The ‹ › arrows browse past days.
- **Widget**: today's top 5. Tap an item to open it or its bookmark to save it, and tap the title to open the app.
- **Background refresh**: a WorkManager job builds the brief after 12:00 even with the app closed, as soon as the phone is online. It survives restarts and catches up if the phone was off at noon.
- **Notifications** (optional, bell button): "Most recent AI & ML trends for you" when the day's brief is ready.

Data is kept in the app's private storage (`files/Refresher/`), in the same `briefs/` and `collection.json` format as the other apps.

### Build

Requires a JDK (17 or later) and the Android SDK with platform 37, for example from [Android Studio](https://developer.android.com/studio). Open `android/` in Android Studio, or use the command line:

```bash
./scripts/make-apk.sh                 # dist/AI-ML-Refresher-<version>-android.apk (signed release)
cd android
./gradlew :core:test                  # core tests on the JVM (ranking, categorization, parsers, schedule, store)
./gradlew :app:installDebug           # install a debug build on a connected phone or emulator
```

`make-apk.sh` finds the JDK and SDK through `JAVA_HOME` and `ANDROID_HOME`, or in `~/.jdk`, `~/.android-sdk` and Android Studio's default locations. Release builds are signed with the key named in `android/keystore.properties`, which isn't in git:

```properties
storeFile=/path/to/release.jks
storePassword=…
keyAlias=release
keyPassword=…
```

Create a key with `keytool -genkeypair -keystore release.jks -storetype PKCS12 -alias release -keyalg RSA -keysize 4096 -validity 36500`. Keep the key and its password backed up: Android only installs an update over an existing app when it's signed with the same key.

## Sync

Official releases can keep the collection (saved items, tags, notes, read state) the same on every device. In *Settings → Sync*, choose **Sync with Google** and sign in with the same Google account on each device. Today's brief isn't synced: each device builds the same list on its own.

- **Where:** one file, *AI-ML Refresher library.json*, in your Google Drive. The app uses Google's `drive.file` permission, so it can only see files it created. See [PRIVACY.md](PRIVACY.md).
- **When:** when the app opens, a few seconds after each change, and every 15 minutes while it runs (on Android, also with the daily brief).
- **Merging:** per item, the most recent change wins. Removing an item removes it everywhere, unless it was changed again on another device after the removal. The rules are in `CollectionSync` (`Sources/BriefCore/Sync.swift`, `windows/Refresher.Core/Sync.cs`, `android/core/…/Sync.kt`) and are the same in all three apps, with tests.
- **Sign-in:** macOS and Windows open Google's sign-in in the browser, which then returns to the app on a `127.0.0.1` port. The sign-in is kept in the macOS keychain, or encrypted for your Windows user. Android uses the Google account on the phone.

Builds from this repository don't offer sync: Google sign-in needs an OAuth client in a Google Cloud project, and the official one is in the private brand kit. To sync your own build, create a project with the Google Drive API and the `drive.file` scope, then provide a Desktop client through `AppBrand.googleClient` (macOS) or `AppBrand.GoogleClient` (Windows). For Android, register an Android client for your package name and signing key, and set `sync_available` to `true`.

## Releases

`./scripts/release.sh` builds the `.dmg`, the `.exe` and the `.apk` on a Mac and attaches them to a draft GitHub release, tagged with the version in `project.yml` (keep `windows/Directory.Build.props` and `versionName` in `android/app/build.gradle.kts` the same, and raise `versionCode` there for every Android release). Review the draft on GitHub, then publish it.

Official releases are built with a private brand kit cloned next to this repository (`../brand-kit`), which adds their name, icon and launch animation. Without it, every script builds the neutral app.

## License

The code is MIT licensed (`LICENSE`). Builds from this repository are unbranded and named "AI-ML Refresher". Official releases (macOS, Windows and Android) add their own name, icon and launch animation from a private brand kit that isn't part of this repository. Those are not licensed for reuse; see `BRAND.md`.

## Data

Data is plain JSON:

- `briefs/YYYY-MM-DD.json`: one ranked list per day, kept as history.
- `collection.json`: your saved items, with tags, notes and read state.

Where the files live depends on how the app was built:

- **Xcode build**: the shared App Group container, which the app and widget both use. *Settings → Show in Finder* opens it.
- **`swift run`**: `~/Library/Application Support/Refresher/`. This is separate from the Xcode build's data.

Optional: set `GITHUB_TOKEN` in the environment to raise GitHub's API rate limit. It isn't needed for one fetch a day.

## Project layout

```
Sources/BriefCore/   fetching, parsing, ranking, storage (shared by app, widget, CLI)
Sources/BriefApp/    SwiftUI app: two-pane window, settings, notifications
Sources/BriefUI/     views shared by app and widget; AppBrand (neutral look unless built with the private brand)
Sources/app-assets/  renders the app icon at build time, plus previews
Agent/               background helper (login item): daily refresh + widget reload
Sources/brief-cli/   command-line fetch/show
Widget/              WidgetKit extension (built by Xcode only)
Tests/               ranking, categorization, parsers, schedule, store
project.yml          XcodeGen spec for the app + widget project
windows/             Windows app (.NET 10 + Avalonia)
  Refresher.Core/    port of BriefCore: same sources, ranking and JSON format
  Refresher.App/     two-pane window, tray menu, start with Windows, notifications; AppBrand
  Refresher.Cli/     command-line fetch/show
  Refresher.Core.Tests/
android/             Android app (Kotlin + Jetpack Compose)
  core/              port of BriefCore (plain Kotlin, tested on the JVM): same sources, ranking and JSON format
  app/               two tabs or panes, Glance widget, WorkManager refresh, notifications; AppBrand
  app/src/neutral/   name, icon and BrandKit for builds without the private brand kit
scripts/make-exe.sh  single-file Windows .exe in dist/
scripts/make-apk.sh  signed Android .apk in dist/
PRIVACY.md           privacy policy (linked from the Google sign-in screen)
scripts/release.sh   .dmg + .exe + .apk as a draft GitHub release
```
