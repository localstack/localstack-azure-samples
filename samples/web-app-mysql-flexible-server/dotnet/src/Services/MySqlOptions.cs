namespace VacationPlanner.Services;

/// <summary>Connection settings read from the same environment variables the Python sample uses.</summary>
public sealed record MySqlOptions(string Host, int Port, string User, string Password, string Database, bool SslEnabled, string Username)
{
    public static MySqlOptions FromEnvironment()
    {
        var username = Environment.GetEnvironmentVariable("LOGIN_NAME") ?? "paolo";
        if (string.IsNullOrWhiteSpace(username))
        {
            throw new InvalidOperationException("LOGIN_NAME cannot be empty");
        }

        var ssl = (Environment.GetEnvironmentVariable("MYSQL_SSL") ?? "true").ToLowerInvariant();
        return new MySqlOptions(
            Host: Require("MYSQL_HOST"),
            Port: int.Parse(Environment.GetEnvironmentVariable("MYSQL_PORT") ?? "3306"),
            User: Require("MYSQL_USER"),
            Password: Require("MYSQL_PASSWORD"),
            Database: Environment.GetEnvironmentVariable("MYSQL_DATABASE") ?? "sampledb",
            SslEnabled: ssl is "true" or "1" or "yes",
            Username: username);
    }

    private static string Require(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : throw new InvalidOperationException(
                $"Missing required environment variable: {name}. Set MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD (and optionally MYSQL_PORT, MYSQL_DATABASE, MYSQL_SSL).");
}
