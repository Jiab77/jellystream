# Jellystream

A simple script that gives you the possibility to listen your music from your terminal within your Jellyfin server API.

## Dependencies

The script has some dependencies that needs to be installed before trying to run it:

```
sudo apt install curl jq mpeg123
```

## How to use it

The script is quite easy to use, you basically just need to do the following before running it:

1. Create an API key
2. Put your new API key and your server address in the script
3. Save and run it

If the API key is correctly defined, you should see a text menu where you'll be asked to enter the number in front of the music genre. It will then automatically create an __IntantMix__ (_a feature from Jellyfin_) for the selected music genre which is apparently limited to __200__ songs.

That __InstantMix__ stream will be then passed to `mpeg123` (or `mpeg321`) that will read it and play the songs.

To skip tracks or play the next one, just hit `[Ctrl + C]` once.

## Todolist

* [ ] Improve navigation between tracks
* [ ] Display songs metadata
* [ ] Find a better way to kill the player
* [ ] Find a better way to pass the generated stream to __Icecast__ or similar

## Known issues

### Can't stop the player

When the stream has been loaded to `mpeg123` via the _stdin_ buffer, it can't be killed as usual while hiting `[Ctrl + C]` twice fast so the only solution I've found so far was to simply close the terminal session and it will stop everything.

## Credits

* [Jiab77](https://twitter.com/jiab77)
