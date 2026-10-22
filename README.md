# AI-ML Refresher

A macOS widget and companion app, and a Windows app, for a 15-minute daily reading habit in AI & ML.

Every day after **12:00 local time** it collects what's popular or trending across GitHub, Hugging Face, Hacker News, Reddit and a set of research blogs. It ranks everything with a fixed, deterministic formula and keeps the **top 15**.

- **Widget** (medium or large): today's top 5. Click an item to open it, click the bookmark to save it, click **Expand** to open the app.
- **App window**: today's items on the left and your **collection** on the right. Drag items across to save them. Saved items keep tags, notes and read/unread state forever. The ‹ › arrows browse past days.
- **Background helper**: a small invisible helper inside the app builds the brief after 12:00 and keeps the widget current, even with the app closed. The app itself behaves like any Mac app: it bounces in the Dock when launched and quits when you close its window.
- **Notifications** (optional, bell button): "Most recent AI & ML trends for you" every day at 12:05.

No AI summaries and no API keys. The same inputs always produce the same list.

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

### Install from the disk image

Open the `.dmg` from `dist/` (or a release) and drag the app onto **Applications**.

The app is signed with a development certificate, not notarized by Apple. On another Mac, macOS will block the first launch. To allow it, go to **System Settings → Privacy & Security** and click **Open Anyway**. You only need to do this once. Notarizing removes this step, but it requires the paid Apple Developer Program.

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

### Install

Download the `.exe` from `dist/` or a release and run it. It's a single self-contained file, so you don't need to install .NET. It isn't code-signed, so the first time you run it, Windows SmartScreen may say "Windows protected your PC". Click **More info → Run anyway**. *Settings → Start with Windows* is on by default.

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

## License

The code is MIT licensed (`LICENSE`). Builds from this repository are unbranded and named "AI-ML Refresher". Official releases (macOS and Windows) add their own name, icon and launch animation from a private package that isn't part of this repository. Those are not licensed for reuse; see `BRAND.md`.

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
scripts/make-exe.sh  single-file Windows .exe in dist/
```
