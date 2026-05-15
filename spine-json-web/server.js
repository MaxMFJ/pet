const http = require("http");
const fs = require("fs");
const fsp = fs.promises;
const path = require("path");
const crypto = require("crypto");
const { spawn } = require("child_process");

const HOST = "127.0.0.1";
const PORT = Number(process.env.PORT || 4318);
const ROOT = __dirname;
const PUBLIC_DIR = path.join(ROOT, "public");
const TMP_DIR = path.join(ROOT, "tmp");
const CONFIG_PATH = path.join(ROOT, "converter.config.json");

const DEFAULT_CONFIG = {
  executablePath: "",
  argumentsTemplate: ["{input}", "{output}"],
  workingDirectory: "",
  lockOutputVersion: false,
  outputVersion: "3.8.75",
  modelApiEndpoint: "https://api.openai.com/v1/chat/completions",
  modelApiKey: "",
  modelName: "gpt-4.1-mini",
  modelSystemPrompt:
    "You are a Spine animation generator that follows the spine-animation-ai workflow. " +
    "Return strict JSON only. Reuse only existing bone names. Produce one valid Spine animation object " +
    "that can be inserted into the source skeleton JSON under animations.<name>. Favor clean keyframes, " +
    "clear anticipation, action, and settle timing.",
  notes: "Set executablePath and argumentsTemplate to match your converter CLI."
};

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8"
};

async function ensureDirectories() {
  await fsp.mkdir(TMP_DIR, { recursive: true });
}

async function loadConfig() {
  try {
    const raw = await fsp.readFile(CONFIG_PATH, "utf8");
    return { ...DEFAULT_CONFIG, ...JSON.parse(raw) };
  } catch (error) {
    if (error.code === "ENOENT") {
      return { ...DEFAULT_CONFIG };
    }
    throw error;
  }
}

async function saveConfig(config) {
  const merged = {
    ...DEFAULT_CONFIG,
    ...config,
    argumentsTemplate: Array.isArray(config.argumentsTemplate)
      ? config.argumentsTemplate.map((item) => String(item))
      : DEFAULT_CONFIG.argumentsTemplate
  };
  await fsp.writeFile(CONFIG_PATH, JSON.stringify(merged, null, 2));
  return merged;
}

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(JSON.stringify(payload));
}

function sendText(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "Content-Type": "text/plain; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(payload);
}

async function readJsonBody(request) {
  const chunks = [];
  let totalLength = 0;

  for await (const chunk of request) {
    totalLength += chunk.length;
    if (totalLength > 64 * 1024 * 1024) {
      throw new Error("Request body is too large.");
    }
    chunks.push(chunk);
  }

  const rawBody = Buffer.concat(chunks).toString("utf8");
  return rawBody.length ? JSON.parse(rawBody) : {};
}

async function serveStatic(requestPath, response) {
  const normalizedPath = requestPath === "/" ? "/index.html" : requestPath;
  const resolvedPath = path.normalize(path.join(PUBLIC_DIR, normalizedPath));

  if (!resolvedPath.startsWith(PUBLIC_DIR)) {
    sendText(response, 403, "Forbidden");
    return;
  }

  try {
    const data = await fsp.readFile(resolvedPath);
    const ext = path.extname(resolvedPath).toLowerCase();
    response.writeHead(200, {
      "Content-Type": MIME_TYPES[ext] || "application/octet-stream",
      "Cache-Control": "no-store"
    });
    response.end(data);
  } catch (error) {
    if (error.code === "ENOENT") {
      sendText(response, 404, "Not found");
      return;
    }
    sendText(response, 500, error.message);
  }
}

async function getStatusPayload() {
  const config = await loadConfig();
  const executableExists = config.executablePath
    ? fs.existsSync(config.executablePath)
    : false;

  return {
    config,
    converterReady: Boolean(config.executablePath && executableExists),
    executableExists,
    modelReady: Boolean(config.modelApiEndpoint && config.modelApiKey && config.modelName),
    configPath: CONFIG_PATH,
    workingDirectory: ROOT,
    recommendations: [
      {
        name: "wang606/SpineSkeletonDataConverter",
        fit: "Best third-party CLI for skel/json plus cross-version conversion.",
        license: "PolyForm Noncommercial 1.0.0",
        repo: "https://github.com/wang606/SpineSkeletonDataConverter"
      },
      {
        name: "kiraio-moe/Skel2Json",
        fit: "Simpler skel/json converter, archived and limited to Spine 4.2.",
        license: "GPL-3.0",
        repo: "https://github.com/kiraio-moe/Skel2Json"
      }
    ]
  };
}

