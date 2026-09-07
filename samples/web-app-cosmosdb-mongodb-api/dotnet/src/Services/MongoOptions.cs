namespace VacationPlanner.Services;

/// <summary>Settings read from the same environment variables the Python sample uses.</summary>
public sealed record MongoOptions(string ConnectionString, string DatabaseName, string CollectionName, string Username)
{
    public static MongoOptions FromEnvironment()
    {
        var connectionString = Environment.GetEnvironmentVariable("COSMOSDB_CONNECTION_STRING")
            ?? Environment.GetEnvironmentVariable("MONGODB_CONNECTION_STRING");
        if (string.IsNullOrEmpty(connectionString))
        {
            throw new InvalidOperationException("Missing required environment variable: COSMOSDB_CONNECTION_STRING or MONGODB_CONNECTION_STRING");
        }

        var username = Environment.GetEnvironmentVariable("LOGIN_NAME") ?? "paolo";
        if (string.IsNullOrWhiteSpace(username))
        {
            throw new InvalidOperationException("Username cannot be None or empty");
        }

        return new MongoOptions(
            ConnectionString: connectionString,
            DatabaseName: Require("COSMOSDB_DATABASE_NAME"),
            CollectionName: Require("COSMOSDB_COLLECTION_NAME"),
            Username: username);
    }

    private static string Require(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : throw new InvalidOperationException($"Missing required environment variable: {name}");
}
