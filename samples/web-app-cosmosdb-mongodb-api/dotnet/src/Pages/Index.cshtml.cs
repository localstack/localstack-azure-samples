using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using VacationPlanner.Models;
using VacationPlanner.Services;

namespace VacationPlanner.Pages;

public class IndexModel(IActivityStore store, ILogger<IndexModel> logger) : PageModel
{
    /// <summary>Shown instead of an error page while the database is not reachable; the next request tries again.</summary>
    internal const string DatabaseUnavailable = "The database is not available. Try again in a minute.";

    public IReadOnlyList<Activity> Activities { get; private set; } = [];

    /// <summary>Flash messages set by the previous request (the equivalent of Flask's <c>flash()</c>).</summary>
    public IReadOnlyList<string> Flashes => TempData["Flash"] is string message ? [message] : [];

    [BindProperty(Name = "activity")]
    public string? Activity { get; set; }

    [BindProperty(Name = "row_id")]
    public string? RowId { get; set; }

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        try
        {
            Activities = await store.ListAsync(cancellationToken);
            // The values of a message template's placeholders reach Application Insights as custom dimensions
            logger.LogInformation("Activities read: {Count}", Activities.Count);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogError(ex, "Could not read the activities");
            TempData["Flash"] = DatabaseUnavailable;
        }
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        var text = Activity?.Trim();
        var id = RowId?.Trim();
        if (!string.IsNullOrEmpty(text))
        {
            try
            {
                if (!string.IsNullOrEmpty(id))
                {
                    if (await store.UpdateAsync(id, text, cancellationToken))
                    {
                        logger.LogInformation("Activity updated: {ActivityId} ({Activity})", id, text);
                        TempData["Flash"] = "Activity updated!";
                    }
                    else
                    {
                        logger.LogWarning("Activity not found: {ActivityId}", id);
                        TempData["Flash"] = "Activity not found.";
                    }
                }
                else
                {
                    var newId = await store.AddAsync(text, cancellationToken);
                    logger.LogInformation("Activity added: {ActivityId} ({Activity})", newId, text);
                    TempData["Flash"] = "Activity added!";
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogError(ex, "Could not save the activity");
                TempData["Flash"] = DatabaseUnavailable;
            }
        }

        return RedirectToPage();
    }
}
