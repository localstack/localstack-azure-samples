using VacationPlanner.Models;

namespace VacationPlanner.Services;

/// <summary>Persistence for the planner's activities. Every call goes to the backing store; nothing is cached in-process.</summary>
public interface IActivityStore
{
    /// <summary>Creates whatever the store needs (container, table, collection) before the first request.</summary>
    Task InitializeAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<Activity>> ListAsync(CancellationToken cancellationToken);

    Task AddAsync(string text, CancellationToken cancellationToken);

    Task UpdateAsync(string id, string text, CancellationToken cancellationToken);

    Task DeleteAsync(string id, CancellationToken cancellationToken);

    /// <summary>Cheap connectivity probe used by <c>GET /health</c>.</summary>
    Task<bool> IsHealthyAsync(CancellationToken cancellationToken);
}
