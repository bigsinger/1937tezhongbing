using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Mission1937.Remake.Resources;

namespace Mission1937.Remake.ResourceTool;

internal sealed record LegacySaveImportResult(
    JsonObject Document,
    int ActorCount,
    int DynamicEnemyCount,
    int BuriedEnemyCount,
    int RemainingPickupCount,
    int InferredObjectiveCount);

internal static class LegacySaveImporter
{
    private const int PatrolBehaviorState = 0;
    private const int ChaseBehaviorState = 1;
    private const int SearchBehaviorState = 3;
    private const int CorpseDiscoveryBehaviorState = 6;
    private const int RestoredTargetMaximumDistance = 96;

    private static readonly HashSet<int> SupportedBackpackItemIds =
    [
        33, 46, 47, 48, 49, 50, 51, 52, 53, 54, 82, 83, 92, 101
    ];

    public static LegacySaveImportResult Build(
        LegacySaveSnapshot snapshot,
        string dataDirectory,
        string slotId,
        LegacySavePreview? preview = null)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        ArgumentException.ThrowIfNullOrWhiteSpace(dataDirectory);
        if (string.IsNullOrWhiteSpace(slotId) ||
            slotId.Length > 32 ||
            slotId.Any(character =>
                !char.IsAsciiLetterOrDigit(character) &&
                character is not '_' and not '-'))
        {
            throw new ArgumentException(
                "The imported slot ID must contain only ASCII letters, digits, '_' or '-'.",
                nameof(slotId));
        }

        var fullDataDirectory = System.IO.Path.GetFullPath(dataDirectory);
        var actorCatalog = ReadJsonObject(
            System.IO.Path.Combine(
                fullDataDirectory,
                "original_runtime_actor_catalog.json"));
        var weaponCatalog = ReadJsonObject(
            System.IO.Path.Combine(
                fullDataDirectory,
                "original_initial_weapon_inventory.json"));
        var missionsDocument = ReadJsonObject(
            System.IO.Path.Combine(fullDataDirectory, "missions.json"));
        var combatProfiles = ReadJsonObject(
            System.IO.Path.Combine(fullDataDirectory, "combat_profiles.json"));
        var worldPickups = ReadJsonObject(
            System.IO.Path.Combine(fullDataDirectory, "world_pickups.json"));

        var levelId = snapshot.Level.LevelId;
        var levelActors = RequiredObject(
            RequiredObject(actorCatalog, "levels"),
            levelId);
        var actorProfiles = RequiredObject(levelActors, "actors");
        var levelWeapons = RequiredObject(
            RequiredObject(weaponCatalog, "levels"),
            levelId);
        var playerScenes = new HashSet<int>();
        foreach (var playerNode in RequiredArray(levelWeapons, "players"))
        {
            if (playerNode is JsonObject player)
            {
                playerScenes.Add(Int(player, "scene_index"));
            }
        }

        var mission = FindMission(missionsDocument, levelId);
        var rescueScenes = RescueSceneIndices(mission);
        var combatTargetScenes = CombatTargetSceneIndices(mission);
        var savedByScene = snapshot.SceneList.Entities.ToDictionary(
            entity => entity.SceneIndex);
        var baseByScene = snapshot.BaseSceneList.Entities.ToDictionary(
            entity => entity.SceneIndex);
        var profileByItem = CombatProfileByItem(combatProfiles);
        var actorTemplateByDatabaseId =
            new Dictionary<int, JsonObject>();
        foreach (var pair in actorProfiles)
        {
            if (pair.Value is not JsonObject profile)
            {
                continue;
            }

            var databaseEntryId = Int(
                profile,
                "database_entry_id",
                -1);
            if (databaseEntryId >= 0 &&
                !actorTemplateByDatabaseId.ContainsKey(databaseEntryId))
            {
                actorTemplateByDatabaseId[databaseEntryId] = profile;
            }
        }

