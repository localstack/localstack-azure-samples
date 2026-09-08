using System.Security.Cryptography;
using System.Text;

namespace VacationPlanner.Services;

/// <summary>MD5 of username + activity + timestamp: the id scheme shared by the Vacation Planner samples.</summary>
public static class ActivityId
{
    public static string Create(string username, string activity)
    {
        var timestamp = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss.ffffff");
        var hash = MD5.HashData(Encoding.UTF8.GetBytes($"{username}_{activity}_{timestamp}"));
        return Convert.ToHexStringLower(hash);
    }
}
