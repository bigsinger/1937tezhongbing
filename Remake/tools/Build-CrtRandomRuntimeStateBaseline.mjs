import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";

const args = process.argv.slice(2);
const option = (name, fallback = "") => {
  const index = args.lastIndexOf(name);
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
};
const options = (name) => {
  const values = [];
  for (let index = 0; index < args.length - 1; index += 1) {
    if (args[index] === name) values.push(args[index + 1]);
  }
  return values;
};
const repositoryRoot = path.resolve(option("--repository-root"));
const outputPath = path.resolve(option("--output"));
const minimumRounds = Number.parseInt(option("--minimum-rounds", "120"), 10);
const evidenceRoots = options("--evidence-root").map((value) => path.resolve(value));
if (
  !repositoryRoot ||
  !outputPath ||
  !Number.isInteger(minimumRounds) ||
  minimumRounds < 60 ||
  evidenceRoots.length === 0
) {
  throw new Error("Runtime-state baseline arguments are incomplete.");
}

const readJson = (filePath) => JSON.parse(fs.readFileSync(filePath, "utf8"));
const sha256File = (filePath) =>
  crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex").toUpperCase();
const canonicalHex = (value) => String(value ?? "").trim().toUpperCase();
const canonicalRva = (value) => {
  const normalized = canonicalHex(value);
  return normalized.startsWith("0X") ? `0x${normalized.slice(2)}` : normalized;
};
const parseCsvLine = (line) => {
  const values = [];
  let value = "";
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];
    if (character === '"') {
      if (quoted && line[index + 1] === '"') {
        value += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === "," && !quoted) {
      values.push(value);
      value = "";
    } else {
      value += character;
    }
  }
  values.push(value);
  return values;
};
const readCsv = (filePath) => {
  const lines = fs.readFileSync(filePath, "utf8").trim().split(/\r?\n/);
  const headers = parseCsvLine(lines.shift());
  return lines.map((line) => {
    const values = parseCsvLine(line);
    return Object.fromEntries(headers.map((header, index) => [header, values[index] ?? ""]));
  });
};
const integer = (row, name, fallback = 0) => {
  const value = Number.parseInt(row?.[name] ?? "", 10);
  return Number.isFinite(value) ? value : fallback;
};
const findLevelEvidence = (selectorLevel) => {
  const directoryName = `level-${String(selectorLevel).padStart(2, "0")}`;
  const required = [
    "crt-random-runtime-telemetry.jsonl",
    "actor-states-entry.csv",
    "actor-states-runtime-exit.csv",
    "result.json",
  ];
  for (let index = evidenceRoots.length - 1; index >= 0; index -= 1) {
    const candidate = path.join(evidenceRoots[index], directoryName);
    if (required.every((name) => fs.existsSync(path.join(candidate, name)))) return candidate;
  }
  throw new Error(`No complete runtime evidence found for ${directoryName}.`);
};

const startupPath = path.join(
  repositoryRoot,
  "Remake",
  "game",
  "data",
  "original_crt_random_startup_catalog.json",
);
const callSitePath = path.join(repositoryRoot, "SDK", "crt-rand-call-sites.json");
const startup = readJson(startupPath);
const callSiteCatalog = readJson(callSitePath);
if (
  startup.schema_version !== 3 ||
  startup.catalog_id !== "original-crt-random-startup-v3" ||
  startup.content_profile !== "repository-mod-12-level-20260729"
) {
  throw new Error("Unsupported startup catalog for runtime-state evidence.");
}
const cataloguedSites = new Set();
for (const caller of callSiteCatalog.callers) {
  for (const operation of caller.operations) {
    for (const site of operation.sites) cataloguedSites.add(canonicalRva(site));
  }
}

