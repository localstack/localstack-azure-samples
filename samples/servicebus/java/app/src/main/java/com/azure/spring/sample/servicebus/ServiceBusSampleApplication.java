// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
package com.azure.spring.sample.servicebus;

import com.azure.spring.messaging.servicebus.implementation.core.annotation.ServiceBusListener;
import org.springframework.stereotype.Component;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusSenderClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ServiceBusSampleApplication {

    private static final Logger LOGGER = LoggerFactory.getLogger(ServiceBusSampleApplication.class);
    public static void main(String[] args) {
        SpringApplication.run(ServiceBusSampleApplication.class, args);
        sendMessage();
    }

    static void sendMessage()
    {
        String connectionString = System.getenv("AZURE_SERVICEBUS_CONNECTION_STRING");
        String queueName = "myqueue";

        // create a Service Bus Sender client for the queue
        ServiceBusSenderClient senderClient = new ServiceBusClientBuilder()
                .connectionString(connectionString)
                .sender()
                .queueName(queueName)
                .buildClient();

        // send one message to the queue
        senderClient.sendMessage(new ServiceBusMessage("Hello, World!"));
        LOGGER.info("Sent a single message to the queue: " + queueName);
    }
}

@Component
class ServiceBusMessageListener {

    private static final Logger LOGGER = LoggerFactory.getLogger(ServiceBusMessageListener.class);

    @ServiceBusListener(destination = "myqueue")
    public void receiveMessage(String message) {
        LOGGER.info("Received message from Azure Service Bus: " + message);
        System.exit(0);
    }
}