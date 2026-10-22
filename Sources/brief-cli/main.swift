import BriefCore
import Foundation

// Usage:
//   brief-cli fetch        build today's brief now and print it
//   brief-cli show         print the latest saved brief
//   brief-cli if-due       build only if the noon refresh is due (for launchd / cron)
let store = BriefStore()
let command = CommandLine.arguments.dropFirst().first ?? "fetch"

func printBrief(_ brief: DailyBrief) {
    print("AI-ML Refresher — \(brief.day)  (\(brief.items.count) items, data in \(store.directory.path))\n")
    for (i, item) in brief.items.enumerated() {
        let rank = String(format: "%2d", i + 1)
        print("\(rank). [\(String(format: "%.2f", item.score))] \(item.title)")
        print("    \(item.field.rawValue) · \(item.source) · \(item.metric)")
        print("    \(item.url.absoluteString)")
    }
    if !brief.errors.isEmpty {
        print("\nSource errors:")
        brief.errors.forEach { print("  - \($0)") }
    }
}

switch command {
case "show":
    guard let brief = store.latestBrief() else { print("No brief saved yet. Run `brief-cli fetch`."); exit(1) }
    printBrief(brief)
case "if-due":
    guard Schedule.isDue(latestDay: store.latestBrief()?.day) else { print("Not due."); exit(0) }
    printBrief(try await BriefBuilder().run(store: store))
default:
    printBrief(try await BriefBuilder().run(store: store))
}