const compactActorState = (row, runtimeIndexByAddress) => ({
  world_x: integer(row, "world_x"),
  world_y: integer(row, "world_y"),
  previous_world_x: integer(row, "previous_world_x"),
  previous_world_y: integer(row, "previous_world_y"),
  facing_direction: integer(row, "direction"),
  dead_or_disabled: integer(row, "dead"),
  stationary_tick_counter: integer(row, "stationary_tick_counter"),
  stationary_tick_limit: integer(row, "stationary_tick_limit"),
  route_update_active: integer(row, "route_update_active"),
  pursuit_runtime_index:
    runtimeIndexByAddress.get(canonicalHex(row.pursuit_address)) ?? -1,
  pursuit_delay_counter: integer(row, "pursuit_delay_counter"),
  target_runtime_index:
    runtimeIndexByAddress.get(canonicalHex(row.target_address)) ?? -1,
  goal_kind: integer(row, "goal_kind"),
  goal_x: integer(row, "goal_x"),
  goal_y: integer(row, "goal_y"),
  command_variant: integer(row, "command_variant"),
  command_pending: integer(row, "command_pending"),
  movement_active: integer(row, "movement_active"),
  movement_path_state: integer(row, "movement_path_state"),
  movement_mode: integer(row, "movement_mode"),
  resolved_goal_x: integer(row, "resolved_goal_x"),
  resolved_goal_y: integer(row, "resolved_goal_y"),
  search_delay_limit: integer(row, "search_delay_limit"),
  search_delay_counter: integer(row, "search_delay_counter"),
  contact_state: integer(row, "contact_state"),
  target_lost: integer(row, "target_lost"),
  reaction_state: integer(row, "reaction_state"),
});

