using Azure.Identity;
using Azure.Security.KeyVault.Secrets;

namespace VacationPlanner.Services;

/// <summary>
/// Connection settings, resolved like the Python sample's <c>SqlHelper.from_env()</c>: the connection string
/// stored in Key Vault (<c>KEY_VAULT_NAME</c> + <c>SECRET_NAME</c>) wins; otherwise <c>SQL_*</c> variables
/// are used, with Microsoft Entra authentication when the <c>AZURE_*</c> service principal variables are set.
/// </summary>
public sealed record SqlOptions(string Server, string Database, string? User, string? Password, bool UseAzureCredential, string Username)
{
    public static async Task<SqlOptions> FromEnvironmentAsync(ILogger logger, CancellationToken cancellationToken)
    {
        var username = Environment.GetEnvironmentVariable("LOGIN_NAME") ?? "paolo";
        if (string.IsNullOrWhiteSpace(username))
        {
            throw new InvalidOperationException("Username cannot be None or empty");
        }

        var keyVaultName = Environment.GetEnvironmentVariable("KEY_VAULT_NAME");
        var secretName = Environment.GetEnvironmentVariable("SECRET_NAME");
        if (!string.IsNullOrEmpty(keyVaultName) && !string.IsNullOrEmpty(secretName))
        {
            var client = new SecretClient(new Uri($"https://{keyVaultName}.vault.azure.net"), new DefaultAzureCredential());
            logger.LogInformation("Retrieving secret [{Secret}] from Key Vault [{Vault}]...", secretName, keyVaultName);
            var secret = await client.GetSecretAsync(secretName, cancellationToken: cancellationToken);
            if (string.IsNullOrEmpty(secret.Value.Value))
            {
                throw new InvalidOperationException($"Secret [{secretName}] in Key Vault [{keyVaultName}] has no value");
            }

            logger.LogInformation("Secret [{Secret}] retrieved successfully from Key Vault [{Vault}]", secretName, keyVaultName);
            return FromConnectionString(secret.Value.Value, username);
        }

        var clientId = Environment.GetEnvironmentVariable("AZURE_CLIENT_ID");
        var clientSecret = Environment.GetEnvironmentVariable("AZURE_CLIENT_SECRET");
        var tenantId = Environment.GetEnvironmentVariable("AZURE_TENANT_ID");
        var server = Environment.GetEnvironmentVariable("SQL_SERVER");
        var database = Environment.GetEnvironmentVariable("SQL_DATABASE");
        var user = Environment.GetEnvironmentVariable("SQL_USERNAME");
        var password = Environment.GetEnvironmentVariable("SQL_PASSWORD");
        if (string.IsNullOrEmpty(server) || string.IsNullOrEmpty(database))
        {
            throw new InvalidOperationException(
                "Set KEY_VAULT_NAME and SECRET_NAME, or SQL_SERVER and SQL_DATABASE (with SQL_USERNAME/SQL_PASSWORD or the AZURE_* service principal variables).");
        }

        var useAzureCredential = !string.IsNullOrEmpty(clientId) && !string.IsNullOrEmpty(clientSecret) && !string.IsNullOrEmpty(tenantId);
        return new SqlOptions(server, database, user, password, useAzureCredential, username);
    }

    /// <summary>Parses an ADO.NET connection string such as the one Key Vault holds (<c>Server=tcp:host,1433;Database=…;User ID=…;Password=…</c>).</summary>
    public static SqlOptions FromConnectionString(string connectionString, string username)
    {
        var parts = connectionString.Split(';', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.Split('=', 2))
            .Where(kv => kv.Length == 2)
            .ToDictionary(kv => kv[0].Trim(), kv => kv[1].Trim(), StringComparer.OrdinalIgnoreCase);

        var server = (parts.GetValueOrDefault("Server") ?? "").Replace("tcp:", "").Replace(",1433", "");
        var database = parts.GetValueOrDefault("Database");
        var user = parts.GetValueOrDefault("User ID");
        var password = parts.GetValueOrDefault("Password");
        if (string.IsNullOrEmpty(server) || string.IsNullOrEmpty(database) || string.IsNullOrEmpty(user) || string.IsNullOrEmpty(password))
        {
            throw new InvalidOperationException(
                $"Could not parse all required parameters from connection string. Found - Server: {server.Length > 0}, Database: {database is not null}, Username: {user is not null}, Password: {password is not null}");
        }

        return new SqlOptions(server, database, user, password, UseAzureCredential: false, username);
    }
}
