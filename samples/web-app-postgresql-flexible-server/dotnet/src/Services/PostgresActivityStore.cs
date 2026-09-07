using Npgsql;
using VacationPlanner.Models;

namespace VacationPlanner.Services;

/// <summary>
/// Activities in a PostgreSQL <c>activities</c> table. Like the Python sample, the store is low-throughput
/// and opens a fresh connection per call instead of managing a pool explicitly.
/// </summary>
public sealed class PostgresActivityStore(PostgresOptions options, ILogger<PostgresActivityStore> logger) : IActivityStore
{
    private const string SchemaDdl = """
        CREATE TABLE IF NOT EXISTS activities (
            id           TEXT PRIMARY KEY,
            username     TEXT NOT NULL,
            activity     TEXT NOT NULL,
            created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_activities_username ON activities(username);
        CREATE INDEX IF NOT EXISTS idx_activities_created_at ON activities(created_at DESC);
        """;

    // Negotiate TLS when the server offers it, without certificate verification (libpq's "prefer", which
    // the Python sample relies on): the flexible server's certificate is publicly trusted on Azure but
    // self-signed under LocalStack. Npgsql only validates certificates with SslMode VerifyCA/VerifyFull.
    private readonly string _connectionString = new NpgsqlConnectionStringBuilder
    {
        Host = options.Host,
        Port = options.Port,
        Username = options.User,
        Password = options.Password,
        Database = options.Database,
        Timeout = 10,
        SslMode = SslMode.Prefer,
    }.ConnectionString;

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(SchemaDdl, connection);
        await command.ExecuteNonQueryAsync(cancellationToken);
        logger.LogInformation("PostgreSQL schema initialized");
    }

    public async Task<IReadOnlyList<Activity>> ListAsync(CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT id, activity FROM activities WHERE username = @username ORDER BY created_at DESC", connection);
        command.Parameters.AddWithValue("username", options.Username);

        var activities = new List<Activity>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            activities.Add(new Activity(reader.GetString(0), reader.GetString(1)));
        }

        return activities;
    }

    public async Task AddAsync(string text, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "INSERT INTO activities (id, username, activity) VALUES (@id, @username, @activity) ON CONFLICT (id) DO NOTHING",
            connection);
        command.Parameters.AddWithValue("id", ActivityId.Create(options.Username, text));
        command.Parameters.AddWithValue("username", options.Username);
        command.Parameters.AddWithValue("activity", text);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task UpdateAsync(string id, string text, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand("UPDATE activities SET activity = @activity WHERE id = @id", connection);
        command.Parameters.AddWithValue("activity", text);
        command.Parameters.AddWithValue("id", id);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task DeleteAsync(string id, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand("DELETE FROM activities WHERE id = @id", connection);
        command.Parameters.AddWithValue("id", id);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<bool> IsHealthyAsync(CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = await OpenAsync(cancellationToken);
            await using var command = new NpgsqlCommand("SELECT 1", connection);
            await command.ExecuteScalarAsync(cancellationToken);
            return true;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "PostgreSQL health check failed");
            return false;
        }
    }

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken cancellationToken)
    {
        var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        return connection;
    }
}
