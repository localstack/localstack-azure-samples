using System.Net;
using Microsoft.Azure.Cosmos;
using VacationPlanner.Models;

namespace VacationPlanner.Services;

/// <summary>Activities as items in an Azure Cosmos DB for NoSQL container partitioned by <c>/username</c>.</summary>
public sealed class CosmosActivityStore : IActivityStore
{
    private readonly CosmosClient _client;
    private readonly CosmosOptions _options;
    private readonly ILogger<CosmosActivityStore> _logger;
    private Container? _container;

    public CosmosActivityStore(CosmosOptions options, ILogger<CosmosActivityStore> logger)
    {
        _options = options;
        _logger = logger;
        // Gateway mode talks plain HTTPS to the account endpoint, which is what the LocalStack emulator
        // exposes; Direct mode (the SDK default) needs the TCP replica endpoints of a real account.
        _client = new CosmosClient(options.Endpoint, options.Key, new CosmosClientOptions
        {
            ConnectionMode = ConnectionMode.Gateway,
            LimitToEndpoint = true,
        });
    }

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        var database = await _client.CreateDatabaseIfNotExistsAsync(_options.DatabaseName, cancellationToken: cancellationToken);
        var container = await database.Database.CreateContainerIfNotExistsAsync(
            new ContainerProperties(_options.ContainerName, "/username"), throughput: 400, cancellationToken: cancellationToken);
        _container = container.Container;
        _logger.LogInformation("Cosmos DB database '{Database}' and container '{Container}' are ready", _options.DatabaseName, _options.ContainerName);
    }

    public async Task<IReadOnlyList<Activity>> ListAsync(CancellationToken cancellationToken)
    {
        var query = new QueryDefinition("SELECT * FROM c WHERE c.username = @username").WithParameter("@username", _options.Username);
        var activities = new List<Activity>();
        using var iterator = Container.GetItemQueryIterator<ActivityDocument>(query);
        while (iterator.HasMoreResults)
        {
            foreach (var document in await iterator.ReadNextAsync(cancellationToken))
            {
                activities.Add(new Activity(document.Id, document.Activity));
            }
        }

        return activities;
    }

    public Task AddAsync(string text, CancellationToken cancellationToken)
    {
        var document = new ActivityDocument
        {
            Id = ActivityId.Create(_options.Username, text),
            Username = _options.Username,
            Activity = text,
            Timestamp = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss.ffffff"),
        };
        return Container.CreateItemAsync(document, new PartitionKey(_options.Username), cancellationToken: cancellationToken);
    }

    public async Task UpdateAsync(string id, string text, CancellationToken cancellationToken)
    {
        try
        {
            var item = await Container.ReadItemAsync<ActivityDocument>(id, new PartitionKey(_options.Username), cancellationToken: cancellationToken);
            item.Resource.Activity = text;
            await Container.ReplaceItemAsync(item.Resource, id, new PartitionKey(_options.Username), cancellationToken: cancellationToken);
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            _logger.LogWarning("Activity {Id} was not found; nothing to update", id);
        }
    }

    public async Task DeleteAsync(string id, CancellationToken cancellationToken)
    {
        try
        {
            await Container.DeleteItemAsync<ActivityDocument>(id, new PartitionKey(_options.Username), cancellationToken: cancellationToken);
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            _logger.LogWarning("Activity {Id} was not found; nothing to delete", id);
        }
    }

    public async Task<bool> IsHealthyAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Container.ReadContainerAsync(cancellationToken: cancellationToken);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Cosmos DB health check failed");
            return false;
        }
    }

    private Container Container => _container ?? _client.GetContainer(_options.DatabaseName, _options.ContainerName);
}
