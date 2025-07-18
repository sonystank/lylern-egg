#!/bin/ash
# Use current directory for all operations
echo "Using working directory: $(pwd)"

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

# Add this function at the top
flush_stdin() {
  while read -r -t 0; do read -r; done
}

# Add set -e for critical install section
set -e

# Prompt for all values in a single input to avoid input buffer issues
if [ ! -f .all_selected ]; then
  echo 'Welcome to Lylern Cloud!'
  echo '--- Server Startup Menu ---'
  echo '1) Paper 2) Purpur 3) Vanilla 4) Spigot 5) Fabric 6) Forge 7) Bedrock 8) PocketMine 9) Nukkit 10) Velocity 11) BungeeCord'
  echo 'World types: 1) DEFAULT 2) FLAT 3) AMPLIFIED'
  echo 'Please enter the following values separated by commas:'
  echo 'server_type_number (1-11), minecraft_version (or skip), motd (or skip), max_players (or skip), world_type_number (1-3), admin_username (or skip)'
  read -r -p 'Example: 2,1.20.4,Welcome!,20,1,Steve: ' ALL_INPUT
  IFS=',' read -r choice MINECRAFT_VERSION SERVER_MOTD MAX_PLAYERS WORLD_TYPE ADMIN_OP <<< "$ALL_INPUT"
  # Set defaults and map numbers to values
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
    *) SERVER_TYPE=paper ;;
  esac
  if [ -z "$MINECRAFT_VERSION" ] || [ "${MINECRAFT_VERSION,,}" = "skip" ]; then MINECRAFT_VERSION=latest; fi
  if [ -z "$SERVER_MOTD" ] || [ "${SERVER_MOTD,,}" = "skip" ]; then SERVER_MOTD='Welcome to Lylern Cloud!'; fi
  if [ -z "$MAX_PLAYERS" ]; then MAX_PLAYERS=20; fi
  case $WORLD_TYPE in
    1|""|DEFAULT) WORLD_TYPE=DEFAULT ;;
    2|FLAT) WORLD_TYPE=FLAT ;;
    3|AMPLIFIED) WORLD_TYPE=AMPLIFIED ;;
    *) WORLD_TYPE=DEFAULT ;;
  esac
  if [ -z "$ADMIN_OP" ] || [ "${ADMIN_OP,,}" = "skip" ]; then ADMIN_OP=""; fi
  echo "$SERVER_TYPE" > .server_type_selected
  echo "$MINECRAFT_VERSION" > .minecraft_version_selected
  echo "$SERVER_MOTD" > .server_motd_selected
  echo "$MAX_PLAYERS" > .max_players_selected
  echo "$WORLD_TYPE" > .world_type_selected
  echo "$ADMIN_OP" > .admin_op_selected
  touch .all_selected
else
  SERVER_TYPE=$(cat .server_type_selected)
  MINECRAFT_VERSION=$(cat .minecraft_version_selected)
  SERVER_MOTD=$(cat .server_motd_selected)
  MAX_PLAYERS=$(cat .max_players_selected)
  WORLD_TYPE=$(cat .world_type_selected)
  ADMIN_OP=$(cat .admin_op_selected)
fi

