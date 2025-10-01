# Azure Functions Methods Documentation

This document describes the Azure Functions implemented in the `GameSessionManager` class, which manages a gaming scoreboard system using various Azure services.

## Overview

The `GameSessionManager` class demonstrates a complete gaming scoreboard system that uses the following triggers and bindings.

### Triggers Used

| Trigger Type | Function | Description |
|-------------|----------|-------------|
| [HttpTrigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-http-webhook-trigger) | `GetPlayerScore` | GET endpoint to retrieve player scores: `/api/player/{gameId}/{name}/status` |
| [HttpTrigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-http-webhook-trigger) | `CreateGameStatus` | POST/PUT endpoint for game status requests: `/api/game/session` |
| [BlobTrigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-blob-trigger) | `ProcessGameFile` | Processes uploaded game files from input container |
| [QueueTrigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-queue-trigger) | `HandleGameEvent` | Processes game events from input queue |
| [QueueTrigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-queue-trigger) | `ProcessScoreboard` | Processes scoreboard data from trigger queue |
| [TimerTrigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-timer) | `CreateGame` | Runs every minute to generate new game rounds |

### Bindings Used

| Binding Type | Usage | Description |
|-------------|-------|-------------|
| [BlobOutput](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-blob-output) | `ProcessGameFile` | Outputs processed game status to output container |
| [QueueOutput](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-queue-output) | `HandleGameEvent` | Sends processed events to output queue |
| [TableInput](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-table-input) | `ProcessScoreboard` | Reads scoreboard entities by game ID |
| [TableOutput](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-table-output) | `ProcessScoreboard` | Writes winner records to winners table |

## Functions

### 1. GetPlayerScore (HTTP GET)

**Function Name:** `GetPlayerScore`  
**Trigger Type:** HTTP GET  
**Route:** `/api/player/{gameId}/{name}/status`

**Description:**  
Retrieves the score and status for a specific player in a specific game session.

**Parameters:**
- `gameId` (int) - The game ID to query
- `name` (string) - The player name to look up

**Returns:**
- HTTP 200: JSON response with PlayerScoreResponse containing player details and score
- HTTP 400: Bad Request if name parameter is missing or invalid
- HTTP 404: Not Found if game/player combination doesn't exist

**Example Response:**
```json
{
  "Date": "2025-09-25T10:30:45",
  "GameId": 1,
  "Name": "Leo",
  "Score": 87
}
```

---

### 2. CreateGameStatus (HTTP POST/PUT)

**Function Name:** `CreateGameStatus`  
**Trigger Type:** HTTP POST/PUT  
**Route:** `/api/game/session`

**Description:**  
Processes game status requests and returns comprehensive game information including winner determination and all player scores.

**Request Body:**
```json
{
  "GameId": 1
}
```

**Returns:**
- HTTP 200: JSON response with GameStatusResponse containing game details, winner, and all players
- HTTP 400: Bad Request if GameId is missing or invalid  
- HTTP 404: Not Found if game doesn't exist

**Example Response:**
```json
{
  "Date": "2025-09-25T10:30:45",
  "GameId": 1,
  "Winner": "Paolo",
  "Players": [
    { "Name": "Paolo", "Score": 95 },
    { "Name": "Leo", "Score": 87 },
    { "Name": "Mia", "Score": 73 }
  ]
}
```

---

### 3. ProcessGameFile (Blob Trigger)

**Function Name:** `ProcessGameFile`  
**Trigger Type:** Blob Trigger  
**Input Container:** `%INPUT_STORAGE_CONTAINER_NAME%`  
**Output Container:** `%OUTPUT_STORAGE_CONTAINER_NAME%`

**Description:**  
Automatically processes uploaded game status files from blob storage, deserializes GameStatusRequest objects, and generates comprehensive GameStatusResponse files in the output container.

**Input:** Blob containing JSON GameStatusRequest  
**Output:** Blob containing JSON GameStatusResponse with winner and player details

**Processing Flow:**
1. Blob uploaded to input container triggers function
2. Deserializes GameStatusRequest from blob content
3. Retrieves game data from internal dictionary
4. Determines winner (highest score)
5. Creates GameStatusResponse blob in output container

---

### 4. HandleGameEvent (Queue Trigger)

**Function Name:** `HandleGameEvent`  
**Trigger Type:** Queue Trigger  
**Input Queue:** `%INPUT_QUEUE_NAME%`  
**Output Queue:** `%OUTPUT_QUEUE_NAME%`

**Description:**  
Processes game events from the input queue, handles GameStatusRequest messages, and generates GameStatusResponse messages for the output queue.

**Input:** Queue message containing Base64-encoded JSON GameStatusRequest  
**Output:** JSON GameStatusResponse message sent to output queue

