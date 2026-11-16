import os
import io
import sys
import datetime
import logging
from typing import List, Tuple
from microsoft.opentelemetry import use_microsoft_opentelemetry

# The logger of the application
LOGGER_NAME = "webapp"

# When App Service passes the connection string of the Application Insights resource, the Microsoft OpenTelemetry
# Distro sends to Application Insights the requests the app serves, its calls to Blob Storage, and the records of the
# application's logger. It runs before Flask is imported, so that its Flask instrumentation wraps the application.
if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    use_microsoft_opentelemetry(enable_azure_monitor=True, logger_name=LOGGER_NAME)

from azure.identity import DefaultAzureCredential, ClientSecretCredential
from azure.storage.blob import BlobServiceClient
from azure.core.exceptions import ResourceExistsError
from flask import Flask, flash, render_template, request, redirect, url_for

# The application's logger also writes its records to the console, which App Service collects as the container's output
logger = logging.getLogger(LOGGER_NAME)
logger.setLevel(logging.INFO)
logger.addHandler(logging.StreamHandler(sys.stdout))

# Initialize Flask application
app: Flask = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", os.urandom(24))

client_id: str | None
client_secret: str | None
tenant_id: str | None

connection_string: str | None = None
account_url: str | None = None
container_name: str | None = None
blob_service_client: BlobServiceClient | None = None

debug: bool = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
activities: List[Tuple[str, str]] = []

def get_environment_variables():
    """Get the value of an environment variable or raise an error if not set."""
    global connection_string, container_name, client_id, client_secret, tenant_id, account_url
    try:
        # Get Azure credentials from environment variables
        client_id = os.environ.get("AZURE_CLIENT_ID")
        client_secret = os.environ.get("AZURE_CLIENT_SECRET")
        tenant_id = os.environ.get("AZURE_TENANT_ID")

        # Get connection string from environment variable
        connection_string = os.environ.get("AZURE_STORAGE_ACCOUNT_CONNECTION_STRING")
        account_url = os.environ.get("AZURE_STORAGE_ACCOUNT_URL")

        # Get container name from environment variable with a default value
        container_name = os.environ.get("CONTAINER_NAME", "activities")
    except ValueError as ve:
        logger.error(f"Configuration Error: {ve}")
    except Exception as ex:
        logger.error(f"An error occurred: {ex}")

def get_blob_service_client():
    """Create a BlobServiceClient using the connection string."""
    global connection_string
    try:
        # Create BlobServiceClient
        logger.info(f"Creating BlobServiceClient...")

        if client_id and client_secret and tenant_id and account_url:
            # Use ClientSecretCredential for authentication
            logger.info("Using ClientSecretCredential with BlobServiceClient...")
            credential = ClientSecretCredential(tenant_id=tenant_id, 
                                                client_id=client_id, 
                                                client_secret=client_secret)
            blob_service_client = BlobServiceClient(account_url=account_url, credential=credential)
        elif connection_string:
            # Use connection string for authentication
            logger.info("Using storage account connection string with BlobServiceClient...")
            blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        elif account_url:
            # Use DefaultAzureCredential for authentication
            logger.info("Using DefaultAzureCredential with BlobServiceClient...")
            credential = DefaultAzureCredential()
            blob_service_client = BlobServiceClient(account_url=account_url, credential=credential)
        else:
            raise ValueError("Insufficient configuration for BlobServiceClient. Please set the necessary environment variables.")
        
        logger.info("BlobServiceClient created successfully.")
        return blob_service_client
    except Exception as ex:
        logger.error(f"An error occurred while creating BlobServiceClient: {ex}")
        return None

def create_container_if_not_exists():
    """Create a container if it does not already exist."""
    global blob_service_client, container_name
    try:
        if not blob_service_client:
            raise ValueError("BlobServiceClient is not initialized. Please call get_blob_service_client() first.")

        # Create a ContainerClient
        if not container_name:
            raise ValueError("Container name is not set. Please set the CONTAINER_NAME environment variable.")

        # Get the container client
        logger.info(f"Creating container client for container: {container_name}")
        container_client = blob_service_client.get_container_client(container_name)

        # Check whether the container exists and create it if it does not
        if not container_client.exists():
            logger.info(f"Attempting to create container '{container_name}' if it does not exist.")
            container_client.create_container()
            logger.info(f"Container '{container_name}' created.")
        else:
            logger.info(f"Container '{container_name}' already exists.")
    except ValueError as ve:
        logger.error(f"Configuration Error: {ve}")
    except ResourceExistsError:
        logger.info(f"Container '{container_name}' already exists.")
    except Exception as ex:
        logger.error(f"An error occurred while creating the container: {ex}")

