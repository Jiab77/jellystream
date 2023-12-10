#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016

# Simple Random CLI Music Player
# Made by Jiab77
#
# Todo:
#  - Add 'mpd' support
#  - Add 'ffplay' support
#  - Add dynamic playlist support
#
# Done:
#  - Add 'XDG_SPEC' support
#  - Add 'mpv' support
#  - Add 'mpg123' support
#  - Add 'gst123' support
#
# Version: 0.0.1

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
DEBUG_MODE=true
CLEAR_SCREEN=true
SHOW_HEADER=true
BUFFER_SIZE=0
GST_VISUALIZATION_ENABLED=true
GST_VISUALIZATION_TYPE="synaescope"
MPV_GUI_ENABLED=false

# Internals
BIN_GST123=$(which gst123 2>/dev/null)
BIN_MPG123=$(which mpg123 2>/dev/null)
BIN_MPV=$(which mpv 2>/dev/null)
BIN_PLAYCTL=$(which playerctl 2>/dev/null)
SCRIPT_DIR="$(dirname "$0")"
SCRIPT_FILE="$(basename "$0")"
SCRIPT_NAME="${SCRIPT_FILE//.sh/}"
CONFIG_FILE="${SCRIPT_NAME}.conf"

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
  [[ $SHOW_HEADER == true ]] && log "${NL}${BLUE}Simple Random CLI Music Player - ${GREEN}v$(get_version)${NC}${NL}"
}
function print_usage() {
  log "${NL}Usage: $SCRIPT_FILE [status|stop|play|pause|prev|next]${NL}"
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
function gen_playlist() {
  find "$MUSIC_DIR" -type f -iname "*.mp3" -print
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
  if [[ -n $MUSIC_DIR ]]; then
    log "${NL}${WHITE}Initializing...${NC}${NL}"

    # mpg123 sample command(s)
    # mpg123 --rva-mix --title --long-tag --control --shuffle -v "$MUSIC_DIR"/*/*/*.mp3
    # mpg123 --rva-mix --title --long-tag --control --shuffle -v -@ - < <(find "$MUSIC_DIR" -type f -iname "*.mp3" -o -iname "*.wav")

    # gst123 sample commnand(s)
    # gst123 -fv synaescope --name="JellyStream" --shuffle "$MUSIC_DIR"/*/*/*.mp3 2>&1 | grep -vi themes
    # gst123 -fv synaescope --name="JellyStream" --shuffle -@ - < <(find "$MUSIC_DIR" -type f -iname "*.mp3" -print) 2>&1 | grep -vi themes

    # mpv sample command(s)
    # mpv --no-config \
    #     --shuffle \
    #     --term-osd-bar \
    #     --no-audio-display \
    #     --term-title='Playing song [${playlist-pos-1}/${playlist-count}]: ${metadata/by-key/Artist} - ${metadata/by-key/Album} - ${metadata/by-key/Title}' \
    #     "$MUSIC_DIR"/*/*/*.mp3
    # mpv --no-config \
    #     --shuffle \
    #     --no-audio-display \
    #     --term-osd-bar \
    #     --term-title='Playing song [${playlist-pos-1}/${playlist-count}]: ${metadata/by-key/Artist} - ${metadata/by-key/Album} - ${metadata/by-key/Title}' \
    #     --playlist=- < <(find "$MUSIC_DIR" -type f -iname "*.mp3" -print)

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
      set_console_title "${SCRIPT_NAME}: Generating Random Mix..."
      if [[ $DEBUG_MODE == true ]]; then
        mpg123 --rva-mix --title --long-tag --control --shuffle --buffer $BUFFER_SIZE --smooth -vvv -@ - < <(gen_playlist)
      else
        mpg123 --rva-mix --title --long-tag --control --shuffle --buffer $BUFFER_SIZE --smooth -v -@ - < <(gen_playlist)
      fi
      exit $?
    elif [[ -n $BIN_GST123 ]]; then
      if [[ $GST_VISUALIZATION_ENABLED == true ]]; then
        gst123 -v "$GST_VISUALIZATION_TYPE" --name="$SCRIPT_NAME" --shuffle -@ - < <(gen_playlist) 2>&1 | grep -vi themes
      else
        gst123 -x --name="$SCRIPT_NAME" --shuffle -@ - < <(gen_playlist) 2>&1 | grep -vi themes
      fi
      exit $?
    else
      die "Unable to find proper audio backend."
    fi
  else
    die "Unable to find music directory."
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
[[ $1 == "status" || $1 == "stop" || $1 == "play" || $1 == "pause" || $1 == "prev" || $1 == "next" ]] && manage_player "$1"

# Get music dir from XDG Spec
[[ -z $MUSIC_DIR && -n $XDG_MUSIC_DIR ]] && MUSIC_DIR="$XDG_MUSIC_DIR"

# If no XDG Spec file found, try to find music folder from possible values
[[ -z $MUSIC_DIR && -r ~/Musique ]] && MUSIC_DIR=~/Musique
[[ -z $MUSIC_DIR && -r ~/Music ]] && MUSIC_DIR=~/Music

# Checks
[[ -z $BIN_MPV && -z $BIN_MPG123 && -z $BIN_GST123 ]] && die "You must have at least 'mpv' or 'mpg123' or 'gst123' installed to run this script."

# Main
run_player
