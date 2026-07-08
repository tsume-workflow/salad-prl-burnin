#!/usr/bin/env node
"use strict";

const fs = require("fs");
const https = require("https");
const path = require("path");

const SALAD_API_BASE = "https://api.salad.com/api/public";
const DEFAULT_ENV_FILES = [
  "/home/openclaw/.openclaw/.env",
  "/home/openclaw/.openclaw/gateway.systemd.env",
  path.join(__dirname, ".env"),
];

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  for (const line of fs.readFileSync(filePath, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;
    const index = trimmed.indexOf("=");
    const key = trimmed.slice(0, index).trim();
    const raw = trimmed.slice(index + 1).trim();
    if (key && !process.env[key]) process.env[key] = raw.replace(/^['"]|['"]$/g, "");
  }
}

for (const filePath of DEFAULT_ENV_FILES) loadEnvFile(filePath);

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const item = argv[i];
    if (!item.startsWith("--")) {
      args._.push(item);
      continue;
    }
    const key = item.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith("--")) args[key] = true;
    else {
      args[key] = next;
      i += 1;
    }
  }
  return args;
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} ausente`);
  return value;
}

function requestJson(method, endpoint, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(`${SALAD_API_BASE}${endpoint}`);
    const payload = body ? JSON.stringify(body) : null;
    const req = https.request({
      hostname: url.hostname,
      path: `${url.pathname}${url.search}`,
      method,
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "User-Agent": "salad-log-entries/0.1.0",
        "Salad-Api-Key": requireEnv("SALAD_API_KEY"),
        ...(payload ? { "Content-Length": Buffer.byteLength(payload) } : {}),
      },
      timeout: 20000,
    }, (res) => {
      let responseBody = "";
      res.setEncoding("utf8");
      res.on("data", (chunk) => { responseBody += chunk; });
      res.on("end", () => {
        let data = null;
        try {
          data = responseBody ? JSON.parse(responseBody) : null;
        } catch {
          data = { raw: responseBody };
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          const error = new Error(`Salad HTTP ${res.statusCode}`);
          error.statusCode = res.statusCode;
          error.payload = data;
          reject(error);
          return;
        }
        resolve(data);
      });
    });
    req.on("timeout", () => req.destroy(new Error("Timeout Salad API")));
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function minutesAgo(minutes) {
  return new Date(Date.now() - minutes * 60000).toISOString();
}

function quote(value) {
  return JSON.stringify(String(value));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const org = encodeURIComponent(requireEnv("SALAD_MINING_ORGANIZATION_NAME"));
  const minutes = Math.max(1, Number(args.minutes || 20));
  const pageSize = Math.max(1, Math.min(100, Number(args.limit || 100)));
  const clauses = [
    'resource.type = "container"',
    `resource.labels.project_name = ${quote(process.env.SALAD_MINING_PROJECT_NAME || "default")}`,
  ];
  if (args.group) clauses.push(`resource.labels.container_group_name = ${quote(args.group)}`);
  if (args.worker) clauses.push(`json_log.worker = ${quote(args.worker)}`);
  if (args.event) clauses.push(`json_log.event = ${quote(args.event)}`);
  if (args.contains) clauses.push(`log contains ${quote(args.contains)}`);

  const result = await requestJson("POST", `/organizations/${org}/log-entries`, {
    start_time: minutesAgo(minutes),
    end_time: new Date().toISOString(),
    page_size: pageSize,
    sort_order: args.asc ? "asc" : "desc",
    query: clauses.join(" and "),
  });
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(error.stack || error.message);
  if (error.payload) console.error(JSON.stringify(error.payload, null, 2));
  process.exit(1);
});