function replaceTemplateValues(template, values) {
  return String(template).replace(/\{(input|output|mode|filename)\}/g, (_, key) => {
    return values[key] ?? "";
  });
}

function ensureJsonExtension(filename) {
  const base = path.basename(filename, path.extname(filename)) || "skeleton";
  return `${base}.json`;
}

function ensureSkelExtension(filename) {
  const base = path.basename(filename, path.extname(filename)) || "skeleton";
  return `${base}.skel`;
}

function asNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function normalizeSkins(skins) {
  if (Array.isArray(skins)) {
    return skins.map((skin) => skin?.attachments || {}).filter((attachments) => attachments && typeof attachments === "object");
  }
  if (skins && typeof skins === "object") {
    return Object.values(skins).filter((attachments) => attachments && typeof attachments === "object");
  }
  return [];
}

function sampleTimeline(frames, time, valueNames, defaults = {}) {
  if (!Array.isArray(frames) || frames.length === 0) {
    return { ...defaults };
  }
  let previous = frames[0];
  let next = null;
  for (const frame of frames) {
    if (asNumber(frame.time) <= time) {
      previous = frame;
      continue;
    }
    next = frame;
    break;
  }
  if (!next) {
    const result = { ...defaults };
    for (const name of valueNames) {
      result[name] = asNumber(previous[name], result[name] ?? defaults[name] ?? 0);
    }
    return result;
  }

  const previousTime = asNumber(previous.time);
  const nextTime = asNumber(next.time);
  const percent = nextTime > previousTime ? Math.max(0, Math.min(1, (time - previousTime) / (nextTime - previousTime))) : 0;
  const result = { ...defaults };
  for (const name of valueNames) {
    const start = asNumber(previous[name], result[name] ?? defaults[name] ?? 0);
    const end = asNumber(next[name], start);
    result[name] = start + ((end - start) * percent);
  }
  return result;
}

function collectAnimationSampleTimes(animation) {
  const times = new Set([0]);
  function visit(value) {
    if (Array.isArray(value)) {
      for (const item of value) {
        if (item && typeof item === "object" && Number.isFinite(Number(item.time))) {
          times.add(Number(item.time));
        }
        visit(item);
      }
      return;
    }
    if (value && typeof value === "object") {
      for (const item of Object.values(value)) {
        visit(item);
      }
    }
  }
  visit(animation);
  return [...times].sort((a, b) => a - b);
}

function multiplyTransforms(parent, local) {
  return {
    a: parent.a * local.a + parent.c * local.b,
    b: parent.b * local.a + parent.d * local.b,
    c: parent.a * local.c + parent.c * local.d,
    d: parent.b * local.c + parent.d * local.d,
    x: parent.a * local.x + parent.c * local.y + parent.x,
    y: parent.b * local.x + parent.d * local.y + parent.y
  };
}

function localTransform(x, y, rotation, scaleX, scaleY) {
  const radians = (rotation * Math.PI) / 180;
  const cos = Math.cos(radians);
  const sin = Math.sin(radians);
  return {
    a: cos * scaleX,
    b: sin * scaleX,
    c: -sin * scaleY,
    d: cos * scaleY,
    x,
    y
  };
}

function transformPoint(transform, x, y) {
  return {
    x: transform.a * x + transform.c * y + transform.x,
    y: transform.b * x + transform.d * y + transform.y
  };
}

function expandBounds(bounds, point) {
  bounds.minX = Math.min(bounds.minX, point.x);
  bounds.maxX = Math.max(bounds.maxX, point.x);
  bounds.minY = Math.min(bounds.minY, point.y);
  bounds.maxY = Math.max(bounds.maxY, point.y);
}

