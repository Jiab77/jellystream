#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016

# Simple Cloud CLI Music Player based on the Jellyfin
# Made by Jiab77
#
# Todo:
#  - Add 'mpd' support
#  - Add 'gst123' support
#  - Add 'ffplay' support
#  - Add 'wget' support
#
# Done:
#  - Add 'XDG_SPEC' support
#  - Add 'mpv' support
#  - Add 'mpg123' support
#
# Version 0.2.0

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
CLEAR_SCREEN=true
SHOW_HEADER=true
SERVER_ADDR="YOUR-SERVER-ADDRESS-WITH-PORT-IF-ANY"
API_KEY="YOUR-API-KEY"
LOGIN_AS="admin"
AUDIO_BITRATE=192000
SAMPLE_RATE=48000
BUFFER_SIZE=0
MPV_GUI_ENABLED=false

# Internals
BIN_CURL=$(which curl 2>/dev/null)
BIN_JQ=$(which jq 2>/dev/null)
BIN_MPG123=$(which mpg123 2>/dev/null)
BIN_MPV=$(which mpv 2>/dev/null)
BIN_PLAYCTL=$(which playerctl 2>/dev/null)
BIN_SED=$(which sed 2>/dev/null)
SCRIPT_DIR="$(dirname "$0")"
SCRIPT_FILE="$(basename "$0")"
SCRIPT_NAME="${SCRIPT_FILE//.sh/}"
CONFIG_FILE="${SCRIPT_NAME}.conf"
CREATE_PLS_FILE=false

