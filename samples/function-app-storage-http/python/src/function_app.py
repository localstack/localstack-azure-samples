"""A gaming scoreboard built with Azure Functions: game sessions, player scores and winners.

Every minute a timer creates a game with a random score for each player, keeps it in memory, writes a scoreboard entry
for each player to Table Storage, uploads the game as a blob, and sends it to two queues. Each storage trigger then
determines the winner of the game in its own way, and two HTTP functions answer for a player's score and for a game's
status:

* ``GetPlayerScore`` (HTTP GET ``/api/player/{gameId}/{name}/status``): the score of a player in a game;
* ``CreateGameStatus`` (HTTP POST or PUT ``/api/game/session``): the status of a game, with its winner;
* ``ProcessGameFile`` (blob trigger on the input container, blob output to the output container): the status of the
  game a blob names;
* ``HandleGameEvent`` (queue trigger on the input queue, queue output to the output queue): the status of the game a
  message names;
* ``ProcessScoreboard`` (queue trigger on the trigger queue, table input from the scoreboards table, table output to
  the winners table): the winner among the scoreboard entries of a game;
* ``CreateGame`` (timer trigger, every minute and at startup): a new game.

The games live in a dictionary of the worker process, so the functions that read them answer only for the games the
same process created.
"""

import json
import logging
import os
import random
import threading
import uuid
from datetime import UTC, datetime

import azure.functions as func
from azure.core.exceptions import ResourceExistsError
from azure.data.tables import TableServiceClient
from azure.storage.blob import BlobServiceClient
from azure.storage.queue import QueueClient, TextBase64EncodePolicy
from opentelemetry import metrics

# The logger of the functions. With the APPLICATIONINSIGHTS_CONNECTION_STRING app setting, telemetryMode set to
# OpenTelemetry in host.json and PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY set to true, the Python worker sends to
# Application Insights the records of the logger that PYTHON_APPLICATIONINSIGHTS_LOGGER_NAME names (traces), the
# exceptions it logs, the custom events and the custom metric below.
LOGGER_NAME = "function_app"
logger = logging.getLogger(LOGGER_NAME)
logger.setLevel(logging.INFO)

# The custom metric: the number of games whose winner a function determined, by the source of the request (http,
# blob, queue, table) (customMetrics table)
games_completed = metrics.get_meter(LOGGER_NAME).create_counter(
    "games_completed",
    unit="{game}",
    description="The number of games whose winner a function determined, by the source of the request.",
)

# The connection of the storage triggers and bindings, and the names of the queues, containers and tables, which the
# bindings resolve by name (%NAME%)
CONNECTION = "STORAGE_ACCOUNT_CONNECTION_STRING"
INPUT_QUEUE_NAME = os.environ.get("INPUT_QUEUE_NAME", "input")
OUTPUT_QUEUE_NAME = os.environ.get("OUTPUT_QUEUE_NAME", "output")
TRIGGER_QUEUE_NAME = os.environ.get("TRIGGER_QUEUE_NAME", "trigger")
INPUT_CONTAINER_NAME = os.environ.get("INPUT_STORAGE_CONTAINER_NAME", "input")
OUTPUT_CONTAINER_NAME = os.environ.get("OUTPUT_STORAGE_CONTAINER_NAME", "output")
INPUT_TABLE_NAME = os.environ.get("INPUT_TABLE_NAME", "scoreboards")
OUTPUT_TABLE_NAME = os.environ.get("OUTPUT_TABLE_NAME", "winners")
DEFAULT_PLAYER_NAMES = ["Alice", "Anastasia", "Paolo", "Leo", "Mia"]

# The games of this process: game id -> list of {"name", "score"}
_games: dict[int, list[dict]] = {}
_games_lock = threading.Lock()
_next_game_id = 1
_infrastructure_ready = False
_infrastructure_lock = threading.Lock()

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


