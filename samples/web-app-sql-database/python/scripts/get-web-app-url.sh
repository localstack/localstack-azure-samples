#!/bin/bash

get_docker_container_name_by_prefix() {
	local app_prefix="$1"
	local container_name

	# Check if Docker is running
	if ! docker info >/dev/null 2>&1; then
		echo "Error: Docker is not running" >&2
		return 1
	fi

	echo "Looking for containers with names starting with [$app_prefix]..." >&2

	# Find the container using grep
	container_name=$(docker ps --format "{{.Names}}" | grep "^${app_prefix}" | head -1)

	if [ -z "$container_name" ]; then
		echo "Error: No running container found with name starting with [$app_prefix]" >&2
		return 1
	fi

	echo "Found matching container [$container_name]" >&2
	echo "$container_name"
}

get_docker_container_ip_address_by_name() {
	local container_name="$1"
	local ip_address

	if [ -z "$container_name" ]; then
		echo "Error: Container name is required" >&2
		return 1
	fi

	# Get IP address
	ip_address=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_name")

	if [ -z "$ip_address" ]; then
		echo "Error: Container [$container_name] has no IP address assigned" >&2
		return 1
	fi

	echo "$ip_address"
}

get_docker_container_port_mapping() {
	local container_name="$1"
	local container_port="$2"
	local host_port

	if [ -z "$container_name" ] || [ -z "$container_port" ]; then
		echo "Error: Container name and container port are required" >&2
		return 1
	fi

	# Get host port mapping
	host_port=$(docker inspect -f "{{(index (index .NetworkSettings.Ports \"${container_port}/tcp\") 0).HostPort}}" "$container_name")

	if [ -z "$host_port" ]; then
		echo "Error: No host port mapping found for container [$container_name] port [$container_port]" >&2
		return 1
	fi

	echo "$host_port"
}

