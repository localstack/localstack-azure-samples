using System.Diagnostics;
using Microsoft.OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;
using VacationPlanner.Services;

var builder = WebApplication.CreateBuilder(args);

// When App Service passes the connection string of the Application Insights resource, the Microsoft OpenTelemetry
// Distro sends to Application Insights the requests the app serves, its calls to MySQL, its log records
// (traces), the exceptions it logs, and the custom events and the custom metric of ActivityTelemetry.
if (!string.IsNullOrEmpty(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
{
    // The distro exports the custom metrics of the meters it's told about, and the traces of the activity
    // source with which MySqlConnector traces its commands
    builder.Services.ConfigureOpenTelemetryMeterProvider(
        (_, meterProvider) => meterProvider.AddMeter(ActivityTelemetry.MeterName));
    builder.Services.ConfigureOpenTelemetryTracerProvider(
        (_, tracerProvider) => tracerProvider.AddSource("MySqlConnector"));
    builder.UseMicrosoftOpenTelemetry(options =>
    {
        options.Exporters = ExportTarget.AzureMonitor;
    });
}

// Code deployments built by Oryx export ASPNETCORE_URLS; custom images and local runs only set PORT.
if (Environment.GetEnvironmentVariable("ASPNETCORE_URLS") is null
    && Environment.GetEnvironmentVariable("PORT") is { Length: > 0 } port)
{
    builder.WebHost.UseUrls($"http://*:{port}");
}

// Read and validate the configuration up front so a misconfigured deployment fails at startup.
var databaseOptions = MySqlOptions.FromEnvironment();

builder.Services.AddRazorPages();
builder.Services.AddSingleton<IActivityStore>(sp =>
    new MySqlActivityStore(databaseOptions, sp.GetRequiredService<ILogger<MySqlActivityStore>>()));
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
