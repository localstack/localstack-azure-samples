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

call_http_trigger_functions() {
	# Get the function app name
	echo "Getting function app name..."
	function_app_name=$(az functionapp list --query '[0].name' --output tsv)

	if [ -n "$function_app_name" ]; then
		echo "Function app [$function_app_name] successfully retrieved."
	else
		echo "Error: No function app found"
		exit 1
	fi

	# Get the resource group name
	echo "Getting resource group name for function app [$function_app_name]..."
	resource_group_name=$(az functionapp list --query '[0].resourceGroup' --output tsv)

	if [ -n "$resource_group_name" ]; then
		echo "Resource group [$resource_group_name] successfully retrieved."
	else
		echo "Error: No resource group found for function app [$function_app_name]"
		exit 1
	fi

	# Get the the default host name of the function app
	echo "Getting the default host name of the function app [$function_app_name]..."
	function_host_name=$(az functionapp show \
		--name "$function_app_name" \
		--resource-group "$resource_group_name" \
		--query 'defaultHostName' \
		--output tsv)

	if [ -n "$function_host_name" ]; then
		echo "Function app default host name [$function_host_name] successfully retrieved."
	else
		echo "Error: No function app default host name found"
		exit 1
	fi

	# Get the Docker container name
	echo "Finding container name with prefix [ls-$function_app_name]..."
	container_name=$(get_docker_container_name_by_prefix "ls-$function_app_name")

	if [ $? -eq 0 ] && [ -n "$container_name" ]; then
		echo "Container [$container_name] found successfully"
	else
		echo "Failed to get container name"
		exit 1
	fi

	# Get the container IP address
	echo "Getting IP address for container [$container_name]..."
	container_ip=$(get_docker_container_ip_address_by_name "$container_name")
	player_name='Leo'
	game_session='1'

	if [ $? -eq 0 ] && [ -n "$container_ip" ]; then
		echo "IP address [$container_ip] retrieved successfully for container [$container_name]"
	else
		echo "Failed to get container IP address"
		exit 1
	fi

	# Get the mapped host port for function app HTTP trigger (internal port 80)
	echo "Getting the host port mapped to internal port 80 in container [$container_name]..."
	host_port=$(get_docker_container_port_mapping "$container_name" "80")
	
	if [ $? -eq 0 ] && [ -n "$host_port" ]; then
		echo "Mapped host port [$host_port] retrieved successfully for container [$container_name]"
	else
		echo "Failed to get mapped host port for container [$container_name]"
		exit 1
	fi

	if [ -n "$function_host_name" ]; then
		# Call the GET HTTP trigger function that returns a player status in a specified game session via the function hostname
		echo "Calling HTTP trigger function to retrieve player [$player_name] status in game session [$game_session] via function hostname [$function_host_name]..."
		curl  -s "http://$function_host_name/api/player/$game_session/$player_name/status" | jq

		# Call the POST HTTP trigger function that returns the game session details via the function hostname
		echo "Calling HTTP trigger function to retrieve game session [$game_session] details via function hostname [$function_host_name]..."
		curl -s -X POST -H "Content-Type: application/json" -d "{\"gameId\": $game_session}" "http://$function_host_name/api/game/session" | jq
	else
		echo "Failed to retrieve function hostname"
	fi
	
	if [ -n "$container_ip" ]; then
		# Call the GET HTTP trigger function that returns a player status in a specified game session via the container IP address
		echo "Calling HTTP trigger function to retrieve player [$player_name] status in game session [$game_session] via container IP address [$container_ip]..."
		curl -s "http://$container_ip/api/player/$game_session/$player_name/status" | jq

		# Call the POST HTTP trigger function that returns the game session details via the container IP address
		echo "Calling HTTP trigger function to retrieve game session [$game_session] details via container IP address [$container_ip]..."
		curl -s -X POST -H "Content-Type: application/json" -d "{\"gameId\": $game_session}" "http://$container_ip/api/game/session" | jq
	else
		echo "Failed to retrieve container IP address"
	fi

	if [ -n "$host_port" ]; then
		# Call the GET HTTP trigger function that returns a player status in a specified game session via the host port
		echo "Calling HTTP trigger function to retrieve player [$player_name] status in game session [$game_session] via host port [$host_port]..."
		curl -s "http://localhost:$host_port/api/player/$game_session/$player_name/status" | jq

		# Call the POST HTTP trigger function that returns the game session details via the host port
		echo "Calling HTTP trigger function to retrieve game session [$game_session] details via host port [$host_port]..."
		curl -s -X POST -H "Content-Type: application/json" -d "{\"gameId\": $game_session}" "http://localhost:$host_port/api/game/session" | jq
	else
		echo "Failed to retrieve host port"
	fi
}

call_http_trigger_functions