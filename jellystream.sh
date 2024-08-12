#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016

# Simple Cloud CLI Music Player based on the Jellyfin
# Made by Jiab77
#
# Todo:
#  - Add 'mpd' support
#  - Add 'vlc' support
#  - Add 'gst123' support
#  - Add 'ffplay' support
#  - Add 'wget' support
#
# Done:
#  - Add 'XDG_SPEC' support
#  - Add 'mpv' support
#  - Add 'mpg123' support
#
# Version 0.2.2

# Options
[[ -r $HOME/.debug ]] && set -o xtrace || set +o xtrace

# Config
DEBUG_MODE=false
CLEAR_SCREEN=false
SHOW_HEADER=true
SERVER_ADDR="YOUR-SERVER-ADDRESS-WITH-PORT-IF-ANY"
API_KEY="YOUR-API-KEY"
LOGIN_AS="admin"
AUDIO_BITRATE=192000
SAMPLE_RATE=48000
BUFFER_SIZE=0
MPV_GUI_ENABLED=false
MPV_MIN_VER="0.34.0"
CREATE_PLS_FILE=false
LIMIT=20

# Internals
BIN_CURL=$(command -v curl 2>/dev/null)
BIN_JQ=$(command -v jq 2>/dev/null)
BIN_MPG123=$(command -v mpg123 2>/dev/null)
BIN_MPV=$(command -v mpv 2>/dev/null)
BIN_VLC=$(command -v vlc 2>/dev/null)
BIN_PLAYCTL=$(command -v playerctl 2>/dev/null)
BIN_SED=$(command -v sed 2>/dev/null)

# Common
if [[ -r "$(dirname "$0")/common/bash_funcs" ]]; then
  source "$(dirname "$0")/common/bash_funcs" || ( echo -e "\nUnable to load '[script_dir]/common/bash_funcs' file.\n" && exit 255 )
fi

