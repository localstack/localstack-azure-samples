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

call_http_trigger_functions() {
	# Get the function app name
	echo "Getting function app name..."
	function_app_name=$(azlocal functionapp list --query '[0].name' --output tsv)

	if [ -n "$function_app_name" ]; then
		echo "Function app [$function_app_name] successfully retrieved."
	else
		echo "Error: No function app found"
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

	# Call the GET HTTP trigger function that returns a player status in a specified game session
	echo "Calling HTTP trigger function to retrieve player [$player_name] status in game session [$game_session]..."
	curl -s "http://$container_ip/api/player/$game_session/$player_name/status" | jq

	# Call the POST HTTP trigger function that returns the game session details
	echo "Calling HTTP trigger function to retrieve game session [$game_session] details..."
	curl -s -X POST -H "Content-Type: application/json" -d "{\"gameId\": $game_session}" "http://$container_ip/api/game/session" | jq
}

call_http_trigger_functions