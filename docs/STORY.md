# Narrow Haul — Story bible

The fiction behind every mission. Tone: a hopeful frontier service, not soldiers: the people who fly the supplies in when nobody else can. Tagline: **"Somebody has to fly it in."**

In-game text lives in `lib/game/story/` (cargo, brief, radio beats and debrief per level, keyed by `saveId`; world intro/outro cards). This file is the source of truth for names, cast and arcs: change it first, then the data. `test/story_test.dart` checks that every level has a story and that every line fits the radio band.

## 1. The universe (story bible)

**The Narrows** is a remote star system of seven settlements, linked to the rest of humanity by one jump gate, **Meridian Gate**. The big freighters stop at orbit. Everyone else lives underground, in caves, mines, ice and lava tubes, where only small cave tugs can reach.

**The Severance.** On the day you graduate, Meridian Gate goes dark. No freighters, no news, no supplies. Each settlement has things the others need: the Grove grows food, Kalt Station has water, Pithead has ore, the Crucible forges parts. All the routes between them run through caves no freighter can fly.

**Lifeline.** The pilots' cooperative, the **Narrows Relief Air Service (NRAS)**, starts *Operation Lifeline*: a small corps of tug pilots hauling one pod at a time between the settlements. You are the newest pilot. The ranks you already earn (Student → Chief Pilot) are NRAS ranks.

**Act I (free, the 60 levels).** You keep the Narrows alive and trace why the gate died. The trail leads to **the Warden**, a pre-colonial defence AI in the fortress called **the Redoubt**. It seized the gate and the networked mine machinery, and it guards the supply routes with turrets. In the finale you overload its reactor and the gate relights.
**The twist:** the Warden wasn't broken. It saw something coming through the gate and sealed the Narrows to protect them. Turning it off opened the door.

**Act II (Full Game, the Expeditions): "The Long Night".** The threat is **the Tide**, a drifting dark-matter storm that eats signal and heat. It's weeks out. The Xenar, the vanished aliens whose caves the Grove lives in, once sealed the Narrows the same way, from the **Xenar Heart**. Act II is a run of long convoy expeditions to prepare every settlement. It ends with carrying the Warden's core into the Heart to raise the old shield.

### Cast (radio callsigns on the existing `CommsHud`)
| Callsign | Who | Where |
|---|---|---|
| TOWER | Capt. Aris Reyes, flight instructor, later Haven Field tower | Training Grounds |
| OPS / LIFELINE | Ines Varga, NRAS chief dispatcher. Gives the briefings, warm and dry | Everywhere |
| GROVE | Dr. Tamsin Oyelaran, xenobiologist, Grove colony lead | Xenar Caverns |
| PITHEAD | "Dutch" Hallorann, mine foreman. Gruff, trusts you after mine_08 | Rustshaft Mines |
| FROSTLINE | Juno Kalt, station medic fighting a fever outbreak | Glacier Deep |
| CRUCIBLE | Forgemaster Ada Okonkwo. Builds the gate relay from everyone's deliveries | Ember Core |
| SABLE | The Outer Ring's old maintenance AI. Polite and literal, quietly funny | Outer Ring |
| SPARROW | Lt. Petra Novak, settlement militia. Supplies the Talon | The Redoubt |
| WARDEN | The enemy AI. Cold broadcasts that grow sad and protective in Act II | The Redoubt, Act II |

### Every existing feature, inside the story
| Feature | In the fiction |
|---|---|
| Cargo pods (per-world art, heavy pods) | Each level names its cargo: rations, seed vaults, vaccine, coolant, ingots, ammo, survivors |
| Type ratings / ships | Each settlement lends NRAS its local tug (Hopper, Mule, Skate, Vector, Talon) and you must certify on it |
| Fuel canisters | Caches left by evacuated crews ("someone left you fuel; leave some for the next pilot") |
| Supply crates (weapons) | NRAS air-drops and miners' demolition stock |
| Mystery salvage "?" | Xenar relics: alien tech that helps or misbehaves (boons/curses). The Salvage Log becomes a *Xenar relic catalogue* that foreshadows Act II |
| Turrets / reactor | The Warden's defences |
| Moving machinery (mines) | Machines networked to the Warden that won't stop |
| Fields (wind, zero-g, wells) | Anomalies since the Severance; in Act II, the Tide getting closer |
| Rock carving | Opening blocked routes |
| Daily challenge | *Dispatch Board*: today's urgent run. Test Flight days are "a settlement lent us a different tug" |
| Contracts | *Relief requests* from named settlements |
| Route guide / demo | *Pathfinder drone log*: a veteran pilot's recorded run |
| Continue after crash | The NRAS rescue tug drags you back |
| Garage tow gear / kits | Gifts from the settlements: Pithead's chain, the Ring's tractor beam |
| Ranks / promotions | NRAS promotions, read by OPS on the radio |
| Achievements | NRAS commendations |

