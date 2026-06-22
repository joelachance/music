tell application "Spotify"
	launch
	set stateText to player state as string
	if stateText is "stopped" then
		return stateText
	end if

	set trackName to name of current track
	set artistName to artist of current track
	set coverURL to artwork url of current track
	return stateText & " | " & artistName & " - " & trackName & " | " & coverURL
end tell
