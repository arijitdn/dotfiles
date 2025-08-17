#!/bin/bash

install_dokploy() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" >&2
        exit 1
    fi

    # Check if running on Mac OS
    if [ "$(uname)" = "Darwin" ]; then
        echo "This script must be run on Linux" >&2
        exit 1
    fi

    # Check if running inside a container
    if [ -f /.dockerenv ]; then
        echo "This script must be run on Linux" >&2
        exit 1
    fi

    # Check if ports 80 or 443 are already in use
    if ss -tulnp | grep ':80 ' >/dev/null; then
        echo "Error: something is already running on port 80" >&2
        exit 1
    fi

    if ss -tulnp | grep ':443 ' >/dev/null; then
        echo "Error: something is already running on port 443" >&2
        exit 1
    fi

    command_exists() {
        command -v "$@" > /dev/null 2>&1
    }

    if command_exists docker; then
        echo "Docker already installed"
    else
        curl -sSL https://get.docker.com | sh
    fi

    docker swarm leave --force 2>/dev/null

    get_ip() {
        local ip=""

        # Try IPv4 first
        ip=$(curl -4s --connect-timeout 5 https://ifconfig.io 2>/dev/null)
        if [ -z "$ip" ]; then
            ip=$(curl -4s --connect-timeout 5 https://icanhazip.com 2>/dev/null)
        fi
        if [ -z "$ip" ]; then
            ip=$(curl -4s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null)
        fi
        # If no IPv4, try IPv6
        if [ -z "$ip" ]; then
            ip=$(curl -6s --connect-timeout 5 https://ifconfig.io 2>/dev/null)
            if [ -z "$ip" ]; then
                ip=$(curl -6s --connect-timeout 5 https://icanhazip.com 2>/dev/null)
            fi
            if [ -z "$ip" ]; then
                ip=$(curl -6s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null)
            fi
        fi

        if [ -z "$ip" ]; then
            echo "Error: Could not determine server IP address automatically (neither IPv4 nor IPv6)." >&2
            echo "Please set the ADVERTISE_ADDR environment variable manually." >&2
            echo "Example: export ADVERTISE_ADDR=<your-server-ip>" >&2
            exit 1
        fi
        echo "$ip"
    }

    advertise_addr="${ADVERTISE_ADDR:-$(get_ip)}"
    echo "Using advertise address: $advertise_addr"

    docker swarm init --advertise-addr "$advertise_addr"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to initialize Docker Swarm" >&2
        exit 1
    fi

    echo "Swarm initialized"

    # Parameter for overlay network subnet to avoid conflicts, default to 10.255.0.0/16
    dokploy_subnet="${DOKPLOY_SUBNET:-10.255.0.0/16}"

    # Remove existing dokploy-network forcibly if exists
    docker network rm -f dokploy-network 2>/dev/null

    # Create dokploy overlay network with custom subnet to prevent overlaps
    docker network create --driver overlay --attachable --subnet "$dokploy_subnet" dokploy-network
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create dokploy-network overlay network" >&2
        exit 1
    fi

    echo "Network created with subnet $dokploy_subnet"

    mkdir -p /etc/dokploy
    chmod 777 /etc/dokploy

    docker service create \
        --name dokploy-postgres \
        --constraint 'node.role==manager' \
        --network dokploy-network \
        --env POSTGRES_USER=dokploy \
        --env POSTGRES_DB=dokploy \
        --env POSTGRES_PASSWORD=amukds4wi9001583845717ad2 \
        --mount type=volume,source=dokploy-postgres-database,target=/var/lib/postgresql/data \
        postgres:16

    docker service create \
        --name dokploy-redis \
        --constraint 'node.role==manager' \
        --network dokploy-network \
        --mount type=volume,source=redis-data-volume,target=/data \
        redis:7

    docker pull traefik:v3.1.2
    docker pull dokploy/dokploy:latest

    docker service create \
        --name dokploy \
        --replicas 1 \
        --network dokploy-network \
        --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
        --mount type=bind,source=/etc/dokploy,target=/etc/dokploy \
        --mount type=volume,source=dokploy-docker-config,target=/root/.docker \
        --publish published=3000,target=3000,mode=host \
        --update-parallelism 1 \
        --update-order stop-first \
        --constraint 'node.role == manager' \
        -e ADVERTISE_ADDR="$advertise_addr" \
        dokploy/dokploy:latest

    sleep 4

    docker run -d \
        --name dokploy-traefik \
        --network dokploy-network \
        --restart always \
        -v /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml \
        -v /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -p 80:80/tcp \
        -p 443:443/tcp \
        -p 443:443/udp \
        traefik:v3.1.2

    # Utility function to format IP for URL (zero-copy)
    format_ip_for_url() {
        local ip="$1"
        if echo "$ip" | grep -q ':'; then
            # IPv6
            echo "[${ip}]"
        else
            # IPv4
            echo "${ip}"
        fi
    }

    formatted_addr=$(format_ip_for_url "$advertise_addr")
    echo ""
    printf "\033[0;32mCongratulations, Dokploy is installed!\033[0m\n"
    printf "\033[0;34mWait 15 seconds for the server to start\033[0m\n"
    printf "\033[1;33mPlease go to http://%s:3000\033[0m\n\n" "$formatted_addr"
}

update_dokploy() {
    echo "Updating Dokploy..."
    docker pull dokploy/dokploy:latest
    docker service update --image dokploy/dokploy:latest dokploy
    echo "Dokploy has been updated to the latest version."
}

# Main execution
if [ "$1" = "update" ]; then
    update_dokploy
else
    install_dokploy
fi
