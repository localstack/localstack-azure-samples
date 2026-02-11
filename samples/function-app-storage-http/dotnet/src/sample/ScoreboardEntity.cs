using Azure;
using Azure.Data.Tables;

namespace LocalStack.Azure.Samples;

/// <summary>
/// Represents a scoreboard entry stored in Azure Table Storage for a specific game.
/// Implements <see cref="ITableEntity"/> to support partitioning, concurrency control, and system metadata.
/// </summary>
public class ScoreboardEntity : ITableEntity
{
  /// <summary>
  /// The player's score.
  /// </summary>
  private int _score;
  /// <summary>
  /// The game ID.
  /// </summary>
  private int _gameId;

  /// <summary>
  /// Gets or sets the partition key that groups related entities together for scalability and query efficiency.
  /// Choose a value that distributes load and aligns with your query patterns (for example, by game or date).
  /// </summary>
  public required string PartitionKey { get; set; }

  /// <summary>
  /// Gets or sets the row key that uniquely identifies the entity within a partition.
  /// Combined with <see cref="PartitionKey"/>, it forms the entity's unique key (for example, a player ID).
  /// </summary>
  public required string RowKey { get; set; }

    /// <summary>
  /// Gets or sets the game ID (for example, a match identifier or sequence number).
  /// </summary>
  public int GameId
  {
    get => _gameId;
    set
    {
      if (value < 0)
      {
        throw new ArgumentOutOfRangeException(nameof(value), "Game ID must be 0 or higher.");
      }
      _gameId = value;
    }
  }

  /// <summary>
  /// Gets or sets the player's display name.
  /// </summary>
  public required string PlayerName { get; set; }

  /// <summary>
  /// Gets or sets the player's score. Must be 0 or higher.
  /// </summary>
  /// <exception cref="ArgumentOutOfRangeException">Thrown when a negative value is assigned.</exception>
  public int Score
  {
    get => _score;
    set
    {
      if (value < 0)
      {
        throw new ArgumentOutOfRangeException(nameof(value), "Score must be 0 or higher.");
      }
      _score = value;
    }
  }

  /// <summary>
  /// Gets or sets the server-assigned timestamp for the entity, updated by the Table service on modifications.
  /// </summary>
  public DateTimeOffset? Timestamp { get; set; }

  /// <summary>
  /// Gets or sets the entity tag used for optimistic concurrency. Set to <see cref="ETag.All"/> to unconditionally update/replace.
  /// </summary>
  public ETag ETag { get; set; }
}
