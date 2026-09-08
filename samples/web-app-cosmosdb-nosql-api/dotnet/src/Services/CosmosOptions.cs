namespace VacationPlanner.Services;

/// <summary>Settings read from the same environment variables the Python sample uses.</summary>
public sealed record CosmosOptions(string Endpoint, string Key, string DatabaseName, string ContainerName, string Username)
{
    public static CosmosOptions FromEnvironment()
    {
        var username = Environment.GetEnvironmentVariable("LOGIN_NAME") ?? "alex";
        if (string.IsNullOrWhiteSpace(username))
        {
            throw new InvalidOperationException("Username cannot be empty");
        }

        return new CosmosOptions(
            Endpoint: Require("AZURECOSMOSDB_ENDPOINT"),
            Key: Require("AZURECOSMOSDB_PRIMARY_KEY"),
            DatabaseName: Require("AZURECOSMOSDB_DATABASENAME"),
            ContainerName: Require("AZURECOSMOSDB_CONTAINERNAME"),
            Username: username);
    }

    private static string Require(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : throw new InvalidOperationException($"Missing required environment variable: {name}");
}
