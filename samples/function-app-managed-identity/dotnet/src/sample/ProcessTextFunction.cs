using System.Text;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace LocalStack.Azure.Samples;

/// <summary>
/// Converts each text file uploaded to the input container to uppercase and writes it, under the same name, to the
/// output container. The blob trigger and the blob output binding reach the storage account through the
/// STORAGE_ACCOUNT_CONNECTION_STRING connection, which the STORAGE_ACCOUNT_CONNECTION_STRING__blobServiceUri,
/// __queueServiceUri and __tableServiceUri app settings make identity-based: the Functions host authenticates with the
/// managed identity of the function app.
/// </summary>
public class ProcessTextFunction(ILogger<ProcessTextFunction> logger)
{
    // Decodes UTF-8 strictly: a file that isn't UTF-8 text fails the invocation instead of turning into replacement
    // characters
    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    [Function("ProcessTextFunction")]
    [BlobOutput("%OUTPUT_STORAGE_CONTAINER_NAME%/{name}", Connection = "STORAGE_ACCOUNT_CONNECTION_STRING")]
    public string Run(
        [BlobTrigger(
            "%INPUT_STORAGE_CONTAINER_NAME%/{name}",
            Connection = "STORAGE_ACCOUNT_CONNECTION_STRING",
            Source = BlobTriggerSource.LogsAndContainerScan)]
        byte[] content,
        string name)
    {
        var inputContainer = Environment.GetEnvironmentVariable("INPUT_STORAGE_CONTAINER_NAME") ?? "input";
        var outputContainer = Environment.GetEnvironmentVariable("OUTPUT_STORAGE_CONTAINER_NAME") ?? "output";
        var blobName = $"{inputContainer}/{name}";
        logger.LogInformation(
            "Blob trigger function picked up blob {BlobName} of {BlobSize} bytes for the {TargetContainer} container",
            blobName,
            content.Length,
            outputContainer);

        try
        {
            // Process the text: convert it to uppercase
            var processedText = StrictUtf8.GetString(content).ToUpperInvariant();
            logger.LogInformation("Blob processed: {BlobName} ({BlobSize} bytes)", blobName, content.Length);
            BlobTelemetry.TrackBlobProcessed(logger, blobName, content.Length, outputContainer);
            return processedText;
        }
        catch (Exception exception)
        {
            // Logged with its stack trace (exceptions table) before the invocation fails
            logger.LogError(exception, "Failed to process blob {BlobName}", blobName);
            throw;
        }
    }
}
