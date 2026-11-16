import logging
import os

import azure.functions as func
from opentelemetry import metrics

logging.basicConfig(level=logging.INFO)

# The Azure SDK clients, the OpenTelemetry exporter's among them, log each of their HTTP requests, and urllib3 each of
# its connections: their warnings are enough, so that the traces hold the records of the function rather than the
# exporter's own calls to Application Insights
logging.getLogger("azure").setLevel(logging.WARNING)
logging.getLogger("urllib3").setLevel(logging.WARNING)

# With the APPLICATIONINSIGHTS_CONNECTION_STRING app setting, telemetryMode set to OpenTelemetry in host.json and
# PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY set to true, the Python worker sends to Application Insights the log
# records of the function (traces), the exceptions it logs, the custom event and the custom metric below.
processed_blobs = metrics.get_meter("function_app").create_counter(
    "processed_blobs", unit="{blob}", description="The number of blobs the function processed."
)

app = func.FunctionApp()

@app.function_name(name="ProcessTextFunction")
@app.blob_trigger(arg_name="input_blob",
                  path="%INPUT_STORAGE_CONTAINER_NAME%/{name}",
                  connection="STORAGE_ACCOUNT_CONNECTION_STRING",
                  source=func.BlobSource.LOGS_AND_CONTAINER_SCAN)
@app.blob_output(arg_name="output_blob",
                 path="%OUTPUT_STORAGE_CONTAINER_NAME%/{name}",
                 connection="STORAGE_ACCOUNT_CONNECTION_STRING")
def ProcessTextFunction(input_blob: func.InputStream, output_blob: func.Out[str]):
    """
    This function is triggered when a new text file is uploaded to the input blob container.
    It reads the content of the text file, processes it (converts to uppercase),
    and writes the processed content to the output blob container.
    """
    output_container = os.environ.get("OUTPUT_STORAGE_CONTAINER_NAME", "output")

    logging.info(
        "Blob trigger function picked up blob",
        extra={
            "blob_name": input_blob.name,
            "blob_size": input_blob.length,
            "target_container": output_container
        }
    )

    try:
        # Read the blob content (text file)
        text = input_blob.read().decode('utf-8')

        # Process the text (convert to uppercase)
        processed_text = text.upper()

        # Write the processed text to the output blob
        output_blob.set(processed_text)
        logging.info("Text processed and saved successfully.")

        # A custom event (customEvents table): the worker sends a log record that carries the
        # microsoft.custom_event.name attribute as a custom event named after its value, with the other attributes as
        # its custom dimensions
        logging.info(
            "BlobProcessed: %s",
            input_blob.name,
            extra={
                "microsoft.custom_event.name": "BlobProcessed",
                "blob.name": input_blob.name,
                "blob.size": input_blob.length or 0,
            },
        )
        # The custom metric (customMetrics table)
        processed_blobs.add(1, {"container": output_container})
    except Exception:
        logging.exception("Failed to process blob %s", input_blob.name)
        raise
