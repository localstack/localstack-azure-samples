namespace VacationPlanner.Services;

/// <summary>
/// Connection settings read from the configuration loaded from Azure App Configuration (see
/// <see cref="AppConfigurationSettings"/>): PG_HOST, PG_PORT, PG_USER, PG_PASSWORD, PG_DATABASE. PG_USER and
/// PG_PASSWORD are Key Vault references in the store and arrive here already resolved. The application user
/// name still comes from the LOGIN_NAME environment variable, like in the Python sample.
/// </summary>
public sealed record PostgresOptions(string Host, int Port, string User, string Password, string Database, string Username)
{
    public static PostgresOptions FromConfiguration(IConfiguration configuration)
    {
        var username = Environment.GetEnvironmentVariable("LOGIN_NAME") ?? "paolo";
        if (string.IsNullOrWhiteSpace(username))
        {
            throw new InvalidOperationException("LOGIN_NAME cannot be empty");
        }

        return new PostgresOptions(
            Host: Require(configuration, "PG_HOST"),
            Port: int.Parse(configuration["PG_PORT"] ?? "5432"),
            User: Require(configuration, "PG_USER"),
            Password: Require(configuration, "PG_PASSWORD"),
            Database: configuration["PG_DATABASE"] ?? "sampledb",
            Username: username);
    }

    private static string Require(IConfiguration configuration, string name) =>
        configuration[name] is { Length: > 0 } value
            ? value
            : throw new InvalidOperationException(
                $"Missing required setting: {name}. The App Configuration store must hold PG_HOST, PG_USER, PG_PASSWORD (and optionally PG_PORT, PG_DATABASE).");
}
