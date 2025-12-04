import logging
import os

import azure.functions as func

logging.basicConfig(level=logging.INFO)

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
    except Exception:
        logging.exception("Failed to process blob %s", input_blob.name)
        raise
