using Azure.Core;
using Azure.Data.AppConfiguration;
using Azure.Identity;
using Microsoft.Extensions.Configuration.AzureAppConfiguration;

namespace VacationPlanner.Services;

/// <summary>
/// Loads the PostgreSQL connection settings from Azure App Configuration with the in-process provider.
/// </summary>
/// <remarks>
/// The settings do not reach the app as environment variables. <c>PG_HOST</c>, <c>PG_PORT</c> and
/// <c>PG_DATABASE</c> are plain key-values in the store; <c>PG_USER</c> and <c>PG_PASSWORD</c> are Key Vault
/// references to two secrets. One <see cref="DefaultAzureCredential"/> authenticates to the store and, through
/// <c>ConfigureKeyVault</c>, to Key Vault: on App Service it resolves to the user-assigned managed identity
/// selected by <c>AZURE_CLIENT_ID</c>, on a developer machine to the signed-in Azure CLI user. The provider
/// resolves the Key Vault references itself, so the loaded configuration already holds the secret values and
/// the app has a single configuration source. The store endpoint comes from the <c>Endpoints:AppConfiguration</c>
/// setting, that is the <c>Endpoints__AppConfiguration</c> app setting.
/// </remarks>
public static class AppConfigurationSettings
{
    public const string EndpointSetting = "Endpoints:AppConfiguration";
    public const string KeyFilter = "PG_*";
    private const string UnresolvedReferencePrefix = "@Microsoft.";
    private const int LoadAttempts = 3;
    private static readonly TimeSpan StartupTimeout = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan RetryDelay = TimeSpan.FromSeconds(10);

    /// <summary>What was loaded, for the startup log line. Never carries secret values.</summary>
    public sealed record Summary(string Endpoint, IReadOnlyList<string> Keys, IReadOnlyList<string> KeyVaultReferences);

    /// <summary>
    /// Loads the <c>PG_*</c> settings from the store into <paramref name="configuration"/>, retrying for a few
    /// minutes so a role assignment that has not propagated yet, or a store that is still starting, produces log
    /// lines rather than a crash loop. Throws when the endpoint setting is missing or the load keeps failing.
    /// </summary>
    public static Summary Load(ConfigurationManager configuration, ILogger logger)
    {
        var endpoint = configuration[EndpointSetting]?.Trim();
        if (string.IsNullOrEmpty(endpoint))
        {
            throw new InvalidOperationException(
                $"The setting {EndpointSetting} was not found. Set the Endpoints__AppConfiguration app setting to the App Configuration store endpoint (az appconfig show --query endpoint).");
        }

        if (endpoint.StartsWith(UnresolvedReferencePrefix, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"The setting {EndpointSetting} holds an unresolved App Service reference ({endpoint[..Math.Min(48, endpoint.Length)]}...). The platform did not resolve it; set the plain store endpoint instead.");
        }

        var credential = new DefaultAzureCredential();
        var loaded = LoadWithRetries(endpoint, credential, logger);

        // Chain the loaded settings into the application configuration, so PG_HOST and the others are read
        // like any other configuration value.
        configuration.AddConfiguration(loaded);

        var settings = loaded.AsEnumerable()
            .Where(pair => pair.Key.StartsWith("PG_", StringComparison.Ordinal) && pair.Value is not null)
            .ToDictionary(pair => pair.Key, pair => pair.Value!);
        RejectUnresolvedReferences(settings);

        var references = ListKeyVaultReferences(endpoint, credential, logger);
        var keys = settings.Keys.Order(StringComparer.Ordinal).ToList();
        logger.LogInformation(
            "Loaded {Count} settings from App Configuration {Endpoint} ({Keys}); {ReferenceCount} Key Vault references resolved ({References})",
            keys.Count,
            endpoint,
            string.Join(", ", keys),
            references.Count,
            references.Count == 0 ? "none" : string.Join(", ", references));

        return new Summary(endpoint, keys, references);
    }

    private static IConfigurationRoot LoadWithRetries(string endpoint, TokenCredential credential, ILogger logger)
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                // Building the root performs the load; the provider itself retries for StartupTimeout.
                return new ConfigurationBuilder()
                    .AddAzureAppConfiguration(options =>
                    {
                        options.Connect(new Uri(endpoint), credential)
                            .Select(KeyFilter)
                            // Without a Key Vault credential the load fails with KeyVaultReferenceException
                            // ("No key vault credential or secret resolver callback configured") as soon as
                            // the store holds a Key Vault reference.
                            .ConfigureKeyVault(keyVault => keyVault.SetCredential(credential))
                            .ConfigureStartupOptions(startup => startup.Timeout = StartupTimeout);
                    })
                    .Build();
            }
            catch (Exception ex) when (attempt < LoadAttempts)
            {
                logger.LogWarning(
                    ex,
                    "App Configuration load failed (attempt {Attempt}/{Attempts}) against {Endpoint}: {ExceptionType}: {Message}. Likely causes: the role assignment of the identity has not propagated yet, the endpoint is unreachable, or the Key Vault credential cannot read the referenced secrets.",
                    attempt,
                    LoadAttempts,
                    endpoint,
                    ex.GetType().Name,
                    ex.Message);
                Thread.Sleep(RetryDelay);
            }
            catch (Exception ex)
            {
                logger.LogError(
                    "App Configuration load failed (attempt {Attempt}/{Attempts}) against {Endpoint}: {ExceptionType}: {Message}",
                    attempt,
                    LoadAttempts,
                    endpoint,
                    ex.GetType().Name,
                    ex.Message);
                throw new InvalidOperationException(
                    $"Could not load the configuration from App Configuration {endpoint} after {LoadAttempts} attempts: {ex.GetType().Name}: {ex.Message}",
                    ex);
            }
        }
    }

    private static void RejectUnresolvedReferences(IReadOnlyDictionary<string, string> settings)
    {
        var unresolved = settings
            .Where(pair => pair.Value.StartsWith(UnresolvedReferencePrefix, StringComparison.Ordinal))
            .Select(pair => pair.Key)
            .Order(StringComparer.Ordinal)
            .ToList();
        if (unresolved.Count > 0)
        {
            throw new InvalidOperationException(
                $"The settings {string.Join(", ", unresolved)} hold unresolved App Service references; they must be plain values or App Configuration Key Vault references.");
        }
    }

    /// <summary>The <c>PG_*</c> keys stored as Key Vault references, for the startup log line (never their values).</summary>
    private static IReadOnlyList<string> ListKeyVaultReferences(string endpoint, TokenCredential credential, ILogger logger)
    {
        try
        {
            var client = new ConfigurationClient(new Uri(endpoint), credential);
            return client.GetConfigurationSettings(new SettingSelector { KeyFilter = KeyFilter })
                .OfType<SecretReferenceConfigurationSetting>()
                .Select(setting => setting.Key)
                .Order(StringComparer.Ordinal)
                .ToList();
        }
        catch (Exception ex)
        {
            logger.LogWarning("Could not list the Key Vault references of the store: {ExceptionType}: {Message}", ex.GetType().Name, ex.Message);
            return [];
        }
    }
}
