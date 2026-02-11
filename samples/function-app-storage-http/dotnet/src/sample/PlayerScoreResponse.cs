using System.Text.Json.Serialization;

namespace LocalStack.Azure.Samples;

/// <summary>
/// Represents the response message for player score operations.
/// </summary>
public class PlayerScoreResponse
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
  /// Gets or sets the player name.
  /// </summary>
  [JsonPropertyName("name")]
  public required string Name { get; set; }

  /// <summary>
  /// Gets or sets the player score (always >= 0).
  /// </summary>
  [JsonPropertyName("score")]
  public int Score { get; set; }
}