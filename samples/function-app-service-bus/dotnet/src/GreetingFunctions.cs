using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Azure.Messaging.ServiceBus.Administration;

namespace LocalStack.Azure.Samples;

/// <summary>
/// A simple Azure Function that processes Service Bus messages and responds with a greeting.
/// </summary>
public class HelloWorld
{
    // Instance field for logging - keeps proper Azure Functions execution context
    private readonly ILogger _logger;

    // Static configuration values - initialized once per application lifetime
    private static string? _connectionString;
    private static string? _clientId;
    private static string? _fullyQualifiedNamespace;
    private static bool _hasConnectionString;
    private static bool _hasClientId;
    private static bool _hasFullyQualifiedNamespace;
    private static string? _inputQueueName;
    private static string? _outputQueueName;
    private static bool _configurationValid = false;
    private static string[]? _names;

    // Greeting templates used by GetGreeting to produce varied responses
    private static readonly string[] _greetingTemplates = new[]
    {
        "Hello {0}, how are you?",
        "Hi {0}, great to see you!",
        "Hey {0}, hope you're having a wonderful day!",
        "Good day {0}, welcome aboard!",
        "Greetings {0}, nice to meet you!",
        "Howdy {0}, what's going on?",
        "Welcome {0}, glad you're here!",
        "Salutations {0}, how's everything going?"
    };

    private static readonly Random _random = new();

    // Circular buffers for message history across all functions
    private const int MaxHistory = 100;
    private static readonly object _historyLock = new();
    private static readonly CircularBuffer _requesterSent = new(MaxHistory);
    private static readonly CircularBuffer _handlerReceived = new(MaxHistory);
    private static readonly CircularBuffer _handlerSent = new(MaxHistory);
    private static readonly CircularBuffer _consumerReceived = new(MaxHistory);

    // Static initialization - runs once per application lifetime
    private static readonly Lazy<bool> _initialized = new Lazy<bool>(() => { Initialize(); return true; });

    /// <summary>
    /// Initializes a new instance of the <see cref="HelloWorld"/> class.
    /// </summary>
    /// <param name="loggerFactory">The logger factory used to create loggers for this class.</param>
    public HelloWorld(ILoggerFactory loggerFactory)
    {
        _logger = loggerFactory.CreateLogger<HelloWorld>();
    }

    /// <summary>
    /// One-time initialization of Azure Storage infrastructure (queues, containers, tables).
    /// This method runs exactly once per application lifetime and stores configuration values in static fields.
    /// </summary>
    /// <returns>A task representing the asynchronous initialization operation.</returns>
    private static void Initialize()
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
            var logger = loggerFactory.CreateLogger<HelloWorld>();

            logger.LogInformation("[Initialize] Starting one-time initialization...");

            // Read and store configuration values in static fields with fallback defaults
            _connectionString = config["SERVICE_BUS_CONNECTION_STRING"];
            _clientId = config["AZURE_CLIENT_ID"];
            _fullyQualifiedNamespace = config["SERVICE_BUS_CONNECTION_STRING:fullyQualifiedNamespace"];
            _inputQueueName = config["INPUT_QUEUE_NAME"] ?? "input";
            _outputQueueName = config["OUTPUT_QUEUE_NAME"] ?? "output";
            _names = config["NAMES"]?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

            _hasConnectionString = !string.IsNullOrWhiteSpace(_connectionString);
            _hasClientId = !string.IsNullOrWhiteSpace(_clientId);
            _hasFullyQualifiedNamespace = !string.IsNullOrWhiteSpace(_fullyQualifiedNamespace);

            // Check if names ae configured. If not use, use default names
            if (_names == null || _names.Length == 0)
            {
                logger.LogWarning("[Initialize] NAMES configuration is missing or empty. Using default names.");
                _names = new[] { "Alice", "Paolo", "Leo", "Mia" };
            }

