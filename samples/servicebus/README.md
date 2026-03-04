# Azure ServiceBus (Java SDK)

This sample creates a minimal Spring Boot application that sends and receive messages via Azure ServiceBus.

## Overview

 - **`app`**: A folder that contains the Java application
 - **`scripts/deploy.sh`**: One script that provisions the required resources for this sample and runs the application
 
## Quick Start 

To deploy the scenario against a LocalStack Emulator:
```bash
bash ./scripts/deploy.sh
```

The script will:
   1. Creates a ResourceGroup
   2. Creates a Servicebus Namespace
   3. Creates a Servicebus Queue
   4. Starts the Java app
 
 The app then:
 1. Connects to the configured ServiceBus
 2. Sends a message to a queue
 3. Receives the message, and shuts down the application
 
 After the application has shutdown, the script will then:
   5. Deletes the resource group with all of it's resources
   
 
