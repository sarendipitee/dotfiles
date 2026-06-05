#!/usr/bin/env node
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const SOT_DIR = path.join(ROOT, "packages/ai/agents");
const KILO_DIR = path.join(ROOT, "packages/ai/.config/kilo/agents");
const OPENCODE_DIR = path.join(ROOT, "packages/ai/.config/opencode/agents");
const CODEX_DIR = path.join(ROOT, "packages/ai/.codex/agents");
const CODEX_SKILLS_DIR = path.join(ROOT, "packages/ai/.codex/skills");
const CLAUDE_CODE_DIR = path.join(ROOT, "packages/ai/.claude/agents");

const TIER_MODELS = {
	cheap: {
		kilo: "openai/gpt-5.4-mini",
		// codex: "gpt-5.3-codex-spark",
		codex: "gpt-5.4-mini",
		claude: "haiku",
	},
	"medium-cheap": {
		kilo: "openai/gpt-5.4-mini",
		//codex: "gpt-5.3-codex-spark",
		codex: "gpt-5.4-mini",
		claude: "haiku",
	},
	"medium-high": {
		kilo: "openai/gpt-5.4",
		codex: "gpt-5.4",
		claude: "sonnet",
	},
	frontier: {
		kilo: "openai/gpt-5.5",
		codex: "gpt-5.5",
		claude: "opus",
	},
};

function parseYaml(yaml) {
	const lines = yaml.split("\n").filter((l) => {
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
			parent[key] =
				rest.startsWith('"') && rest.endsWith('"') ? rest.slice(1, -1) : rest;
		}
	}
	return root;
}

function needsYamlQuotes(key) {
	return !/^[a-zA-Z_][a-zA-Z0-9_-]*$/.test(key);
}

function dumpYamlValue(val, indent) {
	const p = " ".repeat(indent);
	if (val === null || val === undefined) return "";

	if (typeof val === "object" && !Array.isArray(val)) {
		const lines = [];
		for (const [k, v] of Object.entries(val)) {
			if (v === null || v === undefined) continue;
			if (
				typeof v === "object" &&
				!Array.isArray(v) &&
				Object.keys(v).length === 0
			)
				continue;
			const safeKey = needsYamlQuotes(k) ? JSON.stringify(k) : k;
			if (typeof v === "object" && !Array.isArray(v)) {
				lines.push(`${p}${safeKey}:`);
				const child = dumpYamlValue(v, indent + 2);
				if (child) lines.push(child);
			} else if (Array.isArray(v)) {
				if (v.length > 0) {
					lines.push(`${p}${safeKey}:`);
					for (const item of v) {
						lines.push(`${p}  - ${JSON.stringify(item)}`);
					}
				}
			} else {
				lines.push(`${p}${safeKey}: ${JSON.stringify(v)}`);
			}
		}
		return lines.join("\n");
	}

	if (Array.isArray(val)) {
		return val.map((v) => `${p}- ${JSON.stringify(v)}`).join("\n");
	}

	return `${p}${JSON.stringify(val)}`;
}

function dumpYaml(obj, indent = 0) {
	return dumpYamlValue(obj, indent);
}

function readSoT(sotPath) {
	const text = fs.readFileSync(sotPath, "utf-8");

	const promptLineIdx = text.search(/^prompt: \|/m);
	if (promptLineIdx === -1) throw new Error(`Missing prompt in ${sotPath}`);

	const yamlPart = text.slice(0, promptLineIdx).trimEnd();
	const promptRaw = text.slice(promptLineIdx);

	const promptLines = promptRaw.split("\n");
	promptLines.shift();
	while (
		promptLines.length > 0 &&
		promptLines[promptLines.length - 1].trim() === ""
	) {
		promptLines.pop();
	}
	const prompt = promptLines.map((l) => l.replace(/^  /, "")).join("\n");

	const frontmatter = parseYaml(yamlPart);

	if (!frontmatter.description)
		throw new Error(`Missing description in ${sotPath}`);
	if (!frontmatter.tier) throw new Error(`Missing tier in ${sotPath}`);
	if (!TIER_MODELS[frontmatter.tier])
		throw new Error(`Unknown tier "${frontmatter.tier}" in ${sotPath}`);

	return {
		name: path.basename(sotPath, ".yml"),
		path: sotPath,
		frontmatter,
		prompt,
	};
}

function kiloModel(tier) {
	return TIER_MODELS[tier]?.kilo;
}
function codexModel(tier) {
	return TIER_MODELS[tier]?.codex;
}
function claudeModel(tier) {
	return TIER_MODELS[tier]?.claude;
}

function claudeTools(permission) {
	if (!permission) return null;
	const tools = [];
	if (permission.read?.["*"] !== "deny") tools.push("Read");
	if (permission.edit?.["*"] !== "deny") tools.push("Edit");
	if (permission.bash !== "deny") tools.push("Bash");
	if (permission.webfetch !== "deny") tools.push("WebFetch");
	return tools.length > 0 ? tools : null;
}

function codexSandbox(permission) {
	if (!permission) return null;
	return permission.edit === "deny" ? "read-only" : null;
}

function tomlMultilineLiteral(value) {
	if (value.includes("'''")) {
		throw new Error("prompt contains unsupported TOML literal delimiter");
	}
	return "'''\n" + value.replace(/\n$/, "") + "\n'''";
}

function relPath(absPath) {
	return absPath.startsWith(ROOT + "/")
		? absPath.slice(ROOT.length + 1)
		: absPath;
}