        var squad = new JsonArray();
        var enemies = new JsonArray();
        var escorts = new JsonArray();
        var ambient = new JsonArray();
        var actorRecordByScene = new Dictionary<int, JsonObject>();
        var firstLivingPlayerSelected = false;
        foreach (var pair in actorProfiles
                     .OrderBy(pair => int.Parse(pair.Key)))
        {
            if (pair.Value is not JsonObject actorProfile)
            {
                continue;
            }

            var sceneIndex = int.Parse(pair.Key);
            var state = savedByScene.GetValueOrDefault(sceneIndex)
                ?? baseByScene.GetValueOrDefault(sceneIndex);
            if (state is null)
            {
                continue;
            }

            var isPlayer = playerScenes.Contains(sceneIndex);
            var selected =
                isPlayer &&
                !firstLivingPlayerSelected &&
                state.DeathState == 0 &&
                state.CurrentHitPoints > 0;
            var actorRecord = BuildActorRecord(
                actorProfile,
                state,
                selected,
                profileByItem);
            actorRecordByScene[sceneIndex] = actorRecord;
            if (selected)
            {
                firstLivingPlayerSelected = true;
            }

            if (isPlayer)
            {
                squad.Add(actorRecord);
            }
            else if (rescueScenes.Contains(sceneIndex))
            {
                var original = baseByScene.GetValueOrDefault(sceneIndex);
                var rescued = original is not null &&
                    SquaredDistance(original, state) > 40 * 40;
                actorRecord["escort"] = new JsonObject
                {
                    ["rescued"] = rescued,
                    ["follow_scene_index"] = playerScenes
                        .Order()
                        .FirstOrDefault(-1),
                    ["follow_display_name"] = string.Empty
                };
                escorts.Add(actorRecord);
            }
            else if (
                Int(actorProfile, "runtime_faction_id") == 1 ||
                combatTargetScenes.Contains(sceneIndex))
            {
                actorRecord["ai"] = BuildAiState(
                    state,
                    savedByScene,
                    playerScenes);
                enemies.Add(actorRecord);
            }
            else
            {
                actorRecord["ambient"] = BuildAmbientState(state);
                ambient.Add(actorRecord);
            }
        }

        var dynamicEnemyCount = 0;
        var reinforcementSerial = 1;
        foreach (var state in snapshot.AddedEntities
                     .OrderBy(entity => entity.SceneIndex))
        {
            if (!actorTemplateByDatabaseId.TryGetValue(
                    state.DatabaseEntryId,
                    out var template) ||
                Int(template, "runtime_faction_id") != 1 ||
                state.DatabaseEntry?.CategoryName != "角色")
            {
                continue;
            }

            var record = BuildActorRecord(
                template,
                state,
                false,
                profileByItem);
            record["scene_index"] = state.SceneIndex;
            var ai = BuildAiState(
                state,
                savedByScene,
                playerScenes);
            var legacyCorpse = ai["legacy_corpse"] as JsonObject;
            if (legacyCorpse is null)
            {
                legacyCorpse = new JsonObject();
                ai["legacy_corpse"] = legacyCorpse;
            }
            legacyCorpse["reinforcement_spawned"] = true;
            legacyCorpse["reinforcement_serial"] = reinforcementSerial;
            legacyCorpse["reinforcement_source_marker_scene_index"] = -1;
            legacyCorpse["reinforcement_leader_scene_index"] = -1;
            record["ai"] = ai;
            enemies.Add(record);
            actorRecordByScene[state.SceneIndex] = record;
            reinforcementSerial++;
            dynamicEnemyCount++;
        }

        var burialCaches = new JsonArray();
        var buriedEnemySceneIndices = new JsonArray();
        var claimedBurialSources = new HashSet<int>();
        foreach (var cacheEntity in snapshot.AddedEntities
                     .Where(entity => entity.DatabaseEntryId == 1001)
                     .OrderBy(entity => entity.SceneIndex))
        {
            var source = savedByScene.Values
                .Where(entity =>
                    actorRecordByScene.ContainsKey(entity.SceneIndex) &&
                    entity.DeathState != 0 &&
                    !claimedBurialSources.Contains(entity.SceneIndex))
                .OrderBy(entity =>
                    SquaredDistance(entity, cacheEntity))
                .ThenBy(entity => entity.SceneIndex)
                .FirstOrDefault();
            if (source is null ||
                SquaredDistance(source, cacheEntity) > 32 * 32 + 16 * 16)
            {
                continue;
            }

            claimedBurialSources.Add(source.SceneIndex);
            buriedEnemySceneIndices.Add(source.SceneIndex);
            burialCaches.Add(new JsonObject
            {
                ["schema_version"] = 1,
                ["original_actor_type"] = 78,
                ["original_gfl_index"] = 64,
                ["source_enemy_scene_index"] = source.SceneIndex,
                ["x"] = cacheEntity.ReferenceX,
                ["y"] = cacheEntity.ReferenceY,
                ["weapon_inventory"] = BuildCombatInventory(
                    source,
                    profileByItem).Snapshot,
                ["backpack_inventory"] =
                    BuildBackpackInventory(source),
                ["age_world_ticks"] = 0
            });
        }

