#!/usr/bin/env bash
# shellcheck disable=SC2034

# Basic CLI Music Player based on the Jellyfin API
# Made by Jiab77
#
# Version 0.1.1

# Options
set +o xtrace

# Colors
NC="\033[0m"
NL="\n"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
RED="\033[1;31m"
WHITE="\033[1;37m"
PURPLE="\033[1;35m"

# Config
DEBUG_MODE=false
CONFIG_DIR=$(dirname "$0")
CONFIG_FILE=$(basename "$0" | sed -e 's/.sh/.conf/gi')
SERVER_ADDR="YOUR-SERVER-ADDRESS-WITH-PORT-IF-ANY"
API_KEY="YOUR-API-KEY"
LOGIN_AS="admin"

# Load config file if any
if [[ -r $CONFIG_FILE ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_DIR/$CONFIG_FILE"
fi

# Functions
function get_version() {
    grep -i 'version' "$0" | awk '{ print $3 }' | head -n1
}
function jellyfin_connect() {
    # Connect to Jellyfin server
    echo -ne "${WHITE}Connecting to ${PURPLE}Jellyfin API${WHITE}...${NC}"
    USER_ID=$(curl -sSL "${SERVER_ADDR}/Users?api_key=${API_KEY}" 2>/dev/null | jq -r '(.[] | select(.Name == "'${LOGIN_AS}'") | .Id)')
    CONNECTED_AS=$(curl -sSL "${SERVER_ADDR}/Users/${USER_ID}?api_key=${API_KEY}" 2>/dev/null | jq -r .Name)
    if [[ -n $CONNECTED_AS ]]; then
        echo -e " ${GREEN}connected${NC}${NL}"
    else
        echo -e " ${RED}failed${NC}${NL}"
        exit 1
    fi
    echo -e "${WHITE}Connected as: ${YELLOW}${CONNECTED_AS}${NC}${NL}"
}
function get_user_info() {
    # Show connected user info
    echo -e "${PURPLE}[DEBUG]${WHITE} Displaying gathered user info:${NC}${NL}"
    curl -sSL "${SERVER_ADDR}/Users/${USER_ID}?api_key=${API_KEY}" | jq . && echo
}
function get_music_genres() {
    # Gather existing music genres
    echo -ne "${WHITE}Gathering music ${PURPLE}genres${WHITE}...${NC}"
    mapfile -t MUSIC_GENRES < <(curl -sSL "${SERVER_ADDR}/MusicGenres?api_key=${API_KEY}" 2>/dev/null | jq -r '.Items[] | .Name' | sed -e 's/ //gi')
    if [[ ${#MUSIC_GENRES[*]} -gt 0 ]]; then
        echo -e " ${GREEN}done${NC}${NL}"
    else
        echo -e " ${RED}failed${NC}${NL}"
        exit 1
    fi
    echo -e "${WHITE}Gathered music ${PURPLE}genres${WHITE}: ${GREEN}${#MUSIC_GENRES[*]}${NC}"
}
function gen_music_genres_menu() {
    # Generate menu with all existing music genres
    echo -e "${NL}${WHITE}Generating music ${PURPLE}genres${WHITE} menu...${NC}${NL}"
    for mKey in "${!MUSIC_GENRES[@]}" ; do
        echo "${mKey}. ${MUSIC_GENRES[${mKey}]}"
    done
    echo ; read -rp "Select music genre: " SELECTED_GENRE

    [[ -z $SELECTED_GENRE ]] && echo -e "${NL}${RED}Error: ${YELLOW}You must select a music genre.${NC}${NL}" && exit 1

    echo -e "${NL}${WHITE}Selected music genre: ${GREEN}${MUSIC_GENRES[${SELECTED_GENRE}]}${NC}"
}
function gen_music_mix() {
    # Generate InstantMix based on selected genre
    echo -en "${NL}${WHITE}Generating [${PURPLE}${MUSIC_GENRES[${SELECTED_GENRE}]}${WHITE}] InstantMix...${NC}"
    mapfile -t INSTANT_MIX < <(curl -sSL "${SERVER_ADDR}/MusicGenres/${MUSIC_GENRES[${SELECTED_GENRE}]}/InstantMix?api_key=${API_KEY}" 2>/dev/null | jq -r '.Items[] | .Id')
    if [[ ${#INSTANT_MIX[*]} -gt 0 ]]; then
        echo -e " ${GREEN}${#INSTANT_MIX[*]}${WHITE} tracks.${NC}"
    else
        echo -e " ${RED}${#INSTANT_MIX[*]}${WHITE} tracks.${NC}"
        echo ; read -rp "Select another music genre? [Y,N]: " TRY_AGAIN
        if [[ -z $TRY_AGAIN || "${TRY_AGAIN,,}" == "n" ]]; then
            echo -e "${NL}${YELLOW}Leaving...${NC}${NL}"
            exit 1
        elif [[ "${TRY_AGAIN,,}" == "y" ]]; then
            clear
            bash "$0"
        fi
    fi
}
function load_music_mix() {
    # Loading generated InstantMix
    echo -e "${NL}${WHITE}Loading [${PURPLE}${MUSIC_GENRES[${SELECTED_GENRE}]}${WHITE}] InstantMix...${NC}${NL}"
    for SONG in "${INSTANT_MIX[@]}" ; do
        # Gathering song data
        mapfile -t SONG_DETAILS < <(curl -sSL "${SERVER_ADDR}/Items/?api_key=${API_KEY}&userId=${USER_ID}&ids=${SONG}" 2>/dev/null | jq -rc '.Items[] | [.AlbumArtist,.Album,.Name]')
        echo -e "${WHITE}Playing ${BLUE}${SONG_DETAILS[*]}${WHITE}...${NC}${NL}" | sed -e 's/,/ - /gi' -e 's/"//gi'
        if [[ $DEBUG_MODE == true ]]; then
            echo -e "${PURPLE}[DEBUG]${WHITE} Running: ${YELLOW}curl -sSL '${SERVER_ADDR}/Audio/${SONG}/stream.mp3?api_key=${API_KEY}&audioBitRate=192000&audioSampleRate=48000' | mpg123 -v -${NC}${NL}"
        fi
        curl -sSL "${SERVER_ADDR}/Audio/${SONG}/stream.mp3?api_key=${API_KEY}&audioBitRate=192000&audioSampleRate=48000" | mpg123 -q -v -
    done
}
function run_player() {
    # Bootstrap everything
    jellyfin_connect
    [[ $DEBUG_MODE == true ]] && get_user_info
    get_music_genres
    gen_music_genres_menu
    gen_music_mix
    load_music_mix
}
function kill_player() {
    # Very dirty kill function...
    echo -e "${YELLOW}Killing music player...${NC}${NL}"
    for I in {1..500} ; do pkill mpg123 &>/dev/null ; done
    echo -e "${BLUE}Done.${NC}${NL}"
    exit 0
}

# Header
echo -e "${NL}${BLUE}Basic CLI Music Player based on ${PURPLE}Jellyfin API${BLUE} - ${GREEN}v$(get_version)${NC}${NL}"

# Usage
[[ $1 == "-h" || $1 == "--help" ]] && echo -e "${NL}Usage: $(basename "$0") [stop|kill]${NL}" && exit 1

# Arguments
[[ $1 == "stop" || $1 == "kill" ]] && kill_player

# Checks
[[ $SERVER_ADDR == "YOUR-SERVER-ADDRESS-WITH-PORT-IF-ANY" ]] && echo -e "${RED}Error: ${YELLOW}You must define the server address.${NC}${NL}" && exit 1
[[ $API_KEY == "YOUR-API-KEY" ]] && echo -e "${RED}Error: ${YELLOW}You must define the API key defined on your server.${NC}${NL}" && exit 1
[[ -z $LOGIN_AS ]] && echo -e "${RED}Error: ${YELLOW}You must define the user to connect on your server.${NC}${NL}" && exit 1

# Main
run_player