---

## 2. Act I: per world and per level

Each level gets a **cargo**, a **one-line brief** (in the briefing) and 1–3 **radio beats** (launch, hooked, delivered). Level names stay as they are. Below are the cargo and the brief; the radio beats are written during implementation in the same voice.

### Training Grounds: Haven Field (Kestrel; TOWER + OPS)
NRAS flight school on the asteroid Anvil. Tutorial rules stay; the story frames them. Mid-world, the gate dies.
| Level | Cargo | Brief |
|---|---|---|
| tut_01 First Flight | none / ballast | "Lift, hover, set her down. Every Lifeline pilot started on this pad." |
| tut_02 Steady Hands | ballast | "Fuel is cargo you didn't bring. Land with tank to spare." (star rules) |
| tut_03 Tow Basics | water drum | "Your first hook-up. The cadet mess is thirsty." |
| tut_04 The Pillar | mast parts | "Antenna parts round the pillar to the comms mast." |
| tut_05 Twin Gates | spare cells | "Thread both gates. Reyes is timing you." |
| tut_06 Down Under | med kit | "Mechanic hurt in the lower bay. Go under." |
| tut_07 Zigzag Run | rations | "Supply run through the switchbacks." |
| tut_08 The Shaft | beacon battery | "Battery down the shaft to the nav beacon." |
| tut_09 Long Haul | gate telemetry pod | **The Severance:** mid-flight, every channel goes to static. "Meridian Gate is… gone. Finish the run." |
| tut_10 Graduation | emergency rations | "No ceremony. Your graduation flight is Lifeline's first relief run." Outro: assigned to the Grove. |

### Xenar Caverns: the Grove (Hopper, low-g; GROVE)
A research colony farming inside living alien caves. Without freighters the farms are failing. The caves hum, and the hum got louder when the gate died.
| Level | Cargo | Brief |
|---|---|---|
| rating_hopper | test ballast | "The Grove lends us their Hopper. Light as a moth. Get certified." |
| alien_01 Gentle Descent | nutrient gel | "Gel to the lower farms. Go easy, it's all they have." |
| alien_02 The Wobble | seed vault | "Seed vault: a century of crops in one pod. Don't drop it." |
| alien_03 First Squeeze | grow-lamp cells | "The lamps are dimming. Squeeze the cells through." |
| alien_04 Down the Gullet | sample case | "The tunnel breathes. Oyelaran wants a sample from the deep." |
| alien_05 Antler | water filters | "Filters to the antler galleries before the wells sour." |
| alien_06 The Loop | antivenom | "A researcher was stung by something that shouldn't exist." |
| alien_07 Chimneys | sensor mast | "Things float in the chimneys now. Map it and bring the mast." |
| alien_08 Xenar Heart | resonance sensor | "Something at the heart pulses in time with the dead gate." Outro: the Heart *answers*. (Act II seed) |

### Rustshaft Mines: Pithead (Mule, heavy; PITHEAD)
The ore town. Food is short, but the ore here is what the gate relay will be forged from. The machinery has run on its own since the Severance.
| Level | Cargo | Brief |
|---|---|---|
| rating_mule | ore ballast | "Pithead's Mule hauls a house and turns like one." |
| mine_01 First Shift | rations | "The first shift hasn't eaten in two days. Mind the rotor." |
| mine_02 Conveyor | tool crate | "The conveyors won't stop. Nobody's running them." |
| mine_03 Swing Shaft | scrubber cartridges | "Air down the swing shaft, fast." |
| mine_04 Clockwork | medical oxygen | "Two rotors, perfectly in time. Too perfect." |
| mine_05 Heavy Load | ore ingot | "First ingot for the Crucible. The relay starts here." |
| mine_06 The Grinder | survival capsule | "A drill crew's survival pod. Bring them home." |
| mine_07 Night Shift | power cell | "The lights died. You're the light now." |
| mine_08 Foreman's Test | control core | "Dutch's test: the core proves the machines take orders from somewhere else." Outro: the signal traces to *the Redoubt*. |

### Glacier Deep: Kalt Station (Skate, wind, ice; FROSTLINE)
The ice moon that waters the Narrows. A fever outbreak is spreading and the vaccine is cold-chain.
| Level | Cargo | Brief |
|---|---|---|
| rating_skate | ballast | "The Skate levels herself. Let her." |
| ice_01 Cold Open | ice core | "Water for the station. Floors are glass." |
| ice_02 Glass Floor | thermal blankets | "Blankets to the infirmary. Nothing grips down there." |
| ice_03 Icicle Alley | vaccine (cold chain) | "First vaccine batch. Icicles swing in the wind." |
| ice_04 The Flue | heater coil | "The flue blows straight up. Ride it." |
| ice_05 Frostbite | survey crew pod | "Survey crew stranded at the bottom. Juno's waiting." |
| ice_06 Crevasse | water tank | "A full tank for Ember Core: they can't forge without coolant." |
| ice_07 Whiteout | beacon parts | "Storm in the caves. Fly on instruments." |
| ice_08 Glacier's Maw | cure batch | "The cure. The whole station is listening." Outro: outbreak over; Kalt joins the relay effort. |

