#!/usr/bin/env bash

# Made by Jiab77

# Options
set +o xtrace

# Config
SERVER="YOUR-SERVER-ADDRESS"
API_KEY="YOUR-API-KEY"
LOGIN_AS="admin"
USER_ID=`curl -sSL "https://${SERVER}/Users?api_key=${API_KEY}" | jq -r '(.[] | select(.Name == "'${LOGIN_AS}'") | .Id)'`
CONNECTED_AS=`curl -sSL "https://${SERVER}/Users/${USER_ID}?api_key=${API_KEY}" | jq -r .Name`
MUSIC_GENRES=(`curl -sSL "https://${SERVER}/MusicGenres?api_key=${API_KEY}" | jq -r '.Items[] | .Name' | sed -e 's/ //gi'`)
TEST_ITEM_ID="28a495f04633a987b8ae870a598dc914"

# Infos
echo -e "\nConnected as: ${CONNECTED_AS}"
echo -e "\nGathered music genres: ${#MUSIC_GENRES[*]}"

# Music Genres Menu
for mKey in "${!MUSIC_GENRES[@]}" ; do
    echo "${mKey}. ${MUSIC_GENRES[${mKey}]}"
done
echo ; read -p "Select music genre: " SELECTED_GENRE
echo -e "\nSelected music genre: ${MUSIC_GENRES[${SELECTED_GENRE}]}"

# Generate InstantMix based on selected genre
echo -en "\nGenerating [${MUSIC_GENRES[${SELECTED_GENRE}]}] InstantMix..."
INSTANT_MIX=(`curl -sSL "https://${SERVER}/MusicGenres/${MUSIC_GENRES[${SELECTED_GENRE}]}/InstantMix?api_key=${API_KEY}" | jq -r '.Items[] | .Id'`)
echo -e " ${#INSTANT_MIX[*]} tracks."

# Loading generated InstantMix
echo -e "\nLoading [${MUSIC_GENRES[${SELECTED_GENRE}]}] InstantMix..."
for SONG in "${INSTANT_MIX[@]}" ; do
    # Gathering song data
    SONG_DETAILS=(`curl -sSL "https://${SERVER}/Items/?api_key=${API_KEY}&userId=${USER_ID}&ids=${SONG}" | jq -r '.Items[] | [.AlbumArtist,.Album,.Name]'`)
    echo -e "\nPlaying ${SONG_DETAILS[@]}...\n" | sed -e 's/, / - /gi' -e 's/"//gi'
    curl -sSL "https://${SERVER}/Audio/${SONG}/stream.mp3?api_key=${API_KEY}&audioBitRate=192000&audioSampleRate=48000" | mpg123 -v -
done

# Tests
#echo -e "\nDisplaying gathered user info:\n"
#curl -sSL "https://${SERVER}/Users/${USER_ID}?api_key=${API_KEY}" | jq .
#echo -e "\nGathering item [${ITEM_ID}] data...\n"
#curl -sSL "https://${SERVER}/Items/?api_key=${API_KEY}&userId=${USER_ID}&ids=${ITEM_ID}" | jq .
#curl -sSL "https://${SERVER}/Items/?api_key=${API_KEY}&userId=${USER_ID}&ids=${ITEM_ID}" | jq -r '.Items[] | [.AlbumArtist,.Album,.Name]'
