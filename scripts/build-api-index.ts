#!/usr/bin/env npx tsx

/**
 * Fetches the Roblox API dump and builds a compressed API index for lookup_api.
 *
 * Usage: npx tsx scripts/build-api-index.ts
 *
 * This fetches from the Roblox setup CDN and produces packages/server/src/context/api-data.json
 */

import { writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUTPUT_PATH = join(__dirname, "..", "packages", "server", "src", "context", "api-data.json");

// Internal/deprecated classes to skip
const SKIP_CLASSES = new Set([
  "CoreGui",
  "CorePackages",
  "RobloxPluginGuiService",
  "CSGDictionaryService",
  "NonReplicatedCSGDictionaryService",
  "RobloxReplicatedStorage",
  "TestService",
]);

const SKIP_TAGS = new Set(["Deprecated", "Hidden", "NotScriptable", "NotBrowsable"]);

interface RawApiDump {
  Classes: RawClass[];
  Enums: RawEnum[];
}

interface RawClass {
  Name: string;
  Superclass: string;
  Members: RawMember[];
  Tags?: string[];
}

interface RawMember {
  MemberType: string;
  Name: string;
  ValueType?: { Name: string };
  ReturnType?: { Name: string };
  Parameters?: Array<{ Name: string; Type: { Name: string } }>;
  Tags?: string[];
  Security?: string | { Read: string; Write: string };
}

interface RawEnum {
  Name: string;
  Items: Array<{ Name: string; Value: number; Tags?: string[] }>;
}

async function main() {
  console.log("Fetching Roblox version info...");

  // Get latest version hash
  const versionRes = await fetch("https://setup.rbxcdn.com/versionQTStudio");
  const versionHash = (await versionRes.text()).trim();
  console.log(`Latest Studio version: ${versionHash}`);

  // Fetch API dump
  console.log("Fetching API dump...");
  const apiRes = await fetch(`https://setup.rbxcdn.com/${versionHash}-Full-API-Dump.json`);

  if (!apiRes.ok) {
    // Try alternative URL format
    const altRes = await fetch(`https://setup.rbxcdn.com/${versionHash}-API-Dump.json`);
    if (!altRes.ok) {
      console.error("Failed to fetch API dump. Using placeholder data.");
      process.exit(0);
    }
    var apiDump: RawApiDump = await altRes.json() as RawApiDump;
  } else {
    var apiDump: RawApiDump = await apiRes.json() as RawApiDump;
  }

  console.log(`Processing ${apiDump.Classes.length} classes and ${apiDump.Enums.length} enums...`);

  const classes = [];
  for (const cls of apiDump.Classes) {
    if (SKIP_CLASSES.has(cls.Name)) continue;
    if (cls.Tags?.some((t) => SKIP_TAGS.has(t))) continue;

    const properties = [];
    const methods = [];
    const events = [];

    for (const member of cls.Members) {
      if (member.Tags?.some((t) => SKIP_TAGS.has(t))) continue;

      const tags = member.Tags?.filter((t) => !SKIP_TAGS.has(t));

      if (member.MemberType === "Property") {
        properties.push({
          name: member.Name,
          type: member.ValueType?.Name ?? "unknown",
          ...(tags?.length ? { tags } : {}),
        });
      } else if (member.MemberType === "Function") {
        methods.push({
          name: member.Name,
          parameters: member.Parameters?.map((p) => ({
            name: p.Name,
            type: p.Type.Name,
          })),
          returnType: member.ReturnType?.Name,
        });
      } else if (member.MemberType === "Event") {
        events.push({
          name: member.Name,
          parameters: member.Parameters?.map((p) => ({
            name: p.Name,
            type: p.Type.Name,
          })),
        });
      }
    }

    classes.push({
      name: cls.Name,
      ...(cls.Superclass !== "<<<ROOT>>>" ? { superclass: cls.Superclass } : {}),
      properties,
      methods,
      events,
    });
  }

  const enums = [];
  for (const en of apiDump.Enums) {
    const items = en.Items
      .filter((i) => !i.Tags?.some((t) => SKIP_TAGS.has(t)))
      .map((i) => ({ name: i.Name, value: i.Value }));

    enums.push({ name: en.Name, items });
  }

  const output = { classes, enums };
  const json = JSON.stringify(output);
  writeFileSync(OUTPUT_PATH, json, "utf-8");

  const sizeMb = (Buffer.byteLength(json) / 1024 / 1024).toFixed(2);
  console.log(`\nWritten ${OUTPUT_PATH}`);
  console.log(`${classes.length} classes, ${enums.length} enums, ${sizeMb} MB`);
}

main().catch(console.error);
