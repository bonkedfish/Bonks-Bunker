# Bonk's Bunker alpha3.2: Something Is Breathing

The zombies got real faces, and they learned to scare you.

## 🧟 Realistic zombies
- **Shamblers, Runners, Riot Cops, Spitters and Bloaters are now realistic, fully animated zombies** instead of the old cartoon ones: soldiers, a cop, a girl in a torn dress, something that used to be a man, and a hulking brute for the Bloater.
- Each type gets its own walk, idle, run, attacks, hit reactions and death.

## 😱 They hunt you now
- **They scream when they spot you.** A shriek, a beat, then a sprint straight at you. Any zombie within 45 metres hears it and comes running.
- **Crawlers.** Some have no legs left. They are low, slow, and hard to see in the grass. Aim down.
- **They don't always stay down.** Some drop on what should have been the killing shot, lie there a few seconds, then get back up. Put another round in anything that falls a little too easily.
- **Lurkers** wait against walls and in doorways without moving until you walk right past.
- **Stalkers, at night.** They freeze while you look at them. Turn around and they come closer.
- **Flankers.** When a few are after you, some circle round to your side instead of walking in a line.
- **Uneven, lurching walks**, heads and arms that snap and jerk, no two moving quite alike.

## 🔊 Sound
- **Groans that get closer.** The nearest few zombies groan and moan, so you can hear where they are.
- **Breathing** when one is close: wet, ragged, right beside you.
- **A heartbeat** that speeds up as one closes in.
- **Muffled hearing** when one is right on you: the world goes dull and far away.
- A snarl on every swing.

## 👁️ On screen
- **Their eyes catch the light at night.** Two pale points in the dark, out to about 45 metres.
- **The camera shakes** when one screams nearby and when you get hit.
- **When one grabs you**, the colour drains out of the world and the edges close in dark red.

## 🏙️ World fixes
- **Buildings no longer stand in the middle of roads.** The whole town was rebuilt with roads laid down first, and any footprint sitting on a street was dropped.

## ⚡ Performance
- The new zombies use compressed textures: a 48-zombie horde fits in about **270 MB of video memory** instead of 585 MB.
- 48 zombies at night, every scare feature on: about 6 ms a frame on an RTX 4060.

## Install
**Windows:** unzip and run `BonksBunker.exe`.

**Mac:** unzip, then right-click `BonksBunker.app` > Open the first time (the app isn't notarized). If macOS says it's damaged, run `xattr -cr ` followed by the app's path in Terminal.

**Split downloads:** download every `.001`, `.002` ... part into one folder and open the `.001` with 7-Zip (Windows) or The Unarchiver (Mac). Or join them first. Windows: `copy /b file.zip.001+file.zip.002 file.zip`, Mac: `cat file.zip.0* > file.zip`.

Saves from alpha3.1 carry over.
