using Azure.Core;
using Azure.Identity;
using Microsoft.Data.SqlClient;
using VacationPlanner.Models;

namespace VacationPlanner.Services;

/// <summary>
/// Activities in the <c>dbo.Activities</c> table of an Azure SQL Database. The table is created by the
/// deployment scripts, so the store only reads and writes it.
/// </summary>
public sealed class SqlActivityStore(SqlOptions options, ILogger<SqlActivityStore> logger) : IActivityStore
{
    private readonly TokenCredential? _credential = options.UseAzureCredential ? new DefaultAzureCredential() : null;

    // Encrypt + TrustServerCertificate: the emulator's SQL Server container presents a self-signed
    // certificate, so the connection is encrypted without validating the certificate chain.
    private readonly string _connectionString = new SqlConnectionStringBuilder
    {
        DataSource = $"tcp:{options.Server},1433",
        InitialCatalog = options.Database,
        Encrypt = SqlConnectionEncryptOption.Mandatory,
        TrustServerCertificate = true,
        ConnectTimeout = 30,
        UserID = options.UseAzureCredential ? "" : options.User ?? throw new InvalidOperationException("Username and password required when not using Azure credential"),
        Password = options.UseAzureCredential ? "" : options.Password ?? throw new InvalidOperationException("Username and password required when not using Azure credential"),
    }.ConnectionString;

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        // The table is provisioned by the deployment; just prove the database is reachable.
        await using var connection = await OpenAsync(cancellationToken);
        logger.LogInformation("Connected to SQL Database [{Database}] on [{Server}]", options.Database, options.Server);
    }

    public async Task<IReadOnlyList<Activity>> ListAsync(CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new SqlCommand(
            "SELECT id, activity FROM dbo.Activities WHERE username = @username ORDER BY timestamp DESC", connection);
        command.Parameters.AddWithValue("@username", options.Username);

        var activities = new List<Activity>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            activities.Add(new Activity(reader.GetGuid(0).ToString(), reader.GetString(1)));
        }

        return activities;
    }

    public async Task AddAsync(string text, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new SqlCommand(
            """
            INSERT INTO dbo.Activities (username, activity, timestamp)
            OUTPUT INSERTED.id, INSERTED.username, INSERTED.activity, INSERTED.timestamp
            VALUES (@username, @activity, GETDATE())
            """, connection);
        command.Parameters.AddWithValue("@username", options.Username);
        command.Parameters.AddWithValue("@activity", text);
        var id = await command.ExecuteScalarAsync(cancellationToken);
        logger.LogInformation("Activity created: {Id}", id);
    }

    public async Task UpdateAsync(string id, string text, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new SqlCommand(
            "UPDATE dbo.Activities SET activity = @activity, timestamp = GETDATE() WHERE id = CAST(@id AS UNIQUEIDENTIFIER)", connection);
        command.Parameters.AddWithValue("@activity", text);
        command.Parameters.AddWithValue("@id", id);
        var rows = await command.ExecuteNonQueryAsync(cancellationToken);
        if (rows == 0)
        {
            logger.LogWarning("No activity found with ID: {Id}", id);
        }
    }

    public async Task DeleteAsync(string id, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new SqlCommand("DELETE FROM dbo.Activities WHERE id = CAST(@id AS UNIQUEIDENTIFIER)", connection);
        command.Parameters.AddWithValue("@id", id);
        var rows = await command.ExecuteNonQueryAsync(cancellationToken);
        if (rows == 0)
        {
            logger.LogWarning("No activity found with ID: {Id}", id);
        }
    }

    public async Task<bool> IsHealthyAsync(CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = await OpenAsync(cancellationToken);
            await using var command = new SqlCommand("SELECT 1", connection);
            await command.ExecuteScalarAsync(cancellationToken);
            return true;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "SQL Database health check failed");
            return false;
        }
    }

    private async Task<SqlConnection> OpenAsync(CancellationToken cancellationToken)
    {
        var connection = new SqlConnection(_connectionString);
        if (_credential is not null)
        {
            // Passwordless: present a Microsoft Entra access token for Azure SQL Database.
            var token = await _credential.GetTokenAsync(new TokenRequestContext(["https://database.windows.net/.default"]), cancellationToken);
            connection.AccessToken = token.Token;
        }

        await connection.OpenAsync(cancellationToken);
        return connection;
    }
}