def _now() -> str:
    """The time of a response, as the .NET sample formats it."""
    return datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def _player_names() -> list[str]:
    names = [name.strip() for name in os.environ.get("PLAYER_NAMES", "").split(",") if name.strip()]
    if not names:
        logger.warning("[CreateGame] PLAYER_NAMES is missing or empty: using the default names.")
        return DEFAULT_PLAYER_NAMES
    return names


def _game_status(game_id: int, source: str) -> dict | None:
    """The status of a game, with its winner, or None when this process doesn't know the game; counts the game as
    completed by ``source`` and sends the GameWinnerDetermined custom event."""
    with _games_lock:
        players = list(_games.get(game_id) or [])
    if not players:
        logger.warning("[%s] Game %d not found in the internal data store.", source, game_id)
        return None
    winner = max(players, key=lambda player: player["score"])
    track_winner_determined(source, game_id, winner["name"])
    return {"date": _now(), "gameId": game_id, "winner": winner["name"], "players": players}


def track_game_created(game_id: int) -> None:
    """Send the GameCreated custom event (customEvents table)."""
    # The worker sends a log record that carries the microsoft.custom_event.name attribute as a custom event named after
    # its value, with the other attributes as its custom dimensions
    logger.info(f"GameCreated: {game_id}", extra={"microsoft.custom_event.name": "GameCreated", "game.id": game_id})


def track_winner_determined(source: str, game_id: int, winner: str) -> None:
    """Send the GameWinnerDetermined custom event and count the game in the custom metric."""
    logger.info(
        f"GameWinnerDetermined: {game_id}",
        extra={
            "microsoft.custom_event.name": "GameWinnerDetermined",
            "game.id": game_id,
            "game.winner": winner,
            "game.source": source,
        },
    )
    games_completed.add(1, {"source": source})


def _game_id_of(body: str | bytes, source: str) -> int | None:
    """The gameId of a GameStatusRequest, or None when the body is not one."""
    try:
        request = json.loads(body)
        game_id = int(request["gameId"])
    except (TypeError, ValueError, KeyError):
        logger.warning("[%s] The body is not a GameStatusRequest.", source)
        return None
    return game_id if game_id > 0 else None


@app.function_name(name="GetPlayerScore")
@app.route(route="player/{gameId}/{name}/status", methods=["GET"])
def get_player_score(req: func.HttpRequest) -> func.HttpResponse:
    """The score of a player in a game of this process."""
    game_id = req.route_params.get("gameId", "")
    name = req.route_params.get("name", "")
    logger.info("[GetPlayerScore] Received GET request with gameId = %s, name = %s.", game_id, name)
    if not game_id.isdigit() or not name.strip():
        logger.warning("[GetPlayerScore] Invalid parameters: gameId = %s, name = %s.", game_id, name)
        return func.HttpResponse("Invalid parameters: gameId and name are required.", status_code=400)
    with _games_lock:
        players = list(_games.get(int(game_id)) or [])
    player = next((player for player in players if player["name"].lower() == name.lower()), None)
    if player is None:
        logger.warning("[GetPlayerScore] Player not found: game %s, player %s.", game_id, name)
        return func.HttpResponse(f"Game {game_id} and player '{name}' tuple not found.", status_code=404)
    logger.info(
        "[GetPlayerScore] Processed request with gameId = %s, name = %s, score = %d.", game_id, name, player["score"]
    )
    body = {"date": _now(), "gameId": int(game_id), "name": player["name"], "score": player["score"]}
    return func.HttpResponse(json.dumps(body), status_code=200, mimetype="application/json")


