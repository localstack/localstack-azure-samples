namespace VacationPlanner.Services;

/// <summary>Settings read from the same environment variables the Python sample uses.</summary>
public sealed record BlobStorageOptions(
    string? AccountUrl,
    string? ConnectionString,
    string ContainerName,
    string? ClientId,
    string? ClientSecret,
    string? TenantId)
{
    public static BlobStorageOptions FromEnvironment() => new(
        AccountUrl: Environment.GetEnvironmentVariable("AZURE_STORAGE_ACCOUNT_URL"),
        ConnectionString: Environment.GetEnvironmentVariable("AZURE_STORAGE_ACCOUNT_CONNECTION_STRING"),
        ContainerName: Environment.GetEnvironmentVariable("CONTAINER_NAME") ?? "activities",
        ClientId: Environment.GetEnvironmentVariable("AZURE_CLIENT_ID"),
        ClientSecret: Environment.GetEnvironmentVariable("AZURE_CLIENT_SECRET"),
        TenantId: Environment.GetEnvironmentVariable("AZURE_TENANT_ID"));
}
