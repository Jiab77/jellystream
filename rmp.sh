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
# Version: 0.1.0

# Options
[[ -r $HOME/.debug ]] && set -o xtrace || set +o xtrace

# Config
DEBUG_MODE=true
CLEAR_SCREEN=false
SHOW_HEADER=true
BUFFER_SIZE=0
GST_VISUALIZATION_ENABLED=true
GST_VISUALIZATION_TYPE="synaescope"
MPV_GUI_ENABLED=false
MPV_MIN_VER="0.34.0"

# Internals
BIN_GST123=$(command -v gst123 2>/dev/null)
BIN_MPG123=$(command -v mpg123 2>/dev/null)
BIN_MPV=$(command -v mpv 2>/dev/null)
BIN_VLC=$(command -v vlc 2>/dev/null)
BIN_PLAYCTL=$(command -v playerctl 2>/dev/null)

# Common
if [[ -r "$(dirname "$0")/common/bash_funcs" ]]; then
  source "$(dirname "$0")/common/bash_funcs" || ( echo -e "\nUnable to load '[script_dir]/common/bash_funcs' file.\n" && exit 255 )
fi

# Functions
function print_header() {
  [[ $CLEAR_SCREEN == true ]] && reset
  [[ $SHOW_HEADER == true ]] && log_err "${NL}${BLUE}Simple Random CLI Music Player - ${GREEN}v$(get_version)${NC}${NL}"
}
function print_usage() {
  log "${NL}Usage: $SCRIPT_FILE [status|stop|play|pause|prev|next]"
  log "${NL}Flags:"
  log "  -d | --music-dir <directory>${TAB}Override default music folder"
  exit 1
}
function bootstrap() {
  set_script_dir
  set_script_file
  set_config_file
  load_xdg_defs
  load_config_file
}
function set_music_dir() {
  # Get music dir from XDG Spec
  [[ -z $MUSIC_DIR && -n $XDG_MUSIC_DIR ]] && MUSIC_DIR="$XDG_MUSIC_DIR"

  # If no XDG Spec file found, try to find music folder from possible values
  [[ -z $MUSIC_DIR && -r ~/Musique ]] && MUSIC_DIR=~/Musique
  [[ -z $MUSIC_DIR && -r ~/Music ]] && MUSIC_DIR=~/Music

  [[ -z $MUSIC_DIR ]] && die "You must define the 'MUSIC_DIR' variable to run this script."
  [[ ! -r $MUSIC_DIR ]] && die "Folder defined in 'MUSIC_DIR' variable is not readable."
}
function gen_playlist() {
  find "$MUSIC_DIR" -type f -iname "*.mp3" -print
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
  set_music_dir

  if [[ -n $MUSIC_DIR ]]; then
    log_err "${NL}${WHITE}Initializing...${NC}${NL}"
    set_console_title "${SCRIPT_NAME}: Generating Random Mix..."

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
          if [[ $(compare_version $MPV_MIN_VER $(get_mpv_version)) -eq 0 ]]; then
            mpv --no-config \
                --shuffle \
                --no-audio-display \
                --term-osd-bar \
                --term-title='Playing song [${playlist-pos-1}/${playlist-count}]: ${metadata/by-key/Artist} - ${metadata/by-key/Album} - ${metadata/by-key/Title}' \
                --playlist=- < <(gen_playlist)
          else
            set_console_title "${SCRIPT_NAME}: Playing Random Mix..."
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
      set_console_title "${SCRIPT_NAME}: Playing Random Mix..."
      if [[ $DEBUG_MODE == true ]]; then
        mpg123 --rva-mix --title --long-tag --control --shuffle --buffer $BUFFER_SIZE --smooth -vvv -@ - < <(gen_playlist)
      else
        mpg123 --rva-mix --title --long-tag --control --shuffle --buffer $BUFFER_SIZE --smooth -v -@ - < <(gen_playlist)
      fi
      # exit $?
    elif [[ -n $BIN_GST123 ]]; then
      set_console_title "${SCRIPT_NAME}: Playing Random Mix..."
      if [[ $GST_VISUALIZATION_ENABLED == true ]]; then
        gst123 -v "$GST_VISUALIZATION_TYPE" --name="$SCRIPT_NAME" --shuffle -@ - < <(gen_playlist) 2>&1 | grep -vi themes
      else
        gst123 -x --name="$SCRIPT_NAME" --shuffle -@ - < <(gen_playlist) 2>&1 | grep -vi themes
      fi
      # exit $?
    else
      die "Unable to find proper audio backend."
    fi
  else
    die "Unable to find music directory."
  fi
}

# Init
bootstrap

# Header
print_header

# Usage
[[ $1 == "-h" || $1 == "--help" ]] && print_usage

# Overrides
if [[ $1 == "-d" || $1 == "--music-dir" ]]; then
  shift ; MUSIC_DIR="$1"
fi

# Arguments
[[ $1 == "status" || $1 == "stop" || $1 == "play" || $1 == "pause" || $1 == "prev" || $1 == "next" ]] && manage_player "$1"

# Checks
[[ -z $BIN_MPV && -z $BIN_MPG123 && -z $BIN_GST123 ]] && die "You must have at least 'mpv' or 'mpg123' or 'gst123' installed to run this script."

# Main
run_player
