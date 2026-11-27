# Questionable Efficiency

<img src="assets/logo.png" width="128" height="128" alt="Questionable Efficiency logo">

**This project is 100% vibe-coded and requires QuestieDB for World of Warcraft: Forever.**

Questionable Efficiency routes quests already in your World of Warcraft: Forever quest log. It sorts by quest level, then favors shorter straight-line legs among objectives at the same level. An optional setting prioritizes quests you can turn in when you want to make room in your log.

## Install or update

1. Exit World of Warcraft. In Battle.net, select **World of Warcraft: Forever** and use the gear menu's **Show in Explorer** to find the install. Use the live `_forever_\Interface\AddOns` directory. On the verified machine it is `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`.
2. Copy the repository's [QuestionableEfficiency](QuestionableEfficiency/) folder into **AddOns**, keeping the folder name exact. The result should contain `AddOns\QuestionableEfficiency\QuestionableEfficiency.toc` directly. Copy that same source folder's contents into the installed QuestionableEfficiency folder for updates. If the installed folder still contains `QuestionableEfficiency_Forever.toc` from an older version, remove that file so WoW uses the new manifest. Leave `WTF` in place to retain your settings.
3. Install the required [QuestieDB Forever release](https://github.com/Questie/QuestieDB/releases/latest). The single-flavor **Forever** ZIP and the release's recommended **all** ZIP both work. Extract the `QuestieDB` folder next to `QuestionableEfficiency`. Verify that it contains `QuestieDB_Forever.toc`. If you already have the correct version, keep it. Update QuestieDB with the maintainer's packaged addon instructions.
4. Start Forever and enable **Questionable Efficiency** and **QuestieDB** in the character-select **AddOns** list. Log in and left-click the map icon on the lower-left edge of the minimap or type `/qe show`.

QuestieDB supplies quest levels, coordinates, turn-in locations and chain data. Questie can stay disabled. World-map markers and the arrow use Blizzard UI APIs. The installed files run inside WoW without network services, API keys or a companion app.

## Commands and controls

| Command or control | Effect |
| --- | --- |
| **Minimap button** | Left-click the map icon to show or hide the route window. Drag it along the minimap border to move it. Its position is saved across reloads. |
| `/qe`, `/qe toggle`, `/qe show`, `/qe hide` | Toggle, show or hide the window. Drag the title to move it. |
| **Escape** | Close the route window. |
| `/qe help` | List commands. |
| **Route** / **Quest log** | Browse ordered steps or inspect every readable quest, including excluded, deferred and failed quests. Clicking a title or step shows its details. |
| **Do this next** | Explicitly promote the selected unfinished objective or turn-in above automatic priority. The priority expires when that step goes away. |
| **Skip for now** / **Resume step** | Defer one step or return it to automatic routing. Find a deferred step under **Quest log**. |
| **Exclude** / **Include** / **Clear override** | Change the selected quest's classification for this log, or restore automatic classification. **Include** can override the dungeon/raid filter when classification is wrong. |
| **Show on map** | Open the location of the selected step. A preview marker appears if route pins are enabled. |
| **Chain note…** | When follow-up status is unconfirmed, record a standalone quest or a chain ending you already know about. The note is labeled as yours. Use **Clear note** to remove it. |
| **Undo** or `/qe undo` | Undo a recent manual change. The undo stack lasts for this login or UI session. It reconciles against current quests and objectives. |
| **Reset to automatic route** or `/qe reset` | Confirm clearing the manual next priority, deferred steps, include/exclude overrides and chain notes. The reset can be undone during the session. |
| **Refresh route** or `/qe refresh` | Reread the log and rescore from your current position. Your manual choices still apply. |
| **Settings** or `/qe settings` | Enable dungeon routing, set a quest slot target, control navigation, or open diagnostics. |
| `/qe diagnostics` or `/qe diag` | Open a copyable report with client build, capacity, addon status and aggregate counts. |

Window position, visibility, navigation and routing settings use account SavedVariables. Quest overrides, deferred steps, next priority and chain notes use per-character SavedVariables and are cleared when their quest or step expires. The addon never accepts quests, turns them in, selects rewards or controls your character.

## Dungeon routing and quest slots

- Enable **Include dungeon quests in routing** to add recognized dungeon quests. Raid quests stay excluded by default. Per-quest **Include** and **Exclude** overrides still apply.
- **Keep quest slots open** starts unchecked with a target of **5**. While unchecked, normal routing continues even when the log is full. Check it and set the target to **1** to prioritize freeing a slot only when the log is full. Enter a whole number and press **Set** or **Enter**. A target of **0** also keeps normal routing active.
- The route header shows your open slots and the enabled target. Normal routing resumes when you reach the target. With some slots still open and the target unmet, the route looks for confirmed explored outdoor stops. That outdoor mode pauses inside dungeons and raids. Turn in the suggested quests yourself to open the slots.

## How routing works

- The client provides the full log, completion state, outdoor group hints, dungeon/raid tags and standard-quest capacity. A database location can also classify a quest when its objective or turn-in has only instance locations verified by the client's Encounter Journal. Some untagged quests and instances lack enough evidence to distinguish dungeons from raids.
- Normal mode puts known levels in ascending order. It uses QuestieDB's quest level when available, with the client level as the fallback. A scaling quest uses its effective client level when available. Unknown levels sort after known levels. Among equal levels, the addon greedily picks the closest comparable next step from the prior stop. Quest ID and objective index break ties.
- QuestieDB points are candidate locations. The addon associates live rows with database objectives using unique names and objective types. Ambiguous matches, spell targets without a confirmed location, invalid map IDs and instance-only coordinate sentinels can have unknown locations. The addon keeps these steps visible. A phase-dependent point may be unavailable to your character. A quest with every objective finished can remain in **Quest log** while the addon waits for the client to confirm turn-in readiness.
- With **Keep quest slots open** enabled and a positive target, full-log mode activates at the client-reported standard quest cap. It automatically recommends a quest only if the client confirms an explored location for every remaining objective and its turn-in. It uses explored alternatives when a step has multiple locations. If none qualify, the route explains why and the quests remain in **Quest log**, where you can choose a step with **Do this next**. The exploration check covers the stops themselves. It cannot check terrain or the route between them.
- Among those eligible quests, full-log mode weighs remaining objective work, estimated straight-line travel, completion status and chain evidence. The estimate strongly favors practical completed turn-ins, with level as a tiebreaker. The scoring favors confirmed standalone quests and chain endings when practical. A recorded follow-up can still free a slot if you defer accepting it.
- **No follow-up recorded (unconfirmed)** means QuestieDB has a quest record and the chain scan found no outgoing links. It receives a small preference over missing follow-up data, while a confirmed standalone quest or chain ending gets the stronger preference. A zero in the packaged database can represent an omitted successor. Explicit terminal evidence comes from an attributable provider correction or your **Chain note**. Recorded branches are database links whose availability can depend on other prerequisites.
- A valid target and its chosen spawn stay fixed while you move, including through partial progress on the current objective. Objective completion, removal, a newly higher-priority level, a full-log mode transition or an explicit routing action can advance or change the destination. Refresh deliberately rescores it. A chain note affects the next automatic choice or an explicit refresh.
- The arrow uses your character's facing. Pins show the first 12 route positions that project onto the open map, plus an optional selected-step preview. Identical pin locations share a marker. Distance is shown in yards where both endpoints share a world coordinate space. A same-map fallback can prioritize nearby normalized coordinates when world distances are unavailable. Cross-continent, restricted, missing or incompatible locations can have no distance or arrow. These are straight-line estimates and do not account for terrain, boats, portals or travel time.

## Verification and development

This source targets Forever `1.60.1.71091`, product `wowf`, Interface `16001`. The installed product version and the installed QuestieDB 1.1.6 Forever TOC were checked against the matching client UI export and dependency release. Use `/qe diagnostics` to confirm the build and provider in the running client. Follow the [in-game checklist](TESTING.md) for engine behavior that requires a logged-in character.

Run `lua5.1 tests/run.lua` and `lua5.1 tests/smoke.lua` from the repository root. For syntax checks, run `luac5.1 -p` on the addon and test Lua files. The tests supply mock client data to the actual routing and adapter code. Source files are separated into the client adapter, QuestieDB adapter, route, saved settings, navigation, UI and event controller. Keep editing here and copy only the addon folder's contents for installation.

## Release versioning

Questionable Efficiency follows the [Haskell Package Versioning Policy](https://pvp.haskell.org/). Set the release version in `QuestionableEfficiency/QuestionableEfficiency.toc` using `A.B.C` with optional additional numeric components. Apply the compatibility rules to the addon's supported interface, including documented slash commands and the ability to load existing saved settings.

- For a breaking change, increase the major version `A.B`. For example, `0.2.0` can become `0.3.0`.
- For a backward-compatible addition, increase the minor component `C` when `A.B` stays the same. For example, `0.2.0` can become `0.2.1`.
- For changes that leave the supported interface unchanged, `A.B.C` can stay the same. Use an additional component to distinguish a new release, for example `0.2.0.1`.

## Build the CurseForge ZIP

With Docker and the Compose plugin running, run this from the repository root in Bash:

```bash
bash ./build-release.sh
```

The script runs the `package` service in `compose.yaml`. Docker builds an Alpine image with the `zip` utility and reuses the cached build on subsequent runs. The container reads the version from the addon manifest and writes `dist/QuestionableEfficiency-<version>.zip` on your machine. The ZIP contains the addon files and GPLv3 license under one `QuestionableEfficiency/` folder. Upload it for **WoW Forever** and select **QuestieDB** as a required dependency. The [project logo](assets/logo.png) is a separate upload.

## Technical references

- [Forever Blizzard quest API documentation from matching build](https://github.com/Gethe/wow-ui-source/blob/c01a87b549bbc19e0f284c1616d18654c91297de/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua) and [Forever's Blizzard quest-count UI](https://github.com/Gethe/wow-ui-source/blob/c01a87b549bbc19e0f284c1616d18654c91297de/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/QuestMapFrameUtils.lua).
- [Forever Blizzard map API documentation](https://github.com/Gethe/wow-ui-source/blob/c01a87b549bbc19e0f284c1616d18654c91297de/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua) and [Blizzard MapCanvas source](https://github.com/Gethe/wow-ui-source/tree/c01a87b549bbc19e0f284c1616d18654c91297de/Interface/AddOns/Blizzard_MapCanvas).
- [Forever's Blizzard map exploration API](https://github.com/Gethe/wow-ui-source/blob/c01a87b549bbc19e0f284c1616d18654c91297de/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapExplorationDocumentation.lua) and [Blizzard's use of exploration IDs at a map position](https://github.com/Gethe/wow-ui-source/blob/c01a87b549bbc19e0f284c1616d18654c91297de/Interface/AddOns/Blizzard_FrameXMLUtil/Mainline/MapUtil.lua).
- [QuestieDB 1.1.6 public API](https://github.com/Questie/QuestieDB/blob/v1.1.6/docs/api.md), [Forever data notes](https://github.com/Questie/QuestieDB/blob/v1.1.6/docs/forever.md), and [1.1.6 release](https://github.com/Questie/QuestieDB/releases/tag/v1.1.6).

## License

Questionable Efficiency is licensed under the GNU General Public License, version 3 only (GPL-3.0-only). See [LICENSE](LICENSE) for the full text.