function computeBoneWorldTransforms(skeletonJson, animation, time) {
  const boneTimelines = animation?.bones || {};
  const bones = Array.isArray(skeletonJson.bones) ? skeletonJson.bones : [];
  const worldByName = new Map();
  const setupByName = new Map(bones.map((bone) => [bone.name, bone]));
  const resolving = new Set();

  function resolveBone(name) {
    if (worldByName.has(name)) {
      return worldByName.get(name);
    }
    if (resolving.has(name)) {
      return { a: 1, b: 0, c: 0, d: 1, x: 0, y: 0 };
    }
    resolving.add(name);

    const bone = setupByName.get(name) || {};
    const timelines = boneTimelines[name] || {};
    const translate = sampleTimeline(timelines.translate, time, ["x", "y"], { x: 0, y: 0 });
    const rotate = sampleTimeline(timelines.rotate, time, ["angle"], { angle: 0 });
    const scale = sampleTimeline(timelines.scale, time, ["x", "y"], { x: 1, y: 1 });
    const x = asNumber(bone.x) + translate.x;
    const y = asNumber(bone.y) + translate.y;
    const rotation = asNumber(bone.rotation) + rotate.angle;
    const scaleX = asNumber(bone.scaleX, 1) * scale.x;
    const scaleY = asNumber(bone.scaleY, 1) * scale.y;
    const local = localTransform(x, y, rotation, scaleX, scaleY);
    const parent = bone.parent ? resolveBone(bone.parent) : { a: 1, b: 0, c: 0, d: 1, x: 0, y: 0 };
    const world = multiplyTransforms(parent, local);
    worldByName.set(name, world);
    resolving.delete(name);
    return world;
  }

  for (const bone of bones) {
    if (bone?.name) {
      resolveBone(bone.name);
    }
  }
  return worldByName;
}

function collectAttachmentsBySlot(skeletonJson) {
  const attachmentsBySlot = new Map();
  for (const skin of normalizeSkins(skeletonJson.skins)) {
    for (const [slotName, attachments] of Object.entries(skin)) {
      if (!attachments || typeof attachments !== "object") {
        continue;
      }
      if (!attachmentsBySlot.has(slotName)) {
        attachmentsBySlot.set(slotName, []);
      }
      attachmentsBySlot.get(slotName).push(...Object.values(attachments).filter(Boolean));
    }
  }
  return attachmentsBySlot;
}

function expandAttachmentBounds(bounds, attachment, boneTransform) {
  const type = attachment.type || "region";
  if (type === "mesh" && Array.isArray(attachment.vertices)) {
    const vertices = attachment.vertices;
    for (let index = 0; index + 1 < vertices.length; index += 2) {
      expandBounds(bounds, transformPoint(boneTransform, asNumber(vertices[index]), asNumber(vertices[index + 1])));
    }
    return;
  }

  if (type !== "region" && type !== "boundingbox") {
    return;
  }
  const width = Math.max(1, asNumber(attachment.width));
  const height = Math.max(1, asNumber(attachment.height));
  const attachmentTransform = localTransform(
    asNumber(attachment.x),
    asNumber(attachment.y),
    asNumber(attachment.rotation),
    asNumber(attachment.scaleX, 1),
    asNumber(attachment.scaleY, 1)
  );
  const world = multiplyTransforms(boneTransform, attachmentTransform);
  for (const [x, y] of [
    [-width / 2, -height / 2],
    [width / 2, -height / 2],
    [width / 2, height / 2],
    [-width / 2, height / 2]
  ]) {
    expandBounds(bounds, transformPoint(world, x, y));
  }
}

function computeDesktopPetDisplayBounds(skeletonJson) {
  const slots = Array.isArray(skeletonJson.slots) ? skeletonJson.slots : [];
  const attachmentsBySlot = collectAttachmentsBySlot(skeletonJson);
  const animations = skeletonJson.animations && typeof skeletonJson.animations === "object" ? skeletonJson.animations : {};
  const bounds = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity };
  const animationEntries = Object.entries(animations);
  const entriesToSample = animationEntries.length ? animationEntries : [["setup", {}]];

  for (const [, animation] of entriesToSample) {
    for (const time of collectAnimationSampleTimes(animation)) {
      const transforms = computeBoneWorldTransforms(skeletonJson, animation, time);
      for (const slot of slots) {
        const boneTransform = transforms.get(slot.bone);
        if (!boneTransform) {
          continue;
        }
        for (const attachment of attachmentsBySlot.get(slot.name) || []) {
          expandAttachmentBounds(bounds, attachment, boneTransform);
        }
      }
    }
  }

  if (![bounds.minX, bounds.minY, bounds.maxX, bounds.maxY].every(Number.isFinite)) {
    return null;
  }
  const padding = 32;
  const x = Math.floor(bounds.minX - padding);
  const y = Math.floor(bounds.minY - padding);
  const width = Math.ceil((bounds.maxX - bounds.minX) + (padding * 2));
  const height = Math.ceil((bounds.maxY - bounds.minY) + (padding * 2));
  if (width <= 0 || height <= 0) {
    return null;
  }
  return { x, y, width, height, padding };
}

