#!/bin/ash
cd /mnt/server

# Function to (re)create hibernation.sh
create_hibernation() {
cat > ./hibernation.sh <<'EOF'
#!/bin/ash
# Set hibernation time: 12 hours for Velocity/BungeeCord, 2 hours for others
if [ "$SERVER_TYPE" = "velocity" ] || [ "$SERVER_TYPE" = "bungeecord" ]; then
  IDLE_LIMIT=$((12 * 60 * 60)) # 12 hours
else
  IDLE_LIMIT=$((2 * 60 * 60))  # 2 hours
fi
CHECK_INTERVAL=60
IDLE_TIME=0
LOG_FILE=latest.log

while true; do
    if [ ! -f "$LOG_FILE" ]; then
        sleep $CHECK_INTERVAL
        continue
    fi
    # Check for no players for all server types
    if grep -qE "There are 0 of a max|No players online|There are 0/|No players connected|No clients online" "$LOG_FILE"; then
        IDLE_TIME=$((IDLE_TIME + CHECK_INTERVAL))
    else
        IDLE_TIME=0
    fi
    if [ $IDLE_TIME -ge $IDLE_LIMIT ]; then
        echo "No players for $((IDLE_LIMIT/3600)) hours, stopping server for hibernation."
        # Java servers
        if pgrep -f 'server.jar'; then
            pkill -f 'server.jar'
        fi
        # Bedrock Dedicated
        if pgrep -f 'bedrock_server'; then
            pkill -f 'bedrock_server'
        fi
        # PocketMine
        if pgrep -f 'PocketMine-MP.phar'; then
            pkill -f 'PocketMine-MP.phar'
        fi
        # Nukkit (Java, but may have different process name)
        if pgrep -f 'nukkit' || pgrep -f 'Nukkit'; then
            pkill -f 'nukkit'
            pkill -f 'Nukkit'
        fi
        break
    fi
    sleep $CHECK_INTERVAL
done
EOF
chmod +x ./hibernation.sh
}

# Always (re)install hibernation.sh on every server start
create_hibernation

# Get the hash of the correct hibernation.sh
EXPECTED_HASH=$(sha256sum ./hibernation.sh | awk '{print $1}')

# Function to get the current hash
get_hibernation_hash() {
    if [ -f ./hibernation.sh ]; then
        sha256sum ./hibernation.sh | awk '{print $1}'
    else
        echo "missing"
    fi
}

# Background process to re-create hibernation.sh if deleted or edited
(
  while true; do
    if [ ! -f ./hibernation.sh ] || [ "$(get_hibernation_hash)" != "$EXPECTED_HASH" ]; then
      echo "hibernation.sh was deleted or modified, re-creating..."
      create_hibernation
    fi
    sleep 10
  done
) &

# Prompt for server type
if [ ! -f .server_type_selected ]; then
  echo 'Welcome to Lylern Cloud!'
  echo '--- Server Startup Menu ---'
  echo '1) Paper'
  echo '2) Purpur'
  echo '3) Vanilla'
  echo '4) Spigot'
  echo '5) Fabric'
  echo '6) Forge'
  echo '7) Bedrock'
  echo '8) PocketMine'
  echo '9) Nukkit'
  echo '10) Velocity'
  echo '11) BungeeCord'
  read -p 'Enter your choice [1-11]: ' choice
  case $choice in
    1) SERVER_TYPE=paper ;;
    2) SERVER_TYPE=purpur ;;
    3) SERVER_TYPE=vanilla ;;
    4) SERVER_TYPE=spigot ;;
    5) SERVER_TYPE=fabric ;;
    6) SERVER_TYPE=forge ;;
    7) SERVER_TYPE=bedrock ;;
    8) SERVER_TYPE=pocketmine ;;
    9) SERVER_TYPE=nukkit ;;
    10) SERVER_TYPE=velocity ;;
    11) SERVER_TYPE=bungeecord ;;
    *) echo 'Invalid choice, defaulting to Paper'; SERVER_TYPE=paper ;;
  esac
  echo $SERVER_TYPE > .server_type_selected
else
  SERVER_TYPE=$(cat .server_type_selected)
fi

# Prompt for Minecraft version
if [ ! -f .minecraft_version_selected ]; then
  read -p 'Enter Minecraft version (leave blank for latest): ' MINECRAFT_VERSION
  if [ -z "$MINECRAFT_VERSION" ]; then MINECRAFT_VERSION=latest; fi
  echo $MINECRAFT_VERSION > .minecraft_version_selected
else
  MINECRAFT_VERSION=$(cat .minecraft_version_selected)
fi

# Prompt for MOTD
if [ ! -f .server_motd_selected ]; then
  read -p 'Enter server MOTD (default: Welcome to Lylern Cloud!): ' SERVER_MOTD
  if [ -z "$SERVER_MOTD" ]; then SERVER_MOTD='Welcome to Lylern Cloud!'; fi
  echo "$SERVER_MOTD" > .server_motd_selected
else
  SERVER_MOTD=$(cat .server_motd_selected)
fi

# Prompt for max players
if [ ! -f .max_players_selected ]; then
  read -p 'Enter max players (default: 20): ' MAX_PLAYERS
  if [ -z "$MAX_PLAYERS" ]; then MAX_PLAYERS=20; fi
  echo $MAX_PLAYERS > .max_players_selected
else
  MAX_PLAYERS=$(cat .max_players_selected)
fi

# Prompt for world type
if [ ! -f .world_type_selected ]; then
  echo 'Select world type:'
  echo '  1) DEFAULT'
  echo '  2) FLAT'
  echo '  3) AMPLIFIED'
  read -p 'Enter your choice [1-3, default: 1]: ' WORLD_TYPE
  case $WORLD_TYPE in
    2) WORLD_TYPE=FLAT ;;
    3) WORLD_TYPE=AMPLIFIED ;;
    *) WORLD_TYPE=DEFAULT ;;
  esac
  echo $WORLD_TYPE > .world_type_selected
else
  WORLD_TYPE=$(cat .world_type_selected)
fi

# Prompt for admin/OP
if [ ! -f .admin_op_selected ]; then
  read -p 'Enter Minecraft username to OP (leave blank to skip): ' ADMIN_OP
  echo $ADMIN_OP > .admin_op_selected
else
  ADMIN_OP=$(cat .admin_op_selected)
fi

# Update server.properties if present
if [ -f server.properties ]; then
  sed -i "s/^motd=.*/motd=$SERVER_MOTD/" server.properties
  sed -i "s/^max-players=.*/max-players=$MAX_PLAYERS/" server.properties
  sed -i "s/^level-type=.*/level-type=$WORLD_TYPE/" server.properties
fi

# Add OP if username provided
if [ -n "$ADMIN_OP" ] && [ -f ops.json ]; then
  echo "[{'uuid':'','name':'$ADMIN_OP','level':4,'bypassesPlayerLimit':false}]" > ops.json
fi

# Start hibernation if present
if [ -f ./hibernation.sh ]; then
  ./hibernation.sh &
fi

# Start server
exec java -Xms128M -Xmx${SERVER_MEMORY}M -jar server.jar nogui
