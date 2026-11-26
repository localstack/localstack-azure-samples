using System.Diagnostics;
using Microsoft.OpenTelemetry;
using OpenTelemetry.Metrics;
using VacationPlanner;

var builder = WebApplication.CreateBuilder(args);

// When App Service passes the connection string of the Application Insights resource, the Microsoft OpenTelemetry
// Distro sends to Application Insights the requests the app serves, its log records (traces), the exceptions of the
// requests that fail, and the custom event and the custom metric of StatusTelemetry.
if (!string.IsNullOrEmpty(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
{
    // The distro exports the custom metrics of the meters it's told about
    builder.Services.ConfigureOpenTelemetryMeterProvider(
        (_, meterProvider) => meterProvider.AddMeter(StatusTelemetry.MeterName));
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

builder.Services.AddRazorPages();

var app = builder.Build();

// One log line per request, the equivalent of the gunicorn access log the Python sample produces.
var requestLogger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("VacationPlanner.Requests");
var statusLogger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("VacationPlanner.Status");
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

app.MapGet("/api/status", () =>
{
    StatusTelemetry.Track(statusLogger, AppInfo.ImageName, AppInfo.HostName);
    // The values of a message template's placeholders reach Application Insights as custom dimensions
    statusLogger.LogInformation("Status returned: {ImageName} on {HostName}", AppInfo.ImageName, AppInfo.HostName);
    return Results.Json(new
    {
        status = "ok",
        app = AppInfo.AppName,
        image = AppInfo.ImageName,
        hostname = AppInfo.HostName,
    });
});

app.MapGet("/health", () => Results.Json(new { status = "ok" }));

app.Run();
