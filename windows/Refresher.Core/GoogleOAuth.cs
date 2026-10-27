using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Refresher.Core;

/// <summary>
/// Google sign-in for desktop apps ("OAuth 2.0 for installed apps"): the browser shows Google's
/// sign-in and consent, then returns to a 127.0.0.1 port the app listens on, with a code the app
/// exchanges for tokens. PKCE ties the code to this app instance. Same flow as the macOS app.
/// </summary>
/// <param name="ClientSecret">For installed apps Google doesn't treat it as confidential, but it's required.</param>
public sealed record GoogleOAuth(string ClientId, string ClientSecret)
{
    static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(30) };

    /// <param name="RefreshToken">Only on the first sign-in; keep it to get new access tokens.</param>
    public sealed record Tokens(string AccessToken, DateTimeOffset ExpiresAt, string? RefreshToken);

    /// <summary>One sign-in: opens the browser via <paramref name="openBrowser"/>, waits for Google to send it
    /// back, and exchanges the code. Returns null when the user cancelled or declined.</summary>
    public async Task<Tokens?> SignIn(string scope, Action<string> openBrowser, CancellationToken ct)
    {
        var port = FreePort();
        var redirect = $"http://127.0.0.1:{port}/";
        using var listener = new HttpListener();
        listener.Prefixes.Add(redirect);
        listener.Start();

        var verifier = RandomUrlSafe(32);
        var challenge = Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
        var state = RandomUrlSafe(16);
        openBrowser("https://accounts.google.com/o/oauth2/v2/auth?" + Form(new()
        {
            ["client_id"] = ClientId, ["redirect_uri"] = redirect, ["response_type"] = "code", ["scope"] = scope,
            ["code_challenge"] = challenge, ["code_challenge_method"] = "S256", ["state"] = state,
            // A refresh token, so the app stays signed in.
            ["access_type"] = "offline", ["prompt"] = "consent",
        }));

        while (true)
        {
            var context = await listener.GetContextAsync().WaitAsync(ct);
            var query = context.Request.QueryString;
            // Browsers also ask for /favicon.ico; only the redirect carries state.
            if (query["state"] is null) { context.Response.StatusCode = 404; context.Response.Close(); continue; }
            var code = query["code"];
            await Respond(context, code != null);
            if (query["state"] != state) throw new FetchError("Google's sign-in reply didn't match. Try again.");
            if (code is null) return null; // access_denied: the user said no
            return await TokenRequest(new()
            {
                ["grant_type"] = "authorization_code", ["code"] = code, ["code_verifier"] = verifier, ["redirect_uri"] = redirect,
            }, ct);
        }
    }

    /// <summary>A new access token. Throws <see cref="DriveAuthException"/> when Google no longer accepts the
    /// refresh token (signed out, password changed, access removed): the user has to sign in again.</summary>
    public Task<Tokens> Refresh(string refreshToken, CancellationToken ct = default) =>
        TokenRequest(new() { ["grant_type"] = "refresh_token", ["refresh_token"] = refreshToken }, ct);

    /// <summary>Best effort: tells Google to forget this app's access.</summary>
    public static async Task Revoke(string token)
    {
        try { await Client.PostAsync("https://oauth2.googleapis.com/revoke", new FormUrlEncodedContent(new Dictionary<string, string> { ["token"] = token })); }
        catch (Exception) { /* offline: the access stays until the user removes it in their Google Account */ }
    }

    async Task<Tokens> TokenRequest(Dictionary<string, string> fields, CancellationToken ct)
    {
        fields["client_id"] = ClientId;
        fields["client_secret"] = ClientSecret;
        using var res = await Client.PostAsync("https://oauth2.googleapis.com/token", new FormUrlEncodedContent(fields), ct);
        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync(ct));
        var root = doc.RootElement;
        if (root.Str("error") == "invalid_grant") throw new DriveAuthException("Google sign-in expired");
        if (!res.IsSuccessStatusCode || root.Str("access_token") is not { } token)
            throw FetchError.Parse($"Google's sign-in reply ({root.Str("error") ?? "no token"})");
        // Renew a minute early.
        return new Tokens(token, DateTimeOffset.UtcNow.AddSeconds((root.Num("expires_in") ?? 3600) - 60), root.Str("refresh_token"));
    }

    static async Task Respond(HttpListenerContext context, bool ok)
    {
        var body = $"""
            <!doctype html><meta charset="utf-8"><title>Sign-in</title>
            <body style="font: 16px system-ui, sans-serif; text-align: center; padding: 15vh 2em">
            <h2>{(ok ? "You're signed in" : "Sign-in didn't finish")}</h2>
            <p>{(ok ? "You can close this tab and go back to the app." : "Go back to the app and try again.")}</p>
            """;
        var bytes = Encoding.UTF8.GetBytes(body);
        context.Response.ContentType = "text/html; charset=utf-8";
        context.Response.ContentLength64 = bytes.Length;
        await context.Response.OutputStream.WriteAsync(bytes);
        context.Response.Close();
    }

    static int FreePort()
    {
        using var socket = new TcpListener(IPAddress.Loopback, 0);
        socket.Start();
        return ((IPEndPoint)socket.LocalEndpoint).Port;
    }

    static string Form(Dictionary<string, string> fields) =>
        string.Join("&", fields.Select(f => $"{f.Key}={Uri.EscapeDataString(f.Value)}"));

    static string RandomUrlSafe(int bytes) => Base64Url(RandomNumberGenerator.GetBytes(bytes));

    static string Base64Url(byte[] data) => Convert.ToBase64String(data).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