        var pickupDatabaseIds = new HashSet<int>();
        var explosiveDatabaseIds = new HashSet<int>();
        foreach (var pair in RequiredObject(worldPickups, "entities"))
        {
            if (pair.Value is not JsonObject pickupProfile)
            {
                continue;
            }

            var databaseEntryId = Int(
                pickupProfile,
                "database_entry_id",
                int.TryParse(pair.Key, out var parsed) ? parsed : -1);
            switch (String(pickupProfile, "behavior"))
            {
                case "field_pickup":
                    pickupDatabaseIds.Add(databaseEntryId);
                    break;
                case "explosive_prop":
                    explosiveDatabaseIds.Add(databaseEntryId);
                    break;
            }
        }

        var remainingPickups = new JsonArray();
        var collectedScenes = new JsonArray();
        var explosiveProps = new JsonArray();
        var destroyedScenes = new JsonArray();
        foreach (var original in snapshot.BaseSceneList.Entities)
        {
            if (pickupDatabaseIds.Contains(original.DatabaseEntryId))
            {
                if (savedByScene.TryGetValue(
                        original.SceneIndex,
                        out var saved) &&
                    saved.DatabaseEntryId == original.DatabaseEntryId &&
                    saved.DeathState == 0)
                {
                    remainingPickups.Add(original.SceneIndex);
                }
                else
                {
                    collectedScenes.Add(original.SceneIndex);
                }
            }
            else if (explosiveDatabaseIds.Contains(
                         original.DatabaseEntryId))
            {
                if (savedByScene.TryGetValue(
                        original.SceneIndex,
                        out var saved) &&
                    saved.DatabaseEntryId == original.DatabaseEntryId &&
                    saved.DeathState == 0 &&
                    saved.CurrentHitPoints > 0)
                {
                    explosiveProps.Add(new JsonObject
                    {
                        ["scene_index"] = original.SceneIndex,
                        ["hit_points"] =
                            checked((int)saved.CurrentHitPoints)
                    });
                }
                else
                {
                    destroyedScenes.Add(original.SceneIndex);
                }
            }
        }

        var missionState = BuildMissionState(
            mission,
            savedByScene,
            baseByScene,
            actorProfiles,
            actorRecordByScene);
        var inferredObjectiveCount = RequiredObject(
                missionState,
                "completed")
            .Count(pair =>
                pair.Value is JsonValue value &&
                value.TryGetValue<bool>(out var completed) &&
                completed);
        var world = new JsonObject
        {
            ["snapshot_presence"] = new JsonObject
            {
                ["field_pickups"] = true,
                ["explosive_props"] = true
            },
            ["activated_scene_indices"] = new JsonArray(),
            ["collected_scene_indices"] = collectedScenes,
            ["destroyed_scene_indices"] = destroyedScenes,
            ["buried_enemy_scene_indices"] =
                buriedEnemySceneIndices,
            ["remaining_field_pickup_scene_indices"] =
                remainingPickups,
            ["explosive_props"] = explosiveProps,
            ["mission_pickups"] = new JsonArray(),
            ["field_inventory"] = new JsonObject(),
            ["legacy_special_world_objects"] = new JsonArray(),
            ["legacy_explosion_effects"] = new JsonArray(),
            ["legacy_ai_control_effects"] = new JsonArray(),
            ["legacy_burial_caches"] = burialCaches,
            ["legacy_doors"] = new JsonArray(),
            ["pending_burial_command"] = new JsonObject(),
            ["projectiles"] = new JsonArray(),
            ["legacy_source"] = new JsonObject
            {
                ["format"] = "original-vwf-sav-v1",
                ["level_id"] = levelId,
                ["sav_file_name"] =
                    System.IO.Path.GetFileName(snapshot.Path),
                ["sav_sha256"] = Convert.ToHexString(
                    SHA256.HashData(File.ReadAllBytes(snapshot.Path))),
                ["terrain_identity_sha256"] =
                    snapshot.Level.TerrainSha256,
                ["preview_file_name"] = preview is null
                    ? string.Empty
                    : System.IO.Path.GetFileName(preview.Path),
                ["preview_width"] = preview?.Image.Width ?? 0,
                ["preview_height"] = preview?.Image.Height ?? 0,
                ["removed_scene_count"] =
                    snapshot.RemovedSceneIndices.Count,
                ["added_scene_count"] =
                    snapshot.AddedEntities.Count,
                ["changed_scene_count"] =
                    snapshot.ChangedEntities.Count,
                ["mission_progress_policy"] =
                    "conservative world-state inference; unresolved trigger history remains incomplete"
            }
        };
        var cameraWidth = Math.Max(
            snapshot.World.ViewportRight -
                snapshot.World.ViewportLeft,
            1);
        var cameraHeight = Math.Max(
            snapshot.World.ViewportBottom -
                snapshot.World.ViewportTop,
            1);
        var session = new JsonObject
        {
            ["level_id"] = levelId,
            ["mission_rule_mode"] = "stable_mod",
            ["elapsed_seconds"] = 0.0,
            ["camera"] = new JsonObject
            {
                ["x"] = snapshot.World.ViewportLeft +
                    cameraWidth / 2.0,
                ["y"] = snapshot.World.ViewportTop +
                    cameraHeight / 2.0,
                ["zoom"] = 1.0
            },
            ["mission"] = missionState,
            ["squad"] = squad,
            ["enemies"] = enemies,
            ["escorts"] = escorts,
            ["ambient"] = ambient,
            ["world"] = world
        };
        var savedAt = File.GetLastWriteTimeUtc(snapshot.Path);
        var savedAtUnixMsec = new DateTimeOffset(savedAt)
            .ToUnixTimeMilliseconds();
        var document = new JsonObject
        {
            ["schema_version"] = 1,
            ["game_id"] = "1937-remake",
            ["slot_id"] = slotId,
            ["revision"] = 1,
            ["saved_at_unix"] = savedAtUnixMsec / 1000,
            ["saved_at_unix_msec"] = savedAtUnixMsec,
            ["campaign"] = new JsonObject
            {
                ["highest_unlocked_level_id"] = levelId,
                ["completed_level_ids"] = new JsonArray()
            },
            ["session"] = session
        };

