using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using Azure.Storage.Blobs;
using Azure.Storage.Queues;
using Azure.Storage.Queues.Models;
using Azure.Data.Tables;
using Azure;

namespace LocalStack.Azure.Samples;

/// <summary>
/// Manages game sessions and player interactions using Azure Functions with hybrid storage approach.
/// This class demonstrates a complete gaming scoreboard system with blob storage for game files,
/// queue processing for game events, table storage for winners, and internal dictionary for active game data.
/// The system processes GameStatusRequest/GameStatusResponse messages and maintains game state in memory
/// for improved performance while still utilizing Azure Storage services for persistence and messaging.
/// </summary>
public class GameSessionManager
{
    // Instance field for logging - keeps proper Azure Functions execution context
    private readonly ILogger _logger;

    // Static configuration values - initialized once per application lifetime
    private static string? _connectionString;
    private static string? _inputQueueName;
    private static string? _outputQueueName;
    private static string? _triggerQueueName;
    private static string? _inputContainerName;
    private static string? _outputContainerName;
    private static string? _inputTableName;
    private static string? _outputTableName;
    private static string[]? _playerNames;
    private static bool _configurationValid;
    private static int _gameId = 1;

    // Static dictionary to store game data in memory - game ID as key, list of player scores as value
    // This replaces Azure Table Storage for demonstration purposes and provides faster access
    private static readonly Dictionary<int, List<PlayerScore>> _gameData = new Dictionary<int, List<PlayerScore>>();
    private static readonly object _gameDataLock = new object();

    // Static initialization - runs once per application lifetime
    private static readonly Lazy<Task> _infrastructureInitialization = new Lazy<Task>(() => InitializeInfrastructureOnceAsync());

    /// <summary>
    /// Initializes a new instance of the <see cref="GameSessionManager"/> class.
    /// </summary>
    /// <param name="loggerFactory">The logger factory used to create loggers for this class.</param>
    public GameSessionManager(ILoggerFactory loggerFactory)
    {
        _logger = loggerFactory.CreateLogger<GameSessionManager>();
    }

    /// <summary>
    /// Ensures that Azure infrastructure (queues, containers, tables) is initialized exactly once
    /// during the application lifetime. This method is thread-safe and idempotent.
    /// </summary>
    /// <returns>A task that completes when infrastructure initialization is finished.</returns>
    private async Task EnsureInfrastructureInitializedAsync()
    {
        await _infrastructureInitialization.Value;
    }

