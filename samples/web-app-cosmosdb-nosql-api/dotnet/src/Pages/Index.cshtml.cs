using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using VacationPlanner.Models;
using VacationPlanner.Services;

namespace VacationPlanner.Pages;

public class IndexModel(IActivityStore store, ILogger<IndexModel> logger) : PageModel
{
    public IReadOnlyList<Activity> Activities { get; private set; } = [];

    /// <summary>Flash messages set by the previous request (the equivalent of Flask's <c>flash()</c>).</summary>
    public IReadOnlyList<string> Flashes => TempData["Flash"] is string message ? [message] : [];

    [BindProperty(Name = "activity")]
    public string? Activity { get; set; }

    [BindProperty(Name = "row_id")]
    public string? RowId { get; set; }

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        Activities = await store.ListAsync(cancellationToken);
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        var text = Activity?.Trim();
        var id = RowId?.Trim();
        if (!string.IsNullOrEmpty(text))
        {
            if (!string.IsNullOrEmpty(id))
            {
                await store.UpdateAsync(id, text, cancellationToken);
                logger.LogInformation("Activity updated: {Id}", id);
                TempData["Flash"] = "Activity updated.";
            }
            else
            {
                await store.AddAsync(text, cancellationToken);
                logger.LogInformation("Activity added: {Activity}", text);
                TempData["Flash"] = "Activity added.";
            }
        }

        return RedirectToPage();
    }
}