function patchJsonForDesktopPetDisplayBounds(rawJson) {
  const skeletonJson = JSON.parse(rawJson);
  const displayBounds = computeDesktopPetDisplayBounds(skeletonJson);
  if (!displayBounds) {
    return { buffer: Buffer.from(rawJson, "utf8"), displayBounds: null };
  }

  skeletonJson.skeleton ||= {};
  skeletonJson.skeleton.width = displayBounds.width;
  skeletonJson.skeleton.height = displayBounds.height;
  skeletonJson.desktopPet ||= {};
  skeletonJson.desktopPet.displayBounds = {
    x: displayBounds.x,
    y: displayBounds.y,
    width: displayBounds.width,
    height: displayBounds.height,
    source: "spine-json-web-auto",
    padding: displayBounds.padding
  };
  return {
    buffer: Buffer.from(JSON.stringify(skeletonJson, null, 2), "utf8"),
    displayBounds: skeletonJson.desktopPet.displayBounds
  };
}

async function runConverterCommand({ inputPath, outputPath, mode, filename, config }) {
  const templateValues = {
    input: inputPath,
    output: outputPath,
    mode,
    filename: path.basename(filename, path.extname(filename)) || "skeleton"
  };
  const args = (config.argumentsTemplate || DEFAULT_CONFIG.argumentsTemplate).map((item) =>
    replaceTemplateValues(item, templateValues)
  );
  if (config.lockOutputVersion && config.outputVersion) {
    args.push("-v", String(config.outputVersion));
  }

  const commandResult = await new Promise((resolve, reject) => {
    const child = spawn(config.executablePath, args, {
      cwd: config.workingDirectory || path.dirname(config.executablePath),
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });
    child.on("error", reject);
    child.on("close", (code) => {
      resolve({ code, stdout, stderr });
    });
  });

  if (commandResult.code !== 0) {
    throw new Error(
      `Converter exited with code ${commandResult.code}.\n${commandResult.stderr || commandResult.stdout || "No output."}`
    );
  }

  return commandResult;
}

async function createArchive(archivePath, cwd, filenames) {
  await new Promise((resolve, reject) => {
    const child = spawn("/usr/bin/zip", ["-q", archivePath, ...filenames], {
      cwd,
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stderr = "";
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(stderr || `zip exited with code ${code}`));
    });
  });
}

function summarizeAnimations(animations) {
  const samples = {};
  for (const name of ["standby_loop", "idle", "run_loop", "run", "attack", "jump"]) {
    if (animations[name]) {
      samples[name] = animations[name];
    }
  }
  if (!Object.keys(samples).length) {
    for (const [name, value] of Object.entries(animations).slice(0, 3)) {
      samples[name] = value;
    }
  }
  return samples;
}