# Functions
function die() {
    echo -e "${NL}${RED}Error: ${YELLOW}${1}${NC}${NL}" >&2
    exit 255
}
function log() {
    echo -e "$1" >&2
}
function get_version() {
    grep -i 'version' "$0" | awk '{ print $3 }' | head -n1
}
function set_console_title() {
    echo -ne "\033]0;${1}\007"
}
function print_header() {
    [[ $CLEAR_SCREEN == true ]] && reset
    [[ $SHOW_HEADER == true ]] && log "${NL}${BLUE}Simple Cloud CLI Music Player based on ${PURPLE}Jellyfin${BLUE} - ${GREEN}v$(get_version)${NC}${NL}"
}
function print_usage() {
    log "${NL}Usage: $SCRIPT_FILE [generate|status|stop|play|pause|prev|next]${NL}"
    exit 1
}
function load_xdg_defs() {
    if [[ -r ~/.config/user-dirs.dirs ]]; then
        # shellcheck source=/dev/null
        source ~/.config/user-dirs.dirs
    fi
    [[ -z $XDG_CONFIG_HOME ]] && XDG_CONFIG_HOME="$HOME/.config"
}
function load_config_file() {
    if [[ -r "$XDG_CONFIG_HOME/$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$XDG_CONFIG_HOME/$CONFIG_FILE"
    elif [[ -r "$XDG_CONFIG_HOME/$SCRIPT_NAME/$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$XDG_CONFIG_HOME/$SCRIPT_NAME/$CONFIG_FILE"
    elif [[ -r "$SCRIPT_DIR/$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/$CONFIG_FILE"
    fi
}
function get_mpv_mpris_lib() {
    local MPV_MPRIS_PATH
    if [[ -r "$XDG_CONFIG_HOME/mpv/scripts/mpris.so" ]]; then
        MPV_MPRIS_PATH="$XDG_CONFIG_HOME/mpv/scripts/mpris.so"
    elif [[ -r /etc/mpv/scripts/mpris.so ]]; then
        MPV_MPRIS_PATH=/etc/mpv/scripts/mpris.so
    else
        MPV_MPRIS_PATH=
    fi
    echo -n "$MPV_MPRIS_PATH"
}
function jellyfin_connect() {
    # Connect to Jellyfin server
    echo -ne "${WHITE}Connecting to ${PURPLE}Jellyfin API${WHITE}...${NC}" >&2
    USER_ID=$(curl -sSL "${SERVER_ADDR}/Users?api_key=${API_KEY}" 2>/dev/null | jq -r '(.[] | select(.Name == "'${LOGIN_AS}'") | .Id)')
    CONNECTED_AS=$(curl -sSL "${SERVER_ADDR}/Users/${USER_ID}?api_key=${API_KEY}" 2>/dev/null | jq -r .Name)
    if [[ -n $CONNECTED_AS ]]; then
        log " ${GREEN}connected${NC}${NL}"
    else
        log " ${RED}failed${NC}${NL}"
        exit 1
    fi
    if [[ $DEBUG_MODE == true ]]; then
        log "${PURPLE}[DEBUG]${WHITE} Connected as: ${YELLOW}${CONNECTED_AS}${NC}${NL}"
    fi
}
function get_user_info() {
    # Show connected user info
    log "${PURPLE}[DEBUG]${WHITE} Displaying gathered user info:${NC}${NL}"
    curl -sSL "${SERVER_ADDR}/Users/${USER_ID}?api_key=${API_KEY}" | jq . >&2
    echo >&2
}
function get_music_genres() {
    # Gather existing music genres
    echo -ne "${WHITE}Gathering music genres...${NC}" >&2
    mapfile -t MUSIC_GENRES < <(curl -sSL "${SERVER_ADDR}/MusicGenres?api_key=${API_KEY}" 2>/dev/null | jq -r '.Items[] | .Name' | sed -e 's/ /_/gi')
    if [[ ${#MUSIC_GENRES[*]} -gt 0 ]]; then
        log " ${GREEN}done${NC}${NL}"
    else
        log " ${RED}failed${NC}${NL}"
        exit 1
    fi
    log "${WHITE}Gathered music genres: ${GREEN}${#MUSIC_GENRES[*]}${NC}"
}
function gen_music_genres_menu() {
    # Generate menu with all existing music genres
    log "${NL}${WHITE}Generating menu...${NC}${NL}"
    for mKey in "${!MUSIC_GENRES[@]}" ; do
        log "${mKey}. ${MUSIC_GENRES[${mKey}]//_/' '}"
    done
    echo >&2 ; read -rp "Select music genre: " SELECTED_GENRE

    [[ -z $SELECTED_GENRE ]] && die "You must select a music genre."

    log "${NL}${WHITE}Selected: ${GREEN}${MUSIC_GENRES[${SELECTED_GENRE}]//_/' '}${NC}"
}
function gen_music_mix() {
    # Generate InstantMix based on selected genre
    echo -ne "${NL}${WHITE}Generating [${PURPLE}${MUSIC_GENRES[${SELECTED_GENRE}]//_/' '}${WHITE}] InstantMix...${NC}" >&2
    mapfile -t INSTANT_MIX < <(curl -sSL "${SERVER_ADDR}/MusicGenres/${MUSIC_GENRES[${SELECTED_GENRE}]//_/'%20'}/InstantMix?api_key=${API_KEY}" 2>/dev/null | jq -r '.Items[] | .Id')
    if [[ ${#INSTANT_MIX[*]} -gt 0 ]]; then
        log " ${GREEN}${#INSTANT_MIX[*]}${WHITE} tracks.${NC}${NL}"
    else
        log " ${RED}${#INSTANT_MIX[*]}${WHITE} tracks.${NC}${NL}"
        echo >&2 ; read -rp "Select another music genre? [Y,N]: " TRY_AGAIN
        if [[ -z $TRY_AGAIN || "${TRY_AGAIN,,}" == "n" ]]; then
            echo -e "${NL}${YELLOW}Leaving...${NC}${NL}" >&2
            exit 1
        elif [[ "${TRY_AGAIN,,}" == "y" ]]; then
            clear
            bash "$0"
        fi
    fi
}
function gen_playlist() {
    # Create dynamic playlist from generated InstantMix
    if [[ $DEBUG_MODE == true ]]; then
        log "${PURPLE}[DEBUG]${WHITE} Creating dynamic playlist...${NC}${NL}"
    fi

    # Required M3U extended header
    echo "#EXTM3U"

    # Required encoding type
    echo "#EXTENC: UTF-8"

    # Add selected genre info
    echo "#EXTGENRE: ${MUSIC_GENRES[${SELECTED_GENRE}]//_/' '}"

    # Required blank line
    echo

    # Generate extended playlist data
    for SONG in "${INSTANT_MIX[@]}" ; do
        # Gathering song data
        local SONG_DETAILS
        mapfile -t SONG_DETAILS < <(curl -sSL "${SERVER_ADDR}/Items/?api_key=${API_KEY}&userId=${USER_ID}&ids=${SONG}" 2>/dev/null | jq -rc '.Items[] | .AlbumArtist,.Name,.Album')

        # Write song data to playlist
        # echo -e "#EXTINF:-1, ${SONG_DETAILS[0]} - ${SONG_DETAILS[1]}\n#EXTALB: ${SONG_DETAILS[2]}"
        echo -e "#EXTINF:0, ${SONG_DETAILS[0]} - ${SONG_DETAILS[1]}\n#EXTALB: ${SONG_DETAILS[2]}"
        echo "${SERVER_ADDR}/Audio/${SONG}/stream.mp3?api_key=${API_KEY}&audioBitRate=${AUDIO_BITRATE}&audioSampleRate=${SAMPLE_RATE}"
    done
}
function load_playlist() {
    if [[ -n $BIN_MPV ]]; then
        if [[ $MPV_GUI_ENABLED == true ]]; then
            mpv --no-config \
                --shuffle \
                --term-osd-bar \
                --term-title='Playing song [${playlist-pos-1}/${playlist-count}]: ${metadata/by-key/Artist} - ${metadata/by-key/Album} - ${metadata/by-key/Title}' \
                --playlist=- < <(gen_playlist)
        else
            local MPV_MPRIS_LIB; MPV_MPRIS_LIB="$(get_mpv_mpris_lib)"
            if [[ -n "$MPV_MPRIS_LIB" ]]; then
                mpv --no-config \
                    --script="$MPV_MPRIS_LIB" \
                    --shuffle \
                    --no-audio-display \
                    --term-osd-bar \
                    --term-title='Playing song [${playlist-pos-1}/${playlist-count}]: ${metadata/by-key/Artist} - ${metadata/by-key/Album} - ${metadata/by-key/Title}' \
                    --playlist=- < <(gen_playlist)
            else
                mpv --no-config \
                    --shuffle \
                    --no-audio-display \
                    --term-osd-bar \
                    --term-title='Playing song [${playlist-pos-1}/${playlist-count}]: ${metadata/by-key/Artist} - ${metadata/by-key/Album} - ${metadata/by-key/Title}' \
                    --playlist=- < <(gen_playlist)
            fi
        fi
        exit $?
    elif [[ -n $BIN_MPG123 ]]; then
        set_console_title "${SCRIPT_NAME}: ${MUSIC_GENRES[${SELECTED_GENRE}]//_/' '} - Instant Mix"
        if [[ $DEBUG_MODE == true ]]; then
            mpg123 --rva-mix --long-tag --control --shuffle --buffer $BUFFER_SIZE --no-infoframe --smooth -vvv -@ - < <(gen_playlist)
        else
            mpg123 --rva-mix --long-tag --control --shuffle --buffer $BUFFER_SIZE --no-infoframe --smooth -v -@ - < <(gen_playlist)
        fi
        exit $?
    else
        die "Unable to find proper audio backend."
    fi
}
function manage_player() {
    local OPERATION; OPERATION="$1"
    if [[ -n $BIN_PLAYCTL ]]; then
        playerctl -p mpv "$OPERATION" ; RET_CODE_CTL=$?
        [[ ! $OPERATION == "status" ]] && playerctl -p mpv status
        exit $RET_CODE_CTL
    else
        die "You must have 'playerctl' installed to control music players."
    fi  
}
function run_player() {
    # Bootstrap everything
    log "${NL}${WHITE}Initializing...${NC}${NL}"

    # Server connection
    jellyfin_connect

    # User info
    [[ $DEBUG_MODE == true ]] && get_user_info

    # Generate music mix
    get_music_genres
    gen_music_genres_menu
    gen_music_mix

    # Load or print generated playlist
    if [[ $CREATE_PLS_FILE == true ]]; then
        gen_playlist
    else
        load_playlist
    fi
}

# Init
load_xdg_defs
load_config_file

# Header
print_header

# Usage
[[ $1 == "-h" || $1 == "--help" ]] && print_usage

# Arguments
[[ $1 == "generate" ]] && CREATE_PLS_FILE=true
[[ $1 == "status" || $1 == "stop" || $1 == "play" || $1 == "pause" || $1 == "prev" || $1 == "next" ]] && manage_player "$1"

# Checks
[[ $SERVER_ADDR == "YOUR-SERVER-ADDRESS-WITH-PORT-IF-ANY" ]] && die "You must define the server address."
[[ $API_KEY == "YOUR-API-KEY" ]] && die "You must define the API key defined on your server."
[[ -z $LOGIN_AS ]] && die "You must define the user to connect on your server."
[[ -z $BIN_CURL ]] && die "You must have 'curl' installed to run this script."
[[ -z $BIN_JQ ]] && die "You must have 'jq' installed to run this script."
[[ -z $BIN_MPV && -z $BIN_MPG123 ]] && die "You must have 'mpv' or 'mpg123' installed to run this script."
[[ -z $BIN_SED ]] && die "You must have 'sed' installed to run this script."

# Main
run_player
