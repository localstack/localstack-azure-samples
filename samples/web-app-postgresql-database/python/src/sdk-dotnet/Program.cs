// C# Azure SDK Management Demo — PostgreSQL Flexible Server on LocalStack.
//
// Demonstrates Azure.ResourceManager.PostgreSql operations:
//   - List servers in a resource group
//   - Get server properties
//   - List configurations
//   - List databases
//   - List firewall rules
//   - Check name availability
//   - Connect with Npgsql and run queries
//
// Results are posted to the notes-app UI for live display.

using System.Net.Http.Json;
using System.Net.Security;
using System.Text;
using System.Text.Json;
using Azure.Core;
using Azure.Core.Pipeline;
using Azure.Identity;
using Azure.ResourceManager;
using Azure.ResourceManager.PostgreSql.FlexibleServers;
using Azure.ResourceManager.Resources;
using Npgsql;

// ---------------------------------------------------------------------------
// Configuration (from docker-compose environment)
// ---------------------------------------------------------------------------

var subscriptionId = Env("AZURE_SUBSCRIPTION_ID", "00000000-0000-0000-0000-000000000000");
var tenantId = Env("AZURE_TENANT_ID", "00000000-0000-0000-0000-000000000000");
var clientId = Env("AZURE_CLIENT_ID", "00000000-0000-0000-0000-000000000000");
var clientSecret = Env("AZURE_CLIENT_SECRET", "fake-secret");
var resourceGroup = Env("RESOURCE_GROUP", "");
var serverName = Env("SERVER_NAME", "");
var localstackHost = Env("LOCALSTACK_HOST", "localhost.localstack.cloud:4566");
var notesAppUrl = Env("NOTES_APP_URL", "http://notes-app:5001");

var pgHost = Env("PG_HOST", "");
var pgPort = int.Parse(Env("PG_PORT", "5432"));
var pgUser = Env("PG_USER", "pgadmin");
var pgPassword = Env("PG_PASSWORD", "P@ssw0rd12345!");
var pgDatabase = Env("PG_DATABASE", "sampledb");

string Env(string key, string fallback) =>
    Environment.GetEnvironmentVariable(key) ?? fallback;

// ---------------------------------------------------------------------------
// Logging — capture output for the notes-app UI
// ---------------------------------------------------------------------------

var logBuf = new StringBuilder();
int step = 0, failures = 0;
var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };

void Log(string msg = "")
{
    Console.WriteLine(msg);
    logBuf.AppendLine(msg);
}

void Report(string label, bool success, string detail = "")
{
    step++;
    if (!success) failures++;
    var status = success ? "PASS" : "FAIL";
    var msg = $"[{step,2}] {status}: {label}";
    if (!string.IsNullOrEmpty(detail)) msg += $" -- {detail}";
    Log(msg);
}

async Task FlushToNotesApp(bool final = false)
{
    try
    {
        var payload = new { status = final ? "done" : "running", log = logBuf.ToString() };
        await http.PostAsJsonAsync($"{notesAppUrl}/api/sdk-status/dotnet", payload);
    }
    catch { /* notes-app may not be ready yet */ }
}

async Task WaitForNotesApp()
{
    for (int i = 0; i < 60; i++)
    {
        try
        {
            var r = await http.GetAsync($"{notesAppUrl}/api/sdk-status/dotnet");
            if (r.IsSuccessStatusCode) return;
        }
        catch { /* not ready yet */ }
        await Task.Delay(3000);
    }
    Log("WARNING: Notes app not reachable, continuing without UI reporting");
}

// ---------------------------------------------------------------------------
// SDK client setup
// ---------------------------------------------------------------------------

ArmClient CreateArmClient()
{
    var baseUri = new Uri($"https://{localstackHost}");

    // Skip SSL validation for LocalStack's self-signed certificate
    var httpHandler = new HttpClientHandler
    {
        ServerCertificateCustomValidationCallback = (_, _, _, _) => true
    };

    var credential = new ClientSecretCredential(tenantId, clientId, clientSecret,
        new ClientSecretCredentialOptions
        {
            AuthorityHost = baseUri,
            DisableInstanceDiscovery = true,
            Transport = new HttpClientTransport(httpHandler),
        });

    var options = new ArmClientOptions
    {
        Environment = new ArmEnvironment(baseUri, baseUri.AbsoluteUri),
        Transport = new HttpClientTransport(httpHandler),
    };

    return new ArmClient(credential, subscriptionId, options);
}

