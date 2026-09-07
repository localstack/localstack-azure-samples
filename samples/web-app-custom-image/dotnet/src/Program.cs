using VacationPlanner;

var builder = WebApplication.CreateBuilder(args);

// Code deployments built by Oryx export ASPNETCORE_URLS; custom images and local runs only set PORT.
if (Environment.GetEnvironmentVariable("ASPNETCORE_URLS") is null
    && Environment.GetEnvironmentVariable("PORT") is { Length: > 0 } port)
{
    builder.WebHost.UseUrls($"http://*:{port}");
}

builder.Services.AddRazorPages();

var app = builder.Build();

app.UseStaticFiles();
app.MapRazorPages();

app.MapGet("/api/status", () => Results.Json(new
{
    status = "ok",
    app = AppInfo.AppName,
    image = AppInfo.ImageName,
    hostname = AppInfo.HostName,
}));

app.MapGet("/health", () => Results.Json(new { status = "ok" }));

app.Run();