        return new LegacySaveImportResult(
            document,
            actorRecordByScene.Count,
            dynamicEnemyCount,
            claimedBurialSources.Count,
            remainingPickups.Count,
            inferredObjectiveCount);
    }

    private static JsonObject BuildActorRecord(
        JsonObject actorProfile,
        VwfSceneEntity state,
        bool selected,
        IReadOnlyDictionary<int, (string ActionKey, JsonObject Profile)>
            profileByItem)
    {
        var inventory = BuildCombatInventory(state, profileByItem);
        var maximumHitPoints = Math.Max(
            Math.Max(
                Int(
                    actorProfile,
                    "authored_hit_points",
                    checked((int)state.CurrentHitPoints)),
                checked((int)state.CurrentHitPoints)),
            1);
        var runtimeFaction = Int(
            actorProfile,
            "runtime_faction_id",
            checked((int)(state.DatabaseEntry?.FactionId ?? 0)));
        if (state.DatabaseEntry?.FactionId is uint savedFaction &&
            savedFaction > 0 &&
            state.DatabaseEntryId !=
            Int(actorProfile, "database_entry_id", state.DatabaseEntryId))
        {
            runtimeFaction = checked((int)savedFaction);
        }
        var runtimeType = Int(actorProfile, "runtime_type");
        if (state.DatabaseEntry?.HeaderValues.Count > 2 &&
            state.DatabaseEntryId !=
            Int(actorProfile, "database_entry_id", state.DatabaseEntryId))
        {
            runtimeType = checked(
                (int)state.DatabaseEntry.HeaderValues[2]);
        }
        var alive =
            state.DeathState == 0 &&
            state.CurrentHitPoints > 0;
        return new JsonObject
        {
            ["display_name"] = String(
                actorProfile,
                "display_name",
                state.DatabaseEntry?.DisplayName ?? string.Empty),
            ["scene_index"] = state.SceneIndex,
            ["x"] = state.ReferenceX,
            ["y"] = state.ReferenceY,
            ["faction_id"] = runtimeFaction,
            ["runtime_actor_type"] = runtimeType,
            ["current_hit_points"] =
                checked((int)state.CurrentHitPoints),
            ["maximum_hit_points"] = maximumHitPoints,
            ["is_alive"] = alive,
            ["is_crawling"] = state.CrawlState != 0,
            ["is_running"] = true,
            ["selected"] = selected,
            ["animation_group_index"] =
                LegacyGroupIndex(state.DirectionIndex),
            ["original_active_attack_type"] =
                checked((int)state.DefaultAttackType),
            ["inventory"] = inventory.Snapshot,
            ["inventory_weapon_order"] = inventory.WeaponOrder,
            ["backpack_inventory"] =
                BuildBackpackInventory(state),
            ["disguise_appearance_state"] =
                runtimeType == 91 ? 1 : 0
        };
    }

    private static (
        JsonObject Snapshot,
        JsonArray WeaponOrder)
        BuildCombatInventory(
            VwfSceneEntity state,
            IReadOnlyDictionary<int, (string ActionKey, JsonObject Profile)>
                profileByItem)
    {
        var items = new JsonObject();
        var weapons = new JsonObject();
        var order = new JsonArray();
        var activeActionKey = string.Empty;
        var activeAttackType = checked(
            (int)state.DefaultAttackType);
        foreach (var entry in state.AuxiliaryArrays[1])
        {
            var itemId = checked((int)entry.ItemId);
            if (!profileByItem.TryGetValue(
                    itemId,
                    out var mapped))
            {
                throw new InvalidDataException(
                    $"Scene {state.SceneIndex} contains unsupported original weapon item {itemId}.");
            }

            var quantity = checked((int)entry.Quantity);
            var quantityMode = checked((int)entry.QuantityMode);
            var attackType = Int(mapped.Profile, "attack_type");
            var owned = quantityMode == 2 || quantity > 0;
            items[itemId.ToString()] = quantity;
            weapons[mapped.ActionKey] = new JsonObject
            {
                ["action_key"] = mapped.ActionKey,
                ["profile"] = mapped.Profile.DeepClone(),
                ["ammo_item_id"] = itemId,
                ["magazine_capacity"] = 0,
                ["magazine"] = quantity,
                ["ammo_per_attack"] =
                    Int(mapped.Profile, "ammo_per_attack", 1),
                ["original_parity"] = true,
                ["quantity_mode"] = quantityMode,
                ["owned"] = owned
            };
            order.Add(mapped.ActionKey);
            if (attackType == activeAttackType && owned)
            {
                activeActionKey = mapped.ActionKey;
            }
        }
        if (string.IsNullOrEmpty(activeActionKey))
        {
            activeActionKey = order
                .Select(node => node?.GetValue<string>() ?? string.Empty)
                .FirstOrDefault(actionKey =>
                {
                    if (string.IsNullOrEmpty(actionKey) ||
                        weapons[actionKey] is not JsonObject weapon)
                    {
                        return false;
                    }
                    return Bool(weapon, "owned", true);
                }) ?? string.Empty;
        }

        return (
            new JsonObject
            {
                ["schema_version"] = 2,
                ["original_parity"] = true,
                ["active_action_key"] = activeActionKey,
                ["items"] = items,
                ["weapons"] = weapons
            },
            order);
    }

    private static JsonObject BuildBackpackInventory(
        VwfSceneEntity state)
    {
        var entries = new JsonArray();
        var seen = new HashSet<int>();
        foreach (var entry in state.AuxiliaryArrays[0])
        {
            var itemId = checked((int)entry.ItemId);
            var quantityMode = checked((int)entry.QuantityMode);
            if (!SupportedBackpackItemIds.Contains(itemId) ||
                !seen.Add(itemId) ||
                quantityMode is < 0 or > 2)
            {
                throw new InvalidDataException(
                    $"Scene {state.SceneIndex} contains an unsupported original backpack entry " +
                    $"{itemId}/{entry.Quantity}/{entry.QuantityMode}.");
            }

            entries.Add(new JsonObject
            {
                ["item_id"] = itemId,
                ["quantity"] = checked((int)entry.Quantity),
                ["quantity_mode"] = quantityMode
            });
        }
        return new JsonObject
        {
            ["schema_version"] = 1,
            ["entries"] = entries
        };
    }

    private static JsonObject BuildAiState(
        VwfSceneEntity state,
        IReadOnlyDictionary<int, VwfSceneEntity> savedByScene,
        IReadOnlySet<int> playerScenes)
    {
        var contactState = checked((int)state.ContactState);
        var currentTargetSceneIndex = contactState == 1
            ? NearestSceneIndex(
                state.ResolvedGoalX,
                state.ResolvedGoalY,
                savedByScene.Values,
                candidate =>
                    playerScenes.Contains(candidate.SceneIndex) &&
                    candidate.DeathState == 0 &&
                    candidate.CurrentHitPoints > 0)
            : -1;
        var corpseTargetSceneIndex = contactState == 3
            ? NearestSceneIndex(
                state.ResolvedGoalX,
                state.ResolvedGoalY,
                savedByScene.Values,
                candidate =>
                    candidate.SceneIndex != state.SceneIndex &&
                    (candidate.DeathState != 0 ||
                     candidate.CurrentHitPoints == 0) &&
                    candidate.DatabaseEntry?.FactionId == 1)
            : -1;
        var behaviorState = contactState switch
        {
            1 when currentTargetSceneIndex >= 0 => ChaseBehaviorState,
            1 => SearchBehaviorState,
            2 => SearchBehaviorState,
            3 when corpseTargetSceneIndex >= 0 =>
                CorpseDiscoveryBehaviorState,
            3 => SearchBehaviorState,
            _ => PatrolBehaviorState,
        };
        var ai = new JsonObject
        {
            ["behavior_state"] = behaviorState,
            ["patrol_index"] = checked(
                (int)(state.Patrol?.CurrentWaypointIndex ?? 0)),
            ["patrol_enabled"] = state.Patrol is not null,
            ["patrol_wait_remaining"] = 0.0,
            ["patrol_path_in_flight"] =
                state.MovementActive != 0 ||
                state.MovementPathState != 0,
            ["last_known_x"] = contactState == 0
                ? state.ReferenceX
                : state.ResolvedGoalX,
            ["last_known_y"] = contactState == 0
                ? state.ReferenceY
                : state.ResolvedGoalY,
            ["search_elapsed"] = 0.0,
            ["attack_count"] = 0,
            ["regroup_remaining"] = 0.0,
            ["current_target_scene_index"] = currentTargetSceneIndex,
            ["current_target_display_name"] = string.Empty
        };
        ai["legacy_world_item"] = new JsonObject
        {
            ["target_serial"] = 0,
            ["interaction_pending"] = false,
            ["replan_elapsed"] = 0.0,
            ["abandoning"] = false,
            ["abandon_elapsed"] = 0.0,
            ["abandon_serial"] = 0,
            ["hypnosis_active"] = state.HypnosisActive != 0,
            ["hypnosis_counter"] = checked((int)state.HypnosisCounter),
            ["poison_active"] = state.PoisonActive != 0,
            ["poison_counter"] = checked((int)state.PoisonCounter),
            ["distraction_active"] = false,
            ["distraction_counter"] = 0,
            ["distraction_limit"] = 0,
            // The original process-global CRT state is not serialized in SAV.
            ["random_state"] = 1,
        };
        ai["legacy_corpse"] = new JsonObject
        {
            ["discovered"] = state.CorpseDiscovered != 0,
            ["buried"] =
                state.DeathState != 0 &&
                (state.HiddenOrRemoved != 0 ||
                 state.BurialOrDisguiseTransitionReady != 0),
            ["target_scene_index"] = corpseTargetSceneIndex,
            ["reaction_counter"] = contactState == 3
                ? checked((int)state.SearchDelayCounter)
                : 0,
            ["reaction_limit"] = contactState == 3
                ? checked((int)state.SearchDelayLimit)
                : 0,
            ["reaction_elapsed"] = 0.0,
            ["random_state"] = 1,
            ["reinforcement_spawned"] = false,
            ["reinforcement_source_marker_scene_index"] = -1,
            ["reinforcement_serial"] = 0,
            ["reinforcement_leader_scene_index"] = -1,
        };
        ai["legacy_enemy_ai"] = new JsonObject
        {
            ["search_active"] = contactState == 2,
            ["search_finishing"] = false,
            ["search_origin_x"] = state.ResolvedGoalX,
            ["search_origin_y"] = state.ResolvedGoalY,
            ["search_point_index"] = 0,
            ["search_wait_counter"] = checked((int)state.SearchDelayCounter),
            ["search_wait_limit"] = checked((int)state.SearchDelayLimit),
            ["search_tick_elapsed"] = 0.0,
            ["search_random_state"] = 1,
            ["idle_search_completion_serial"] = 0,
            ["tracked_face_gate_elapsed"] = 0.0,
            ["tracked_face_gate_serial"] = 0,
            ["tracked_face_gate_last_value"] = -1,
            ["tracked_face_gate_last_passed"] = false,
            ["tracked_face_gate_last_evidence_round_index"] = 0,
            ["pending_coordinate_alert_active"] = contactState == 2,
            ["pending_coordinate_alert_x"] = state.ResolvedGoalX,
            ["pending_coordinate_alert_y"] = state.ResolvedGoalY,
            ["actor_command_serial"] = 0,
        };
        return ai;
    }

    private static int NearestSceneIndex(
        int targetX,
        int targetY,
        IEnumerable<VwfSceneEntity> candidates,
        Func<VwfSceneEntity, bool> predicate)
    {
        var maximumSquaredDistance =
            (long)RestoredTargetMaximumDistance *
            RestoredTargetMaximumDistance;
        var bestSceneIndex = -1;
        var bestSquaredDistance = long.MaxValue;
        foreach (var candidate in candidates)
        {
            if (!predicate(candidate))
            {
                continue;
            }
            var deltaX = (long)candidate.ReferenceX - targetX;
            var deltaY = (long)candidate.ReferenceY - targetY;
            var squaredDistance = deltaX * deltaX + deltaY * deltaY;
            if (squaredDistance > maximumSquaredDistance ||
                squaredDistance > bestSquaredDistance ||
                (squaredDistance == bestSquaredDistance &&
                 candidate.SceneIndex >= bestSceneIndex))
            {
                continue;
            }
            bestSceneIndex = candidate.SceneIndex;
            bestSquaredDistance = squaredDistance;
        }
        return bestSceneIndex;
    }

    private static JsonObject BuildAmbientState(
        VwfSceneEntity state) =>
        new()
        {
            ["patrol_index"] = checked(
                (int)(state.Patrol?.CurrentWaypointIndex ?? 0)),
            ["patrol_enabled"] = state.Patrol is not null,
            ["patrol_wait_remaining"] = 0.0,
            ["patrol_path_in_flight"] = false
        };

    private static JsonObject BuildMissionState(
        JsonObject mission,
        IReadOnlyDictionary<int, VwfSceneEntity> savedByScene,
        IReadOnlyDictionary<int, VwfSceneEntity> baseByScene,
        JsonObject actorProfiles,
        IReadOnlyDictionary<int, JsonObject> actorRecords)
    {
        var completed = new JsonObject();
        var progress = new JsonObject();
        var seenValues = new JsonObject();
        var bindings = RequiredObject(mission, "scene_bindings");
        foreach (var node in RequiredArray(mission, "objectives"))
        {
            if (node is not JsonObject objective)
            {
                continue;
            }

            var objectiveId = String(objective, "id");
            var condition = RequiredObject(objective, "condition");
            var requiredCount = Int(
                condition,
                "required_count",
                1);
            var inferredProgress = InferObjectiveProgress(
                condition,
                bindings,
                savedByScene,
                baseByScene,
                actorProfiles,
                actorRecords);
            inferredProgress = Math.Clamp(
                inferredProgress,
                0,
                requiredCount);
            completed[objectiveId] =
                inferredProgress >= requiredCount;
            progress[objectiveId] = inferredProgress;
            seenValues[objectiveId] = new JsonArray();
        }

        return new JsonObject
        {
            ["completed"] = completed,
            ["progress"] = progress,
            ["seen_values"] = seenValues,
            ["failure_id"] = string.Empty,
            ["durable_facts"] = new JsonArray(),
            ["applied_fact_objectives"] = new JsonObject()
        };
    }

    private static int InferObjectiveProgress(
        JsonObject condition,
        JsonObject bindings,
        IReadOnlyDictionary<int, VwfSceneEntity> savedByScene,
        IReadOnlyDictionary<int, VwfSceneEntity> baseByScene,
        JsonObject actorProfiles,
        IReadOnlyDictionary<int, JsonObject> actorRecords)
    {
        var where = condition["where"] as JsonObject
            ?? new JsonObject();
        switch (String(condition, "event"))
        {
            case "role_eliminated":
            {
                var scenes = BindingScenes(
                    bindings,
                    String(where, "role_id"));
                return scenes.Count > 0 &&
                    scenes.All(scene =>
                        !savedByScene.TryGetValue(
                            scene,
                            out var state) ||
                        state.DeathState != 0 ||
                        state.CurrentHitPoints == 0)
                    ? 1
                    : 0;
            }
            case "entity_rescued":
            {
                var displayName = String(
                    where,
                    "display_name");
                if (!string.IsNullOrEmpty(displayName))
                {
                    foreach (var pair in actorProfiles)
                    {
                        if (pair.Value is not JsonObject profile ||
                            String(profile, "display_name") != displayName)
                        {
                            continue;
                        }
                        var scene = int.Parse(pair.Key);
                        if (savedByScene.TryGetValue(scene, out var saved) &&
                            baseByScene.TryGetValue(scene, out var original) &&
                            SquaredDistance(original, saved) > 40 * 40)
                        {
                            return 1;
                        }
                    }
                    return 0;
                }

                var familyRole = String(where, "family_role");
                return BindingScenes(bindings, familyRole)
                    .Count(scene =>
                        savedByScene.TryGetValue(scene, out var saved) &&
                        baseByScene.TryGetValue(scene, out var original) &&
                        SquaredDistance(original, saved) > 40 * 40);
            }
            case "item_acquired":
            {
                var desiredItemIds = new HashSet<int>();
                if (String(where, "item_name") == "日军军服")
                {
                    desiredItemIds.UnionWith([54, 92, 99]);
                }
                else
                {
                    desiredItemIds.Add(101);
                }
                var count = 0;
                foreach (var record in actorRecords.Values)
                {
                    if (Int(record, "faction_id") != 3)
                    {
                        continue;
                    }
                    if (record["backpack_inventory"] is JsonObject backpack &&
                        backpack["entries"] is JsonArray entries)
                    {
                        count += entries.Count(entry =>
                            entry is JsonObject item &&
                            desiredItemIds.Contains(
                                Int(item, "item_id")));
                    }
                    if (record["inventory"] is JsonObject inventory &&
                        inventory["items"] is JsonObject items)
                    {
                        count += items.Count(pair =>
                            int.TryParse(pair.Key, out var itemId) &&
                            desiredItemIds.Contains(itemId) &&
                            pair.Value?.GetValue<int>() > 0);
                    }
                }
                return count;
            }
            case "area_hostiles_cleared":
                return actorRecords.Values
                    .Where(record =>
                        Int(record, "faction_id") == 1)
                    .All(record => !Bool(record, "is_alive", true))
                    ? 1
                    : 0;
            default:
                return 0;
        }
    }

    private static IReadOnlyDictionary<
        int,
        (string ActionKey, JsonObject Profile)> CombatProfileByItem(
        JsonObject combatProfiles)
    {
        var result = new Dictionary<
            int,
            (string ActionKey, JsonObject Profile)>();
        foreach (var pair in RequiredObject(
                     combatProfiles,
                     "weapons"))
        {
            if (pair.Value is not JsonObject profile)
            {
                continue;
            }
            var itemId = Int(profile, "ammo_item_id");
            if (itemId > 0)
            {
                result[itemId] = (pair.Key, profile);
            }
        }
        return result;
    }

    private static JsonObject FindMission(
        JsonObject document,
        string levelId)
    {
        foreach (var node in RequiredArray(document, "missions"))
        {
            if (node is JsonObject mission &&
                String(mission, "id") == levelId)
            {
                return mission;
            }
        }
        throw new InvalidDataException(
            $"Mission data does not contain {levelId}.");
    }

    private static HashSet<int> RescueSceneIndices(
        JsonObject mission)
    {
        var result = new HashSet<int>();
        var bindings = RequiredObject(mission, "scene_bindings");
        foreach (var key in new[]
                 {
                     "rescued", "driver", "reporter", "father", "mother"
                 })
        {
            result.UnionWith(BindingScenes(bindings, key));
        }
        return result;
    }

    private static HashSet<int> CombatTargetSceneIndices(
        JsonObject mission)
    {
        var result = new HashSet<int>();
        var bindings = RequiredObject(mission, "scene_bindings");
        foreach (var node in RequiredArray(mission, "objectives"))
        {
            if (node is not JsonObject objective ||
                objective["condition"] is not JsonObject condition ||
                String(condition, "event") != "role_eliminated" ||
                condition["where"] is not JsonObject where)
            {
                continue;
            }
            result.UnionWith(
                BindingScenes(
                    bindings,
                    String(where, "role_id")));
        }
        if (mission["role_drops"] is JsonObject roleDrops)
        {
            foreach (var pair in roleDrops)
            {
                result.UnionWith(
                    BindingScenes(bindings, pair.Key));
            }
        }
        return result;
    }

    private static HashSet<int> BindingScenes(
        JsonObject bindings,
        string key)
    {
        var result = new HashSet<int>();
        if (!string.IsNullOrEmpty(key) &&
            bindings[key] is JsonArray values)
        {
            foreach (var node in values)
            {
                if (node is not null)
                {
                    result.Add(node.GetValue<int>());
                }
            }
        }
        return result;
    }

    private static int SquaredDistance(
        VwfSceneEntity first,
        VwfSceneEntity second)
    {
        var deltaX =
            (long)first.ReferenceX - second.ReferenceX;
        var deltaY =
            (long)first.ReferenceY - second.ReferenceY;
        return checked((int)Math.Min(
            deltaX * deltaX + deltaY * deltaY,
            int.MaxValue));
    }

    private static int LegacyGroupIndex(uint directionIndex) =>
        directionIndex is >= 1 and <= 8
            ? checked((int)((directionIndex + 2) % 8))
            : 0;

    private static JsonObject ReadJsonObject(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException(
                "Required Remake product data is missing.",
                path);
        }
        var node = JsonNode.Parse(File.ReadAllText(path));
        return node as JsonObject
            ?? throw new InvalidDataException(
                $"The JSON root is not an object: {path}");
    }

    private static JsonObject RequiredObject(
        JsonObject parent,
        string key) =>
        parent[key] as JsonObject
        ?? throw new InvalidDataException(
            $"Required JSON object '{key}' is missing.");

    private static JsonArray RequiredArray(
        JsonObject parent,
        string key) =>
        parent[key] as JsonArray
        ?? throw new InvalidDataException(
            $"Required JSON array '{key}' is missing.");

    private static int Int(
        JsonObject value,
        string key,
        int fallback = 0) =>
        value[key] is JsonValue node &&
        node.TryGetValue<int>(out var result)
            ? result
            : fallback;

    private static string String(
        JsonObject value,
        string key,
        string fallback = "") =>
        value[key] is JsonValue node &&
        node.TryGetValue<string>(out var result)
            ? result
            : fallback;

    private static bool Bool(
        JsonObject value,
        string key,
        bool fallback = false) =>
        value[key] is JsonValue node &&
        node.TryGetValue<bool>(out var result)
            ? result
            : fallback;
}
