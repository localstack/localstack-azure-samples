using System.Diagnostics;
using VacationPlanner.Services;

var builder = WebApplication.CreateBuilder(args);

// Code deployments built by Oryx export ASPNETCORE_URLS; custom images and local runs only set PORT.
if (Environment.GetEnvironmentVariable("ASPNETCORE_URLS") is null
    && Environment.GetEnvironmentVariable("PORT") is { Length: > 0 } port)
{
    builder.WebHost.UseUrls($"http://*:{port}");
}

// Load the PostgreSQL connection settings from Azure App Configuration with the in-process provider: the
// store endpoint comes from the Endpoints:AppConfiguration setting (the Endpoints__AppConfiguration app
// setting), one DefaultAzureCredential authenticates to the store and to Key Vault (the user-assigned managed
// identity selected by AZURE_CLIENT_ID on App Service), and the provider resolves the two Key Vault
// references. The host is not built yet, so a bootstrap console logger reports the load.
using var bootstrapLoggerFactory = LoggerFactory.Create(logging => logging.AddConsole());
AppConfigurationSettings.Load(builder.Configuration, bootstrapLoggerFactory.CreateLogger("VacationPlanner.AppConfiguration"));

// Read and validate the configuration up front so a misconfigured deployment fails at startup.
var databaseOptions = PostgresOptions.FromConfiguration(builder.Configuration);

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

// One log line per request, the equivalent of the gunicorn access log the Python sample produces.
var requestLogger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("VacationPlanner.Requests");
app.Use(
    async (context, next) =>
    {
        var started = Stopwatch.GetTimestamp();
        await next();
        requestLogger.LogInformation(
            "{Method} {Path} -> {StatusCode} in {Elapsed:0.0}ms",
            context.Request.Method,
            context.Request.Path,
            context.Response.StatusCode,
            Stopwatch.GetElapsedTime(started).TotalMilliseconds
        );
    }
);

app.UseStaticFiles();
app.MapRazorPages();

app.MapGet("/health", async (IActivityStore store, CancellationToken cancellationToken) =>
    await store.IsHealthyAsync(cancellationToken)
        ? Results.Json(new { status = "ok" })
        : Results.Json(new { status = "unavailable" }, statusCode: StatusCodes.Status503ServiceUnavailable));

app.Run();
