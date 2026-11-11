namespace VacationPlanner.Services;

/// <summary>
/// Runs <see cref="IActivityStore.InitializeAsync"/> in the background and retries it until it succeeds, so the app
/// starts even when the database is not reachable yet, for example while Azure Cosmos DB for MongoDB upgrades the
/// server version of the account. Until then, the pages show an error and <c>/health</c> answers 503.
/// </summary>
public sealed class StoreInitializer(
    IActivityStore store,
    ILogger<StoreInitializer> logger,
    TimeSpan delay = default) : BackgroundService
{
    private readonly TimeSpan _delay = delay > TimeSpan.Zero ? delay : TimeSpan.FromSeconds(15);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            for (var attempt = 1; !stoppingToken.IsCancellationRequested; attempt++)
            {
                try
                {
                    await store.InitializeAsync(stoppingToken);
                    logger.LogInformation("Activity store initialized after {Attempts} attempt(s).", attempt);
                    return;
                }
                catch (Exception ex) when (!stoppingToken.IsCancellationRequested)
                {
                    logger.LogWarning(ex, "Activity store not ready (attempt {Attempt}); retrying in {Delay}s.",
                        attempt, _delay.TotalSeconds);
                    await Task.Delay(_delay, stoppingToken);
                }
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            // The app is stopping before the store was initialized: nothing left to do.
        }
    }
}
