using Newtonsoft.Json;

namespace VacationPlanner.Services;

/// <summary>The Cosmos DB item shape shared with the Python sample: <c>{id, username, activity, timestamp}</c>.</summary>
public sealed class ActivityDocument
{
    [JsonProperty("id")]
    public string Id { get; set; } = "";

    [JsonProperty("username")]
    public string Username { get; set; } = "";

    [JsonProperty("activity")]
    public string Activity { get; set; } = "";

    [JsonProperty("timestamp")]
    public string Timestamp { get; set; } = "";
}