def read_blobs_from_container():
    """Read all blobs from the container."""
    global blob_service_client, container_name, activities
    try:
        if not blob_service_client:
            raise ValueError("BlobServiceClient is not initialized. Please call get_blob_service_client() first.")

        if not container_name:
            raise ValueError("Container name is not set. Please set the CONTAINER_NAME environment variable.")

        # Get the container client
        container_client = blob_service_client.get_container_client(container_name)

        # List all blobs in the container
        blob_list = container_client.list_blobs()

        for blob in blob_list:
            if blob.name:
                # Log blob details
                logger.info(f"Found blob: {blob.name} with size {blob.size} bytes")

                # Read blob content
                blob_client = container_client.get_blob_client(blob.name)
                blob_content = blob_client.download_blob().readall()
                if isinstance(blob_content, bytes):
                    blob_content = blob_content.decode('utf-8')
                else:
                    blob_content = str(blob_content)

                logger.info(f"Content of blob '{blob.name}': {blob_content}")
                activities.append((blob.name, blob_content))

        logger.info(f"Read {len(activities)} activities from container '{container_name}'.")
    except ValueError as ve:
        logger.error(f"Configuration Error: {ve}")
    except Exception as ex:
        logger.error(f"An error occurred while reading blobs from the container: {ex}")

def create_blob_if_not_exists(name: str | None, content: str | None):
    """Create a blob in the container if it does not already exist."""
    global blob_service_client, container_name

    # Check if name and content are provided
    if not name or not content:
        raise ValueError("Both 'name' and 'content' must be provided to create a blob.")
    
    try:
        if not blob_service_client:
            raise ValueError("BlobServiceClient is not initialized. Please call get_blob_service_client() first.")

        if not container_name:
            raise ValueError("Container name is not set. Please set the CONTAINER_NAME environment variable.")

        # Get the container client
        container_client = blob_service_client.get_container_client(container_name)

        # Create a blob client
        blob_client = container_client.get_blob_client(name)

        # Check if the blob exists and create it if it does not
        logger.info(f"Creating blob '{name}' in container '{container_name}'.")
        with io.BytesIO(content.encode("utf-8")) as content_stream:
            blob_client.upload_blob(content_stream, blob_type="BlockBlob", overwrite=True)
        logger.info(f"Blob '{name}' created successfully.")
    except ValueError as ve:
        logger.error(f"Configuration Error: {ve}")
    except ResourceExistsError:
        logger.info(f"Blob '{name}' already exists in container '{container_name}'.")
    except Exception as ex:
        logger.error(f"An error occurred while creating the blob: {ex}")

def delete_blob(name: str):
    """Delete a blob from the container."""
    global blob_service_client, container_name
    try:
        if not blob_service_client:
            raise ValueError("BlobServiceClient is not initialized. Please call get_blob_service_client() first.")

        if not container_name:
            raise ValueError("Container name is not set. Please set the CONTAINER_NAME environment variable.")

        # Get the container client
        container_client = blob_service_client.get_container_client(container_name)

        # Create a blob client
        blob_client = container_client.get_blob_client(name)

        # Delete the blob
        logger.info(f"Deleting blob '{name}' from container '{container_name}'.")
        blob_client.delete_blob()
        logger.info(f"Blob '{name}' deleted successfully.")
    except ValueError as ve:
        logger.error(f"Configuration Error: {ve}")
    except Exception as ex:
        logger.error(f"An error occurred while deleting the blob: {ex}")

def update_blob(name: str, content: str):
    """Update the content of an existing blob (overwrite in place)."""
    global blob_service_client, container_name
    if not name or not content:
        raise ValueError("Both 'name' and 'content' must be provided.")
    try:
        if not blob_service_client:
            raise ValueError("BlobServiceClient is not initialized.")
        if not container_name:
            raise ValueError("Container name is not set.")
        container_client = blob_service_client.get_container_client(container_name)
        blob_client = container_client.get_blob_client(name)
        logger.info(f"Updating blob '{name}' in container '{container_name}'.")
        with io.BytesIO(content.encode("utf-8")) as content_stream:
            blob_client.upload_blob(content_stream, blob_type="BlockBlob", overwrite=True)
        logger.info(f"Blob '{name}' updated successfully.")
    except ValueError as ve:
        logger.error(f"Configuration Error: {ve}")
    except Exception as ex:
        logger.error(f"An error occurred while updating the blob: {ex}")

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        row_id = request.form.get('row_id', '').strip()
        activity = request.form.get('activity', '').strip()
        if activity:
            if row_id:
                # Update existing blob content in place
                update_blob(row_id, activity)
                for i, act in enumerate(activities):
                    if act[0] == row_id:
                        activities[i] = (row_id, activity)
                        break
                flash('Activity updated successfully.')
            else:
                # Generate a unique blob name with a timestamp
                timestamp = datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
                name = f"{timestamp}-activity.txt"
                create_blob_if_not_exists(name, activity)
                activities.append((name, activity))
                flash('Activity added successfully.')
        return redirect(url_for('index'))

    # Always reload activities from blob storage on GET
    activities.clear()
    read_blobs_from_container()
    return render_template('index.html', activities=activities)

@app.route('/delete/<int:activity_id>', methods=['POST'])
def delete(activity_id):
    if 0 <= activity_id < len(activities):
        delete_blob(activities[activity_id][0])
        activities.pop(activity_id)
        flash('Activity deleted successfully.')
    return redirect(url_for('index'))

# Initialize the application and Azure services when the module is loaded.
# This ensures that the setup runs regardless of how the app is started (e.g., via 'flask run' or directly).
get_environment_variables()
blob_service_client = get_blob_service_client()
if blob_service_client:
    # Create the container if it does not exist
    create_container_if_not_exists()

    # Read existing blobs from the container, if any
    read_blobs_from_container()

if __name__ == '__main__':
    app.run(debug=True)