function extractJsonObject(raw) {
  const trimmed = String(raw || "").trim();
  if (!trimmed) {
    throw new Error("Model returned an empty response.");
  }

  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]+?)```/i);
  const candidate = fenced ? fenced[1].trim() : trimmed;

  try {
    return JSON.parse(candidate);
  } catch (error) {
    const start = candidate.indexOf("{");
    const end = candidate.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(candidate.slice(start, end + 1));
    }
    throw error;
  }
}

function buildAnimationGenerationMessages({ prompt, animationName, skeletonJson, config }) {
  const bones = (skeletonJson.bones || []).map((bone) => bone.name);
  const existingAnimations = Object.keys(skeletonJson.animations || {});
  const animationSamples = summarizeAnimations(skeletonJson.animations || {});

  return [
    {
      role: "system",
      content:
        `${config.modelSystemPrompt}\n` +
        'Reply with strict JSON only in this shape: {"animationName":"name","animation":{...},"notes":"short optional note"}.\n' +
        "Do not include markdown fences. Do not invent bone names. Preserve the source skeleton version."
    },
    {
      role: "user",
      content: JSON.stringify({
        task: "Generate one new Spine animation for the provided skeleton JSON.",
        requestedAnimationName: animationName,
        userPrompt: prompt,
        skeletonMeta: skeletonJson.skeleton || {},
        boneNames: bones,
        existingAnimationNames: existingAnimations,
        animationSamples
      })
    }
  ];
}

async function callModelApi({ prompt, animationName, skeletonJson, config }) {
  if (!config.modelApiEndpoint || !config.modelApiKey || !config.modelName) {
    throw new Error("Model API endpoint, key, and model are all required.");
  }

  const response = await fetch(config.modelApiEndpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${config.modelApiKey}`
    },
    body: JSON.stringify({
      model: config.modelName,
      temperature: 0.4,
      messages: buildAnimationGenerationMessages({
        prompt,
        animationName,
        skeletonJson,
        config
      })
    })
  });

  const rawText = await response.text();
  if (!response.ok) {
    throw new Error(`Model API request failed (${response.status}): ${rawText}`);
  }

  let payload;
  try {
    payload = JSON.parse(rawText);
  } catch (error) {
    throw new Error(`Model API returned non-JSON payload: ${rawText}`);
  }

  const content = payload?.choices?.[0]?.message?.content;
  if (!content) {
    throw new Error(`Model API response did not include message content: ${rawText}`);
  }

  return extractJsonObject(content);
}

async function runConverter({
  inputBuffer,
  filename,
  mode,
  config,
  companionFiles = [],
  includePaths = false
}) {
  if (!config.executablePath) {
    throw new Error("Converter executable path is not configured.");
  }
  if (!fs.existsSync(config.executablePath)) {
    throw new Error("Configured converter executable was not found on disk.");
  }

  const safeBaseName = path.basename(filename, path.extname(filename)) || "skeleton";
  const requestId = crypto.randomUUID();
  const requestDir = path.join(TMP_DIR, requestId);
  await fsp.mkdir(requestDir, { recursive: true });

  const inputExtension = mode === "json_to_skel" ? ".json" : ".skel";
  const outputExtension = mode === "json_to_skel" ? ".skel" : ".json";
  const inputPath = path.join(requestDir, safeBaseName + inputExtension);
  const outputPath = path.join(requestDir, safeBaseName + outputExtension);

  await fsp.writeFile(inputPath, inputBuffer);

  const bundledFiles = [];
  for (const file of companionFiles) {
    if (!file || !file.filename || !file.fileBase64) {
      continue;
    }
    const companionName = path.basename(file.filename);
    const companionPath = path.join(requestDir, companionName);
    await fsp.writeFile(companionPath, Buffer.from(file.fileBase64, "base64"));
    bundledFiles.push({
      filename: companionName,
      path: companionPath
    });
  }

  const commandResult = await runConverterCommand({
    inputPath,
    outputPath,
    mode,
    filename,
    config
  });

  let outputBuffer = await fsp.readFile(outputPath);
  let displayBounds = null;
  if (mode === "skel_to_json" && outputExtension === ".json") {
    const patched = patchJsonForDesktopPetDisplayBounds(outputBuffer.toString("utf8"));
    outputBuffer = patched.buffer;
    displayBounds = patched.displayBounds;
    await fsp.writeFile(outputPath, outputBuffer);
  }
  const archivePath = path.join(requestDir, `${safeBaseName}.zip`);
  const archiveEntries = [
    { filename: path.basename(outputPath), path: outputPath },
    ...bundledFiles
  ];
  await createArchive(archivePath, requestDir, archiveEntries.map((item) => item.filename));
  const archiveBuffer = await fsp.readFile(archivePath);
  const preview =
    outputExtension === ".json"
      ? outputBuffer.toString("utf8").slice(0, 1200)
      : `Generated ${path.basename(outputPath)} (${outputBuffer.length} bytes)`;

  const result = {
    requestId,
    outputFilename: path.basename(archivePath),
    outputBase64: archiveBuffer.toString("base64"),
    outputMimeType: "application/zip",
    preview,
    bundledFiles: archiveEntries.map((item) => item.filename),
    logs: {
      stdout: [
        commandResult.stdout,
        displayBounds
          ? `DesktopPet displayBounds: x=${displayBounds.x}, y=${displayBounds.y}, width=${displayBounds.width}, height=${displayBounds.height}`
          : ""
      ].filter(Boolean).join("\n"),
      stderr: commandResult.stderr
    }
  };
  if (includePaths) {
    result.outputPath = outputPath;
    result.outputBuffer = outputBuffer;
    result.requestDir = requestDir;
  }
  return result;
}

