using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using VacationPlanner.Services;

namespace VacationPlanner.Pages;

/// <summary>Handles <c>POST /delete/{id}</c>; the activity is addressed by its store id, never by its position in the list.</summary>
public class DeleteModel(IActivityStore store, ILogger<DeleteModel> logger) : PageModel
{
    public IActionResult OnGet() => RedirectToPage("/Index");

    public async Task<IActionResult> OnPostAsync(string id, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(id))
        {
            try
            {
                if (await store.DeleteAsync(id, cancellationToken))
                {
                    logger.LogInformation("Activity deleted: {ActivityId}", id);
                    TempData["Flash"] = "Activity deleted successfully.";
                }
                else
                {
                    logger.LogWarning("Activity not found: {ActivityId}", id);
                    TempData["Flash"] = "Activity not found.";
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // The distro sends a log record that carries an exception to Application Insights as an exception
                logger.LogError(ex, "Failed to delete the activity {ActivityId}.", id);
                TempData["Flash"] = "Failed to delete the activity.";
            }
        }

        return RedirectToPage("/Index");
    }
}