const evidenceFiles = [];
const levels = [];
for (let selectorLevel = 1; selectorLevel <= 12; selectorLevel += 1) {
  const levelId = `m${String(selectorLevel - 1).padStart(3, "0")}`;
  const startupLevel = startup.levels.find((level) => level.id === levelId);
  if (!startupLevel) throw new Error(`Startup profile is missing: ${levelId}`);
  const evidenceDirectory = findLevelEvidence(selectorLevel);
  const telemetryPath = path.join(
    evidenceDirectory,
    "crt-random-runtime-telemetry.jsonl",
  );
  const entryPath = path.join(evidenceDirectory, "actor-states-entry.csv");
  const exitPath = path.join(
    evidenceDirectory,
    "actor-states-runtime-exit.csv",
  );
  const resultPath = path.join(evidenceDirectory, "result.json");
  if (!readJson(resultPath).passed) throw new Error(`Probe failed: ${levelId}`);

  const entryRows = readCsv(entryPath);
  const exitRows = readCsv(exitPath);
  if (entryRows.length === 0 || entryRows.length !== exitRows.length) {
    throw new Error(`Actor snapshots are inconsistent: ${levelId}`);
  }
  const entryTick = integer(entryRows[0], "captured_tick_ms", -1);
  const exitTick = integer(exitRows[0], "captured_tick_ms", -1);
  if (entryTick <= 0 || exitTick <= entryTick) {
    throw new Error(`Actor snapshot timestamps are invalid: ${levelId}`);
  }
  const entryByRuntime = new Map();
  const exitByRuntime = new Map();
  const runtimeIndexByAddress = new Map();
  for (const row of entryRows) {
    const runtimeIndex = integer(row, "index", -1);
    const address = canonicalHex(row.address);
    if (runtimeIndex < 0 || !/^0X[0-9A-F]{8}$/.test(address)) {
      throw new Error(`Invalid actor identity in ${levelId}: ${address}`);
    }
    entryByRuntime.set(runtimeIndex, row);
    runtimeIndexByAddress.set(address, runtimeIndex);
  }
  for (const row of exitRows) exitByRuntime.set(integer(row, "index", -1), row);

  const activeProfiles = [...startupLevel.actor_initialization].sort(
    (left, right) => left.runtime_index - right.runtime_index,
  );
  const sceneByRuntime = new Map(
    activeProfiles.map((profile) => [profile.runtime_index, profile.scene_index]),
  );
  for (const profile of activeProfiles) {
    if (
      !entryByRuntime.has(profile.runtime_index) ||
      !exitByRuntime.has(profile.runtime_index)
    ) {
      throw new Error(
        `${levelId} is missing active runtime actor ${profile.runtime_index}.`,
      );
    }
  }

  let sequence = 0;
  let lcgState = 1;
  let recordCount = 0;
  let gameplayBoundaryFound = false;
  let roundSerial = 0;
  let currentRound = null;
  let completeRoundCount = 0;
  let completeDrawCount = 0;
  const expectedGateActors = startupLevel.observation_gate_actor_indices.map(Number);
  const firstGateRuntime = expectedGateActors[0];
  const callSiteCounts = new Map();
  const orderHash = crypto.createHash("sha256");
  const valueHash = crypto.createHash("sha256");
  let routeEventCount = 0;
  let stationaryEventCount = 0;
  let routeViolations = 0;
  let stationaryViolations = 0;
  let pursuitEventCount = 0;
  let pursuitViolations = 0;
  let searchEventCount = 0;
  let searchGroupCount = 0;
  let searchViolations = 0;
  const pursuitGroups = new Map();

  const finalizeRound = (round) => {
    if (!round) return;
    if (round.gateActors.join(",") !== expectedGateActors.join(",")) return;
    completeRoundCount += 1;
    const searchEvents = [];
    for (const item of round.records) {
      completeDrawCount += 1;
      callSiteCounts.set(item.site, (callSiteCounts.get(item.site) ?? 0) + 1);
      orderHash.update(`${round.serial}:${item.site}:${item.runtimeIndex}\n`);
      valueHash.update(`${item.record.sequence}:${item.record.value}\n`);
      const actor = item.record.actor_snapshot;
      if (actor && sceneByRuntime.has(item.runtimeIndex)) {
        if (Number(actor.scene_index) !== sceneByRuntime.get(item.runtimeIndex)) {
          throw new Error(
            `${levelId} runtime/scene identity diverged for ${item.runtimeIndex}.`,
          );
        }
      }
      if (item.site === "0x00058946" && actor) {
        routeEventCount += 1;
        if (
          Number(actor.route_update_active) !== 1 ||
          Number(actor.stationary_tick_counter) <
            Number(actor.stationary_tick_limit)
        ) {
          routeViolations += 1;
        }
      } else if (item.site === "0x00056105" && actor) {
        stationaryEventCount += 1;
        if (
          Number(actor.stationary_tick_counter) <
            Number(actor.stationary_tick_limit) ||
          Number(actor.world_x) !== Number(actor.previous_world_x) ||
          Number(actor.world_y) !== Number(actor.previous_world_y)
        ) {
          stationaryViolations += 1;
        }
      } else if (
        (item.site === "0x0005D394" || item.site === "0x0005D47E") &&
        actor
      ) {
        pursuitEventCount += 1;
        const target = item.record.pursuit_snapshot;
        const targetRuntimeIndex = runtimeIndexByAddress.get(
          canonicalHex(actor.pursuit_address),
        );
        let valid =
          target &&
          targetRuntimeIndex !== undefined &&
          Number(actor.movement_path_state) === 0 &&
          Number(target.dead_or_disabled) === 0;
        if (item.site === "0x0005D47E") {
          valid =
            valid &&
            Number(actor.goal_x) === Number(target?.world_x) &&
            Number(actor.goal_y) === Number(target?.world_y) &&
            Number(actor.command_pending) === 1;
        } else {
          valid = valid && Number(actor.runtime_type) === 56;
        }
        if (!valid) pursuitViolations += 1;
        if (target && targetRuntimeIndex !== undefined) {
          const key = `${item.runtimeIndex}:${targetRuntimeIndex}:${item.site}`;
          let group = pursuitGroups.get(key);
          if (!group) {
            group = {
              runtime_index: item.runtimeIndex,
              scene_index: Number(actor.scene_index),
              target_runtime_index: targetRuntimeIndex,
              target_scene_index: Number(target.scene_index),
              call_site_rva: item.site,
              event_count: 0,
              first_round: round.serial,
              last_round: round.serial,
              far_override_count: 0,
            };
            pursuitGroups.set(key, group);
          }
          group.event_count += 1;
          group.last_round = round.serial;
          if (
            item.site === "0x0005D47E" &&
            Number(item.record.value) % 10 < 5 &&
            Number(actor.command_variant) === 1
          ) {
            group.far_override_count += 1;
          }
        }
      }
      if (
        [
          "0x0005D08F",
          "0x0005D09D",
          "0x0005D0B4",
          "0x0005D0CB",
          "0x0005D15F",
        ].includes(item.site) &&
        actor
      ) {
        searchEvents.push(item);
        searchEventCount += 1;
      }
    }
    const searchSites = [
      "0x0005D08F",
      "0x0005D09D",
      "0x0005D0B4",
      "0x0005D0CB",
      "0x0005D15F",
    ];
    for (let index = 0; index < searchEvents.length; index += 5) {
      const group = searchEvents.slice(index, index + 5);
      const valid =
        group.length === 5 &&
        group.map((item) => item.site).join(",") === searchSites.join(",") &&
        new Set(group.map((item) => item.runtimeIndex)).size === 1;
      if (valid) searchGroupCount += 1;
      else searchViolations += 1;
    }
  };

  const stream = fs.createReadStream(telemetryPath, { encoding: "utf8" });
  const lines = readline.createInterface({ input: stream, crlfDelay: Infinity });
  for await (const line of lines) {
    if (!line.includes('"event":"crt_rand_batch"')) continue;
    const batch = JSON.parse(line);
    for (const record of batch.records) {
      recordCount += 1;
      sequence += 1;
      if (Number(record.sequence) !== sequence) {
        throw new Error(`CRT sequence diverged in ${levelId} at ${sequence}.`);
      }
      const site = canonicalRva(record.call_site_rva);
      if (!cataloguedSites.has(site)) {
        throw new Error(`Uncatalogued CRT site in ${levelId}: ${site}`);
      }
      lcgState = (Math.imul(lcgState, 214013) + 2531011) >>> 0;
      const expectedValue = (lcgState >>> 16) & 0x7fff;
      if (expectedValue !== Number(record.value)) {
        throw new Error(`CRT LCG mismatch in ${levelId} at ${sequence}.`);
      }
      if (sequence === startupLevel.first_gameplay_update_sequence) {
        if (site !== "0x0005C81C") {
          throw new Error(`Gameplay boundary site changed in ${levelId}.`);
        }
        gameplayBoundaryFound = true;
      }
      const tick = Number(record.tick_ms);
      if (tick < entryTick || tick > exitTick) continue;
      const runtimeIndex =
        runtimeIndexByAddress.get(canonicalHex(record.caller_esi)) ?? -1;
      if (site === "0x0005C81C" && runtimeIndex === firstGateRuntime) {
        finalizeRound(currentRound);
        roundSerial += 1;
        currentRound = { serial: roundSerial, gateActors: [], records: [] };
      }
      if (!currentRound) continue;
      const item = { record, runtimeIndex, site };
      currentRound.records.push(item);
      if (site === "0x0005C81C") currentRound.gateActors.push(runtimeIndex);
    }
  }
  finalizeRound(currentRound);
  if (!gameplayBoundaryFound) {
    throw new Error(`Gameplay boundary is absent from ${levelId}.`);
  }
  if (recordCount === 0 || recordCount >= 524288) {
    throw new Error(`CRT trace is empty or capacity-truncated: ${levelId}`);
  }
  if (completeRoundCount < minimumRounds) {
    throw new Error(
      `${levelId} has only ${completeRoundCount} complete read-only rounds.`,
    );
  }
  if (
    routeViolations !== 0 ||
    stationaryViolations !== 0 ||
    pursuitViolations !== 0 ||
    searchViolations !== 0
  ) {
    throw new Error(
      `${levelId} runtime law violations: route=${routeViolations}, ` +
        `stationary=${stationaryViolations}, pursuit=${pursuitViolations}, ` +
        `search=${searchViolations}.`,
    );
  }

  const actors = activeProfiles.map((profile) => {
    const entry = entryByRuntime.get(profile.runtime_index);
    const exit = exitByRuntime.get(profile.runtime_index);
    if (
      integer(entry, "runtime_type") !== integer(exit, "runtime_type") ||
      integer(entry, "faction") !== integer(exit, "faction")
    ) {
      throw new Error(
        `${levelId} actor identity changed: ${profile.runtime_index}.`,
      );
    }
    return {
      runtime_index: profile.runtime_index,
      scene_index: profile.scene_index,
      runtime_type: integer(entry, "runtime_type"),
      faction_id: integer(entry, "faction"),
      entry: compactActorState(entry, runtimeIndexByAddress),
      exit: compactActorState(exit, runtimeIndexByAddress),
    };
  });
  const counts = [...callSiteCounts.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([call_site_rva, count]) => ({ call_site_rva, count }));
  const pursuitLinks = [...pursuitGroups.values()].sort(
    (left, right) =>
      left.runtime_index - right.runtime_index ||
      left.target_runtime_index - right.target_runtime_index ||
      left.call_site_rva.localeCompare(right.call_site_rva),
  );
  levels.push({
    id: levelId,
    selector_level: selectorLevel,
    first_gameplay_sequence: startupLevel.first_gameplay_update_sequence,
    actor_snapshot_count: entryRows.length,
    active_actor_count: actors.length,
    capture_entry_tick_ms: entryTick,
    capture_exit_tick_ms: exitTick,
    capture_span_ms: exitTick - entryTick,
    complete_round_count: completeRoundCount,
    complete_draw_count: completeDrawCount,
    complete_call_order_sha256: orderHash.digest("hex").toUpperCase(),
    complete_value_sha256: valueHash.digest("hex").toUpperCase(),
    call_site_counts: counts,
    reset_laws: {
      route_event_count: routeEventCount,
      route_violation_count: routeViolations,
      stationary_event_count: stationaryEventCount,
      stationary_violation_count: stationaryViolations,
      next_limit_formula: "rand()%160+40",
    },
    pursuit: {
      event_count: pursuitEventCount,
      violation_count: pursuitViolations,
      links: pursuitLinks,
    },
    local_search: {
      event_count: searchEventCount,
      complete_group_count: searchGroupCount,
      violation_count: searchViolations,
      call_sites: [
        "0x0005D08F",
        "0x0005D09D",
        "0x0005D0B4",
        "0x0005D0CB",
        "0x0005D15F",
      ],
    },
    actors,
  });
  for (const [role, filePath] of [
    ["crt-random-runtime-telemetry.jsonl", telemetryPath],
    ["actor-states-entry.csv", entryPath],
    ["actor-states-runtime-exit.csv", exitPath],
    ["result.json", resultPath],
  ]) {
    evidenceFiles.push({ level_id: levelId, role, sha256: sha256File(filePath) });
  }
  process.stdout.write(
    `${levelId}: ${completeRoundCount} rounds, ${actors.length} active actors, ` +
      `${pursuitLinks.length} pursuit links\n`,
  );
}

const result = {
  schema_version: 1,
  baseline_id: "original-crt-random-runtime-state-v1",
  content_profile: startup.content_profile,
  executable_sha256: startup.executable_sha256,
  evidence: {
    capture_mode: "process-local-crt-rand-hook-and-memory-snapshot",
    hook_scope: "test-only-environment-gated",
    input_scope: "target-window-only",
    observation_scope: "read-only-gameplay-window",
    clock: "GetTickCount milliseconds in hook and actor snapshots",
    files: evidenceFiles,
  },
  recovered_rules: {
    actor_tick_hz: 60,
    stationary_counter:
      "sub_456070 increments while current position equals prior position",
    route_counter:
      "sub_4587E0 increments the same counter while route_update_active=1",
    pursuit:
      "sub_45D330 follows persistent +0x23C only when path_state=0",
    local_search:
      "sub_45D060 consumes x,y,x-sign,y-sign,next-limit in order",
  },
  levels,
};
fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`, "utf8");
const activeActorTotal = levels.reduce(
  (total, level) => total + level.active_actor_count,
  0,
);
process.stdout.write(
  `Runtime state baseline wrote 12 levels and ${activeActorTotal} active actors: ` +
    `${outputPath}\n`,
);
