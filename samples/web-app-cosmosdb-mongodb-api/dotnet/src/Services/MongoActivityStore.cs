using MongoDB.Bson;
using MongoDB.Bson.IO;
using MongoDB.Driver;
using VacationPlanner.Models;

namespace VacationPlanner.Services;

/// <summary>Activities as documents <c>{_id, username, activity, timestamp}</c> in an Azure Cosmos DB for MongoDB collection.</summary>
public sealed class MongoActivityStore : IActivityStore
{
    private readonly IMongoDatabase _database;
    private readonly IMongoCollection<BsonDocument> _collection;
    private readonly MongoOptions _options;
    private readonly ILogger<MongoActivityStore> _logger;

    /// <summary>Documents are logged indented, like the Python sample's <c>json.dumps(indent=3)</c> output.</summary>
    private static readonly JsonWriterSettings Indented = new() { Indent = true };

    public MongoActivityStore(MongoOptions options, ILogger<MongoActivityStore> logger)
    {
        _options = options;
        _logger = logger;
        var client = new MongoClient(options.ConnectionString);
        _database = client.GetDatabase(options.DatabaseName);
        _collection = _database.GetCollection<BsonDocument>(options.CollectionName);
    }

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        var existing = await (await _database.ListCollectionNamesAsync(cancellationToken: cancellationToken)).ToListAsync(cancellationToken);
        if (existing.Contains(_options.CollectionName))
        {
            _logger.LogInformation("Collection '{Collection}' already exists in database '{Database}'", _options.CollectionName, _options.DatabaseName);
            return;
        }

        await _database.CreateCollectionAsync(_options.CollectionName, cancellationToken: cancellationToken);
        var keys = Builders<BsonDocument>.IndexKeys;
        await _collection.Indexes.CreateManyAsync(
        [
            new CreateIndexModel<BsonDocument>(keys.Ascending("username")),
            new CreateIndexModel<BsonDocument>(keys.Ascending("activity")),
            new CreateIndexModel<BsonDocument>(keys.Ascending("timestamp")),
        ], cancellationToken);
        _logger.LogInformation("Created collection '{Collection}' in database '{Database}'", _options.CollectionName, _options.DatabaseName);
    }

    public async Task<IReadOnlyList<Activity>> ListAsync(CancellationToken cancellationToken)
    {
        var filter = Builders<BsonDocument>.Filter.Eq("username", _options.Username);
        var documents = await _collection.Find(filter).ToListAsync(cancellationToken);
        _logger.LogInformation(
            "Retrieved {Count} document(s) from collection '{Collection}': {Documents}",
            documents.Count,
            _options.CollectionName,
            documents.ToJson(Indented)
        );
        return documents.Select(d => new Activity(d["_id"].AsString, d["activity"].AsString)).ToList();
    }

    public async Task AddAsync(string text, CancellationToken cancellationToken)
    {
        var document = new BsonDocument
        {
            ["_id"] = ActivityId.Create(_options.Username, text),
            ["username"] = _options.Username,
            ["activity"] = text,
            ["timestamp"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss.ffffff"),
        };
        await _collection.InsertOneAsync(document, cancellationToken: cancellationToken);
        _logger.LogInformation(
            "Inserted document into collection '{Collection}': {Document}",
            _options.CollectionName,
            document.ToJson(Indented)
        );
    }

    public async Task UpdateAsync(string id, string text, CancellationToken cancellationToken)
    {
        var result = await _collection.UpdateOneAsync(
            Builders<BsonDocument>.Filter.Eq("_id", id),
            Builders<BsonDocument>.Update.Set("activity", text),
            cancellationToken: cancellationToken
        );
        _logger.LogInformation(
            "Updated {Count} document(s) with id {Id} in collection '{Collection}'",
            result.ModifiedCount,
            id,
            _options.CollectionName
        );
    }

    public async Task DeleteAsync(string id, CancellationToken cancellationToken)
    {
        var result = await _collection.DeleteOneAsync(
            Builders<BsonDocument>.Filter.Eq("_id", id),
            cancellationToken
        );
        _logger.LogInformation(
            "Deleted {Count} document(s) with id {Id} from collection '{Collection}'",
            result.DeletedCount,
            id,
            _options.CollectionName
        );
    }

    public async Task<bool> IsHealthyAsync(CancellationToken cancellationToken)
    {
        try
        {
            await _database.RunCommandAsync<BsonDocument>(new BsonDocument("ping", 1), cancellationToken: cancellationToken);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "MongoDB health check failed");
            return false;
        }
    }
}
