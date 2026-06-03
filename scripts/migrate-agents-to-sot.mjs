#!/usr/bin/env node
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const KILO_DIR = path.join(ROOT, "packages/ai/.config/kilo/agents");
const SOT_DIR = path.join(ROOT, "packages/ai/agents");

const MODEL_TIER = {
  "openai/gpt-5.5": "frontier",
  "openai/gpt-5.4": "medium-high",
  "openai/gpt-5.4-mini": "medium-cheap",
  "openai/gpt-5.3-codex-spark": "cheap",
};

function parseYaml(yaml) {
  const lines = yaml.split("\n").filter(l => {
    const t = l.trim();
    return t !== "" && !t.startsWith("#");
  });
  const root = {};
  const stack = [{ indent: -1, obj: root }];
  for (const line of lines) {
    const indent = line.length - line.trimStart().length;
    const trimmed = line.trim();
    while (stack.length > 1 && indent <= stack[stack.length - 1].indent) {
      stack.pop();
    }
    const colonIdx = trimmed.indexOf(":");
    if (colonIdx === -1) continue;
    let key = trimmed.slice(0, colonIdx).trim();
    const rest = trimmed.slice(colonIdx + 1).trim();
    if (key.startsWith('"') && key.endsWith('"')) {
      key = key.slice(1, -1);
    }
    const parent = stack[stack.length - 1].obj;
    if (rest === "") {
      parent[key] = {};
      stack.push({ indent, obj: parent[key] });
    } else {
      parent[key] = rest.startsWith('"') && rest.endsWith('"') ? rest.slice(1, -1) : rest;
    }
  }
  return root;
}

function needsYamlQuotes(key) {
  if (/^[a-zA-Z_]/.test(key) && /^[a-zA-Z_][a-zA-Z0-9_-]*$/.test(key)) return false;
  return true;
}

function dumpYamlValue(val, indent) {
  const p = " ".repeat(indent);
  if (val === null || val === undefined) return "";
  if (typeof val === "object" && !Array.isArray(val)) {
    const lines = [];
    for (const [k, v] of Object.entries(val)) {
      const safeKey = needsYamlQuotes(k) ? JSON.stringify(k) : k;
      if (typeof v === "object" && !Array.isArray(v) && v !== null) {
        const childLines = dumpYamlValue(v, indent + 2);
        if (childLines) {
          lines.push(`${p}${safeKey}:`);
          lines.push(childLines);
        } else {
          lines.push(`${p}${safeKey}: {}`);
        }
      } else if (Array.isArray(v)) {
        if (v.length > 0) {
          lines.push(`${p}${safeKey}:`);
          for (const item of v) {
            lines.push(`${p}  - ${JSON.stringify(item)}`);
          }
        }
      } else {
        lines.push(`${p}${safeKey}: ${v === null || v === undefined ? "null" : JSON.stringify(v)}`);
      }
    }
    return lines.join("\n");
  }
  if (Array.isArray(val)) {
    return val.map(v => `${p}- ${JSON.stringify(v)}`).join("\n");
  }
  return `${p}${JSON.stringify(val)}`;
}

fs.mkdirSync(SOT_DIR, { recursive: true });

const agentFiles = fs.readdirSync(KILO_DIR)
  .filter(f => f.endsWith(".md"))
  .sort();

for (const file of agentFiles) {
  const text = fs.readFileSync(path.join(KILO_DIR, file), "utf-8");
  const match = text.match(/^---\n(?<frontmatter>[\s\S]*?)\n---\n(?<prompt>[\s\S]*)$/);
  if (!match) throw new Error(`Missing frontmatter: ${file}`);

  const fm = parseYaml(match.groups.frontmatter);
  const prompt = match.groups.prompt;

  const tier = MODEL_TIER[fm.model];
  if (!tier) throw new Error(`Unknown model "${fm.model}" in ${file}`);

  delete fm.model;

  const lines = [];
  lines.push(`description: ${JSON.stringify(fm.description)}`);
  delete fm.description;

  if (fm.mode) {
    lines.push(`mode: ${JSON.stringify(fm.mode)}`);
    delete fm.mode;
  }

  lines.push(`tier: ${JSON.stringify(tier)}`);

  if (fm.steps) {
    lines.push(`steps: ${fm.steps}`);
    delete fm.steps;
  }

  if (fm.permission && typeof fm.permission === "object" && Object.keys(fm.permission).length > 0) {
    lines.push("permission:");
    lines.push(dumpYamlValue(fm.permission, 2));
  }
  delete fm.permission;

  const remaining = Object.keys(fm).filter(k => fm[k] !== null && fm[k] !== undefined && !(typeof fm[k] === "object" && Object.keys(fm[k]).length === 0));
  for (const key of remaining) {
    const safeKey = needsYamlQuotes(key) ? JSON.stringify(key) : key;
    if (typeof fm[key] === "object") {
      lines.push(`${safeKey}:`);
      lines.push(dumpYamlValue(fm[key], 2));
    } else {
      lines.push(`${safeKey}: ${JSON.stringify(fm[key])}`);
    }
  }

  lines.push(`prompt: |`);
  const promptLines = prompt.split("\n");
  const lastNonEmpty = promptLines.reduce((idx, l, i) => l.trim() ? i : idx, -1);
  const trimmedPrompt = lastNonEmpty >= 0 ? promptLines.slice(0, lastNonEmpty + 1) : promptLines;
  for (const pl of trimmedPrompt) {
    lines.push(`  ${pl}`);
  }

  const name = path.basename(file, ".md");
  fs.writeFileSync(path.join(SOT_DIR, `${name}.yml`), lines.join("\n") + "\n");
  console.log(`  ${name}.yml`);
}

console.log(`\nWrote ${agentFiles.length} SoT agents to ${SOT_DIR}`);