async function normalizeSourceSkeleton({ filename, fileBase64, companionFiles, config }) {
  const extension = path.extname(filename).toLowerCase();
  if (extension === ".json") {
    return {
      sourceJson: JSON.parse(Buffer.from(fileBase64, "base64").toString("utf8")),
      sourceWasSkel: false,
      logs: { stdout: "", stderr: "" }
    };
  }
  if (extension !== ".skel") {
    throw new Error("Only .json and .skel source files are supported for animation generation.");
  }

  const converted = await runConverter({
    inputBuffer: Buffer.from(fileBase64, "base64"),
    filename,
    mode: "skel_to_json",
    config,
    companionFiles,
    includePaths: true
  });

  return {
    sourceJson: JSON.parse(converted.outputBuffer.toString("utf8")),
    sourceWasSkel: true,
    logs: converted.logs
  };
}

async function generateAnimationPackage({
  filename,
  fileBase64,
  companionFiles,
  prompt,
  animationName,
  config
}) {
  const source = await normalizeSourceSkeleton({
    filename,
    fileBase64,
    companionFiles,
    config
  });

  const generated = await callModelApi({
    prompt,
    animationName,
    skeletonJson: source.sourceJson,
    config
  });

  const finalAnimationName =
    String(generated.animationName || animationName || "").trim() || "generated_animation";
  if (!generated.animation || typeof generated.animation !== "object") {
    throw new Error("Model response must include an animation object.");
  }

  const mergedJson = JSON.parse(JSON.stringify(source.sourceJson));
  mergedJson.animations ||= {};
  mergedJson.animations[finalAnimationName] = generated.animation;
  const patchedMerged = patchJsonForDesktopPetDisplayBounds(JSON.stringify(mergedJson));
  const finalJsonBuffer = patchedMerged.buffer;
  const finalJson = JSON.parse(finalJsonBuffer.toString("utf8"));

  const requestId = crypto.randomUUID();
  const requestDir = path.join(TMP_DIR, requestId);
  await fsp.mkdir(requestDir, { recursive: true });

  const jsonFilename = ensureJsonExtension(filename).replace(/\.json$/i, `_${finalAnimationName}.json`);
  const jsonPath = path.join(requestDir, jsonFilename);
  await fsp.writeFile(jsonPath, finalJsonBuffer);

  const bundledFiles = [{ filename: jsonFilename, path: jsonPath }];
  const extraLogs = [];

  if (config.executablePath && fs.existsSync(config.executablePath)) {
    const skelFilename = ensureSkelExtension(filename).replace(/\.skel$/i, `_${finalAnimationName}.skel`);
    const skelPath = path.join(requestDir, skelFilename);
    try {
      const backConversion = await runConverterCommand({
        inputPath: jsonPath,
        outputPath: skelPath,
        mode: "json_to_skel",
        filename: jsonFilename,
        config
      });
      bundledFiles.push({ filename: skelFilename, path: skelPath });
      extraLogs.push(`json_to_skel stdout:\n${backConversion.stdout || "(empty)"}`);
      extraLogs.push(`json_to_skel stderr:\n${backConversion.stderr || "(empty)"}`);
    } catch (error) {
      extraLogs.push(`json_to_skel skipped: ${error.message}`);
    }
  }

  for (const file of companionFiles || []) {
    if (!file?.filename || !file?.fileBase64) {
      continue;
    }
    const companionName = path.basename(file.filename);
    const companionPath = path.join(requestDir, companionName);
    await fsp.writeFile(companionPath, Buffer.from(file.fileBase64, "base64"));
    bundledFiles.push({ filename: companionName, path: companionPath });
  }

  const archiveFilename = `${path.basename(filename, path.extname(filename))}_${finalAnimationName}.zip`;
  const archivePath = path.join(requestDir, archiveFilename);
  await createArchive(archivePath, requestDir, bundledFiles.map((file) => file.filename));
  const archiveBuffer = await fsp.readFile(archivePath);

  return {
    requestId,
    outputFilename: archiveFilename,
    outputBase64: archiveBuffer.toString("base64"),
    outputMimeType: "application/zip",
    preview: JSON.stringify(finalJson.animations[finalAnimationName], null, 2).slice(0, 2000),
    bundledFiles: bundledFiles.map((file) => file.filename),
    animationName: finalAnimationName,
    sourceWasSkel: source.sourceWasSkel,
    modelNotes: generated.notes || "",
    logs: {
      stdout: source.logs.stdout || "",
      stderr: [
        source.logs.stderr || "",
        patchedMerged.displayBounds
          ? `DesktopPet displayBounds: x=${patchedMerged.displayBounds.x}, y=${patchedMerged.displayBounds.y}, width=${patchedMerged.displayBounds.width}, height=${patchedMerged.displayBounds.height}`
          : "",
        ...extraLogs
      ].filter(Boolean).join("\n\n")
    }
  };
}