    /// <summary>
    /// One-time initialization of Azure Storage infrastructure (queues, containers, tables).
    /// This method runs exactly once per application lifetime and stores configuration values in static fields.
    /// </summary>
    /// <returns>A task representing the asynchronous initialization operation.</returns>
    private static async Task InitializeInfrastructureOnceAsync()
    {
        try
        {
            // Create a temporary configuration instance for initialization
            var configBuilder = new ConfigurationBuilder()
                .AddEnvironmentVariables()
                .AddJsonFile("local.settings.json", optional: true);
            var config = configBuilder.Build();

            // Create a temporary logger for initialization
            using var loggerFactory = LoggerFactory.Create(builder => builder.AddConsole());
            var logger = loggerFactory.CreateLogger<GameSessionManager>();

            logger.LogInformation("[InitializeInfrastructureOnceAsync] Starting one-time infrastructure initialization...");

            // Read and store configuration values in static fields with fallback defaults
            _connectionString = config["STORAGE_ACCOUNT_CONNECTION_STRING"];
            _inputQueueName = config["INPUT_QUEUE_NAME"] ?? "input";
            _outputQueueName = config["OUTPUT_QUEUE_NAME"] ?? "output";
            _triggerQueueName = config["TRIGGER_QUEUE_NAME"] ?? "trigger";
            _inputContainerName = config["INPUT_STORAGE_CONTAINER_NAME"] ?? "input";
            _outputContainerName = config["OUTPUT_STORAGE_CONTAINER_NAME"] ?? "output";
            _inputTableName = config["INPUT_TABLE_NAME"] ?? "scoreboards";
            _outputTableName = config["OUTPUT_TABLE_NAME"] ?? "winners";
            _playerNames = config["PLAYER_NAMES"]?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

            // Check if player names ae configured. If not use, use default names
            if (_playerNames == null || _playerNames.Length == 0)
            {
                logger.LogWarning("[InitializeInfrastructureOnceAsync] PLAYER_NAMES configuration is missing or empty. Using default names.");
                _playerNames = new[] { "Alice", "Anastasia", "Paolo", "Leo", "Mia" };
            }

            // Validate configuration and set the flag
            _configurationValid = ValidateConfigurationValues(logger);

            if (_configurationValid && _connectionString != null)
            {
                // Initialize all infrastructure components
                await InitializeQueuesAsync(_connectionString, logger, new[] { _inputQueueName, _outputQueueName, _triggerQueueName }.Where(q => q != null).ToArray()!);
                await InitializeContainersAsync(_connectionString, logger, new[] { _inputContainerName, _outputContainerName }.Where(c => c != null).ToArray()!);
                await InitializeTablesAsync(_connectionString, logger, new[] { _inputTableName, _outputTableName }.Where(t => t != null).ToArray()!);

                logger.LogInformation("[InitializeInfrastructureOnceAsync] Infrastructure initialization completed successfully.");
            }
            else
            {
                logger.LogError("[InitializeInfrastructureOnceAsync] Configuration validation failed. Infrastructure initialization aborted.");
            }
        }
        catch (Exception ex)
        {
            // Log error but don't throw - let functions continue to work even if initialization fails
            Console.WriteLine("[InitializeInfrastructureOnceAsync] Failed to initialize infrastructure: {0}", ex.Message);
            _configurationValid = false;
        }
    }

    /// <summary>
    /// Validates that all required configuration values are present and not empty.
    /// With default values in place, only the connection string is mandatory.
    /// </summary>
    /// <param name="logger">Logger for reporting validation errors.</param>
    /// <returns>True if all configuration values are valid, false otherwise.</returns>
    private static bool ValidateConfigurationValues(ILogger logger)
    {
        bool isValid = true;

        // Connection string is the only truly required value - everything else has defaults
        if (string.IsNullOrWhiteSpace(_connectionString))
        {
            logger.LogError("[ValidateConfigurationValues] STORAGE_ACCOUNT_CONNECTION_STRING configuration value is missing and is required.");
            isValid = false;
        }

        // Log the configuration values being used (helpful for debugging)
        if (isValid)
        {
            logger.LogInformation("[ValidateConfigurationValues] Configuration loaded successfully:");
            logger.LogInformation("  - Input Queue: {inputQueue}", _inputQueueName);
            logger.LogInformation("  - Output Queue: {outputQueue}", _outputQueueName);
            logger.LogInformation("  - Trigger Queue: {triggerQueue}", _triggerQueueName);
            logger.LogInformation("  - Input Container: {inputContainer}", _inputContainerName);
            logger.LogInformation("  - Output Container: {outputContainer}", _outputContainerName);
            logger.LogInformation("  - Input Table: {inputTable}", _inputTableName);
            logger.LogInformation("  - Output Table: {outputTable}", _outputTableName);
        }

        return isValid;
    }

    /// <summary>
    /// Checks if configuration values have been successfully loaded and validated.
    /// This method provides a fast runtime check without re-reading configuration.
    /// With default values, this primarily checks if the connection string is available.
    /// </summary>
    /// <returns>True if configuration is valid and available, false otherwise.</returns>
    private static bool IsConfigurationValid()
    {
        // Since we have defaults for all values except connection string, 
        // we only need to check the configuration validation flag and connection string
        return _configurationValid && !string.IsNullOrWhiteSpace(_connectionString);
    }

