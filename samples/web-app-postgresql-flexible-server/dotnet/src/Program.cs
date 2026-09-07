using VacationPlanner.Services;

var builder = WebApplication.CreateBuilder(args);

// Code deployments built by Oryx export ASPNETCORE_URLS; custom images and local runs only set PORT.
if (Environment.GetEnvironmentVariable("ASPNETCORE_URLS") is null
    && Environment.GetEnvironmentVariable("PORT") is { Length: > 0 } port)
{
    builder.WebHost.UseUrls($"http://*:{port}");
}

// Read and validate the configuration up front so a misconfigured deployment fails at startup.
var databaseOptions = PostgresOptions.FromEnvironment();

builder.Services.AddRazorPages();
builder.Services.AddSingleton<IActivityStore>(sp =>
    new PostgresActivityStore(databaseOptions, sp.GetRequiredService<ILogger<PostgresActivityStore>>()));
// The flexible server can take a few seconds to accept connections on the first deploy.
builder.Services.AddHostedService(sp => new StoreInitializer(
    sp.GetRequiredService<IActivityStore>(),
    sp.GetRequiredService<ILogger<StoreInitializer>>(),
    attempts: 30,
    delay: TimeSpan.FromSeconds(2)));

var app = builder.Build();

app.UseStaticFiles();
app.MapRazorPages();

app.MapGet("/health", async (IActivityStore store, CancellationToken cancellationToken) =>
    await store.IsHealthyAsync(cancellationToken)
        ? Results.Json(new { status = "ok" })
        : Results.Json(new { status = "unavailable" }, statusCode: StatusCodes.Status503ServiceUnavailable));

app.Run();
