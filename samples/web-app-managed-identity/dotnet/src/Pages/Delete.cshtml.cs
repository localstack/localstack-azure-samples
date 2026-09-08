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
            await store.DeleteAsync(id, cancellationToken);
            logger.LogInformation("Activity deleted: {Id}", id);
            TempData["Flash"] = "Activity deleted successfully.";
        }

        return RedirectToPage("/Index");
    }
}
