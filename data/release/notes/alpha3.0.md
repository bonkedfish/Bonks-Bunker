# Bonk's Bunker alpha3.0: Loot, Looks & Links

## 🧍 Character creator
- **Make your survivor every time you load in.** It opens already filled in, so one click on Play keeps your look.
- Pick your **body**, **skin tone**, **hair** and **hair colour**, a **beard**, and **shirt / pants / shoes** colours.
- Add a **hat** (ball cap, beanie, hard hat, cowboy hat, bandana) and an **extra** (backpack, bandolier, goggles, scarf), each in the colour you choose.
- Spinning 3D preview (drag to turn it) and a **Randomize** button.
- Your name and look are saved with your character in each world, and other players see them in co-op.

## 🔫 Armor, weapons & loot
- **Gear slots:** 2 guns, 1 melee/thrown, plus **helmet, chest and legs** armor.
- **10 weapons:**
  - 9mm pistol, .44 revolver, SMG, pump shotgun, hunting rifle, AR, sniper rifle
  - baseball bat, combat knife, fire axe
- **Rarity rolls:** Worn, Standard, Pristine and Legendary (legendaries get a perk). Condition wears down with use.
- **Mods:** red dot, 4x scope, suppressor, compensator, extended mag, quick mag. Attach them at the bunker workbench.
- **Repairs:** fix weapons and armor at the workbench with scrap metal.
- **Armor** takes a cut off every hit, up to 70% for a full legendary set, and wears down as it blocks.
- **Aim / scope with right click.** The sniper zooms in properly.
- Bosses drop gear. Dropped gear keeps its roll when someone picks it up.
- **Golden Ace Disc:** now a legendary throwing weapon. It hits hard and flies back to your hand.

## ⛳ Golf, done right
- **3-click swing meter:** click to start, click to set power, click on the line for accuracy. Early hooks, late slices, miss it and you shank.
- **Camera behind the ball**, with the full-power shot arc and a landing ring. Putts get an aim line and slope arrows.
- **6 clubs + putter.** The course picks a club for the distance, and the putter on the green.
- **Kearney Country Club is playable:** all 18 holes on the real terrain. Press **E at any tee sign** to start a round. Fairway, rough, bunkers and greens play differently, trees knock balls down, and water and out of bounds cost a stroke. A marker with your name floats over your ball.
- The Drop Zone driving range and putting course use the new swing. The putting greens now have slopes.

## 🥒 Pickleball, rebuilt
- **Timed swings:** every swing has a wind-up and a recovery, so spam clicking just whiffs.
- **Timing grades:** Perfect, Good, Early, Late, Whiff. Perfect shots fly flat and deep.
- **Real rules:** the two-bounce rule, and no volleys from the kitchen.
- **Smarter CPU:** it lobs anyone camping at the net and smashes floaters.
- Ball shadow, landing ring, rally counter and score callouts.

## 🌐 Multiplayer fixes
- Creating or joining a lobby no longer needs a restart. A failed or dropped session resets to the menu and tells you why.
- Two dead lobby servers were swapped for working ones.
- Fixed John Pork not talking or trading for guests in co-op.
- **Every player has their own colour.** Names show on the minimap, the big map and the disc golf scorecard instead of P1/P2.

## 🛠️ Fixes
- **All road blocks are removed.**
- **Tree collisions now match the trees.** Discs no longer bounce off thin air.
- **No more falling through the world:**
  - The country club pool hole is fixed, and the drained pool has a ramp out.
  - If you do fall, you're put back where you last stood.
  - The pause menu has **Respawn at Bunker**.

| New controls | Key |
|---|---|
| Gun slot 1 / 2 | 1 / 2 |
| Melee / thrown slot | 4 |
| Aim / scope | Right click |
| Golf swing (start / power / accuracy) | Left click x3 |
| Change club | 3 or mouse wheel |
| Golf / putting scorecard | Q |

## Install
**Windows:** unzip and run `BonksBunker.exe`.

**Mac:** unzip, then right-click `BonksBunker.app` > Open the first time (the app isn't notarized). If macOS says it's damaged, run `xattr -cr ` followed by the app's path in Terminal.

**Split downloads:** download every `.001`, `.002` ... part into one folder and open the `.001` with 7-Zip (Windows) or The Unarchiver (Mac). Or join them first. Windows: `copy /b file.zip.001+file.zip.002 file.zip`, Mac: `cat file.zip.0* > file.zip`.

Saves from alpha2.x carry over. Old weapons become rolled gear, and old characters start with a random look you can change in the creator.
