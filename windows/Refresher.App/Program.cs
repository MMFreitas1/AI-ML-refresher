using System.IO.Pipes;
using Avalonia;

namespace Refresher.App;

static class Program
{
    const string InstanceName = "AI-ML-Refresher-7d1c";

    [STAThread]
    public static int Main(string[] args)
    {
        // One copy at a time: a second launch (Start menu, double-click) asks the running one to
        // show its window, then exits.
        using var mutex = new Mutex(true, $"Local\\{InstanceName}", out var isFirst);
        if (!isFirst)
        {
            if (!args.Contains(Startup.BackgroundArg)) SignalRunningInstance();
            return 0;
        }

        return BuildAvaloniaApp().StartWithClassicDesktopLifetime(args, lifetime =>
            lifetime.ShutdownMode = Avalonia.Controls.ShutdownMode.OnExplicitShutdown);
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBrand.Configure(AppBuilder.Configure<App>().UsePlatformDetect().LogToTrace());

    static void SignalRunningInstance()
    {
        try
        {
            using var pipe = new NamedPipeClientStream(".", InstanceName, PipeDirection.Out);
            pipe.Connect(2000);
            pipe.WriteByte(1);
        }
        catch (Exception) { /* The other copy is exiting; nothing to show. */ }
    }

    /// <summary>Calls <paramref name="onShow"/> whenever another launch asks for the window.</summary>
    public static void ListenForOtherInstances(Action onShow)
    {
        var thread = new Thread(() =>
        {
            while (true)
            {
                try
                {
                    using var pipe = new NamedPipeServerStream(InstanceName, PipeDirection.In, 1);
                    pipe.WaitForConnection();
                    if (pipe.ReadByte() == 1) onShow();
                }
                catch (IOException) { Thread.Sleep(500); }
            }
        }) { IsBackground = true, Name = "single-instance" };
        thread.Start();
    }
}
