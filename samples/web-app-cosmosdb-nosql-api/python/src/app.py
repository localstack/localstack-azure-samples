import os
import datetime
import logging
import hashlib
from flask import Flask, render_template, request, redirect, url_for
from cosmosdb_client import CosmosDbClient


app = Flask(__name__)
app.debug = True

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

logger.info("Loading app")

cosmos_client = None
activities = None

username = os.environ.get("LOGIN_NAME", "alex")
if not username.strip():
    raise ValueError("Username cannot be empty")

def get_activities():
    global activities
    if activities is None:
        logger.info("Initializing Activities data structure")
        activities = set()
    return activities

def get_cosmos():
    global cosmos_client
    if cosmos_client is None:
        logger.info("Initializing Cosmos client")
        cosmos_client = CosmosDbClient.from_env()
    return cosmos_client

def create_document(activity: str) -> dict:
    get_cosmos().ensure_initialized()
    
    timestamp = datetime.datetime.now().isoformat()
    id_string = f"{username}_{activity}_{timestamp}"
    document_id = hashlib.md5(id_string.encode()).hexdigest()

    return {
        "id": document_id,
        "username": username,
        "activity": activity,
        "timestamp": timestamp
    }

def read_documents(username: str):
    get_cosmos().ensure_initialized()
    get_activities().clear()

    try:
        docs = get_cosmos().read_documents(username)
        for d in docs:
            get_activities().add((d["id"], d["activity"]))
        return docs
    except Exception as e:
        logger.error(f"Cosmos read failed: {e}")
        return []


@app.route('/', methods=['GET', 'POST'])
def index():
    edit_id = request.args.get('edit_id')
    edit_activity = request.args.get('edit_activity')

    if request.method == 'POST':
        activity = request.form.get('activity')
        row_id = request.form.get('row_id')

        if activity:
            if row_id:
                get_cosmos().update_document_by_id(
                    doc_id=row_id,
                    username=username,
                    updates={"activity": activity}
                )
            else:
                doc = create_document(activity)
                get_cosmos().insert_document(doc)
                get_activities().add((doc["id"], activity))

        return redirect(url_for('index'))
    
    read_documents(username)
    
    return render_template(
        'index.html',
        activities=get_activities(),
        username=username,
        edit_id=edit_id,
        edit_activity=edit_activity
    )

@app.route('/delete/<string:activity_id>', methods=['POST'])
def delete(activity_id: str):
    logger.info(f"Deleting activity with ID: {activity_id}")
    
    # Direct deletion using the ID passed in the URL
    get_cosmos().delete_document_by_id(activity_id, username)
    
    return redirect(url_for('index'))

@app.route('/edit/<string:activity_id>', methods=['POST'])
def edit(activity_id: str):
    new_text = request.form.get('new_text')
    
    if new_text:
        logger.info(f"Updating ID {activity_id} with activity: {new_text}")
        get_cosmos().update_document_activity(activity_id, username, new_text) 
        
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(debug=True)