@app.function_name(name="CreateGameStatus")
@app.route(route="game/session", methods=["POST", "PUT"])
def create_game_status(req: func.HttpRequest) -> func.HttpResponse:
    """The status of the game a GameStatusRequest names, with its winner."""
    logger.info("[CreateGameStatus] Received %s request.", req.method)
    body = req.get_body()
    if not body or not body.strip():
        logger.warning("[CreateGameStatus] The request has no body.")
        return func.HttpResponse(
            "[CreateGameStatus] Invalid request message: Request body is required.", status_code=400
        )
    game_id = _game_id_of(body, "CreateGameStatus")
    if game_id is None:
        return func.HttpResponse(
            "[CreateGameStatus] Invalid request message: 'gameId' is required and must be greater than 0.",
            status_code=400,
        )
    status = _game_status(game_id, "http")
    if status is None:
        return func.HttpResponse(f"Game {game_id} not found.", status_code=404)
    logger.info("[CreateGameStatus] Processed request with gameId = %d, winner = %s.", game_id, status["winner"])
    return func.HttpResponse(json.dumps(status), status_code=200, mimetype="application/json")


@app.function_name(name="ProcessGameFile")
@app.blob_trigger(arg_name="blob", path="%INPUT_STORAGE_CONTAINER_NAME%/{name}", connection=CONNECTION)
@app.blob_output(arg_name="output", path="%OUTPUT_STORAGE_CONTAINER_NAME%/{name}", connection=CONNECTION)
def process_game_file(blob: func.InputStream, output: func.Out[str]) -> None:
    """The status of the game an uploaded blob names, written to a blob of the same name in the output container."""
    content = blob.read()
    if not content:
        logger.warning("[ProcessGameFile] The [%s] blob is empty.", blob.name)
        return
    game_id = _game_id_of(content, "ProcessGameFile")
    if game_id is None:
        return
    status = _game_status(game_id, "blob")
    if status is None:
        return
    output.set(json.dumps(status))
    logger.info("[ProcessGameFile] Processed the [%s] blob for game %d.", blob.name, game_id)


@app.function_name(name="HandleGameEvent")
@app.queue_trigger(arg_name="message", queue_name="%INPUT_QUEUE_NAME%", connection=CONNECTION)
@app.queue_output(arg_name="output", queue_name="%OUTPUT_QUEUE_NAME%", connection=CONNECTION)
def handle_game_event(message: func.QueueMessage, output: func.Out[str]) -> None:
    """The status of the game a queue message names, sent to the output queue."""
    game_id = _game_id_of(message.get_body(), "HandleGameEvent")
    if game_id is None:
        return
    status = _game_status(game_id, "queue")
    if status is None:
        return
    output.set(json.dumps(status))
    logger.info("[HandleGameEvent] Processed the [%s] queue message for game %d.", message.id, game_id)


@app.function_name(name="ProcessScoreboard")
# The trigger queue is read through the storage account of the Functions host (AzureWebJobsStorage), as in the .NET
# sample, whose trigger names no connection
@app.queue_trigger(arg_name="game_id", queue_name="%TRIGGER_QUEUE_NAME%", connection="AzureWebJobsStorage")
@app.table_input(
    arg_name="entities", table_name="%INPUT_TABLE_NAME%", partition_key="{queueTrigger}", connection=CONNECTION
)
@app.table_output(arg_name="winner", table_name="%OUTPUT_TABLE_NAME%", connection=CONNECTION)
def process_scoreboard(game_id: func.QueueMessage, entities: str, winner: func.Out[str]) -> None:
    """The winner among the scoreboard entries of a game, written to the winners table."""
    game = game_id.get_body().decode("utf-8").strip()
    rows = json.loads(entities) if entities else []
    best = max(rows, key=lambda row: int(row.get("Score", 0)), default=None)
    if best is None:
        logger.info("[ProcessScoreboard] Processed game ID %s. Winner: No winner with score N/A.", game)
        return
    logger.info(
        "[ProcessScoreboard] Processed game ID %s. Winner: %s with score %s.",
        game,
        best.get("PlayerName"),
        best.get("Score"),
    )
    track_winner_determined("table", int(best.get("GameId", game)), best.get("PlayerName") or "")
    winner.set(
        json.dumps(
            {
                "PartitionKey": f"winner-game-{int(game):03d}",
                "RowKey": str(uuid.uuid4()),
                "GameId": int(best.get("GameId", game)),
                "PlayerName": best.get("PlayerName"),
                "Score": int(best.get("Score", 0)),
            }
        )
    )