function kiloMarkdown(agent) {
	const { frontmatter, prompt } = agent;

	const parts = [];
	parts.push(`description: ${JSON.stringify(frontmatter.description)}`);
	parts.push(`mode: ${JSON.stringify(frontmatter.mode)}`);
	parts.push(`model: ${JSON.stringify(kiloModel(frontmatter.tier))}`);
	if (frontmatter.steps) parts.push(`steps: ${frontmatter.steps}`);

	if (
		frontmatter.permission &&
		Object.keys(frontmatter.permission).length > 0
	) {
		parts.push("permission:");
		parts.push(dumpYamlValue(frontmatter.permission, 2));
	}

	return `---\n${parts.join("\n")}\n---\n${prompt}`;
}

function claudeCodeMarkdown(agent) {
	const { name, frontmatter, prompt } = agent;

	const model = claudeModel(frontmatter.tier);
	const tools = claudeTools(frontmatter.permission);

	const fm = { name, description: frontmatter.description, model };
	if (tools) fm.tools = tools;

	return `---\n${dumpYaml(fm)}\n---\n${prompt}`;
}

function codexToml(agent) {
	const { name, frontmatter, prompt } = agent;

	const model = codexModel(frontmatter.tier);
	const sandbox = codexSandbox(frontmatter.permission);

	const lines = [
		`# Generated by scripts/generate-ai-agents.mjs from ${relPath(agent.path)}.`,
		"# Do not edit directly; update the source agent YAML instead.",
		`name = ${JSON.stringify(name)}`,
		`description = ${JSON.stringify(frontmatter.description)}`,
	];
	if (model) lines.push(`model = ${JSON.stringify(model)}`);
	if (sandbox) lines.push(`sandbox_mode = ${JSON.stringify(sandbox)}`);
	lines.push(`developer_instructions = ${tomlMultilineLiteral(prompt)}`);
	return lines.join("\n") + "\n";
}

function codexSkill(agent) {
	const { name, frontmatter } = agent;
	return [
		"---",
		`# Generated by scripts/generate-ai-agents.mjs from ${relPath(agent.path)}.`,
		"# Do not edit directly; update the source agent YAML instead.",
		`name: ${name}`,
		`description: ${JSON.stringify(frontmatter.description)}`,
		"---",
		`# ${name}`,
		agent.prompt.trim(),
		"",
	].join("\n");
}

function generate(agents, check) {
	const outputs = {};

	for (const agent of agents) {
		outputs[path.join(KILO_DIR, `${agent.name}.md`)] = kiloMarkdown(agent);
		outputs[path.join(OPENCODE_DIR, `${agent.name}.md`)] = kiloMarkdown(agent);
		outputs[path.join(CODEX_DIR, `${agent.name}.toml`)] = codexToml(agent);
		outputs[path.join(CLAUDE_CODE_DIR, `${agent.name}.md`)] =
			claudeCodeMarkdown(agent);
	}

	const overseer = agents.find((a) => a.name === "overseer");
	if (!overseer) throw new Error("missing overseer agent");

	outputs[path.join(CODEX_SKILLS_DIR, "overseer", "SKILL.md")] =
		codexSkill(overseer);

	const changed = Object.entries(outputs).filter(([p, c]) => {
		let existing;
		try {
			existing = fs.readFileSync(p, "utf-8");
		} catch {
			return true;
		}
		return existing !== c;
	});

	if (check) {
		if (changed.length === 0) {
			console.log("Generated agents are up to date.");
			return true;
		}
		const changedPaths = changed.map(([p]) => relPath(p)).sort();
		console.error("Generated agents are stale:");
		for (const p of changedPaths) console.error(`  ${p}`);
		return false;
	}

	fs.mkdirSync(KILO_DIR, { recursive: true });
	fs.mkdirSync(OPENCODE_DIR, { recursive: true });
	fs.mkdirSync(CODEX_DIR, { recursive: true });
	fs.mkdirSync(CLAUDE_CODE_DIR, { recursive: true });
	fs.mkdirSync(path.join(CODEX_SKILLS_DIR, "overseer"), { recursive: true });

	for (const [filePath, content] of Object.entries(outputs)) {
		fs.writeFileSync(filePath, content, "utf-8");
	}

	const rootRel = ROOT + "/";
	console.log(
		`Generated ${agents.length} Kilo agents   in ${KILO_DIR.replace(rootRel, "")}`,
	);
	console.log(
		`Generated ${agents.length} OpenCode agents in ${OPENCODE_DIR.replace(rootRel, "")}`,
	);
	console.log(
		`Generated ${agents.length} Codex agents   in ${CODEX_DIR.replace(rootRel, "")}`,
	);
	console.log(
		`Generated ${agents.length} Claude Code agents in ${CLAUDE_CODE_DIR.replace(rootRel, "")}`,
	);
	console.log(
		`Generated Codex Overseer skill in ${CODEX_SKILLS_DIR.replace(rootRel, "")}/overseer`,
	);
	return true;
}

const args = process.argv.slice(2);
const checkIndex = args.indexOf("--check");
let check = false;
if (checkIndex !== -1) {
	check = true;
	args.splice(checkIndex, 1);
}
if (args.length > 0) {
	throw new Error(`unknown arguments: ${args.join(" ")}`);
}

const agentFiles = fs
	.readdirSync(SOT_DIR)
	.filter((f) => f.endsWith(".yml"))
	.sort()
	.map((f) => path.join(SOT_DIR, f));

const agents = agentFiles.map(readSoT);
process.exit(generate(agents, check) ? 0 : 1);
