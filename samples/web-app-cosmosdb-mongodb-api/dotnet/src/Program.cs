using VacationPlanner.Services;

var builder = WebApplication.CreateBuilder(args);

// Code deployments built by Oryx export ASPNETCORE_URLS; custom images and local runs only set PORT.
if (Environment.GetEnvironmentVariable("ASPNETCORE_URLS") is null
    && Environment.GetEnvironmentVariable("PORT") is { Length: > 0 } port)
{
    builder.WebHost.UseUrls($"http://*:{port}");
}

// Read and validate the configuration up front so a misconfigured deployment fails at startup.
var mongoOptions = MongoOptions.FromEnvironment();

builder.Services.AddRazorPages();
builder.Services.AddSingleton<IActivityStore>(sp =>
    new MongoActivityStore(mongoOptions, sp.GetRequiredService<ILogger<MongoActivityStore>>()));
builder.Services.AddHostedService(sp =>
    new StoreInitializer(sp.GetRequiredService<IActivityStore>(), sp.GetRequiredService<ILogger<StoreInitializer>>()));

var app = builder.Build();

app.UseStaticFiles();
app.MapRazorPages();

app.MapGet("/health", async (IActivityStore store, CancellationToken cancellationToken) =>
    await store.IsHealthyAsync(cancellationToken)
        ? Results.Json(new { status = "ok" })
        : Results.Json(new { status = "unavailable" }, statusCode: StatusCodes.Status503ServiceUnavailable));

app.Run();
