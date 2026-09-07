using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using VacationPlanner.Services;

namespace VacationPlanner.Pages;

/// <summary>Handles <c>GET /update/{id}</c>: bounces to the index page with the activity to edit in the query string.</summary>
public class UpdateModel(IActivityStore store) : PageModel
{
    public async Task<IActionResult> OnGetAsync(string id, CancellationToken cancellationToken)
    {
        var activity = (await store.ListAsync(cancellationToken)).FirstOrDefault(a => a.Id == id);
        return activity is null
            ? RedirectToPage("/Index")
            : RedirectToPage("/Index", new { edit_id = activity.Id, edit_activity = activity.Text });
    }
}