# After SERVER_TYPE is set from the menu
if [ ! -f .server_installed ] || [ "$(cat .server_installed)" != "$SERVER_TYPE-$MINECRAFT_VERSION" ]; then
  echo "Installing $SERVER_TYPE server..."
  case $SERVER_TYPE in
    paper)
      VERSION=${MINECRAFT_VERSION:-latest}
      if [ "$VERSION" = "latest" ]; then
        VERSION=$(curl -s https://api.papermc.io/v2/projects/paper | jq -r '.versions[-1]')
      fi
      BUILD=${BUILD_NUMBER:-latest}
      if [ "$BUILD" = "latest" ]; then
        BUILD=$(curl -s https://api.papermc.io/v2/projects/paper/versions/$VERSION | jq -r '.builds[-1]')
      fi
      curl -o server.jar https://api.papermc.io/v2/projects/paper/versions/$VERSION/builds/$BUILD/downloads/paper-$VERSION-$BUILD.jar
      # After downloading server.jar in each case, add debug output and abort if corrupt
      ls -lh server.jar
      file server.jar
      head -20 server.jar
      if [ $(stat -c%s server.jar) -lt 100000 ]; then
        echo "ERROR: server.jar is too small or corrupt. Aborting startup."
        cat server.jar
        exit 1
      fi
      ;;
    purpur)
      VERSION=${MINECRAFT_VERSION:-latest}
      if [ "$VERSION" = "latest" ]; then
        VERSION=$(curl -s https://api.purpurmc.org/v2/purpur | jq -r '.versions[-1]')
      fi
      BUILD=${BUILD_NUMBER:-latest}
      if [ "$BUILD" = "latest" ]; then
        BUILD=$(curl -s https://api.purpurmc.org/v2/purpur/$VERSION | jq -r '.builds.latest')
      fi
      curl -o server.jar https://api.purpurmc.org/v2/purpur/$VERSION/$BUILD/download
      # After downloading server.jar in each case, add debug output and abort if corrupt
      ls -lh server.jar
      file server.jar
      head -20 server.jar
      if [ $(stat -c%s server.jar) -lt 100000 ]; then
        echo "ERROR: server.jar is too small or corrupt. Aborting startup."
        cat server.jar
        exit 1
      fi
      ;;
    vanilla)
      VERSION=${MINECRAFT_VERSION:-latest}
      if [ "$VERSION" = "latest" ]; then
        VERSION=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r .latest.release)
      fi
      JAR_URL=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r --arg v "$VERSION" '.versions[] | select(.id==$v) | .url')
      if [ -z "$JAR_URL" ]; then echo "Invalid version"; exit 2; fi
      DL_URL=$(curl -s $JAR_URL | jq -r '.downloads.server.url')
      curl -o server.jar $DL_URL
      # After downloading server.jar in each case, add debug output and abort if corrupt
      ls -lh server.jar
      file server.jar
      head -20 server.jar
      if [ $(stat -c%s server.jar) -lt 100000 ]; then
        echo "ERROR: server.jar is too small or corrupt. Aborting startup."
        cat server.jar
        exit 1
      fi
      ;;
    spigot)
      VERSION=${MINECRAFT_VERSION:-latest}
      if [ "$VERSION" = "latest" ]; then
        VERSION=1.20.4 # fallback
      fi
      echo 'Spigot requires BuildTools. Please build manually.' > server.jar
      ;;
    fabric)
      VERSION=${MINECRAFT_VERSION:-latest}
      if [ "$VERSION" = "latest" ]; then
        VERSION=$(curl -s https://meta.fabricmc.net/v2/versions/game | jq -r '.[0].version')
      fi
      LOADER=$(curl -s https://meta.fabricmc.net/v2/versions/loader/$VERSION | jq -r '.[0].loader.version')
      INSTALLER=$(curl -s https://meta.fabricmc.net/v2/versions/installer | jq -r '.[0].version')
      curl -o fabric-installer.jar https://maven.fabricmc.net/net/fabricmc/fabric-installer/$INSTALLER/fabric-installer-$INSTALLER.jar
      java -jar fabric-installer.jar server -mcversion $VERSION -loader $LOADER -downloadMinecraft
      mv server.jar server-*.jar 2>/dev/null || true
      ;;
    forge)
      VERSION=${MINECRAFT_VERSION:-latest}
      if [ "$VERSION" = "latest" ]; then
        VERSION=$(curl -s https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json | jq -r '.promos["1.20.4-latest"]')
      fi
      echo 'Forge requires installer. Please build manually.' > server.jar
      ;;
    bedrock)
      DL_URL=$(curl -s https://www.minecraft.net/en-us/download/server/bedrock | grep -oP 'https://minecraft.azureedge.net/bin-linux/bedrock-server-.*?\\.zip')
      curl -o bedrock.zip $DL_URL
      unzip bedrock.zip
      mv bedrock_server server.jar 2>/dev/null || true
      ;;
    pocketmine)
      curl -L -o PocketMine-MP.phar https://jenkins.pmmp.io/job/PocketMine-MP/lastSuccessfulBuild/artifact/PocketMine-MP.phar
      echo '#!/bin/sh\nexec php PocketMine-MP.phar --no-wizard --enable-ansi --disable-ansi' > start.sh
      chmod +x start.sh
      ln -sf start.sh server.jar
      ;;
    nukkit)
      curl -L -o server.jar https://ci.opencollab.dev/job/NukkitX/job/Nukkit/job/master/lastSuccessfulBuild/artifact/target/nukkit-1.0-SNAPSHOT.jar
      ;;
    bungeecord)
      curl -L -o server.jar https://ci.md-5.net/job/BungeeCord/lastSuccessfulBuild/artifact/bootstrap/target/BungeeCord.jar
      ;;
    velocity)
      VERSION=$(curl -s https://api.papermc.io/v2/projects/velocity | jq -r '.versions[-1]')
      curl -o server.jar https://api.papermc.io/v2/projects/velocity/versions/$VERSION/builds/latest/downloads/velocity-$VERSION-latest.jar
      ;;
    *)
      echo "Unknown server type"; exit 1 ;;
  esac
  echo "$SERVER_TYPE-$MINECRAFT_VERSION" > .server_installed
fi

# Download default server.properties if missing
if [ ! -f server.properties ]; then
  echo "server.properties missing, downloading default."
  curl -fsSL -o server.properties https://raw.githubusercontent.com/parkervcp/eggs/master/minecraft/java/server.properties || { echo "Failed to download server.properties"; exit 1; }
fi
# Only run sed if server.properties exists and is not empty
if [ -s server.properties ]; then
  sed -i "s/^motd=.*/motd=$SERVER_MOTD/" server.properties || { echo "Failed to update motd in server.properties"; cat server.properties; }
  sed -i "s/^max-players=.*/max-players=$MAX_PLAYERS/" server.properties || { echo "Failed to update max-players in server.properties"; cat server.properties; }
  sed -i "s/^level-type=.*/level-type=$WORLD_TYPE/" server.properties || { echo "Failed to update level-type in server.properties"; cat server.properties; }
else
  echo "server.properties missing or empty, skipping sed."
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
echo "SERVER_MEMORY is: $SERVER_MEMORY"
exec java -Xms128M -Xmx${SERVER_MEMORY}M -jar server.jar nogui
