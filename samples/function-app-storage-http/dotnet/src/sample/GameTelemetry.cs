using System.Diagnostics.Metrics;
using Microsoft.Extensions.Logging;

namespace LocalStack.Azure.Samples;

/// <summary>
/// The custom telemetry of the games: a custom event for each game created and for each winner a function determines,
/// and a counter of the games completed, by the source of the request. With the connection string of an Application
/// Insights resource, the OpenTelemetry exporter of Azure Monitor sends the events to the customEvents table and the
/// counter to the customMetrics table.
/// </summary>
public static class GameTelemetry
{
    /// <summary>The name of the meter, which <c>Program.cs</c> adds to the meters the exporter sends.</summary>
    public const string MeterName = "GameSessionManager";

    private static readonly Meter Meter = new(MeterName);

    private static readonly Counter<long> GamesCompleted = Meter.CreateCounter<long>(
        "games_completed",
        unit: "{game}",
        description: "The number of games whose winner a function determined, by the source of the request.");

    /// <summary>Sends the GameCreated custom event.</summary>
    public static void TrackGameCreated(ILogger logger, int gameId)
    {
        // The exporter sends a log record whose message template carries the microsoft.custom_event.name attribute as a
        // custom event named after its value, with the other attributes as its custom dimensions.
        logger.LogInformation("{microsoft.custom_event.name} {game.id}", "GameCreated", gameId);
    }

    /// <summary>Sends the GameWinnerDetermined custom event and counts the game in the custom metric.</summary>
    public static void TrackWinnerDetermined(ILogger logger, string source, int gameId, string winner)
    {
        logger.LogInformation(
            "{microsoft.custom_event.name} {game.id} {game.winner} {game.source}",
            "GameWinnerDetermined",
            gameId,
            winner,
            source);
        GamesCompleted.Add(1, new KeyValuePair<string, object?>("source", source));
    }
}
