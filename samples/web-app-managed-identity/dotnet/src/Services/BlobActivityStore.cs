using System.Text;
using Azure.Identity;
using Azure.Storage.Blobs;
using VacationPlanner.Models;

namespace VacationPlanner.Services;

/// <summary>One blob per activity in a Blob Storage container; the blob name is the activity id and its content the text.</summary>
public sealed class BlobActivityStore : IActivityStore
{
    private readonly BlobContainerClient _container;
    private readonly ILogger<BlobActivityStore> _logger;

    public BlobActivityStore(BlobStorageOptions options, ILogger<BlobActivityStore> logger)
    {
        BlobServiceClient service;
        if (options is { ClientId: { Length: > 0 }, ClientSecret: { Length: > 0 }, TenantId: { Length: > 0 }, AccountUrl: { Length: > 0 } })
        {
            logger.LogInformation("Using ClientSecretCredential with BlobServiceClient.");
            var credential = new ClientSecretCredential(options.TenantId, options.ClientId, options.ClientSecret);
            service = new BlobServiceClient(new Uri(options.AccountUrl), credential);
        }
        else if (!string.IsNullOrEmpty(options.ConnectionString))
        {
            logger.LogInformation("Using storage account connection string with BlobServiceClient.");
            service = new BlobServiceClient(options.ConnectionString);
        }
        else if (!string.IsNullOrEmpty(options.AccountUrl))
        {
            // DefaultAzureCredential picks up AZURE_CLIENT_ID for the user-assigned managed identity.
            logger.LogInformation("Using DefaultAzureCredential with BlobServiceClient.");
            service = new BlobServiceClient(new Uri(options.AccountUrl), new DefaultAzureCredential());
        }
        else
        {
            throw new InvalidOperationException(
                "Insufficient configuration for BlobServiceClient. Set AZURE_STORAGE_ACCOUNT_URL (managed identity) or AZURE_STORAGE_ACCOUNT_CONNECTION_STRING.");
        }

        _container = service.GetBlobContainerClient(options.ContainerName);
        _logger = logger;
    }

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        await _container.CreateIfNotExistsAsync(cancellationToken: cancellationToken);
    }

    public async Task<IReadOnlyList<Activity>> ListAsync(CancellationToken cancellationToken)
    {
        var activities = new List<Activity>();
        await foreach (var blob in _container.GetBlobsAsync(cancellationToken: cancellationToken))
        {
            var content = await _container.GetBlobClient(blob.Name).DownloadContentAsync(cancellationToken);
            _logger.LogInformation(
                "Found blob '{Blob}' with size {Size} bytes",
                blob.Name,
                blob.Properties.ContentLength
            );
            activities.Add(new Activity(blob.Name, content.Value.Content.ToString()));
        }

        _logger.LogInformation(
            "Retrieved {Count} blob(s) from container '{Container}'",
            activities.Count,
            _container.Name
        );
        return activities;
    }

    public Task AddAsync(string text, CancellationToken cancellationToken)
    {
        var name = $"{DateTime.Now:yyyy-MM-dd-HH-mm-ss}-activity.txt";
        return UploadAsync(name, text, cancellationToken);
    }

    public Task UpdateAsync(string id, string text, CancellationToken cancellationToken) => UploadAsync(id, text, cancellationToken);

    public async Task DeleteAsync(string id, CancellationToken cancellationToken)
    {
        await _container.GetBlobClient(id).DeleteIfExistsAsync(cancellationToken: cancellationToken);
        _logger.LogInformation("Deleted blob '{Blob}' from container '{Container}'", id, _container.Name);
    }

    public async Task<bool> IsHealthyAsync(CancellationToken cancellationToken)
    {
        return await _container.ExistsAsync(cancellationToken);
    }

    private async Task UploadAsync(string name, string text, CancellationToken cancellationToken)
    {
        await _container.GetBlobClient(name).UploadAsync(new BinaryData(Encoding.UTF8.GetBytes(text)), overwrite: true, cancellationToken);
        _logger.LogInformation("Uploaded blob '{Blob}' to container '{Container}'", name, _container.Name);
    }
}