            // Validate configuration and set the flag
            _configurationValid = ValidateConfigurationValues(logger);
        }
        catch (Exception ex)
        {
            // Log error but don't throw - let functions continue to work even if initialization fails
            Console.WriteLine("[Initialize] Initialization failed: {0}", ex.Message);
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

        // Requirement: Must have (ID AND Namespace) OR (Connection String)
        if (!(_hasClientId && _hasFullyQualifiedNamespace) && !_hasConnectionString)
        {
            logger.LogError("[ValidateConfigurationValues] Incomplete configuration. You must provide BOTH Client ID and Namespace, OR a Connection String.");
            isValid = false;
        }

        // Additional Safety: If they provided a partial Identity, catch it!
        if (_hasClientId != _hasFullyQualifiedNamespace && !_hasConnectionString)
        {
            logger.LogError("[ValidateConfigurationValues] Partial Identity detected. Both Client ID and Namespace are required.");
            isValid = false;
        }

        // Log the configuration values being used (helpful for debugging)
        if (isValid)
        {
            logger.LogInformation("[ValidateConfigurationValues] Configuration loaded successfully:");
            logger.LogInformation("  - Input Queue: {inputQueue}", _inputQueueName);
            logger.LogInformation("  - Output Queue: {outputQueue}", _outputQueueName);
            logger.LogInformation("  - Names: {names}", string.Join(", ", _names != null ? _names : Array.Empty<string>()));
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
        // Valid if we have a connection string OR (client ID + fully qualified namespace)
        return _configurationValid && (_hasConnectionString || (_hasClientId && _hasFullyQualifiedNamespace));
    }

    /// <summary>
    /// Processes a Service Bus message by reading, validating, and responding to the input message.
    /// </summary>
    /// <param name="message">The received Service Bus message containing the request payload as JSON.</param>
    /// <param name="messageActions">Actions for managing the Service Bus message lifecycle (e.g., completion).</param>
    /// <returns>
    /// A JSON-formatted response message containing a greeting and the current date, or null if the input is invalid.
    /// </returns>
    [Function("GreetingHandler")]
    [ServiceBusOutput("%OUTPUT_QUEUE_NAME%", Connection = "SERVICE_BUS_CONNECTION_STRING")]
    public async Task<string?> GreetingHandlerAsync(
    [ServiceBusTrigger("%INPUT_QUEUE_NAME%", Connection = "SERVICE_BUS_CONNECTION_STRING", AutoCompleteMessages = false)] ServiceBusReceivedMessage message,
    ServiceBusMessageActions messageActions)
    {
        // Log the incoming message details
        _logger.LogInformation("[GreetingHandler] Message ID: {id}", message.MessageId);
        _logger.LogInformation("[GreetingHandler] Message Body: {body}", message.Body);
        _logger.LogInformation("[GreetingHandler] Message Content-Type: {contentType}", message.ContentType);

        // Read the message body as a byte array
        byte[] bodyBytes = message.Body.ToArray();

        // Check that the bodyBytes is not null or empty
        if (bodyBytes == null || bodyBytes.Length == 0)
        {
            _logger.LogError("[GreetingHandler] Received message [{messageId}] body is empty or null.", message.MessageId);
            return null;
        }
        // Convert the byte array to a string
        string json = System.Text.Encoding.UTF8.GetString(bodyBytes);

        // Check that the JSON is not null or empty
        if (string.IsNullOrEmpty(json))
        {
            _logger.LogError("[GreetingHandler] Received message [{messageId}] body is empty or invalid.", message.MessageId);
            return null;
        }

        // Deserialize the JSON into a RequestMessage object
        RequestMessage? requestMessage = JsonSerializer.Deserialize<RequestMessage>(json);

        // Check that the request message is not null or empty
        if (requestMessage == null || string.IsNullOrWhiteSpace(requestMessage?.Name))
        {
            _logger.LogError("[GreetingHandler] Received request message [{messageId}] body is empty or invalid.", message.MessageId);
            return null;
        }

        _logger.LogInformation("[GreetingHandler] Processing request for name: {name}", requestMessage.Name);

        // Record received name in history
        lock (_historyLock)
        {
            _handlerReceived.Add(requestMessage.Name);
        }

        // Create the response message
        var greetingText = GetGreeting(requestMessage.Name);
        var outputObj = new ResponseMessage
        {
            Date = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
            Text = greetingText
        };
        var outputMessage = JsonSerializer.Serialize(outputObj);

        // Complete the message after processing
        await messageActions.CompleteMessageAsync(message);

        // Log the successful processing of the message
        _logger.LogInformation("[GreetingHandler] Processed message [{messageId}] successfully: {greetingText}", message.MessageId, greetingText);

        // Return the response message
        return outputMessage;
    }

    /// <summary>
    /// Timer-triggered function that sends a greeting request message to the input queue.
    /// </summary>
    /// <param name="timerInfo">Timer metadata containing schedule status and next occurrence information.</param>
    [Function("GreetingRequester")]
    [FixedDelayRetry(5, "00:00:10")]
    public async Task GreetingRequesterAsync([TimerTrigger("%TIMER_SCHEDULE%", RunOnStartup = true)] TimerInfo timerInfo)
    {
        // Log the start of the function execution
        _logger.LogInformation("[GreetingRequester] Timer trigger function started.");

        // Ensure one-time initialization has run
        _ = _initialized.Value;

        // Fast configuration validation using pre-loaded static values
        if (!IsConfigurationValid())
        {
            _logger.LogError("[GreetingRequester] Configuration is invalid or not loaded. Aborting function execution.");
            return;
        }

        if (_names == null || _names.Length == 0)
        {
            _logger.LogError("[GreetingRequester] Names are not configured. Aborting function execution.");
            return;
        }

        try
        {
            // Create Service Bus client
            _logger.LogInformation("[GreetingRequester] Creating Service Bus client for sending messages...");
            await using var client = _hasClientId && _hasFullyQualifiedNamespace
                ? new ServiceBusClient(_fullyQualifiedNamespace, new DefaultAzureCredential())
                : new ServiceBusClient(_connectionString);

            // Create message sender for the input queue
            _logger.LogInformation("[GreetingRequester] Creating sender for input queue '{inputQueue}'", _inputQueueName);
            await using var sender = client.CreateSender(_inputQueueName);

            // Create request message with randomly selected name
            var random = new Random();
            var selectedName = _names[random.Next(_names.Length)];
            var requestMessage = new RequestMessage { Name = selectedName };
            var messageBody = JsonSerializer.Serialize(requestMessage);

            // Create and send Service Bus message
            var serviceBusMessage = new ServiceBusMessage(messageBody)
            {
                ContentType = "application/json"
            };

            _logger.LogInformation("[GreetingRequester] Sending message to input queue '{inputQueue}'...", _inputQueueName);
            await sender.SendMessageAsync(serviceBusMessage);
            _logger.LogInformation("[GreetingRequester] Successfully sent message to input queue '{inputQueue}' with name: {Name}", _inputQueueName, selectedName);

            // Record sent name in history
            lock (_historyLock)
            {
                _requesterSent.Add(selectedName);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[GreetingRequester] Failed to send message to input queue '{inputQueue}'", _inputQueueName);
            return;
        }

        // Log the next scheduled timer occurrence
        _logger.LogInformation("[GreetingRequester] Function Ran. Next timer schedule = {nextSchedule}", timerInfo.ScheduleStatus?.Next);
    }

    /// <summary>
    /// Timer-triggered function that receives and processes greeting response messages from the output queue.
    /// </summary>
    /// <param name="timerInfo">Timer metadata containing schedule status and next occurrence information.</param>
    [Function("GreetingConsumer")]
    [FixedDelayRetry(5, "00:00:10")]
    public async Task GreetingConsumerAsync([TimerTrigger("%TIMER_SCHEDULE%", RunOnStartup = true)] TimerInfo timerInfo)
    {
        // Log the start of the function execution
        _logger.LogInformation("[GreetingConsumer] Timer trigger function started.");

        // Ensure one-time initialization has run
        _ = _initialized.Value;

        // Fast configuration validation using pre-loaded static values
        if (!IsConfigurationValid())
        {
            _logger.LogError("[GreetingConsumer] Configuration is invalid or not loaded. Aborting function execution.");
            return;
        }

        try
        {
            // Create Service Bus client for receiving messages from the output queue
            _logger.LogInformation("[GreetingConsumer] Creating Service Bus client for receiving messages...");
            await using var client = _hasClientId && _hasFullyQualifiedNamespace
                ? new ServiceBusClient(_fullyQualifiedNamespace, new DefaultAzureCredential())
                : new ServiceBusClient(_connectionString);
            var receiver = client.CreateReceiver(_outputQueueName);

            _logger.LogInformation("[GreetingConsumer] Starting to receive messages from output queue '{outputQueue}'", _outputQueueName);

            // Loop to receive messages (with timeout to prevent infinite waiting)
            var timeout = TimeSpan.FromSeconds(30);
            var startTime = DateTime.UtcNow;

            try
            {
                while (DateTime.UtcNow - startTime < timeout)
                {
                    try
                    {
                        // Receive message with a short timeout
                        var receivedMessage = await receiver.ReceiveMessageAsync(TimeSpan.FromSeconds(5));

                        if (receivedMessage == null)
                        {
                            _logger.LogInformation("[GreetingConsumer] No more messages available in output queue '{outputQueue}'", _outputQueueName);
                            break;
                        }

                        // Convert message body to string
                        var messageBody = receivedMessage.Body.ToString();

                        try
                        {
                            // Attempt to deserialize to ResponseMessage
                            var responseMessage = JsonSerializer.Deserialize<ResponseMessage>(messageBody);

                            if (responseMessage != null)
                            {
                                _logger.LogInformation("[GreetingConsumer] Successfully received and deserialized message from output queue. Date: {Date}, Text: {Text}",
                                responseMessage.Date, responseMessage.Text);

                                // Complete the message after successful processing
                                await receiver.CompleteMessageAsync(receivedMessage);

                                // Record received greeting in history
                                lock (_historyLock)
                                {
                                    _consumerReceived.Add(responseMessage.Text);
                                }
                            }
                            else
                            {
                                _logger.LogWarning("[GreetingConsumer] Received message could not be deserialized to ResponseMessage (null result)");
                                await receiver.DeadLetterMessageAsync(receivedMessage, "DeserializationFailed", "Message deserialized to null");
                            }
                        }
                        catch (JsonException jsonEx)
                        {
                            _logger.LogError(jsonEx, "[GreetingConsumer] Failed to deserialize message from output queue. Message body: {messageBody}", messageBody);
                            await receiver.DeadLetterMessageAsync(receivedMessage, "DeserializationFailed", jsonEx.Message);
                        }
                    }
                    catch (Exception messageEx)
                    {
                        _logger.LogError(messageEx, "[GreetingConsumer] Error occurred while receiving message from output queue '{outputQueue}'", _outputQueueName);
                        // Continue the loop to try receiving more messages
                    }
                }
            }
            finally
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                try
                {
                    await receiver.CloseAsync(cts.Token);
                }
                catch
                { /* timeout or error on close */ }
                try
                {
                    await client.DisposeAsync();
                }
                catch
                { /* benign */
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[GreetingConsumer] Failed to receive messages from output queue '{outputQueue}'", _outputQueueName);
        }

        // Log the next scheduled timer occurrence
        _logger.LogInformation("[GreetingConsumer] Function Ran. Next timer schedule = {nextSchedule}", timerInfo.ScheduleStatus?.Next);
    }

    /// <summary>
    /// Selects a random greeting template and formats it with the given name.
    /// The generated greeting is also stored in a circular buffer for later retrieval.
    /// </summary>
    /// <param name="name">The name to include in the greeting.</param>
    /// <returns>A randomly chosen greeting string addressed to the specified name.</returns>
    private static string GetGreeting(string name)
    {
        var template = _greetingTemplates[_random.Next(_greetingTemplates.Length)];
        var greeting = string.Format(template, name);

        lock (_historyLock)
        {
            _handlerSent.Add(greeting);
        }

        return greeting;
    }

    /// <summary>
    /// HTTP-triggered function that returns the most recent greetings from the circular buffer.
    /// Greetings are returned in reverse chronological order (newest first).
    /// </summary>
    /// <param name="request">The incoming HTTP request.</param>
    /// <param name="count">The number of greetings to return (default: 20, max: 100).</param>
    /// <returns>An HTTP response containing a JSON array of recent greetings.</returns>
    [Function("GetGreetings")]
    public async Task<HttpResponseData> GetGreetingsAsync(
        [HttpTrigger(AuthorizationLevel.Function, "get", Route = "greetings")] HttpRequestData request,
        int count = 20)
    {
        _logger.LogInformation("[GetGreetings] Retrieving last {count} entries.", count);

        // Clamp count to valid range
        if (count < 1) count = 1;
        if (count > MaxHistory) count = MaxHistory;

        object history;
        lock (_historyLock)
        {
            history = new
            {
                requester = new
                {
                    sent = _requesterSent.ToArray(count)
                },
                handler = new
                {
                    received = _handlerReceived.ToArray(count),
                    sent = _handlerSent.ToArray(count)
                },
                consumer = new
                {
                    received = _consumerReceived.ToArray(count)
                }
            };
        }

        var response = request.CreateResponse(HttpStatusCode.OK);
        response.Headers.Add("Content-Type", "application/json");
        await response.WriteStringAsync(JsonSerializer.Serialize(history));
        return response;
    }

    private sealed class CircularBuffer
    {
        private readonly string[] _items;
        private int _index;
        private int _count;

        public CircularBuffer(int capacity) => _items = new string[capacity];

        public void Add(string item)
        {
            _items[_index] = item;
            _index = (_index + 1) % _items.Length;
            if (_count < _items.Length) _count++;
        }

        public string[] ToArray(int count)
        {
            var available = Math.Min(count, _count);
            var result = new string[available];
            for (int i = 0; i < available; i++)
            {
                var idx = (_index - available + i + _items.Length) % _items.Length;
                result[i] = _items[idx];
            }
            return result;
        }
    }
}

/// <summary>
/// Represents the input payload for greeting requests.
/// </summary>
public class RequestMessage
{
    /// <summary>
    /// Gets or sets the name to greet.
    /// </summary>
    [JsonPropertyName("name")]
    public required string Name { get; set; }
}

/// <summary>
/// Represents the response payload for greeting requests.
/// </summary>
public class ResponseMessage
{
    /// <summary>
    /// Gets or sets the date of the response message.
    /// </summary>
    [JsonPropertyName("date")]
    public required string Date { get; set; }

    /// <summary>
    /// Gets or sets the text of the response message.
    /// </summary>
    [JsonPropertyName("text")]
    public required string Text { get; set; }
}