# Functions
function print_header() {
    [[ $CLEAR_SCREEN == true ]] && reset
    [[ $SHOW_HEADER == true ]] && log_err "${NL}${BLUE}Simple Cloud CLI Music Player based on ${PURPLE}Jellyfin${BLUE} - ${GREEN}v$(get_version)${NC}${NL}"
}
function print_usage() {
    log "${NL}Usage: $SCRIPT_FILE [flags] [generate|status|stop|play|pause|prev|next]"
    log "${NL}Flags:"
    log "  -h | --help\tPrint this message and exit"
    log "  -l | --limit <value>\tLimit created playlist to given value (default: $LIMIT)"
    log
    exit
}
function bootstrap() {
  set_script_dir
  set_script_file
  set_config_file
  load_xdg_defs
  load_config_file
}
function jellyfin_connect() {
    # Connect to Jellyfin server
    echo -ne "${WHITE}Connecting to ${PURPLE}Jellyfin API${WHITE}...${NC}" >&2
    USER_ID=$(curl -sSL "${SERVER_ADDR}/Users?api_key=${API_KEY}" 2>/dev/null | jq -r '(.[] | select(.Name == "'${LOGIN_AS}'") | .Id)')
    CONNECTED_AS=$(curl -sSL "${SERVER_ADDR}/Users/${USER_ID}?api_key=${API_KEY}" 2>/dev/null | jq -r .Name)
    if [[ -n $CONNECTED_AS ]]; then
        log_err " ${GREEN}connected${NC}${NL}"
    else
        log_err " ${RED}failed${NC}${NL}"
        exit 1
    fi
    if [[ $DEBUG_MODE == true ]]; then
        log_err "${PURPLE}[DEBUG]${WHITE} Connected as: ${YELLOW}${CONNECTED_AS}${NC}${NL}"
    fi
}
function get_user_info() {
    # Show connected user info
    log_err "${PURPLE}[DEBUG]${WHITE} Displaying gathered user info:${NC}${NL}"
    curl -sSL "${SERVER_ADDR}/Users/${USER_ID}?api_key=${API_KEY}" | jq . >&2
    echo >&2
}
function get_music_genres() {
    # Gather existing music genres
    echo -ne "${WHITE}Gathering music genres...${NC}" >&2
    mapfile -t MUSIC_GENRES < <(curl -sSL "${SERVER_ADDR}/MusicGenres?api_key=${API_KEY}" 2>/dev/null | jq -r '.Items[] | .Name' | sed -e 's/ /_/gi')
    if [[ ${#MUSIC_GENRES[*]} -gt 0 ]]; then
        log_err " ${GREEN}done${NC}${NL}"
    else
        log_err " ${RED}failed${NC}${NL}"
        exit 1
    fi
    log_err "${WHITE}Gathered music genres: ${GREEN}${#MUSIC_GENRES[*]}${NC}"
}
function gen_music_genres_menu() {
    # Generate menu with all existing music genres
    log_err "${NL}${WHITE}Generating menu...${NC}${NL}"
    for mKey in "${!MUSIC_GENRES[@]}" ; do
        log_err "${mKey}. ${MUSIC_GENRES[${mKey}]//_/' '}"
    done
    echo >&2 ; read -rp "Select music genre: " SELECTED_GENRE

    [[ -z $SELECTED_GENRE ]] && die "You must select a music genre."

    log_err "${NL}${WHITE}Selected: ${GREEN}${MUSIC_GENRES[${SELECTED_GENRE}]//_/' '}${NC}"
}
function gen_music_mix() {
    # Generate InstantMix based on selected genre
    echo -ne "${NL}${WHITE}Generating [${PURPLE}${MUSIC_GENRES[${SELECTED_GENRE}]//_/' '}${WHITE}] InstantMix...${NC}" >&2
    mapfile -t INSTANT_MIX < <(curl -sSL "${SERVER_ADDR}/MusicGenres/${MUSIC_GENRES[${SELECTED_GENRE}]//_/'%20'}/InstantMix?api_key=${API_KEY}" 2>/dev/null | jq -r '.Items[] | .Id')
    if [[ ${#INSTANT_MIX[*]} -gt 0 ]]; then
        log_err " ${GREEN}${#INSTANT_MIX[*]}${WHITE} tracks.${NC}${NL}"
    else
        log_err " ${RED}${#INSTANT_MIX[*]}${WHITE} tracks.${NC}${NL}"
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
    local INDEX=0

    # Create dynamic playlist from generated InstantMix
    if [[ $DEBUG_MODE == true ]]; then
        log_err "${PURPLE}[DEBUG]${WHITE} Creating dynamic playlist...${NC}${NL}"
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
        ((++INDEX))

        [[ $INDEX -gt $LIMIT ]] && continue

        # Gathering song data
        local SONG_DETAILS
        mapfile -t SONG_DETAILS < <(curl -sSL "${SERVER_ADDR}/Items/?api_key=${API_KEY}&userId=${USER_ID}&ids=${SONG}" 2>/dev/null | jq -rc '.Items[] | .AlbumArtist,.Name,.Album')

        # Write song data to playlist
        # echo -e "#EXTINF:-1, ${SONG_DETAILS[0]} - ${SONG_DETAILS[1]}\n#EXTALB: ${SONG_DETAILS[2]}"
        echo -e "#EXTINF:0, ${SONG_DETAILS[0]} - ${SONG_DETAILS[1]}\n#EXTALB: ${SONG_DETAILS[2]}"
        echo "${SERVER_ADDR}/Audio/${SONG}/stream.mp3?api_key=${API_KEY}&audioBitRate=${AUDIO_BITRATE}&audioSampleRate=${SAMPLE_RATE}"

        sleep 0.2
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
                if [[ $(compare_version $MPV_MIN_VER $(get_mpv_version)) -eq 0 ]]; then
                    mpv --no-config \
                        --shuffle \
                        --no-audio-display \
                        --term-osd-bar \
                        --term-title='Playing song [${playlist-pos-1}/${playlist-count}]: ${metadata/by-key/Artist} - ${metadata/by-key/Album} - ${metadata/by-key/Title}' \
                        --playlist=- < <(gen_playlist)
                else
                    set_console_title "${SCRIPT_NAME}: ${MUSIC_GENRES[${SELECTED_GENRE}]//_/' '} - InstantMix"
                    mpv --no-config \
                        --shuffle \
                        --no-audio-display \
                        --term-osd-bar \
                        --playlist=- < <(gen_playlist)
                fi
            fi
        fi
        # exit $?
    elif [[ -n $BIN_MPG123 ]]; then
        set_console_title "${SCRIPT_NAME}: ${MUSIC_GENRES[${SELECTED_GENRE}]//_/' '} - Instant Mix"
        if [[ $DEBUG_MODE == true ]]; then
            mpg123 --rva-mix --long-tag --control --shuffle --buffer $BUFFER_SIZE --no-infoframe --smooth -vvv -@ - < <(gen_playlist)
        else
            mpg123 --rva-mix --long-tag --control --shuffle --buffer $BUFFER_SIZE --no-infoframe --smooth -v -@ - < <(gen_playlist)
        fi
        # exit $?
    else
        die "Unable to find proper audio backend."
    fi
}
function manage_player() {
    local OPERATION; OPERATION="$1"
    if [[ -n $BIN_PLAYCTL ]]; then
        playerctl -p mpv "$OPERATION" ; RET_CODE_CTL=$?
        # [[ ! $OPERATION == "status" ]] && playerctl -p mpv status ; RET_CODE_CTL=$?
        exit $RET_CODE_CTL
    else
        die "You must have 'playerctl' installed to control music players."
    fi
}
function run_player() {
    # Bootstrap everything
    log_err "${NL}${WHITE}Initializing...${NC}${NL}"

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
bootstrap

# Header
print_header

# Usage
[[ $1 == "-h" || $1 == "--help" ]] && print_usage
if [[ $1 == "-l" || $1 == "--limit" ]]; then
  shift ; LIMIT=$1
fi

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
