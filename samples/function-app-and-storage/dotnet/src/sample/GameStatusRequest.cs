using System.Text.Json.Serialization;

namespace LocalStack.Azure.Samples;

/// <summary>
/// Represents the request message for game status operations.
/// </summary>
public class GameStatusRequest
{
  /// <summary>
  /// Gets or sets the game ID.
  /// </summary>
  [JsonPropertyName("gameId")]
  public int GameId { get; set; }
}