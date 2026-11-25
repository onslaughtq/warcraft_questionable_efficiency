# Questional Efficiency

Questional Efficiency routes quests already in your World of Warcraft: Forever quest log. It sorts by quest level, then favors shorter straight-line legs among objectives at the same level. When the log is full, it looks for a practical way to free one slot.

## Install or update

1. Exit World of Warcraft. In Battle.net, select **World of Warcraft: Forever** and use the gear menu's **Show in Explorer** to find the install. Use the live `_forever_\Interface\AddOns` directory. On the verified machine it is `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`.
2. Copy the repository's [QuestionalEfficiency](QuestionalEfficiency/) folder into **AddOns**, keeping the folder name exact. The result should contain `AddOns\QuestionalEfficiency\QuestionalEfficiency_Forever.toc` directly. Copy that same source folder's contents into the installed QuestionalEfficiency folder for updates. Leave `WTF` in place to retain your settings.
3. For coordinates, database levels, finishers and chain data, install the packaged [QuestieDB Forever release](https://github.com/Questie/QuestieDB/releases/latest). The single-flavor **Forever** ZIP and the release's recommended **all** ZIP both work. Extract the `QuestieDB` folder next to `QuestionalEfficiency`. Verify that it contains `QuestieDB_Forever.toc`. If you already have the correct version, keep it. Update QuestieDB with the maintainer's packaged addon instructions.
4. Start Forever and enable **Questional Efficiency** and **QuestieDB** in the character-select **AddOns** list. Log in and type `/qe show`.

The base addon has no hard dependencies. QuestieDB supplies location and chain data, and its provider API works without Questie enabled. The route remains readable with client levels, objective progress and classification if QuestieDB is absent or loading. World-map markers and the arrow use Blizzard UI APIs. The installed files run inside WoW without network services, API keys or a companion app.

## Commands and controls

| Command or control | Effect |
| --- | --- |
| `/qe`, `/qe toggle`, `/qe show`, `/qe hide` | Toggle, show or hide the window. Drag the title to move it. |
| `/qe help` | List commands. |
| **Route** / **Quest log** | Browse ordered steps or inspect every readable quest, including excluded, deferred and failed quests. Clicking a title or step shows its details. |
| **Do this next** | Explicitly promote the selected unfinished objective or turn-in above automatic priority. The priority expires when that step goes away. |
| **Skip for now** / **Resume step** | Defer one step or return it to automatic routing. Find a deferred step under **Quest log**. |
| **Exclude** / **Include** / **Clear override** | Change the selected quest's classification for this log, or restore automatic classification. **Include** can override the dungeon/raid filter when classification is wrong. |
| **Show on map** | Open the location of the selected step. A preview marker appears if route pins are enabled. |
| **Chain note…** | When chain status is unknown, record a standalone quest or a chain ending you already know about. The note is labeled as yours. Use **Clear note** to remove it. |
| **Undo** or `/qe undo` | Undo a recent manual change. The undo stack lasts for this login or UI session. It reconciles against current quests and objectives. |
| **Reset to automatic route** or `/qe reset` | Confirm clearing the manual next priority, deferred steps, include/exclude overrides and chain notes. The reset can be undone during the session. |
| **Refresh route** or `/qe refresh` | Reread the log and rescore from your current position. Your manual choices still apply. |
| **Settings** or `/qe settings` | Control markers and the arrow, center the window, or open diagnostics. |
| `/qe diagnostics` or `/qe diag` | Open a copyable report with client build, capacity, addon status and aggregate counts. |

Window position, visibility and navigation settings use account SavedVariables. Quest overrides, deferred steps, next priority and chain notes use per-character SavedVariables and are cleared when their quest or step expires. The addon never accepts quests, turns them in, selects rewards or controls your character.

## How routing works

- The client provides the full log, completion state, outdoor group hints, dungeon/raid tags and standard-quest capacity. Dungeon and raid tags exclude a quest by default. A database location can also exclude a quest when its objective or turn-in has only instance locations verified by the client's Encounter Journal. Some untagged quests and instances lack enough evidence to classify automatically.
- Normal mode puts known levels in ascending order. It uses QuestieDB's quest level when available, with the client level as the fallback. A scaling quest uses its effective client level when available. Unknown levels sort after known levels. Among equal levels, the addon greedily picks the closest comparable next step from the prior stop. Quest ID and objective index break ties.
- QuestieDB points are candidate locations. The addon associates live rows with database objectives using unique names and objective types. Ambiguous matches, spell targets without a confirmed location, invalid map IDs and instance-only coordinate sentinels can have unknown locations. The addon keeps these steps visible. A phase-dependent point may be unavailable to your character. A quest with every objective finished can remain in **Quest log** while the addon waits for the client to confirm turn-in readiness.
- Full-log mode activates at the client-reported standard quest cap. It scores a finishable quest from its remaining objective count, estimated straight-line travel through those objectives and to its finisher, completion status and chain evidence. The estimate strongly favors practical completed turn-ins, with level as a tiebreaker. Travel and work penalties use internal scoring units. A long or incomparable trip can outweigh preference for a chain ending. A quest with a known follow-up can still free a slot if you defer accepting the follow-up.
- A direct follow-up or reverse prerequisite can supply branch evidence. The packaged Forever database returns zero for omitted successors, so a zero with no attributable correction remains **Chain unknown**. Explicit terminal evidence from a provider correction or a manual chain note gets a preference. A recorded branch count describes database links. Whether every branch will be available to your character depends on its prerequisites.
- A valid target and its chosen spawn stay fixed while you move, including through partial progress on the current objective. Objective completion, removal, a newly higher-priority level, a full-log mode transition or an explicit routing action can advance or change the destination. Refresh deliberately rescores it. A chain note affects the next automatic choice or an explicit refresh.
- The arrow uses your character's facing. Pins show the first 12 route positions that project onto the open map, plus an optional selected-step preview. Identical pin locations share a marker. Distance is shown in yards where both endpoints share a world coordinate space. A same-map fallback can prioritize nearby normalized coordinates when world distances are unavailable. Cross-continent, restricted, missing or incompatible locations can have no distance or arrow. These are straight-line estimates and do not account for terrain, boats, portals or travel time.

## Verification and development

This source targets Forever `1.60.1.71091`, product `wowf`, Interface `16001`. The installed product version and the installed QuestieDB 1.1.6 Forever TOC were checked against the matching client UI export and dependency release. Use `/qe diagnostics` to confirm the build and provider in the running client. Follow the [in-game checklist](TESTING.md) for engine behavior that requires a logged-in character.

Run `lua5.1 tests/run.lua` and `lua5.1 tests/smoke.lua` from the repository root. For syntax checks, run `luac5.1 -p` on the addon and test Lua files. The tests supply mock client data to the actual routing and adapter code. Source files are separated into the client adapter, QuestieDB adapter, route, saved settings, navigation, UI and event controller. Keep editing here and copy only the addon folder's contents for installation.

Technical references used for this build

- [Forever Blizzard quest API documentation from matching build](https://github.com/Gethe/wow-ui-source/blob/c01a87b549bbc19e0f284c1616d18654c91297de/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua) and [Forever's Blizzard quest-count UI](https://github.com/Gethe/wow-ui-source/blob/c01a87b549bbc19e0f284c1616d18654c91297de/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/QuestMapFrameUtils.lua).
- [Forever Blizzard map API documentation](https://github.com/Gethe/wow-ui-source/blob/c01a87b549bbc19e0f284c1616d18654c91297de/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua) and [Blizzard MapCanvas source](https://github.com/Gethe/wow-ui-source/tree/c01a87b549bbc19e0f284c1616d18654c91297de/Interface/AddOns/Blizzard_MapCanvas).
- [QuestieDB 1.1.6 public API](https://github.com/Questie/QuestieDB/blob/v1.1.6/docs/api.md), [Forever data notes](https://github.com/Questie/QuestieDB/blob/v1.1.6/docs/forever.md), and [1.1.6 release](https://github.com/Questie/QuestieDB/releases/tag/v1.1.6).
