using Microsoft.AspNetCore.Mvc.RazorPages;

namespace VacationPlanner.Pages;

public class IndexModel : PageModel
{
    public string AppName => AppInfo.AppName;

    public string ImageName => AppInfo.ImageName;

    public string HostName => AppInfo.HostName;

    public void OnGet()
    {
    }
}
