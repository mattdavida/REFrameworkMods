# Johari Shard / Oni Sense

Research notes. The trainer no longer ships a Johari tab or `oni_sense.lua`.

Player-facing name: **Johari Shard** (King Enma's mirror, L2+R2 / LT+RT while exploring).  
Internal name: **Oni Eyes** / **Oni Sense**. There is no `Johari` string in the REFramework dump.

This is a timed world-query pulse: input chord → player pose → supporter module → detector scan → nav icons + guide light → expire → cooldown. Same family as Witcher Sense / detective vision. The always-on toggle keeps the supporter in `ACTIVE` and ignores the room lock.

## Runtime path

```
LT + RT  (or MKB_ONI_EYE_SONER)
        ↓
PlayerCommonSubAction.cOniEyesActivationBase
  PlayerBasicSubAction.cOniEyesActivation
  PlayerOneHandedSubAction.cOniEyesActivation
        ↓
cPlayerCharacterEntity.get_OniEyeActivationSupporter()
        ↓
cPlayerOniEyeActivationSupporter
  PHASE: NONE(0) → START(1) → ACTIVE(2)
  nortifyStartActivation / nortifyStartActivationDelay / readyActive
  updateOniSenseTarget / updateAutoDetectItemTargetList / updateEffect
  finishActive
```

Two different presentations share this supporter:

| What you see | What it is |
| --- | --- |
| Glowing eyes / gauntlet | Activation pose + `_EyeActivationEffectContainer`. `nortifyStartActivation` is enough. |
| White ground shard (Johari light) | A detector hit on `_OniSenseTarget`, then `app.PlayerManager.requestOniSenseStartEffect`. Needs the **spread search** to finish. |

The pose is optional. The shard is not. A pulse that only starts eyes and then freezes timers will never spawn a marker.

Search loop while `PHASE == ACTIVE`:

1. `_OniActivationSpreadTimer` grows `_CurrentSearchDistance` from `_ActivationStartPlayerPos`.
2. `_Detector` (`cPlayerOniEyeActivationDetectorSearcher`, single-frame, slot 9) filters joints.
3. `searchOniSenseTargetJonint` / `updateOniSenseTarget` pick one destination.
4. `onOniSenseFindTiming` → `PlayerManager.requestOniSenseStartEffect` (VFX `ONI_SENSE_START` / `LOOP`).
5. Walk inside `_OniSenseEndRange` and that marker is consumed. A **new pulse from the new position** is what finds the next shard.

Always-on must let spread/vanish run, then `finishActive` + `nortifyStartActivation` again. Do not skip `finishActive` and do not reset the spread timer — that was glowing-eyes-only, and it also blocked L2+R2 until a reload.

## Duration (why it only lasts a bit)

`app.user_data.PlayerOniChangeParam.cOniEyeActivationParam` on the supporter `_Param`:

| Field | Role |
| --- | --- |
| `_SpreadSecond` | Pulse expands (`_OniActivationSpreadTimer`) |
| `_VanishSecond` | Pulse fades (`_OniActivationVanishTimer`) |
| `_CoolTime` | Cannot restart (`_CoolTimer`) |
| `_DetectIconDispTime` | How long destination icons stay |
| `_OniSenseStartRange` / `_OniSenseEndRange` | Guide-light distance (+ `_SkillUp` variants) |
| `_DetectItemRangeMax` / `_DetectItemRangeOuter` | Item / gimmick sonar |
| `_ActivationStartRange` / `_ActivationRangeMax` | Activation collect radius |
| flash / absorption frames | Gauntlet VFX only |

Always-on resets vanish/spread while `PHASE == ACTIVE`, skips `finishActive`, and retriggers from `NONE`.

## Why rifts kill it

Most likely stack (all present in the dump):

1. **`PlayerDef.CONTINUE_FLAG.DISABLE_ONI_EYE_ACTIVATION = 18`** on `cPlayerCharacterEntity._PlayerContinueFlag` (`ace.cContinueFlag`). Locked combat / rift rooms set this. Checked via `checkPlayerContinueFlag`. The toggle hooks that check to false and also `off(18)`.
2. **Per-target `cPlayerOniEyeActivationDetectorAttribute.DisableOniSense`**. Destinations inside a sealed room can refuse the guide light even if the pulse is running. Toggle forces the getter false.
3. **`mcGimmickOniSense.isSenseEyeHide`**. Gimmick-side hide callback. Toggle forces false.
4. **`fsm_condition.CheckEnableOniSense`** (`NEAR` / `MIDDLE` / `FAR`) gated by mission tag, stage, context tag. This drives *world* reactions (appear / blockade), not the player pulse itself.
5. **`GmOniEyeBlockadeGimmickBase`**. Objects that only exist / unlock under Oni Eye. Separate from "can I press L2+R2".
6. **`isUnlockOniSense` / skill tree `ONI_EYE_LV1..3`**. Story / shrine unlock. Toggle forces true so the pulse can run before the skill is bought.

If a rift still shows no light after the toggle, the destination object itself is probably not registered on detector slot `PLAYER_ONI_EYE_ACTIVATION_DETECTOR` (9). That is content, not the pulse.

## Detector / guide light

`cPlayerOniEyeActivationDetectorAttribute` on each highlightable object:

- `DisableOniSense`
- `OverwriteOniSenseLevel` (`NONE=0 LOW=1 MEDIUM=2 HIGH=3`)
- `NaviIconOffset`
- `GroupOwner`

The supporter keeps:

- `_OniSenseTarget` — current guide destination (`ace.cDetectorTargetJoint`)
- `_SonarDetectIconList` — item / gimmick pings
- `_OniActivationTargetList` — joints that got the pulse
- `_SonarZoneGimmickTargetList`

`getOniSenseTargetTagID` / `getOniSenseTargetContext` are the live "what is the light pointing at" API.

World objects opt in with `mcGimmickOniSense` (`registerCheckFunc`, `isSenseEyeHide`).

## Input

Tutorial: hold/press LT+RT in Eastern Kyoto.

`PlayerKeyType` has no dual-trigger enum. Pad mapping is a combo that starts `cOniEyesActivation`. Mouse/keyboard is `MKB_ONI_EYE_SONER = 43`.

`isUseEyeActivation(cPlayerCommandResult)` is the command-side "did the player ask for the pose". Do not force this — it would spam the animation.

## VFX / audio IDs (portable checklist)

| ID | Use |
| --- | --- |
| `ONI_EYES_START` / `IDLE` / `END` | Pose loop |
| `ONI_EYES_SONAR` + gauntlet / flash / detection | Item ping |
| `ONI_EYES_SLOW` | Time dilation during pulse |
| `ONI_SENSE_START` / `LOOP` | Guide light |
| Icon `IconDef.INTERACT.ONI_EYE = 8` | HUD marker |
| BTable `ONI_EYES_VALID` | Script "is sense up?" |

## What the removed toggle did (`oni_sense.lua`)

`app.PlayerManager` sense API (next to the Oni Gate methods in Object Explorer):

| Method | Role |
| --- | --- |
| `getOniSenseTargetTagID` | Current guide destination id |
| `getOniSenseTargetContext` | Destination context holder |
| `requestOniSenseStartEffect` | Letter / Gm100 VFX. Do **not** call from tick. |

Oni Gate / Oni Change on the same type are a different system.

Current always-on is **flash only** (the working pulse):

- `nortifyStartActivation` when `PHASE == NONE` (~1.5s frame cooldown, cool timer forced off)
- `IsCanUpdateActive` / `isEnableOniSense` / `isUnlockOniSense` → true while toggled
- never `requestOniSenseStartEffect`, `onOniSenseFindTiming`, `readyActive`, or `reset`
- toggle off → `finishActive` + show mesh
- Restore character button if a leftover effect hid the player

Shard planting waits until `getOniSenseTargetTagID` is a real destination, not the player. Then the game's own find path can be reused — including in combat.

The supporter still owns the pulse. PlayerManager is the read/VFX surface.

## Porting this to another game

Build the same five layers. Names change; the shape does not.

1. **Input chord** — find the "sense" command, not the lore name.
2. **Timed supporter** — a module with `NONE/START/ACTIVE`, spread/vanish/cool timers, and `start` / `finish` / `update`.
3. **World query** — detector or overlap query. Per-object attributes: hidden, priority, icon offset.
4. **Presentation** — start/loop/end VFX, nav icons, optional slow-mo, rumble.
5. **Area gates** — a persist flag ("disable in combat lock"), FSM conditions, and object-side hide.

Always-on in any title is: keep layer 2 in `ACTIVE`, ignore layer 5, do not force layer 1's animation.

Do not reuse Onimusha's class names. Reuse this split. A UE game will hang the query off a component + collision channel; an RE Engine game will look like this supporter + detector slot.
