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

import java.util.UUID;

@SpringBootApplication
public class ServiceBusSampleApplication {

    private static final Logger LOGGER = LoggerFactory.getLogger(ServiceBusSampleApplication.class);
    public static void main(String[] args) {
        SpringApplication.run(ServiceBusSampleApplication.class, args);
        try {
            sendMessage();
        } catch (RuntimeException e) {
            // The listener stops the application when the message arrives: without a sent message it would wait forever
            LOGGER.error("Failed to send the message to the queue", e);
            System.exit(1);
        }
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

        // send one message to the queue, with a message id: a partitioned queue with duplicate detection, which the
        // Terraform configuration creates by default, refuses a message that has neither a message id nor a partition key
        senderClient.sendMessage(new ServiceBusMessage("Hello, World!").setMessageId(UUID.randomUUID().toString()));
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