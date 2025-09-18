using System.Text.Json.Serialization;

namespace LocalStack.Azure.Samples;

/// <summary>
/// Represents the response message for game status operations.
/// </summary>
public class GameStatusResponse
{
  /// <summary>
  /// Gets or sets the date of the response message.
  /// </summary>
  [JsonPropertyName("date")]
  public required string Date { get; set; }

  /// <summary>
  /// Gets or sets the game ID.
  /// </summary>
  [JsonPropertyName("gameId")]
  public int GameId { get; set; }

  /// <summary>
  /// Gets or sets the winner player name.
  /// </summary>
  [JsonPropertyName("winner")]
  public required string Winner { get; set; }

  /// <summary>
  /// Gets or sets the list of player scores for this game.
  /// </summary>
  [JsonPropertyName("players")]
  public required List<PlayerScore> Players { get; set; }
}