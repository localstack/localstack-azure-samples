using System.Text.Json.Serialization;

namespace LocalStack.Azure.Samples;

/// <summary>
/// Represents a player's score information.
/// </summary>
public class PlayerScore
{
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