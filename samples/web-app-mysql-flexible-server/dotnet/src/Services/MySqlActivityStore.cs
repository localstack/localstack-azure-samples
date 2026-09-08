using MySqlConnector;
using VacationPlanner.Models;

namespace VacationPlanner.Services;

/// <summary>
/// Activities in a MySQL <c>activities</c> table. Like the Python sample, the store is low-throughput
/// and opens a fresh connection per call instead of managing a pool explicitly.
/// </summary>
public sealed class MySqlActivityStore(MySqlOptions options, ILogger<MySqlActivityStore> logger) : IActivityStore
{
    // Single statement on purpose: MySQL has no CREATE INDEX IF NOT EXISTS, so the indexes are declared
    // inline and the whole DDL stays idempotent. `id` is VARCHAR(32) because the ids are MD5 hex digests.
    private const string SchemaDdl = """
        CREATE TABLE IF NOT EXISTS activities (
            id           VARCHAR(32)  NOT NULL,
            username     VARCHAR(255) NOT NULL,
            activity     TEXT         NOT NULL,
            created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            INDEX idx_activities_username (username),
            INDEX idx_activities_created_at (created_at DESC)
        )
        """;

    // Azure MySQL Flexible Server defaults to require_secure_transport=ON (the LocalStack emulator mirrors
    // this), so the connection must use TLS or the server rejects it. The server certificate is publicly
    // trusted on Azure but self-signed under LocalStack, so TLS is enabled without certificate verification
    // (MySqlSslMode.Required) and the same code path works against both targets. MYSQL_SSL=false disables it.
    private readonly string _connectionString = new MySqlConnectionStringBuilder
    {
        Server = options.Host,
        Port = (uint)options.Port,
        UserID = options.User,
        Password = options.Password,
        Database = options.Database,
        CharacterSet = "utf8mb4",
        ConnectionTimeout = 10,
        SslMode = options.SslEnabled ? MySqlSslMode.Required : MySqlSslMode.Disabled,
    }.ConnectionString;

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new MySqlCommand(SchemaDdl, connection);
        await command.ExecuteNonQueryAsync(cancellationToken);
        logger.LogInformation("MySQL schema initialized");
    }

    public async Task<IReadOnlyList<Activity>> ListAsync(CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new MySqlCommand(
            "SELECT id, activity FROM activities WHERE username = @username ORDER BY created_at DESC", connection);
        command.Parameters.AddWithValue("@username", options.Username);

        var activities = new List<Activity>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            activities.Add(new Activity(reader.GetString(0), reader.GetString(1)));
        }

        logger.LogInformation(
            "Retrieved {Count} activities for user: {Username}",
            activities.Count,
            options.Username
        );
        return activities;
    }

    public async Task AddAsync(string text, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new MySqlCommand(
            "INSERT IGNORE INTO activities (id, username, activity) VALUES (@id, @username, @activity)", connection);
        command.Parameters.AddWithValue("@id", ActivityId.Create(options.Username, text));
        command.Parameters.AddWithValue("@username", options.Username);
        command.Parameters.AddWithValue("@activity", text);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task UpdateAsync(string id, string text, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new MySqlCommand("UPDATE activities SET activity = @activity WHERE id = @id", connection);
        command.Parameters.AddWithValue("@activity", text);
        command.Parameters.AddWithValue("@id", id);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task DeleteAsync(string id, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new MySqlCommand("DELETE FROM activities WHERE id = @id", connection);
        command.Parameters.AddWithValue("@id", id);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<bool> IsHealthyAsync(CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = await OpenAsync(cancellationToken);
            await using var command = new MySqlCommand("SELECT 1", connection);
            await command.ExecuteScalarAsync(cancellationToken);
            return true;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "MySQL health check failed");
            return false;
        }
    }

    private async Task<MySqlConnection> OpenAsync(CancellationToken cancellationToken)
    {
        var connection = new MySqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        return connection;
    }
}
