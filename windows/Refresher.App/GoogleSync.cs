using System.Security.Cryptography;
using System.Text;
using Avalonia.Threading;
using Refresher.Core;

namespace Refresher.App;

/// <summary>
/// Keeps the collection the same on every device signed in to the same Google account, through one
/// file in the user's Google Drive (see <see cref="DriveFile"/>). Only official builds have it: they
/// carry the Google client the sign-in needs (<see cref="AppBrand.GoogleClient"/>).
///
/// Syncs at launch, every 15 minutes while the app runs, when the window is activated, and a few
/// seconds after each change.
/// </summary>
public sealed class GoogleSync : Observable
{
    public enum Status { Off, SigningIn, Syncing, On, NeedsSignIn, Failed }

    readonly BriefStore store;
    readonly GoogleOAuth? oauth;
    readonly SemaphoreSlim gate = new(1, 1);
    GoogleOAuth.Tokens? tokens;
    CancellationTokenSource? signIn;
    CancellationTokenSource? pending;

    /// <summary>Raised (on the UI thread) when a sync changed the local collection.</summary>
    public event Action? CollectionChanged;

    public GoogleSync(BriefStore store)
    {
        this.store = store;
        oauth = AppBrand.GoogleClient is { } c ? new GoogleOAuth(c.Id, c.Secret) : null;
        var saved = TokenFile.Load(store);
        if (oauth != null && saved?.RefreshToken != null)
        {
            email = saved.Email;
            lastSync = saved.LastSync;
            status = Status.On;
        }
    }

    public bool IsAvailable => oauth != null;

    Status status;
    public Status Current
    {
        get => status;
        private set
        {
            if (Set(ref status, value))
                Raise(nameof(IsOn), nameof(IsOff), nameof(IsSigningIn), nameof(StatusText), nameof(NeedsSignIn), nameof(CanSyncNow), nameof(IsProblem));
        }
    }

    public bool IsOn => status is not (Status.Off or Status.SigningIn);
    public bool IsOff => status == Status.Off;
    public bool IsSigningIn => status == Status.SigningIn;
    public bool NeedsSignIn => status == Status.NeedsSignIn;
    public bool CanSyncNow => status is Status.On or Status.Failed;
    public bool IsProblem => status is Status.NeedsSignIn or Status.Failed;

    string? email;
    public string Email => email ?? "Google account";

    DateTimeOffset? lastSync;
    string? failure;

    public string StatusText => status switch
    {
        Status.Syncing => "Syncing…",
        Status.NeedsSignIn => "Google signed you out",
        Status.Failed => $"Last sync failed: {failure}",
        _ when lastSync is null => "On",
        _ when DateTimeOffset.UtcNow - lastSync.Value < TimeSpan.FromMinutes(1) => "Synced just now",
        _ => $"Synced {lastSync.Value.ToLocalTime():g}",
    };

    string? signInError;
    /// <summary>Shown under the button after a failed sign-in.</summary>
    public string? SignInError { get => signInError; private set { if (Set(ref signInError, value)) Raise(nameof(HasSignInError)); } }
    public bool HasSignInError => signInError != null;

    // MARK: Sign-in

    /// <summary>Opens Google's sign-in in the browser and waits for it to come back.</summary>
    public async Task SignIn()
    {
        if (oauth == null || status == Status.SigningIn) return;
        Current = Status.SigningIn;
        SignInError = null;
        signIn = new CancellationTokenSource(TimeSpan.FromMinutes(5));
        try
        {
            var t = await oauth.SignIn(DriveFile.Scope, Shell.Open, signIn.Token);
            if (t == null) { Current = Status.Off; return; }
            if (t.RefreshToken == null) throw new FetchError("Google didn't keep you signed in. Try again.");
            tokens = t;
            Current = Status.On;
            App.Current?.ShowMainWindow();
            try { email = await new DriveFile(AccessToken).Email(); } catch (Exception) { email = null; }
            Raise(nameof(Email));
            TokenFile.Save(store, new TokenFile.Data(t.RefreshToken, email, null));
            await Sync();
        }
        catch (OperationCanceledException)
        {
            Current = Status.Off;
            if (signIn?.IsCancellationRequested == true && signIn.Token.CanBeCanceled && !cancelledByUser) SignInError = "Sign-in timed out. Try again.";
        }
        catch (Exception e)
        {
            Current = Status.Off;
            SignInError = e.Message;
        }
        finally { cancelledByUser = false; }
    }

