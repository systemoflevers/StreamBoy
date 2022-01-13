# StreamBoy

This allows you to stream a chunk of your screen to a GameBoy. Assuming you have a a WiFi cartridge exactly like mine ;P I don't have a circuit diagram of the cartridge yet, sorry!

I haven't spent any time cleaning the code so it's a snapshot of my incremental development style and is filled with vistigual cruft and commented-out code. Enjoy!

The gameboy code is built using rgbds.

The esp code is intended to run on a wemos D1 mini and is built with arduino.

The PLD is for an ATF16V8 and is built using wincupl. The PLD file is the source code and it's used to generate a jed file. I included the jed file in case that's useful to anyone who can't build from the source.

The server is python and requires FFmpeg and uses ffmpeg-python and pyautogui.