    /// <summary>
    /// Static version of queue initialization for one-time setup.
    /// </summary>
    private static async Task InitializeQueuesAsync(string connectionString, ILogger logger, string[] queues)
    {
        try
        {
            foreach (var queueName in queues.Where(q => !string.IsNullOrWhiteSpace(q)))
            {
                var queueClient = new QueueClient(connectionString, queueName);
                await queueClient.CreateIfNotExistsAsync();
                logger.LogInformation("[InitializeQueuesAsync] Initialized queue: {queueName}", queueName);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "[InitializeQueuesAsync] Failed to initialize queues.");
        }
    }

    /// <summary>
    /// Static version of container initialization for one-time setup.
    /// </summary>
    private static async Task InitializeContainersAsync(string connectionString, ILogger logger, string[] containers)
    {
        try
        {
            var blobServiceClient = new BlobServiceClient(connectionString);
            foreach (var containerName in containers.Where(c => !string.IsNullOrWhiteSpace(c)))
            {
                var containerClient = blobServiceClient.GetBlobContainerClient(containerName);
                await containerClient.CreateIfNotExistsAsync();
                logger.LogInformation("[InitializeContainersAsync] Initialized container: {containerName}", containerName);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "[InitializeContainersAsync] Failed to initialize containers.");
        }
    }

    /// <summary>
    /// Static version of table initialization for one-time setup.
    /// </summary>
    private static async Task InitializeTablesAsync(string connectionString, ILogger logger, string[] tables)
    {
        try
        {
            foreach (var tableName in tables.Where(t => !string.IsNullOrWhiteSpace(t)))
            {
                var tableClient = new TableClient(connectionString, tableName);
                await tableClient.CreateIfNotExistsAsync();
                logger.LogInformation("[InitializeTablesAsync] Initialized table: {tableName}", tableName);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "[InitializeTablesAsync] Failed to initialize tables.");
        }
    }

