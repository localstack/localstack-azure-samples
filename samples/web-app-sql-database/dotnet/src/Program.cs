using VacationPlanner.Services;

var builder = WebApplication.CreateBuilder(args);
var startupLogger = LoggerFactory.Create(logging => logging.AddConsole()).CreateLogger("Startup");

// Code deployments built by Oryx export PORT (and ASPNETCORE_URLS); custom images and local runs set PORT.
var httpPort = int.Parse(Environment.GetEnvironmentVariable("PORT") ?? "8080");
var vaultUri = Environment.GetEnvironmentVariable("KEYVAULT_URI");
var certificateName = Environment.GetEnvironmentVariable("CERT_NAME");

// Serve HTTPS on 8443 with the certificate stored in Key Vault, next to the plain HTTP endpoint App Service proxies to.
builder.WebHost.ConfigureKestrel(kestrel =>
{
    kestrel.ListenAnyIP(httpPort);
    if (!string.IsNullOrEmpty(vaultUri) && !string.IsNullOrEmpty(certificateName))
    {
        try
        {
            var certificate = KeyVaultCertificates.LoadServerCertificateAsync(vaultUri, certificateName, CancellationToken.None).GetAwaiter().GetResult();
            kestrel.ListenAnyIP(8443, listen => listen.UseHttps(certificate));
            startupLogger.LogInformation("HTTPS enabled on port 8443 with Key Vault certificate [{Certificate}]", certificateName);
        }
        catch (Exception ex)
        {
            startupLogger.LogError(ex, "Could not load certificate [{Certificate}] from Key Vault; HTTPS on 8443 is disabled", certificateName);
        }
    }
});

// Resolve the SQL connection (Key Vault secret first) up front so a misconfigured deployment fails at startup.
var sqlOptions = await SqlOptions.FromEnvironmentAsync(startupLogger, CancellationToken.None);

builder.Services.AddRazorPages();
builder.Services.AddSingleton<IActivityStore>(sp =>
    new SqlActivityStore(sqlOptions, sp.GetRequiredService<ILogger<SqlActivityStore>>()));
builder.Services.AddHostedService(sp =>
    new StoreInitializer(sp.GetRequiredService<IActivityStore>(), sp.GetRequiredService<ILogger<StoreInitializer>>()));

var app = builder.Build();

app.UseStaticFiles();
app.MapRazorPages();

app.MapGet("/health", async (IActivityStore store, CancellationToken cancellationToken) =>
    await store.IsHealthyAsync(cancellationToken)
        ? Results.Json(new { status = "ok" })
        : Results.Json(new { status = "unavailable" }, statusCode: StatusCodes.Status503ServiceUnavailable));

// Downloads the certificate from Key Vault and returns its properties, proving the Key Vault certificate integration works.
app.MapGet("/api/certificate", async (ILogger<Program> logger, CancellationToken cancellationToken) =>
{
    if (string.IsNullOrEmpty(vaultUri) || string.IsNullOrEmpty(certificateName))
    {
        return Results.Json(new { error = "KEYVAULT_URI not configured" }, statusCode: StatusCodes.Status500InternalServerError);
    }

    try
    {
        return Results.Json(await KeyVaultCertificates.GetCertificateInfoAsync(vaultUri, certificateName, cancellationToken));
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Error validating certificate");
        return Results.Json(new { error = ex.Message }, statusCode: StatusCodes.Status500InternalServerError);
    }
});

app.Run();
