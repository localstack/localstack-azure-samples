using System.Diagnostics.Metrics;

namespace VacationPlanner.Services;

/// <summary>
/// The custom telemetry of the activities: a custom event for each activity added, updated or deleted, and a counter of
/// these operations. With the connection string of an Application Insights resource, the Microsoft OpenTelemetry Distro
/// sends the events to the customEvents table and the counter to the customMetrics table.
/// </summary>
public static class ActivityTelemetry
{
    /// <summary>The name of the meter, which <c>Program.cs</c> adds to the meters the distro exports.</summary>
    public const string MeterName = "VacationPlanner";

    private static readonly Meter Meter = new(MeterName);

    private static readonly Counter<long> Activities = Meter.CreateCounter<long>(
        "activities",
        unit: "{activity}",
        description: "The number of activities added, updated and deleted.");

    /// <summary>Sends a custom event named <paramref name="eventName"/> and counts the operation in the custom metric.</summary>
    public static void Track(ILogger logger, string eventName, string operation, string activityId)
    {
        // The distro sends a log record whose message template carries the microsoft.custom_event.name attribute as a
        // custom event named after its value, with the other attributes as its custom dimensions.
        logger.LogInformation("{microsoft.custom_event.name} {activity.id}", eventName, activityId);
        Activities.Add(1, new KeyValuePair<string, object?>("operation", operation));
    }
}
