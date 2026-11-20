using Azure.Monitor.OpenTelemetry.Exporter;
using LocalStack.Azure.Samples;
using Microsoft.Azure.Functions.Worker.OpenTelemetry;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using OpenTelemetry;
using OpenTelemetry.Metrics;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        // With the APPLICATIONINSIGHTS_CONNECTION_STRING app setting and telemetryMode set to OpenTelemetry in host.json,
        // the worker sends to Application Insights the log records of the function (traces), the exceptions it logs,
        // and the custom event and the custom metric of BlobTelemetry
        if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_CONNECTION_STRING")))
        {
            services.AddOpenTelemetry()
                .UseFunctionsWorkerDefaults()
                .WithMetrics(metrics => metrics.AddMeter(BlobTelemetry.MeterName))
                .UseAzureMonitorExporter();
        }
    })
    .Build();

host.Run();