def _ensure_infrastructure(connection_string: str) -> None:
    """Create the queues, the containers and the tables of the sample once per process."""
    global _infrastructure_ready
    with _infrastructure_lock:
        if _infrastructure_ready:
            return
        blob_service = BlobServiceClient.from_connection_string(connection_string)
        for container in (INPUT_CONTAINER_NAME, OUTPUT_CONTAINER_NAME):
            try:
                blob_service.create_container(container)
            except ResourceExistsError:
                logger.info("[CreateGame] The [%s] container already exists.", container)
        for queue in (INPUT_QUEUE_NAME, OUTPUT_QUEUE_NAME, TRIGGER_QUEUE_NAME):
            try:
                QueueClient.from_connection_string(connection_string, queue).create_queue()
            except ResourceExistsError:
                logger.info("[CreateGame] The [%s] queue already exists.", queue)
        table_service = TableServiceClient.from_connection_string(connection_string)
        for table in (INPUT_TABLE_NAME, OUTPUT_TABLE_NAME):
            table_service.create_table_if_not_exists(table)
        _infrastructure_ready = True
        logger.info("[CreateGame] Created the queues, the containers and the tables.")


@app.function_name(name="CreateGame")
@app.timer_trigger(arg_name="timer", schedule="0 */1 * * * *", run_on_startup=True)
@app.retry(strategy="fixed_delay", max_retry_count="5", delay_interval="00:00:10")
def create_game(timer: func.TimerRequest) -> None:
    """A new game: a random score for each player, kept in memory and written to the scoreboards table, then the game
    uploaded as a blob and sent to the input and trigger queues."""
    global _next_game_id
    connection_string = os.environ.get(CONNECTION)
    if not connection_string:
        logger.error("[CreateGame] %s is missing: no game created.", CONNECTION)
        return
    _ensure_infrastructure(connection_string)
    with _games_lock:
        game_id = _next_game_id
        _next_game_id += 1
    players = [{"name": name, "score": random.randint(0, 100)} for name in _player_names()]

    table = TableServiceClient.from_connection_string(connection_string).get_table_client(INPUT_TABLE_NAME)
    for player in players:
        table.create_entity(
            {
                "PartitionKey": str(game_id),
                "RowKey": str(uuid.uuid4()),
                "GameId": game_id,
                "PlayerName": player["name"],
                "Score": player["score"],
            }
        )
    with _games_lock:
        _games[game_id] = players
    logger.info("[CreateGame] Created %d scoreboard entries for game %d.", len(players), game_id)

    message = json.dumps({"gameId": game_id})
    blob_name = f"game-{game_id:03d}-status-{datetime.now(UTC).strftime('%Y-%m-%d-%H-%M-%S')}.json"
    blob_service = BlobServiceClient.from_connection_string(connection_string)
    blob_service.get_blob_client(INPUT_CONTAINER_NAME, blob_name).upload_blob(message, overwrite=True)
    logger.info("[CreateGame] Uploaded the [%s] blob to the [%s] container.", blob_name, INPUT_CONTAINER_NAME)
    # The queue triggers expect base64-encoded messages, as the Functions host writes them
    for queue, body in ((INPUT_QUEUE_NAME, message), (TRIGGER_QUEUE_NAME, str(game_id))):
        QueueClient.from_connection_string(
            connection_string, queue, message_encode_policy=TextBase64EncodePolicy()
        ).send_message(body)
        logger.info("[CreateGame] Sent game %d to the [%s] queue.", game_id, queue)
    track_game_created(game_id)
    if timer.past_due:
        logger.info("[CreateGame] The timer is past due.")