call_web_app() {
	# Get the web app name
	echo "Getting web app name..."
	web_app_name=$(az webapp list --query '[0].name' --output tsv)

	if [ -n "$web_app_name" ]; then
		echo "Web app [$web_app_name] successfully retrieved."
	else
		echo "Error: No web app found"
		exit 1
	fi

	# Get the resource group name
	echo "Getting resource group name for web app [$web_app_name]..."
	resource_group_name=$(az webapp list --query '[0].resourceGroup' --output tsv)

	if [ -n "$resource_group_name" ]; then
		echo "Resource group [$resource_group_name] successfully retrieved."
	else
		echo "Error: No resource group found for web app [$web_app_name]"
		exit 1
	fi

	# Get the the default host name of the web app
	echo "Getting the default host name of the web app [$web_app_name]..."
	app_host_name=$(az webapp show \
		--name "$web_app_name" \
		--resource-group "$resource_group_name" \
		--query 'defaultHostName' \
		--output tsv)

	if [ -n "$app_host_name" ]; then
		echo "Web app default host name [$app_host_name] successfully retrieved."
	else
		echo "Error: No web app default host name found"
		exit 1
	fi

	# Get the Docker container name
	echo "Finding container name with prefix [ls-$web_app_name]..."
	container_name=$(get_docker_container_name_by_prefix "ls-$web_app_name")

	if [ $? -eq 0 ] && [ -n "$container_name" ]; then
		echo "Container [$container_name] found successfully"
	else
		echo "Failed to get container name"
		exit 1
	fi

	# Get the container IP address
	echo "Getting IP address for container [$container_name]..."
	container_ip=$(get_docker_container_ip_address_by_name "$container_name")

	if [ $? -eq 0 ] && [ -n "$container_ip" ]; then
		echo "IP address [$container_ip] retrieved successfully for container [$container_name]"
	else
		echo "Failed to get container IP address"
		exit 1
	fi

	# Get the mapped host port for web app HTTP trigger (internal port 80)
	echo "Getting the host port mapped to internal port 80 in container [$container_name]..."
	host_port=$(get_docker_container_port_mapping "$container_name" "80")
	
	if [ $? -eq 0 ] && [ -n "$host_port" ]; then
		echo "Mapped host port [$host_port] retrieved successfully for container [$container_name]"
	else
		echo "Failed to get mapped host port for container [$container_name]"
		exit 1
	fi

	# Retrieve LocalStack proxy port
	proxy_port=$(curl http://localhost:4566/_localstack/proxy -s | jq '.proxy_port')

	if [ -n "$proxy_port" ]; then
		# Call the web app via emulator proxy
		echo "Calling web app [$web_app_name] via emulator..."
		curl --proxy "http://localhost:$proxy_port/" -s "http://$app_host_name/" 1> /dev/null
		
		if [ $? == 0 ]; then
			echo "Web app call via emulator proxy port [$proxy_port] succeeded."
		else
			echo "Web app call via emulator proxy port [$proxy_port] failed."
		fi
	else
		echo "Failed to retrieve LocalStack proxy port"
	fi
	
	if [ -n "$container_ip" ]; then
		# Call the web app via the container IP address
		echo "Calling web app [$web_app_name] via container IP address [$container_ip]..."
		curl -s "http://$container_ip/" 1> /dev/null

		if [ $? == 0 ]; then
			echo "Web app call via container IP address [$container_ip] succeeded."
		else
			echo "Web app call via container IP address [$container_ip] failed."
		fi
	else
		echo "Failed to retrieve container IP address"
	fi

	if [ -n "$host_port" ]; then
		# Call the web app via the host port
		echo "Calling web app [$web_app_name] via host port [$host_port]..."
		curl -s "http://127.0.0.1:$host_port/" 1> /dev/null

		if [ $? == 0 ]; then
			echo "Web app call via host port [$host_port] succeeded."
		else
			echo "Web app call via host port [$host_port] failed."
		fi
	else
		echo "Failed to retrieve host port"
	fi

	if [ -n "$app_host_name" ]; then
		# Call the web app via the default hostname
		echo "Calling web app [$web_app_name] via default hostname [$app_host_name]..."
		curl -s "http://$app_host_name/" 1> /dev/null

		if [ $? == 0 ]; then
			echo "Web app call via default hostname [$app_host_name] succeeded."
		else
			echo "Web app call via default hostname [$app_host_name] failed."
		fi
	else
		echo "Failed to retrieve web app hostname"
	fi

	echo "Validating certificate from Key Vault..."
	KV_RESPONSE=$(curl -sk "https://$container_ip:8443/api/certificate")
	KV_THUMBPRINT=$(echo "$KV_RESPONSE" | jq -r '.thumbprint')
	KV_NAME=$(echo "$KV_RESPONSE" | jq -r '.name')
	KV_SUBJECT=$(echo "$KV_RESPONSE" | jq -r '.subject')

	SSL_CERT=$(echo | openssl s_client -connect "$container_ip:8443" 2>/dev/null | openssl x509)

	SSL_THUMBPRINT=$(echo "$SSL_CERT" \
		| openssl x509 -fingerprint -noout -sha1 \
		| sed 's/.*=//;s/://g' \
		| tr '[:upper:]' '[:lower:]')

	if [ "$KV_THUMBPRINT" == "$SSL_THUMBPRINT" ]; then
		echo "Certificate [$KV_NAME] validated: SSL cert matches Key Vault cert."
	else
		echo "Certificate mismatch! KV: $KV_THUMBPRINT, SSL: $SSL_THUMBPRINT"
		exit 1
	fi

	SSL_SUBJECT=$(echo "$SSL_CERT" \
		| openssl x509 -noout -subject \
		| sed 's/subject=//')

	if echo "$SSL_SUBJECT" | grep -q "$KV_SUBJECT"; then
		echo "Certificate subject [$KV_SUBJECT] matches SSL certificate."
	else
		echo "Certificate subject mismatch! KV: $KV_SUBJECT, SSL: $SSL_SUBJECT"
		exit 1
	fi
}

call_web_app