async function handleApi(request, response, pathname) {
  if (request.method === "GET" && pathname === "/api/status") {
    sendJson(response, 200, await getStatusPayload());
    return;
  }

  if (request.method === "POST" && pathname === "/api/config") {
    const body = await readJsonBody(request);
    const saved = await saveConfig(body);
    sendJson(response, 200, { ok: true, config: saved });
    return;
  }

  if (request.method === "POST" && pathname === "/api/convert") {
    const body = await readJsonBody(request);
    const config = await loadConfig();

    if (!body.fileBase64 || !body.filename) {
      sendJson(response, 400, { error: "filename and fileBase64 are required." });
      return;
    }

    const companionFiles = Array.isArray(body.companionFiles) ? body.companionFiles : [];
    const atlasFile = companionFiles.find((file) => String(file.filename || "").toLowerCase().endsWith(".atlas"));
    const pngFile = companionFiles.find((file) => String(file.filename || "").toLowerCase().endsWith(".png"));
    if (!atlasFile || !pngFile) {
      sendJson(response, 400, { error: "atlas 和 png 文件都需要同时上传。" });
      return;
    }

    const result = await runConverter({
      inputBuffer: Buffer.from(body.fileBase64, "base64"),
      filename: body.filename,
      mode: body.mode === "json_to_skel" ? "json_to_skel" : "skel_to_json",
      config,
      companionFiles
    });

    sendJson(response, 200, result);
    return;
  }

  if (request.method === "POST" && pathname === "/api/generate-animation") {
    const body = await readJsonBody(request);
    const config = await loadConfig();

    if (!body.fileBase64 || !body.filename) {
      sendJson(response, 400, { error: "filename and fileBase64 are required." });
      return;
    }
    if (!String(body.prompt || "").trim()) {
      sendJson(response, 400, { error: "prompt is required." });
      return;
    }

    const companionFiles = Array.isArray(body.companionFiles) ? body.companionFiles : [];
    const atlasFile = companionFiles.find((file) => String(file.filename || "").toLowerCase().endsWith(".atlas"));
    const pngFile = companionFiles.find((file) => String(file.filename || "").toLowerCase().endsWith(".png"));
    if (!atlasFile || !pngFile) {
      sendJson(response, 400, { error: "atlas 和 png 文件都需要同时上传。" });
      return;
    }

    const result = await generateAnimationPackage({
      filename: body.filename,
      fileBase64: body.fileBase64,
      companionFiles,
      prompt: String(body.prompt),
      animationName: String(body.animationName || ""),
      config
    });

    sendJson(response, 200, result);
    return;
  }

  sendJson(response, 404, { error: "Unknown API route." });
}

async function requestListener(request, response) {
  try {
    const url = new URL(request.url, `http://${request.headers.host || HOST}`);
    if (url.pathname.startsWith("/api/")) {
      await handleApi(request, response, url.pathname);
      return;
    }

    await serveStatic(url.pathname, response);
  } catch (error) {
    sendJson(response, 500, { error: error.message });
  }
}

async function start() {
  await ensureDirectories();
  const server = http.createServer(requestListener);
  server.listen(PORT, HOST, () => {
    console.log(`Spine JSON Web listening on http://${HOST}:${PORT}`);
  });
}

start().catch((error) => {
  console.error(error);
  process.exit(1);
});
