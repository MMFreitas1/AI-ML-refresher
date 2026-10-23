using Refresher.Core;

// brief-cli fetch [--dir <path>]   build today's brief now and print it
// brief-cli show  [--dir <path>]   print the latest saved brief
var dirIndex = Array.IndexOf(args, "--dir");
var store = new BriefStore(dirIndex >= 0 && dirIndex + 1 < args.Length ? args[dirIndex + 1] : null);

switch (args.FirstOrDefault())
{
    case "fetch":
        Print(await new BriefBuilder().Run(store));
        break;
    case "show":
        if (store.LatestBrief() is { } brief) Print(brief);
        else Console.WriteLine("No brief saved yet. Run: brief-cli fetch");
        break;
    default:
        Console.WriteLine("usage: brief-cli fetch|show [--dir <path>]");
        return 1;
}
return 0;

void Print(DailyBrief brief)
{
    Console.WriteLine($"{brief.Day} · {brief.Items.Count} items · {store.Directory}");
    for (var i = 0; i < brief.Items.Count; i++)
    {
        var item = brief.Items[i];
        Console.WriteLine($"{i + 1,2}. [{item.Field.Label()}] {item.Title}");
        Console.WriteLine($"    {item.Source} · {item.Metric} · score {item.Score:0.000}");
        Console.WriteLine($"    {item.Url}");
    }
    foreach (var error in brief.Errors) Console.WriteLine($"! {error}");
}