// ---------------------------------------------------------------------------
// Main execution — poll for trigger, run demo on demand
// ---------------------------------------------------------------------------

await WaitForNotesApp();
try { await http.PostAsJsonAsync($"{notesAppUrl}/api/sdk-status/dotnet", new { status = "idle", log = "" }); }
catch { /* not ready */ }

Console.WriteLine("C# SDK demo container ready — waiting for trigger...");

int lastGeneration = 0;
while (true)
{
    try
    {
        var triggerResp = await http.GetAsync($"{notesAppUrl}/api/sdk-trigger/dotnet");
        if (triggerResp.IsSuccessStatusCode)
        {
            var json = await triggerResp.Content.ReadFromJsonAsync<JsonElement>();
            int gen = json.GetProperty("generation").GetInt32();
            if (gen > lastGeneration)
            {
                lastGeneration = gen;
                Console.WriteLine($"Trigger received (generation={lastGeneration}), running demo...");
                await RunDemo();
                Console.WriteLine("Demo complete — waiting for next trigger...");
            }
        }
    }
    catch { /* transient error, retry */ }
    await Task.Delay(2000);
}

async Task RunDemo()
{
    logBuf.Clear();
    step = 0;
    failures = 0;

    Log(new string('=', 60));
    Log("C# Azure SDK — PostgreSQL Flexible Server Demo");
    Log(new string('=', 60));
    Log();
    await FlushToNotesApp();

    ArmClient armClient;
    try
    {
        armClient = CreateArmClient();
        Report("Create ARM client", true, "ArmClient ready");
    }
    catch (Exception ex)
    {
        Report("Create ARM client", false, ex.Message);
        await FlushToNotesApp(final: true);
        return;
    }
    await FlushToNotesApp();

    ResourceGroupResource rg;
    try
    {
        var sub = armClient.GetSubscriptionResource(new ResourceIdentifier($"/subscriptions/{subscriptionId}"));
        var rgResponse = await sub.GetResourceGroups().GetAsync(resourceGroup);
        rg = rgResponse.Value;
        Report("Get resource group", true, $"name={rg.Data.Name}");
    }
    catch (Exception ex)
    {
        Report("Get resource group", false, ex.Message);
        await FlushToNotesApp(final: true);
        return;
    }
    await FlushToNotesApp();

    // List Servers
    Log();
    Log(new string('=', 60));
    Log("List Servers in Resource Group");
    Log(new string('=', 60));

    var servers = new List<PostgreSqlFlexibleServerResource>();
    await foreach (var s in rg.GetPostgreSqlFlexibleServers().GetAllAsync())
        servers.Add(s);

    Report("List servers", servers.Count >= 1, $"found {servers.Count} server(s)");
    foreach (var s in servers)
        Log($"  - {s.Data.Name}  version={s.Data.Version}  state={s.Data.State}  fqdn={s.Data.FullyQualifiedDomainName}");

    await FlushToNotesApp();

    // Get Server Properties
    Log();
    Log(new string('=', 60));
    Log("Get Server Properties");
    Log(new string('=', 60));

    PostgreSqlFlexibleServerResource server;
    try
    {
        var resp = await rg.GetPostgreSqlFlexibleServers().GetAsync(serverName);
        server = resp.Value;
        Report("Get server", server.Data.Name == serverName, $"name={server.Data.Name}");
        Report("Server version", server.Data.Version?.ToString() == "16", $"version={server.Data.Version}");
        Report("Server SKU", server.Data.Sku != null, $"sku={server.Data.Sku?.Name ?? "N/A"}");
    }
    catch (Exception ex)
    {
        Report("Get server", false, ex.Message);
        await FlushToNotesApp(final: true);
        return;
    }
    await FlushToNotesApp();

    // List Configurations
    Log();
    Log(new string('=', 60));
    Log("List Configurations");
    Log(new string('=', 60));

    var configs = new List<PostgreSqlFlexibleServerConfigurationResource>();
    await foreach (var c in server.GetPostgreSqlFlexibleServerConfigurations().GetAllAsync())
        configs.Add(c);

    Report("List configurations", configs.Count > 0, $"found {configs.Count} parameter(s)");

    var interesting = new HashSet<string> { "max_connections", "shared_buffers", "work_mem", "log_min_duration_statement" };
    foreach (var c in configs.Where(c => interesting.Contains(c.Data.Name)))
        Log($"  - {c.Data.Name} = {c.Data.Value}  (default: {c.Data.DefaultValue})");

    await FlushToNotesApp();

    // List Databases
    Log();
    Log(new string('=', 60));
    Log("List Databases");
    Log(new string('=', 60));

    var databases = new List<PostgreSqlFlexibleServerDatabaseResource>();
    await foreach (var d in server.GetPostgreSqlFlexibleServerDatabases().GetAllAsync())
        databases.Add(d);

    var dbNames = databases.Select(d => d.Data.Name).ToList();
    Report("List databases", databases.Count >= 1, $"found: {string.Join(", ", dbNames)}");
    Report("Primary DB exists", dbNames.Contains("sampledb"), "sampledb");
    Report("Secondary DB exists", dbNames.Contains("analyticsdb"), "analyticsdb");
    await FlushToNotesApp();

    // List Firewall Rules
    Log();
    Log(new string('=', 60));
    Log("List Firewall Rules");
    Log(new string('=', 60));

    var rules = new List<PostgreSqlFlexibleServerFirewallRuleResource>();
    await foreach (var r in server.GetPostgreSqlFlexibleServerFirewallRules().GetAllAsync())
        rules.Add(r);

    var ruleNames = rules.Select(r => r.Data.Name).ToList();
    Report("List firewall rules", rules.Count >= 1, $"found: {string.Join(", ", ruleNames)}");

    var expected = new[] { "allow-all", "corporate-network", "vpn-access" };
    var allPresent = expected.All(e => ruleNames.Contains(e));
    Report("Expected rules present", allPresent, $"expected={string.Join(",", expected)}");
    await FlushToNotesApp();

    // Direct PostgreSQL Connection (Npgsql)
    Log();
    Log(new string('=', 60));
    Log("Direct PostgreSQL Connection (Npgsql)");
    Log(new string('=', 60));

    if (!string.IsNullOrEmpty(pgHost))
    {
        try
        {
            var connStr = $"Host={pgHost};Port={pgPort};Username={pgUser};Password={pgPassword};Database={pgDatabase};Timeout=10";
            await using var conn = new NpgsqlConnection(connStr);
            await conn.OpenAsync();
            Report("Connect to PostgreSQL", true, $"{pgHost}:{pgPort}/{pgDatabase}");

            await using var versionCmd = new NpgsqlCommand("SELECT version()", conn);
            var version = (await versionCmd.ExecuteScalarAsync())?.ToString() ?? "";
            Report("Get PG version", version.Contains("PostgreSQL"), version.Length > 60 ? version[..60] : version);

            await using var tablesCmd = new NpgsqlCommand(
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'", conn);
            var count = Convert.ToInt32(await tablesCmd.ExecuteScalarAsync());
            Report("Query information_schema", true, $"{count} public table(s)");
        }
        catch (Exception ex)
        {
            Report("Connect to PostgreSQL", false, ex.Message);
        }
    }
    else
    {
        Log("  PG_HOST not set, skipping direct connection test");
    }
    await FlushToNotesApp();

    // Summary
    Log();
    Log(new string('=', 60));
    var passed = step - failures;
    Log($"TOTAL: {passed}/{step} tests passed");
    Log(new string('=', 60));
    Log(failures == 0 ? "ALL TESTS PASSED" : $"{failures} TEST(S) FAILED");

    await FlushToNotesApp(final: true);
}
