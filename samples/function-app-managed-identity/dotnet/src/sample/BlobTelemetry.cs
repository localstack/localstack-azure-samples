using System.Diagnostics.Metrics;
using Microsoft.Extensions.Logging;

namespace LocalStack.Azure.Samples;

/// <summary>
/// The custom telemetry of the function: a BlobProcessed custom event for each file it processes, and a counter of the
/// files. With the connection string of an Application Insights resource, the OpenTelemetry exporter of Azure Monitor
/// sends the event to the customEvents table and the counter to the customMetrics table.
/// </summary>
public static class BlobTelemetry
{
    /// <summary>The name of the meter, which <c>Program.cs</c> adds to the meters the exporter sends.</summary>
    public const string MeterName = "ProcessTextFunction";

    private static readonly Meter Meter = new(MeterName);

    private static readonly Counter<long> ProcessedBlobs = Meter.CreateCounter<long>(
        "processed_blobs",
        unit: "{blob}",
        description: "The number of blobs the function processed.");

    /// <summary>Sends the BlobProcessed custom event and counts the file in the custom metric.</summary>
    public static void TrackBlobProcessed(ILogger logger, string blobName, long blobSize, string outputContainer)
    {
        // The exporter sends a log record whose message template carries the microsoft.custom_event.name attribute as a
        // custom event named after its value, with the other attributes as its custom dimensions.
        logger.LogInformation(
            "{microsoft.custom_event.name} {blob.name} {blob.size}",
            "BlobProcessed",
            blobName,
            blobSize);
        ProcessedBlobs.Add(1, new KeyValuePair<string, object?>("container", outputContainer));
    }
}
