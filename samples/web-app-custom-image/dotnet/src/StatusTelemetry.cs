using System.Diagnostics.Metrics;

namespace VacationPlanner;

/// <summary>
/// The custom telemetry of the status endpoint: a custom event for each status request, and a counter of them. With the
/// connection string of an Application Insights resource, the Microsoft OpenTelemetry Distro sends the events to the
/// customEvents table and the counter to the customMetrics table.
/// </summary>
public static class StatusTelemetry
{
    /// <summary>The name of the meter, which <c>Program.cs</c> adds to the meters the distro exports.</summary>
    public const string MeterName = "VacationPlanner";

    private static readonly Meter Meter = new(MeterName);

    private static readonly Counter<long> StatusRequests = Meter.CreateCounter<long>(
        "status_requests",
        unit: "{request}",
        description: "The number of status requests the app answered.");

    /// <summary>Sends the <c>StatusRequested</c> custom event and counts the request in the custom metric.</summary>
    public static void Track(ILogger logger, string imageName, string hostName)
    {
        // The distro sends a log record whose message template carries the microsoft.custom_event.name attribute as a
        // custom event named after its value, with the other attributes as its custom dimensions.
        logger.LogInformation("{microsoft.custom_event.name} {image.name} {hostname}", "StatusRequested", imageName, hostName);
        StatusRequests.Add(1, new KeyValuePair<string, object?>("image", imageName));
    }
}
