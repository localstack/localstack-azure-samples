namespace VacationPlanner;

/// <summary>Deployment details shown on the page and returned by <c>/api/status</c>.</summary>
public static class AppInfo
{
    public static string AppName => Environment.GetEnvironmentVariable("APP_NAME") ?? "Custom Image Web App";

    public static string ImageName => Environment.GetEnvironmentVariable("IMAGE_NAME") ?? "custom-image-webapp:v1";

    public static string HostName => Environment.MachineName;
}
