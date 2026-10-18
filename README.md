# AI Brief

A macOS widget and companion app for a 15-minute daily reading habit in AI & ML.

Every day after **12:00 local time** it collects what's popular or trending across GitHub, Hugging Face, Hacker News, Reddit and a set of research blogs. It ranks everything with a fixed, deterministic formula and keeps the **top 15**.

- **Widget** (medium or large): today's top 5. Click an item to open it, click the bookmark to save it, click **Expand** to open the app.
- **App window**: today's items on the left and your **collection** on the right. Drag items across to save them. Saved items keep tags, notes and read/unread state forever. The ‹ › arrows browse past days.
- **Menu bar**: the top 5, *Refresh Now*, and *Open AI Brief*. The app is a background app with no Dock icon, so the noon refresh runs even with the window closed.

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

### Install (app + widget)

Requires Xcode and macOS 15 or later. Xcode doesn't need to be open.

```bash
./scripts/install.sh     # generates the project, builds a signed Release, installs to /Applications
```

1. Add the widget: right-click the desktop → **Edit Widgets** → search "AI Brief" → pick medium or large.
2. Open the app from the menu bar icon (✨) → **Settings…** and turn on **Open at login**.

The app runs in the background with no Dock icon and no window at launch. Its window opens from the widget's **Expand** button or from the menu bar icon. Run the script again after any code change.

The signing team is set in `project.yml` (`DEVELOPMENT_TEAM`). The Xcode project is generated from that file and is git-ignored, so make target or entitlement changes there. To work in Xcode, run `./scripts/make-xcode-project.sh` and open `AIBrief.xcodeproj`.

### Without Xcode (app window only, no widget)

```bash
swift run AIBrief          # the two-pane app + menu bar
swift run brief-cli fetch  # build today's brief now and print it
swift run brief-cli show   # print the latest saved brief
swift test                 # unit tests (needs Xcode's toolchain)
```

## Data

Data is plain JSON:

- `briefs/YYYY-MM-DD.json`: one ranked list per day, kept as history.
- `collection.json`: your saved items, with tags, notes and read state.

Where the files live depends on how the app was built:

- **Xcode build**: the shared App Group container, which the app and widget both use. *Settings → Show in Finder* opens it.
- **`swift run`**: `~/Library/Application Support/AIBrief/`. This is separate from the Xcode build's data.

Optional: set `GITHUB_TOKEN` in the environment to raise GitHub's API rate limit. It isn't needed for one fetch a day.

## Project layout

```
Sources/BriefCore/   fetching, parsing, ranking, storage (shared by app, widget, CLI)
Sources/BriefApp/    SwiftUI app: two-pane window, menu bar, settings
Sources/brief-cli/   command-line fetch/show
Widget/              WidgetKit extension (built by Xcode only)
Tests/               ranking, categorization, parsers, schedule, store
project.yml          XcodeGen spec for the app + widget project
```
