using System.Diagnostics.Metrics;
using Microsoft.Extensions.Logging;

namespace LocalStack.Azure.Samples;

/// <summary>
/// The custom telemetry of the greetings: a custom event for each greeting a function requests, processes or receives,
/// and a counter of these operations. With the connection string of an Application Insights resource, the
/// OpenTelemetry exporter of Azure Monitor sends the events to the customEvents table and the counter to the
/// customMetrics table.
/// </summary>
public static class GreetingTelemetry
{
    /// <summary>The name of the meter, which <c>Program.cs</c> adds to the meters the exporter sends.</summary>
    public const string MeterName = "GreetingService";

    private static readonly Meter Meter = new(MeterName);

    private static readonly Counter<long> Greetings = Meter.CreateCounter<long>(
        "greetings",
        unit: "{greeting}",
        description: "The number of greetings requested, processed and received, by operation.");

    /// <summary>Sends the custom event named <paramref name="eventName"/> and counts the operation in the custom metric.</summary>
    public static void Track(ILogger logger, string eventName, string operation, string name)
    {
        // The exporter sends a log record whose message template carries the microsoft.custom_event.name attribute as a
        // custom event named after its value, with the other attributes as its custom dimensions.
        logger.LogInformation("{microsoft.custom_event.name} {greeting.name}", eventName, name);
        Greetings.Add(1, new KeyValuePair<string, object?>("operation", operation));
    }
}
