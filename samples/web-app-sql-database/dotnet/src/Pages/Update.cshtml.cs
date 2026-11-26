using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using VacationPlanner.Services;

namespace VacationPlanner.Pages;

/// <summary>Handles <c>GET /update/{id}</c>: bounces to the index page with the activity to edit in the query string.</summary>
public class UpdateModel(IActivityStore store, ILogger<UpdateModel> logger) : PageModel
{
    public async Task<IActionResult> OnGetAsync(string id, CancellationToken cancellationToken)
    {
        try
        {
            var activity = (await store.ListAsync(cancellationToken)).FirstOrDefault(a => a.Id == id);
            if (activity is null)
            {
                logger.LogWarning("Activity not found: {ActivityId}", id);
                return RedirectToPage("/Index");
            }

            logger.LogInformation("Activity read: {ActivityId} ({Activity})", activity.Id, activity.Text);
            return RedirectToPage("/Index", new { edit_id = activity.Id, edit_activity = activity.Text });
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // The distro sends a log record that carries an exception to Application Insights as an exception
            logger.LogError(ex, "Failed to read the activity {ActivityId}.", id);
            TempData["Flash"] = "Failed to load the activity.";
            return RedirectToPage("/Index");
        }
    }
}