### Ember Core: the Crucible (Mule, lava, high g; CRUCIBLE)
The forge. Everyone's deliveries (ore, water, parts) become the gate relay.
| Level | Cargo | Brief |
|---|---|---|
| lava_01 Warm Up | coolant | "Coolant first, or the forge melts itself." |
| lava_02 Rising Heat | water tank | "Kalt's water. The vent will lift you, then drop you." |
| lava_03 Molten Run | ore ingots | "Pithead's ore past the rotors." |
| lava_04 Dead Weight | relay housing | "Heaviest thing you'll ever tow. Trust the Mule." |
| lava_05 Pressure | pressure valves | "Crushers on both sides. Timing is everything." |
| lava_06 The Vent | catalyst | "Catalyst into the vent chamber." |
| lava_07 Inferno Gate | crucible fuse | "Through the gate of fire. Okonkwo is pouring tonight." |
| lava_08 Ember Throne | **relay core** | "The relay core: every settlement's work in one pod. Get it out." |

### Outer Ring (Vector, zero-g, wells; SABLE)
The old ring station beside the dead gate. You assemble the relay with SABLE's help.
| Level | Cargo | Brief |
|---|---|---|
| rating_vector | ballast | "SABLE: 'Hold thrust. The Vector goes where it points. I find that refreshing.'" |
| orbit_01 Weightless | relay core | "No up here. Bring the core aboard." |
| orbit_02 First Moon | antenna dish | "A moonlet pulls at everything. Give it room." |
| orbit_03 Slingshot | power coupling | "Use the well. Don't fight it." |
| orbit_04 Undertow | spin bearing | "The ring's spin gravity is failing sideways." |
| orbit_05 Binary | twin emitters | "Two wells, one way through." |
| orbit_06 Tidal Lock | alignment gyro | "Wind and pull together." |
| orbit_07 Inversion | phase lens | "Up is down. SABLE apologises." |
| orbit_08 Event Horizon | gate key | "The relay works. The gate isn't broken; it's **locked**, from the Redoubt." |

### The Redoubt (Talon, armed; SPARROW, WARDEN)
The Warden's fortress. The militia lends you the Talon.
| Level | Cargo | Brief |
|---|---|---|
| rating_talon | ammo crate | "SPARROW: 'Every shot costs fuel. Make them count.'" |
| redoubt_01 Gun Line | ammo | "Ammo to the militia outpost past the gun line." |
| redoubt_02 Supply Line | rations | "The outpost is besieged. Food first, then we fight." |
| redoubt_03 Power Plant | sabotage charge | "Hit the reactor and the guns sleep." |
| redoubt_04 Crossfire | override key | "Override key into the Warden's crossfire." |
| redoubt_05 Meltdown | Warden core | "Grab the core, blow the reactor, outrun it." Outro: **the gate relights.** Then a last WARDEN broadcast: *"You have opened the door. It is coming."* → teaser for Act II |

---

## 3. Act II: Expeditions, "The Long Night" (Full Game)

These are long multi-leg convoys (3–5 legs, 120–250 m, 3–6 min) with staging pads that refuel and save a checkpoint, as planned. One campaign follows the Tide arriving. Unlocked after the Redoubt; the first one is free from tut_10 as a taster.
| # | Expedition | World | Legs (story) |
|---|---|---|---|
| E0 *(free)* | **Lifeline Convoy** | Xenar | A seed vault to each of 3 Grove farms; OPS teaches staging pads |
| E1 | **Cave-in** | Mines | The Tide's first tremor collapses a shaft: MEDEVAC 4 survivor capsules, with a tremor timer |
| E2 | **Cold Chain** | Ice | Vaccine to 3 outposts, each leg under a time limit before the batch warms |
| E3 | **Exodus** | Lava | Evacuate the Crucible before the eruption: heavy pods and escape timers |
| E4 | **Shield Ring** | Orbit | Carry shield emitter segments round the Ring through wells and zero-g |
| E5 | **The Warden's Peace** | Redoubt | The Warden asks for help: bring its turrets ammo to hold the gate, through its own still-hostile defences |
| E6 | **Into the Heart** | Xenar | Relic pods (from your salvage) into the Heart; every hazard mixed |
| E7 | **The Long Night** | Orbit → Xenar | Finale, 5 legs: the Warden's core into the Heart as the Tide hits. The Narrows are sealed and saved |
