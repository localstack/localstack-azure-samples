namespace VacationPlanner.Services;

/// <summary>Connection settings read from the same environment variables the Python sample uses.</summary>
public sealed record PostgresOptions(string Host, int Port, string User, string Password, string Database, string Username)
{
    public static PostgresOptions FromEnvironment()
    {
        var username = Environment.GetEnvironmentVariable("LOGIN_NAME") ?? "paolo";
        if (string.IsNullOrWhiteSpace(username))
        {
            throw new InvalidOperationException("LOGIN_NAME cannot be empty");
        }

        return new PostgresOptions(
            Host: Require("PG_HOST"),
            Port: int.Parse(Environment.GetEnvironmentVariable("PG_PORT") ?? "5432"),
            User: Require("PG_USER"),
            Password: Require("PG_PASSWORD"),
            Database: Environment.GetEnvironmentVariable("PG_DATABASE") ?? "sampledb",
            Username: username);
    }

    private static string Require(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : throw new InvalidOperationException(
                $"Missing required environment variable: {name}. Set PG_HOST, PG_USER, PG_PASSWORD (and optionally PG_PORT, PG_DATABASE).");
}
