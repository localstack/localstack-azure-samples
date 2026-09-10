namespace VacationPlanner.Services;

/// <summary>
/// Runs <see cref="IActivityStore.InitializeAsync"/> at startup with a bounded retry, so the app fails fast
/// (and the container exits) when the backing service never becomes reachable.
/// </summary>
public sealed class StoreInitializer(
    IActivityStore store,
    ILogger<StoreInitializer> logger,
    int attempts = 1,
    TimeSpan delay = default) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                await store.InitializeAsync(cancellationToken);
                logger.LogInformation("Activity store initialized after {Attempts} attempt(s).", attempt);
                return;
            }
            catch (Exception ex) when (attempt < attempts && !cancellationToken.IsCancellationRequested)
            {
                logger.LogWarning(ex, "Activity store not ready (attempt {Attempt}/{Attempts}); retrying in {Delay}s.",
                    attempt, attempts, delay.TotalSeconds);
                await Task.Delay(delay, cancellationToken);
            }
        }
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
