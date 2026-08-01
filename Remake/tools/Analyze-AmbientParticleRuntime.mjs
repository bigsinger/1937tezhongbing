import fs from "node:fs";
import readline from "node:readline";

const args = process.argv.slice(2);
const option = (name, fallback = "") => {
  const index = args.lastIndexOf(name);
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback;
};

const telemetryPath = option("--telemetry");
const logicalWidth = Number.parseInt(option("--width", "1024"), 10);
const logicalHeight = Number.parseInt(option("--height", "768"), 10);
const maximumUpdates = Number.parseInt(option("--updates", "0"), 10);
if (
  !telemetryPath ||
  !fs.existsSync(telemetryPath) ||
  logicalWidth <= 0 ||
  logicalHeight <= 80
) {
  throw new Error(
    "Usage: node Analyze-AmbientParticleRuntime.mjs " +
      "--telemetry <jsonl> [--width 1024] [--height 768] [--updates N]",
  );
}

const resetSites = new Set([
  "0x0005FD2C",
  "0x0005FD41",
  "0x0005FD54",
  "0x0005FD6A",
  "0x0005FD7F",
  "0x0005FDA8",
  "0x0005FDDB",
  "0x0005FDEE",
  "0x0005FE02",
  "0x0005FE19",
]);
const updateSites = new Set([
  "0x0005FF45",
  "0x0005FF65",
  "0x000600F0",
  "0x00060105",
  "0x000601D6",
  "0x000601E5",
  "0x00060202",
  "0x0006026D",
  "0x00060291",
  "0x000602A7",
  "0x000602BC",
  "0x000602D1",
  "0x000602FA",
  "0x00060374",
  "0x00060396",
  "0x000603AD",
  "0x000603C4",
]);
const acceptedSites = new Set([...resetSites, ...updateSites]);
const records = [];
let started = false;
const stream = fs.createReadStream(telemetryPath, { encoding: "utf8" });
const lines = readline.createInterface({ input: stream, crlfDelay: Infinity });
for await (const line of lines) {
  if (!line.includes('"event":"crt_rand_batch"')) continue;
  const batch = JSON.parse(line);
  for (const record of batch.records ?? []) {
    const site = String(record.call_site_rva ?? "");
    if (!started && site === "0x0005FF45") started = true;
    if (started && acceptedSites.has(site)) {
      records.push({
        site,
        value: Number(record.value),
        sequence: Number(record.sequence),
      });
    }
  }
}
if (records.length === 0) {
  throw new Error("No active ambient-particle update was found.");
}

const simulate = (angleDegrees) => {
  const radians = (angleDegrees * Math.PI) / 180.0;
  const directionX = Math.cos(radians);
  const directionY = Math.sin(radians);
  const primary = Array.from({ length: 150 }, () => ({
    x: 0,
    y: 0,
    lifetime: 0,
    speed: 0,
    size: 0,
  }));
  const secondary = Array.from({ length: 20 }, () => ({
    x: 0,
    y: 0,
    lifetime: 0,
  }));
  let cursor = 0;
  let updates = 0;
  let tickCounter = 0;
  let phase = 0;
  let phaseIncreasing = true;
  let storedWidth = 0;
  let storedHeight = 0;
  let mismatch = "";

  const take = (site) => {
    const record = records[cursor];
    if (!record || record.site !== site) {
      mismatch =
        `expected ${site}, got ${record?.site ?? "EOF"} ` +
        `at particle record ${cursor}`;
      throw new Error(mismatch);
    }
    cursor += 1;
    return record.value;
  };
  const reset = () => {
    for (const particle of primary) {
      take("0x0005FD2C");
      particle.x = 0;
      take("0x0005FD41");
      particle.y = 0;
      take("0x0005FD54");
      particle.lifetime = take("0x0005FD6A") % 250 + 250;
      particle.speed = take("0x0005FD7F") % 8 + 6;
      particle.size = take("0x0005FDA8") % 9 + 8;
    }
    for (const particle of secondary) {
      take("0x0005FDDB");
      particle.x = 0;
      take("0x0005FDEE");
      particle.y = 0;
      take("0x0005FE02");
      particle.lifetime = take("0x0005FE19") % 2 + 1;
    }
  };

  try {
    while (
      cursor < records.length &&
      (maximumUpdates <= 0 || updates < maximumUpdates)
    ) {
      tickCounter += 1;
      take("0x0005FF45");
      if (tickCounter >= 80 && take("0x0005FF65") % 250 === 30) {
        tickCounter = 0;
        phaseIncreasing = !phaseIncreasing;
      }
      if (phaseIncreasing) phase = Math.min(phase + 1, 8);
      else phase = Math.max(phase - 1, 0);
      if (storedWidth !== logicalWidth) reset();
      storedWidth = logicalWidth;
      storedHeight = logicalHeight;
      const divisor = 9 - phase;
      const secondaryVisible = Math.trunc(secondary.length / divisor);
      for (let index = 0; index < secondaryVisible; index += 1) {
        take("0x000600F0");
        take("0x00060105");
      }
      const primaryVisible = Math.trunc(primary.length / divisor);
      for (let index = 0; index < primaryVisible; index += 1) {
        const particle = primary[index];
        particle.x -= particle.speed * directionX;
        particle.y += particle.speed * directionY;
        const left = take("0x000601D6") % 19;
        const right = take("0x000601E5") % 20;
        const tailSpan = Math.max(left - right + 21, 1);
        particle.lifetime -= right + take("0x00060202") % tailSpan;
        if (
          particle.lifetime <= 0 ||
          particle.x < 0 ||
          particle.x > storedWidth ||
          particle.y < 0 ||
          particle.y > storedHeight
        ) {
          particle.x = take("0x0006026D") % Math.max(storedWidth, 1);
          particle.y =
            take("0x00060291") % Math.max(storedHeight - 80, 1);
          take("0x000602A7");
          particle.lifetime = take("0x000602BC") % 250 + 250;
          particle.speed = take("0x000602D1") % 8 + 6;
          particle.size = take("0x000602FA") % 9 + 8;
        }
      }
      for (let index = 0; index < secondaryVisible; index += 1) {
        const particle = secondary[index];
        particle.lifetime -= 1;
        if (particle.lifetime === 0) {
          particle.x = take("0x00060374") % Math.max(storedWidth, 1);
          particle.y = take("0x00060396") % Math.max(storedHeight, 1);
          take("0x000603AD");
          particle.lifetime = take("0x000603C4") % 2 + 1;
        }
      }
      updates += 1;
    }
  } catch {
    // The caller compares how far each candidate followed the real sequence.
  }
  return { angleDegrees, cursor, updates, mismatch };
};

const candidates = [];
for (let angle = 0; angle < 360; angle += 1) {
  candidates.push(simulate(angle));
}
candidates.sort(
  (left, right) =>
    right.cursor - left.cursor ||
    right.updates - left.updates ||
    left.angleDegrees - right.angleDegrees,
);
for (const candidate of candidates.slice(0, 12)) {
  console.log(
    `${candidate.angleDegrees.toString().padStart(3)} degrees: ` +
      `${candidate.cursor}/${records.length} records, ` +
      `${candidate.updates} updates` +
      (candidate.mismatch ? `; ${candidate.mismatch}` : "; exact"),
  );
}
if (candidates[0].cursor !== records.length) {
  process.exitCode = 1;
}