    bool cancelledByUser;

    public void CancelSignIn()
    {
        cancelledByUser = true;
        signIn?.Cancel();
    }

    public void SignOut()
    {
        pending?.Cancel();
        if (TokenFile.Load(store)?.RefreshToken is { } token) _ = GoogleOAuth.Revoke(token);
        TokenFile.Delete(store);
        tokens = null;
        email = null;
        lastSync = null;
        Raise(nameof(Email));
        Current = Status.Off;
    }

    // MARK: Syncing

    /// <summary>After a change: syncs a few seconds later, so quick edits (typing a note) go up together.</summary>
    public void SyncSoon()
    {
        if (!IsOn) return;
        pending?.Cancel();
        pending = new CancellationTokenSource();
        var token = pending.Token;
        _ = Task.Delay(TimeSpan.FromSeconds(5), token).ContinueWith(t =>
        {
            if (!t.IsCanceled) Dispatcher.UIThread.Post(async () => await Sync());
        }, TaskScheduler.Default);
    }

    public async Task Sync()
    {
        if (!IsOn || !await gate.WaitAsync(0)) return;
        Current = Status.Syncing;
        try
        {
            var outcome = await Task.Run(() => new CollectionSyncer(store, new DriveFile(AccessToken)).Sync());
            lastSync = DateTimeOffset.UtcNow;
            if (TokenFile.Load(store) is { } saved) TokenFile.Save(store, saved with { Email = email, LastSync = lastSync });
            Current = Status.On;
            Raise(nameof(StatusText));
            if (outcome.ChangedLocally) CollectionChanged?.Invoke();
        }
        catch (DriveAuthException) { Current = Status.NeedsSignIn; }
        catch (Exception e)
        {
            failure = e is TaskCanceledException ? "timed out" : e.Message;
            Current = Status.Failed;
        }
        finally { gate.Release(); }
    }

    /// <summary>A current access token, refreshed with the stored refresh token when needed.</summary>
    async Task<string> AccessToken(CancellationToken ct)
    {
        if (tokens is { } t && t.ExpiresAt > DateTimeOffset.UtcNow) return t.AccessToken;
        if (oauth == null || TokenFile.Load(store)?.RefreshToken is not { } refresh) throw new DriveAuthException("Not signed in");
        tokens = await oauth.Refresh(refresh, ct);
        return tokens.AccessToken;
    }

    /// <summary>
    /// The Google refresh token, kept signed in across launches: google-sync.bin next to the data,
    /// encrypted for this Windows user (DPAPI). A preview run on a Mac stores it unencrypted.
    /// </summary>
    static class TokenFile
    {
        public sealed record Data(string? RefreshToken, string? Email, DateTimeOffset? LastSync);

        static string PathIn(BriefStore store) => Path.Combine(store.Directory, "google-sync.bin");

        public static Data? Load(BriefStore store)
        {
            try
            {
                var bytes = File.ReadAllBytes(PathIn(store));
                if (OperatingSystem.IsWindows()) bytes = ProtectedData.Unprotect(bytes, null, DataProtectionScope.CurrentUser);
                return System.Text.Json.JsonSerializer.Deserialize<Data>(bytes, BriefStore.Json);
            }
            catch (Exception) { return null; }
        }

        public static void Save(BriefStore store, Data data)
        {
            var bytes = System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(data, BriefStore.Json);
            if (OperatingSystem.IsWindows()) bytes = ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(PathIn(store), bytes);
            if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(PathIn(store), UnixFileMode.UserRead | UnixFileMode.UserWrite);
        }

        public static void Delete(BriefStore store)
        {
            try { File.Delete(PathIn(store)); } catch (IOException) { }
        }
    }
}