    /// <summary>
    /// Handles HTTP GET requests to retrieve player score for a specific game and player.
    /// </summary>
    /// <param name="request">The HTTP request data.</param>
    /// <param name="gameId">The game ID to retrieve scores for, provided in the route.</param>
    /// <param name="name">The player name to retrieve status for, provided in the route.</param>
    /// <returns>An HTTP response with player score information or an error message.</returns>
    [Function("GetPlayerScore")]
    public async Task<HttpResponseData> GetPlayerScoreAsync([HttpTrigger(AuthorizationLevel.Function, "get", Route = "player/{gameId}/{name}/status")] HttpRequestData request, int gameId, string name)
    {
        HttpResponseData response;

        // Log the incoming request
        _logger.LogInformation("[GetPlayerScore] Received GET request with gameId = {gameId}, name = {name}.", gameId, name ?? "NULL");

        // Validate the name parameter
        if (name == null || string.IsNullOrWhiteSpace(name))
        {
            response = request.CreateResponse(HttpStatusCode.BadRequest);
            await response.WriteStringAsync("Invalid parameters: name parameter is required.");
            return response;
        }

        // Check if the game and player exist in the internal dictionary
        PlayerScore? playerScore = null;
        lock (_gameDataLock)
        {
            if (_gameData.TryGetValue(gameId, out var players))
            {
                playerScore = players.FirstOrDefault(p => p.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
            }
        }

        if (playerScore == null)
        {
            response = request.CreateResponse(HttpStatusCode.NotFound);
            await response.WriteStringAsync($"Game {gameId} and player '{name}' tuple not found.");
            return response;
        }

        // Return the player score information
        response = request.CreateResponse(HttpStatusCode.OK);

        // Create the response message
        var outputObj = new PlayerScoreResponse
        {
            Date = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
            GameId = gameId,
            Name = playerScore.Name,
            Score = playerScore.Score
        };
        var outputMessage = JsonSerializer.Serialize(outputObj);

        // Write the response message to the HTTP response
        await response.WriteStringAsync(outputMessage);

        // Log the successful processing
        _logger.LogInformation("[GetPlayerScore] Processed request successfully with gameId = {gameId}, name = {name}, score = {score}.", gameId, name, playerScore.Score);

        // Return the HTTP response
        return response;
    }

    /// <summary>
    /// Handles HTTP POST and PUT requests to retrieve game status information.
    /// Accepts a GameStatusRequest in the request body and returns comprehensive game status
    /// including winner determination and all player scores for the specified game.
    /// </summary>
    /// <param name="request">The HTTP request data containing a JSON-serialized GameStatusRequest.</param>
    /// <returns>An HTTP response with GameStatusResponse containing game status details, winner, and all players, or an error message if the game is not found or invalid.</returns>
    [Function("CreateGameStatus")]
    public async Task<HttpResponseData> CreateGameStatusAsync([HttpTrigger(AuthorizationLevel.Function, "post", "put", Route = "game/session")] HttpRequestData request)
    {
        HttpResponseData response;

        // Log the incoming request method
        _logger.LogInformation("[CreateGameStatus] Received {method} request.", request.Method);

        // Read the request body as a string
        var requestBody = await request.ReadAsStringAsync();

        // Validate that the request body is not empty
        if (requestBody == null || string.IsNullOrWhiteSpace(requestBody))
        {
            response = request.CreateResponse(HttpStatusCode.BadRequest);
            await response.WriteStringAsync("[CreateGameStatus] Invalid request message: Request body is required.");
            return response;
        }

        GameStatusRequest? requestMessage;
        try
        {
            // Attempt to deserialize the request body into a GameStatusRequest object
            requestMessage = JsonSerializer.Deserialize<GameStatusRequest>(requestBody);
        }
        catch (JsonException)
        {
            // Handle invalid JSON format
            response = request.CreateResponse(HttpStatusCode.BadRequest);
            await response.WriteStringAsync("[CreateGameStatus] Invalid request message: Request body is not in the proper format.");
            return response;
        }

        // Validate that the GameId property is present and valid
        if (requestMessage == null || requestMessage.GameId <= 0)
        {
            response = request.CreateResponse(HttpStatusCode.BadRequest);
            await response.WriteStringAsync("[CreateGameStatus] Invalid request message: 'GameId' is required and must be greater than 0.");
            return response;
        }

        // Check if the game exists in the internal dictionary
        List<PlayerScore>? players = null;
        bool gameFound = false;
        lock (_gameDataLock)
        {
            gameFound = _gameData.TryGetValue(requestMessage.GameId, out players);
        }

        if (!gameFound || players == null)
        {
            _logger.LogWarning("[CreateGameStatus] Game {gameId} not found in internal data store.", requestMessage.GameId);
            response = request.CreateResponse(HttpStatusCode.NotFound);
            await response.WriteStringAsync($"Game {requestMessage.GameId} not found.");
            return response;
        }

        if (players.Count == 0)
        {
            _logger.LogWarning("[CreateGameStatus] Game {gameId} has no player data.", requestMessage.GameId);
            response = request.CreateResponse(HttpStatusCode.NotFound);
            await response.WriteStringAsync($"Game {requestMessage.GameId} has no player data.");
            return response;
        }

        // Find the winner (player with highest score)
        var winner = players.OrderByDescending(p => p.Score).First();

        // Return a response if the request message is valid
        response = request.CreateResponse(HttpStatusCode.OK);

        // Create the response message
        var outputObj = new GameStatusResponse
        {
            Date = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
            GameId = requestMessage.GameId,
            Winner = winner.Name,
            Players = new List<PlayerScore>(players) // Create a copy of the list
        };
        var outputMessage = JsonSerializer.Serialize(outputObj);

        // Write the response message to the HTTP response
        await response.WriteStringAsync(outputMessage);

        // Log the successful processing
        _logger.LogInformation("[CreateGameStatus] Processed request successfully with gameId = {gameId}, winner = {winner}.", requestMessage.GameId, winner.Name);

        // Return the HTTP response
        return response;
    }

    /// <summary>
    /// Processes uploaded game status files from blob storage and generates comprehensive game status responses.
    /// Deserializes GameStatusRequest from blob content, retrieves game data from internal dictionary,
    /// determines the winner, and returns a GameStatusResponse with complete game information.
    /// </summary>
    /// <param name="blobBytes">The blob content as byte array containing JSON-serialized GameStatusRequest.</param>
    /// <param name="name">The name of the blob file being processed.</param>
    /// <returns>A JSON-formatted GameStatusResponse string containing game status, winner, and all players, or null if the input is invalid or game not found.</returns>
    [Function("ProcessGameFile")]
    [BlobOutput("%OUTPUT_STORAGE_CONTAINER_NAME%/{name}")]
    public string? ProcessGameFile(
        [BlobTrigger("%INPUT_STORAGE_CONTAINER_NAME%/{name}", Connection = "STORAGE_ACCOUNT_CONNECTION_STRING")] byte[] blobBytes,
        string name)
    {
        // Check that the blobBytes is not null or empty
        if (blobBytes == null || blobBytes.Length == 0)
        {
            _logger.LogError("[ProcessGameFile] Received [{name}] blob is empty or null.", name);
            return null;
        }

        // Convert the byte array to a string
        string json = System.Text.Encoding.UTF8.GetString(blobBytes);

        // Check that the JSON is not null or empty
        if (string.IsNullOrEmpty(json))
        {
            _logger.LogError("[ProcessGameFile] Received [{name}] blob is empty or invalid.", name);
            return null;
        }

        // Deserialize the JSON into a GameStatusRequest object
        GameStatusRequest? gameStatusRequest = JsonSerializer.Deserialize<GameStatusRequest>(json);

        // Check that the request message is not null
        if (gameStatusRequest == null)
        {
            _logger.LogError("[ProcessGameFile] Received [{name}] blob contains invalid GameStatusRequest.", name);
            return null;
        }

        // Check if the game exists in the internal dictionary
        List<PlayerScore>? players = null;
        lock (_gameDataLock)
        {
            if (!_gameData.TryGetValue(gameStatusRequest.GameId, out players))
            {
                _logger.LogWarning("[ProcessGameFile] Game {gameId} not found in internal data store.", gameStatusRequest.GameId);
                return null;
            }
        }

        if (players == null || players.Count == 0)
        {
            _logger.LogWarning("[ProcessGameFile] Game {gameId} has no player data.", gameStatusRequest.GameId);
            return null;
        }

        // Find the winner (player with highest score)
        var winner = players.OrderByDescending(p => p.Score).First();

        // Create the response message
        var outputObj = new GameStatusResponse
        {
            Date = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
            GameId = gameStatusRequest.GameId,
            Winner = winner.Name,
            Players = new List<PlayerScore>(players) // Create a copy of the list
        };
        var outputMessage = JsonSerializer.Serialize(outputObj);

        // Log the successful processing of the blob
        _logger.LogInformation("[ProcessGameFile] Processed blob [{name}] successfully for game {gameId}.", name, gameStatusRequest.GameId);

        // Return the response message
        return outputMessage;
    }

    /// <summary>
    /// Handles game events from Azure Storage Queue and processes game status requests.
    /// Deserializes GameStatusRequest from queue messages, retrieves game data from internal dictionary,
    /// determines the winner, and returns a GameStatusResponse for further processing in the output queue.
    /// </summary>
    /// <param name="message">The incoming queue message containing JSON-serialized GameStatusRequest data.</param>
    /// <param name="context">The function execution context provided by the Azure Functions runtime.</param>
    /// <returns>
    /// A JSON-formatted GameStatusResponse string containing game status, winner, and all players for output queue processing, or null if the input is invalid or game not found.
    /// </returns>
    [Function("HandleGameEvent")]
    [QueueOutput("%OUTPUT_QUEUE_NAME%", Connection = "STORAGE_ACCOUNT_CONNECTION_STRING")]
    public string? HandleGameEvent([QueueTrigger("%INPUT_QUEUE_NAME%", Connection = "STORAGE_ACCOUNT_CONNECTION_STRING")] QueueMessage message, FunctionContext context)
    {

        // Check that the message and the body are not null or empty
        if (message == null || string.IsNullOrWhiteSpace(message.Body?.ToString()))
        {
            _logger.LogError("[HandleGameEvent] Received queue message is null or empty.");
            return null;
        }

        var json = message.Body.ToString() ?? string.Empty;

        // Check that the JSON is not null or empty
        if (string.IsNullOrEmpty(json))
        {
            _logger.LogError("[HandleGameEvent] Received [{messageId}] queue message is empty or invalid.", message.MessageId);
            return null;
        }

        // Deserialize the JSON into a GameStatusRequest object
        GameStatusRequest? requestMessage = JsonSerializer.Deserialize<GameStatusRequest>(json);

        // Check that the request message is not null
        if (requestMessage == null)
        {
            _logger.LogError("[HandleGameEvent] Received [{messageId}] queue message contains invalid GameStatusRequest.", message.MessageId);
            return null;
        }

        // Check if the game exists in the internal dictionary
        List<PlayerScore>? players = null;
        lock (_gameDataLock)
        {
            if (!_gameData.TryGetValue(requestMessage.GameId, out players))
            {
                _logger.LogWarning("[HandleGameEvent] Game {gameId} not found in internal data store.", requestMessage.GameId);
                // Return null for now, but could create an error response if needed
                return null;
            }
        }

        if (players == null || players.Count == 0)
        {
            _logger.LogWarning("[HandleGameEvent] Game {gameId} has no player data.", requestMessage.GameId);
            return null;
        }

        // Find the winner (player with highest score)
        var winner = players.OrderByDescending(p => p.Score).First();

        // Create the response message
        var outputObj = new GameStatusResponse
        {
            Date = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
            GameId = requestMessage.GameId,
            Winner = winner.Name,
            Players = new List<PlayerScore>(players) // Create a copy of the list
        };
        var outputMessage = JsonSerializer.Serialize(outputObj);

        // Log the successful processing of the queue message
        _logger.LogInformation("[HandleGameEvent] Processed queue message [{messageId}] successfully for game {gameId}.", message.MessageId, requestMessage.GameId);

        // Return the response message
        return outputMessage;

    }

    /// <summary>
    /// Processes game scoreboards to determine winners and manage game results.
    /// Retrieves scoreboard entries for a game, finds the highest score, and records the winner.
    /// </summary>
    /// <param name="gameId">The game ID from the queue message to filter scoreboard entries.</param>
    /// <param name="entities">The scoreboard entities matching the specified game ID.</param>
    /// <returns>The winning ScoreboardEntity with the highest score, or null if no entities are found.</returns>
    [Function("ProcessScoreboard")]
    [TableOutput("%OUTPUT_TABLE_NAME%", Connection = "STORAGE_ACCOUNT_CONNECTION_STRING")]
    public ScoreboardEntity? ProcessScoreboard(
        [QueueTrigger("%TRIGGER_QUEUE_NAME%")] string gameId,
        [TableInput("%INPUT_TABLE_NAME%", "{queueTrigger}",
                    Connection = "STORAGE_ACCOUNT_CONNECTION_STRING")] IEnumerable<ScoreboardEntity> entities)
    {
        // Find the entity with the highest score
        var winner = entities.OrderByDescending(e => e.Score).FirstOrDefault();
        _logger.LogInformation("[ProcessScoreboard] Processed game ID {gameId}. Winner: {winnerName} with score {score}.", gameId, winner?.PlayerName ?? "No winner", winner?.Score.ToString() ?? "N/A");

        if (winner != null)
        {
            // Create a new entity for the output table with a new RowKey
            var winnerEntity = new ScoreboardEntity
            {
                PartitionKey = $"winner-game-{int.Parse(gameId):D3}",
                RowKey = Guid.NewGuid().ToString(),
                GameId = winner.GameId,
                PlayerName = winner.PlayerName,
                Score = winner.Score,
                Timestamp = DateTimeOffset.UtcNow,
                ETag = ETag.All
            };

            return winnerEntity;
        }

        return null;
    }

    /// <summary>
    /// Timer-triggered function that generates new game rounds with random player data and initiates the complete gaming workflow.
    /// Creates GameStatusRequest objects, uploads them as blobs, sends queue messages, creates internal dictionary entries
    /// with random player scores, and triggers the scoreboard processing pipeline. Runs every minute and on startup.
    /// </summary>
    /// <param name="timerInfo">Timer metadata containing schedule status and next occurrence information.</param>
    /// <returns>A task that represents the asynchronous game round generation operation.</returns>
    [Function("CreateGame")]
    [FixedDelayRetry(5, "00:00:10")]
    public async Task CreateGameAsync([TimerTrigger("0 */1 * * * *", RunOnStartup = true)] TimerInfo timerInfo)
    {
        _logger.LogInformation("[CreateGameAsync] Triggered execution.");

        // Ensure infrastructure is initialized (runs only once per app lifetime)
        await EnsureInfrastructureInitializedAsync();

        // Fast configuration validation using pre-loaded static values
        if (!IsConfigurationValid())
        {
            _logger.LogError("[CreateGameAsync] Configuration is invalid or not loaded. Aborting function execution.");
            return;
        }

        if (_playerNames == null || _playerNames.Length == 0)
        {
            _logger.LogError("[CreateGameAsync] Player names are not configured. Aborting function execution.");
            return;
        }
        
        var random = new Random();
        var gameStatusRequest = new GameStatusRequest { GameId = _gameId };

        // Serialize the request message to JSON
        var message = JsonSerializer.Serialize(gameStatusRequest);

        // Log the generated message and configuration values
        _logger.LogInformation("[CreateGameAsync] Generated message: {message}", message);

        // Create a unique blob name with the required format
        var now = DateTime.UtcNow;
        var blobFileName = $"game-{_gameId:D3}-status-{now:yyyy-MM-dd-HH-mm-ss}.json";

        // Create scoreboard entries for all players using the updated method
        await CreateScoreboardEntriesAsync(_connectionString, _inputTableName);
        
        // Upload blob to the input container
        await UploadBlobAsync(_connectionString, _inputContainerName, blobFileName, message);
        
        // Send message to the input queue
        await SendQueueMessageAsync(_connectionString, _inputQueueName, message);

        // Send message to the trigger queue
        await SendQueueMessageAsync(_connectionString, _triggerQueueName, _gameId.ToString());

        // Increment game ID for next execution
        _gameId++;

        // Log the next scheduled timer occurrence
        _logger.LogInformation("[CreateGameAsync] Function Ran. Next timer schedule = {nextSchedule}", timerInfo.ScheduleStatus?.Next);
    }

    /// <summary>
    /// Uploads a message as a blob to the specified Azure Storage container.
    /// </summary>
    /// <param name="connectionString">The storage account connection string.</param>
    /// <param name="inputContainerName">The name of the container to upload to.</param>
    /// <param name="blobFileName">The name of the blob file to create.</param>
    /// <param name="message">The message content to upload as blob data.</param>
    /// <returns>A task that represents the asynchronous upload operation.</returns>
    private async Task UploadBlobAsync(string? connectionString, string? inputContainerName, string blobFileName, string message)
    {
        try
        {
            var blobServiceClient = new BlobServiceClient(connectionString);
            var blobContainerClient = blobServiceClient.GetBlobContainerClient(inputContainerName);

            await blobContainerClient.CreateIfNotExistsAsync();

            var blobClient = blobContainerClient.GetBlobClient(blobFileName);

            using (var stream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(message)))
            {
                await blobClient.UploadAsync(stream, overwrite: true);
            }
            _logger.LogInformation("[UploadBlobAsync] Uploaded blob: {blobFileName} to container: {containerName}", blobFileName, inputContainerName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[UploadBlobAsync] Failed to upload blob: {blobFileName} to container: {containerName}", blobFileName, inputContainerName);
        }
    }

    /// <summary>
    /// Sends a message to the specified Azure Storage queue.
    /// </summary>
    /// <param name="connectionString">The storage account connection string.</param>
    /// <param name="queueName">The name of the queue to send the message to.</param>
    /// <param name="message">The message content to send (will be Base64 encoded).</param>
    /// <returns>A task that represents the asynchronous send operation.</returns>
    private async Task SendQueueMessageAsync(string? connectionString, string? queueName, string message)
    {
        try
        {
            var queueClient = new QueueClient(connectionString, queueName);

            await queueClient.CreateIfNotExistsAsync();

            await queueClient.SendMessageAsync(Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(message)));
            _logger.LogInformation("[SendQueueMessageAsync] Sent message to queue: {queueName}", queueName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[SendQueueMessageAsync] Failed to send message to queue: {queueName}", queueName);
        }
    }

    /// <summary>
    /// Creates scoreboard entries for each player with random scores and stores them in the internal dictionary.
    /// This method replaces Azure Table Storage operations by maintaining game data in memory using a thread-safe
    /// Dictionary structure. Each game is stored with its unique game ID and contains all player scores.
    /// </summary>
    /// <param name="connectionString">The storage account connection string.</param>
    /// <param name="tableName">The name of the table to store the scoreboard entries in.</param>
    /// <returns>A task that represents the asynchronous operation of creating and storing player scores.</returns>
    private async Task CreateScoreboardEntriesAsync(string? connectionString, string? tableName)
    {
        try
        {
            var random = new Random();
            var playerScores = new List<PlayerScore>();
            var tableClient = new TableClient(connectionString, tableName);
            await tableClient.CreateIfNotExistsAsync();
            var partitionKey = _gameId.ToString();

            if (_playerNames == null || _playerNames.Length == 0)
            {
                _logger.LogWarning("[CreateScoreboardEntriesAsync] No player names configured. Skipping scoreboard entry creation.");
                return;
            }

            foreach (var name in _playerNames)
            {
                var score = Math.Max(0, random.Next(0, 101)); // Random number between 0 and 100, ensure >= 0
                var playerScore = new PlayerScore
                {
                    Name = name,
                    Score = score
                };

                playerScores.Add(playerScore);

                var entity = new ScoreboardEntity
                {
                    PartitionKey = partitionKey,
                    RowKey = Guid.NewGuid().ToString(),
                    GameId = _gameId,
                    PlayerName = name,
                    Score = score,
                    Timestamp = DateTimeOffset.UtcNow,
                    ETag = ETag.All
                };

                await tableClient.AddEntityAsync(entity);

                _logger.LogInformation("[CreateScoreboardEntriesAsync] Added scoreboard entry for {playerName} with score {score} in game {gameId}", name, score, _gameId);
            }

            // Store the game data in the internal dictionary (thread-safe)
            lock (_gameDataLock)
            {
                _gameData[_gameId] = playerScores;
            }

            _logger.LogInformation("[CreateScoreboardEntriesAsync] Created {playerCount} scoreboard entries for game {gameId}.", _playerNames.Length, _gameId);

            // Simulate async work to maintain the async signature
            await Task.CompletedTask;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[CreateScoreboardEntriesAsync] Failed to create scoreboard entries for game {gameId}", _gameId);
        }
    }
}