**Processing Flow:**
1. Message arrives in input queue
2. Deserializes GameStatusRequest from message body
3. Looks up game data in internal dictionary
4. Determines winner and creates response
5. Sends GameStatusResponse to output queue

---

### 5. ProcessScoreboard (Table/Queue Trigger)

**Function Name:** `ProcessScoreboard`  
**Trigger Type:** Queue Trigger with Table Input  
**Input Queue:** `%TRIGGER_QUEUE_NAME%`  
**Input Table:** `%INPUT_TABLE_NAME%`  
**Output Table:** `%OUTPUT_TABLE_NAME%`

**Description:**  
Processes scoreboard data to determine winners. Retrieves all scoreboard entries for a game, finds the highest scoring player, and records the winner in the output table.

**Input:**
- Queue message containing gameId
- Table entities matching the gameId from input table

**Output:** ScoreboardEntity representing the winner stored in output table

**Processing Flow:**
1. Queue message triggers function with gameId
2. Queries input table for all players in that game
3. Identifies player with highest score
4. Creates winner entity in output table

---

### 6. CreateGame (Timer Trigger)

**Function Name:** `CreateGame`  
**Trigger Type:** Timer Trigger  
**Schedule:** Every minute (`0 */1 * * * *`)  
**Run On Startup:** Yes

**Description:**  
Automated function that generates new game rounds with random player data and initiates the complete gaming workflow. This function orchestrates the entire game pipeline.

**Operations Performed:**
1. **Infrastructure Initialization**: Ensures all Azure Storage components are created
2. **Game Data Generation**: Creates random scores for all configured players
3. **Internal Storage**: Stores game data in memory dictionary for fast access
4. **Blob Upload**: Creates GameStatusRequest blob in input container
5. **Queue Messages**: Sends messages to input and trigger queues
6. **Table Entries**: Creates scoreboard entries for all players
7. **Workflow Trigger**: Initiates the complete processing pipeline

**Configuration Dependencies:**
- `PLAYER_NAMES`: Comma-separated list of player names
- `STORAGE_ACCOUNT_CONNECTION_STRING`: Azure Storage connection string
- Various queue/container/table name settings

---

### 7. ServiceBusHello (Service Bus - Commented Out)

**Function Name:** `ServiceBusHello`  
**Trigger Type:** Service Bus Trigger  
**Status:** Currently commented out in code

**Description:**  
Template function for processing Service Bus messages. When enabled, it would process messages from a Service Bus queue and send responses to an output queue.

**Note:** This function is commented out in the current implementation but serves as a reference for Service Bus integration.

---

## Data Models

### PlayerScore
```csharp
{
  string Name;
  int Score;
}
```

### GameStatusRequest
```csharp
{
  int GameId;
}
```

### GameStatusResponse
```csharp
{
  string Date;
  int GameId;
  string Winner;
  List<PlayerScore> Players;
}
```

### PlayerScoreResponse
```csharp
{
  string Date;
  int GameId;  
  string Name;
  int Score;
}
```

### ScoreboardEntity (Table Storage)
```csharp
{
  string PartitionKey;
  string RowKey;
  int GameId;
  string PlayerName;
  int Score;
  DateTimeOffset Timestamp;
  ETag ETag;
}
```

---

## Configuration Settings

The application requires the following environment variables/application settings:

| Setting | Description | Default Value |
|---------|-------------|---------------|
| `STORAGE_ACCOUNT_CONNECTION_STRING` | Azure Storage connection string | Required |
| `INPUT_QUEUE_NAME` | Input queue name | `input` |
| `OUTPUT_QUEUE_NAME` | Output queue name | `output` |
| `TRIGGER_QUEUE_NAME` | Trigger queue name | `trigger` |
| `INPUT_STORAGE_CONTAINER_NAME` | Input blob container | `input` |
| `OUTPUT_STORAGE_CONTAINER_NAME` | Output blob container | `output` |
| `INPUT_TABLE_NAME` | Input table name | `scoreboards` |
| `OUTPUT_TABLE_NAME` | Output table name | `winners` |
| `PLAYER_NAMES` | Comma-separated player names | `Alice,Anastasia,Paolo,Leo,Mia` |

---

## Processing Workflow

1. **Timer triggers CreateGame**: Generates game data and initiates workflow
2. **Blob uploaded**: ProcessGameFile processes the blob
3. **Queue message sent**: HandleGameEvent processes the queue message  
4. **Trigger queue message**: ProcessScoreboard determines winner
5. **HTTP endpoints available**: GetPlayerScore and CreateGameStatus provide API access

This creates a complete gaming system with multiple trigger types and processing patterns demonstrating various Azure Functions capabilities.