# Bonk's Bunker alpha2.5: Bikes, Billiards & Booze

## 🏍️ Motorcycles
- **5 bikes** to find parked around Kearney, each in 3 stock colour schemes:
  - Sandhills Scrambler 250 (dirt bike)
  - Platte Hooligan 450
  - Union Pacific Cafe 500
  - Cornhusker RR600 (sport bike)
  - Prairie King 1200 (cruiser)
- **Motorcycle Mayhem-style handling.** Pull wheelies and stoppies and lean into corners. Loop it or land badly and you're eating pavement.
- **Manual gearbox with a clutch.** Hold **Shift** for the clutch, then **E** to shift up and **Q** to shift down. Let the clutch out wrong and you'll stall.
- **Fuel.** Bikes burn gas. Gas cans (1 gal) are new loot, and **R** refuels.
- **No weapons while riding.** You can't hold or fire anything on a bike.
- Riding HUD gauges, plus real engine sounds and shift / start / stall / crash / refuel sounds.
- Bikes you take and park are saved with your world.
- Works in co-op.

| Bike controls | Key |
|---|---|
| Get on a parked bike | E |
| Start engine / refuel | B / R |
| Throttle / brake / lean | W / S / A, D |
| Lean back (wheelie) / forward (stoppie) | Space / Ctrl |
| Shift up / down (hold Shift = clutch) | E / Q |
| Get off (when slow) | F |
| Chase cam / first-person | V |

## 🎱 Pool at the Big Apple
- **Both bar tables are playable 8-ball.** Challenge another player or practice solo.
- **First person:** **E** sits you down or gets you up. Hold and release **left click** to shoot where you look.
- Aim line, ghost ball and cue stick show your shot.
- **Real 8-ball rules:**
  - The first ball potted sets solids and stripes.
  - A scratch gives your opponent ball in hand.
  - Sinking the 8 early loses; sinking it last wins.
  - An 8 sunk on the break gets re-spotted.
- Ball, rail, pocket and cue sounds.

## 🍺 Drinking, food & effects
- **16 new drinks:**
  - Beers: Platte Valley Light, Sandhills Lager, Sandhill Crane IPA, Buffalo County Stout, Warm Tallboy
  - Hard seltzers: Black Cherry, Lime, Mango
  - Shots: Bottom-Shelf Whiskey, Rotgut Vodka, Tequila, Cinnamon Fire
  - Jungle Juice, Long Island Iced Tea, Boxed Wine, Prairie Moonshine
- **New food:** John's Pork Rinds, Gas Station Hot Dog, Corn Dog.
- New **Booze** tab in the inventory.
- **Being drunk now does something:**
  - Drinks stack and last longer.
  - Your view sways and you get double vision and blur.
  - You stumble.
  - At 8+ drinks you throw up, and you wake up hungover.
- **Chems** are stronger and last longer, and the comedown scales with how much you took.
- **Hunger and thirst** drain slower: 3 hours to empty hunger, 2 hours for thirst.
- The quick eat/drink keys skip anything with an effect, so no accidental moonshine.

## 🥏 Disc golf
- **John Pork camps** at Centennial and Cottonmill. Each has a tent, John Pork's barter shop, a records board and a Meepo dock.
- **Course records** are saved and posted on the board under your name.
- Drunk or high? Your aim drifts and the power bar gets shaky.
- **Water fix:** discs that land in water stop at the surface. You take +1 and drop where the disc crossed onto the water.
- Other players now see your throwing swing.

## 🛴 Meepo docks
- **E** docks a Meepo or takes it back, and docked Meepos charge instantly.
- Docks are at both camps and the bunker.

## 🚪 Door fixes
- You can now walk into every building at the Big Apple, Merryman, Cope Stadium, the country club, the RV park and the Centennial pool bathhouse. That's 45 doorways, all with ramps.
- Moved props that blocked doorways, like the Big Apple back bar and the country club lockers.
- Removed a Merryman dock door that opened into a wall.
- Smoothed the hill in front of Cope Stadium's north door.

## Known issues
- Pool games aren't saved if you quit mid-game.

---

## Install
**Windows:** unzip and run `BonksBunker.exe`.

**Mac:** unzip, then right-click `BonksBunker.app` > Open the first time (the app isn't notarized). If macOS says it's damaged, run `xattr -cr ` followed by the app's path in Terminal.

**Split downloads:** download every `.001`, `.002` ... part into one folder and open the `.001` with 7-Zip (Windows) or The Unarchiver (Mac). Or join them first. Windows: `copy /b file.zip.001+file.zip.002 file.zip`, Mac: `cat file.zip.0* > file.zip`.
