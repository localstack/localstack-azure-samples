import os
import io
import datetime
from typing import List, Tuple
from azure.identity import DefaultAzureCredential, ClientSecretCredential
from azure.storage.blob import BlobServiceClient
from azure.core.exceptions import ResourceExistsError
from flask import Flask, render_template, request, redirect, url_for

# Initialize Flask application
app: Flask = Flask(__name__)

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
        print(f"Configuration Error: {ve}")
    except Exception as ex:
        print(f"An error occurred: {ex}")

def get_blob_service_client():
    """Create a BlobServiceClient using the connection string."""
    global connection_string
    try:
        # Create BlobServiceClient
        print(f"Creating BlobServiceClient...")

        if client_id and client_secret and tenant_id and account_url:
            # Use ClientSecretCredential for authentication
            print("Using ClientSecretCredential with BlobServiceClient...")
            credential = ClientSecretCredential(tenant_id=tenant_id, 
                                                client_id=client_id, 
                                                client_secret=client_secret)
            blob_service_client = BlobServiceClient(account_url=account_url, credential=credential)
        elif connection_string:
            # Use connection string for authentication
            print("Using storage account connection string with BlobServiceClient...")
            blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        elif account_url:
            # Use DefaultAzureCredential for authentication
            print("Using DefaultAzureCredential with BlobServiceClient...")
            credential = DefaultAzureCredential()
            blob_service_client = BlobServiceClient(account_url=account_url, credential=credential)
        else:
            raise ValueError("Insufficient configuration for BlobServiceClient. Please set the necessary environment variables.")
        
        print("BlobServiceClient created successfully.")
        return blob_service_client
    except Exception as ex:
        print(f"An error occurred while creating BlobServiceClient: {ex}")
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
        print(f"Creating container client for container: {container_name}")
        container_client = blob_service_client.get_container_client(container_name)

        # Check whether the container exists and create it if it does not
        if not container_client.exists():
            print(f"Attempting to create container '{container_name}' if it does not exist.")
            container_client.create_container()
            print(f"Container '{container_name}' created.")
        else:
            print(f"Container '{container_name}' already exists.")
    except ValueError as ve:
        print(f"Configuration Error: {ve}")
    except ResourceExistsError:
        print(f"Container '{container_name}' already exists.")
    except Exception as ex:
        print(f"An error occurred while creating the container: {ex}")

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
                # Print blob details
                print(f"Found blob: {blob.name} with size {blob.size} bytes")

                # Read blob content
                blob_client = container_client.get_blob_client(blob.name)
                blob_content = blob_client.download_blob().readall()
                if isinstance(blob_content, bytes):
                    blob_content = blob_content.decode('utf-8')
                else:
                    blob_content = str(blob_content)

                print(f"Content of blob '{blob.name}': {blob_content}")
                activities.append((blob.name, blob_content))
    except ValueError as ve:
        print(f"Configuration Error: {ve}")
    except Exception as ex:
        print(f"An error occurred while reading blobs from the container: {ex}")

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
        print(f"Creating blob '{name}' in container '{container_name}'.")
        with io.BytesIO(content.encode("utf-8")) as content_stream:
            blob_client.upload_blob(content_stream, blob_type="BlockBlob", overwrite=True)
        print(f"Blob '{name}' created successfully.")
    except ValueError as ve:
        print(f"Configuration Error: {ve}")
    except ResourceExistsError:
        print(f"Blob '{name}' already exists in container '{container_name}'.")
    except Exception as ex:
        print(f"An error occurred while creating the blob: {ex}")

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
        print(f"Deleting blob '{name}' from container '{container_name}'.")
        blob_client.delete_blob()
        print(f"Blob '{name}' deleted successfully.")
    except ValueError as ve:
        print(f"Configuration Error: {ve}")
    except Exception as ex:
        print(f"An error occurred while deleting the blob: {ex}")

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        activity = request.form.get('activity')
        if activity:
            # Generate a unique blob name with a timestamp
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
            name = f"{timestamp}-activity.txt"

            try:
                # Create a blob with the name provided
                create_blob_if_not_exists(name, activity)

                # Append the activity to the activities list
                activities.append((name, activity))
                
            except Exception as e:
                print(f"Error creating blob: {e}")

        return redirect(url_for('index'))
    
    # Always reload activities from blob storage on GET (refresh)
    activities.clear()
    read_blobs_from_container()
    return render_template('index.html', activities=activities)

@app.route('/delete/<int:activity_id>', methods=['POST'])
def delete(activity_id):
    if 0 <= activity_id < len(activities):
        # Delete the blob associated with the activity
        delete_blob(activities[activity_id][0])

        # Remove the activity from the list
        activities.pop(activity_id)
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
