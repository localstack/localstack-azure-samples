using System.Text.Json.Serialization;

namespace LocalStack.Azure.Samples;

/// <summary>
/// Represents the request message for player score operations.
/// </summary>
public class PlayerScoreRequest
{
  /// <summary>
  /// Gets or sets the game ID.
  /// </summary>
  [JsonPropertyName("gameId")]
  public int GameId { get; set; }

  /// <summary>
  /// Gets or sets the player name.
  /// </summary>
  [JsonPropertyName("playerName")]
  public required string PlayerName { get; set; }
}

