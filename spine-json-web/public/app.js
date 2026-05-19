const state = {
  mode: "skel_to_json",
  files: {
    primary: null,
    atlases: [],
    pngs: []
  },
  output: null,
  generatedOutput: null
};

const elements = {
  statusBadge: document.getElementById("statusBadge"),
  executablePathInput: document.getElementById("executablePathInput"),
  argumentsTemplateInput: document.getElementById("argumentsTemplateInput"),
  workingDirectoryInput: document.getElementById("workingDirectoryInput"),
  lockOutputVersionInput: document.getElementById("lockOutputVersionInput"),
  outputVersionInput: document.getElementById("outputVersionInput"),
  modelApiEndpointInput: document.getElementById("modelApiEndpointInput"),
  modelNameInput: document.getElementById("modelNameInput"),
  modelApiKeyInput: document.getElementById("modelApiKeyInput"),
  modelSystemPromptInput: document.getElementById("modelSystemPromptInput"),
  saveConfigButton: document.getElementById("saveConfigButton"),
  refreshStatusButton: document.getElementById("refreshStatusButton"),
  recommendationsList: document.getElementById("recommendationsList"),
  fileInput: document.getElementById("fileInput"),
  projectDirInput: document.getElementById("projectDirInput"),
  primaryFileInput: document.getElementById("primaryFileInput"),
  atlasFileInput: document.getElementById("atlasFileInput"),
  pngFileInput: document.getElementById("pngFileInput"),
  dropZone: document.getElementById("dropZone"),
  dropZoneLabel: document.getElementById("dropZoneLabel"),
  fileMeta: document.getElementById("fileMeta"),
  convertButton: document.getElementById("convertButton"),
  downloadButton: document.getElementById("downloadButton"),
  animationNameInput: document.getElementById("animationNameInput"),
  animationPromptInput: document.getElementById("animationPromptInput"),
  generateAnimationButton: document.getElementById("generateAnimationButton"),
  downloadGeneratedButton: document.getElementById("downloadGeneratedButton"),
  previewPane: document.getElementById("previewPane"),
  logPane: document.getElementById("logPane"),
  segments: Array.from(document.querySelectorAll(".segment"))
};

function setLog(message) {
  elements.logPane.textContent = message;
}

function setPreview(message) {
  elements.previewPane.textContent = message;
}

function setStatus(ready, executableExists) {
  elements.statusBadge.className = "badge";
  if (ready) {
    elements.statusBadge.classList.add("ready");
    elements.statusBadge.textContent = "已就绪";
    return;
  }

  elements.statusBadge.classList.add("missing");
  elements.statusBadge.textContent = executableExists ? "待配置" : "未找到";
}

function splitArgumentsTemplate(value) {
  return value
    .split(/\s+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function updateFileMeta() {
  const { primary, atlases, pngs } = state.files;
  const atlasCount = atlases.length;
  const pngCount = pngs.length;
  if (!primary && atlasCount === 0 && pngCount === 0) {
    elements.fileMeta.textContent = "未选择完整文件组";
    elements.dropZoneLabel.textContent = "拖入主文件、atlas 和所有 png，或直接选择工程目录";
    return;
  }

  const labels = [
    primary ? `主文件: ${primary.name}` : "主文件: 未选",
    atlasCount ? `Atlas: ${atlasCount} 个 (${atlases.map((file) => file.name).join(", ")})` : "Atlas: 未选",
    pngCount ? `PNG: ${pngCount} 个 (${pngs.map((file) => file.name).join(", ")})` : "PNG: 未选"
  ];
  elements.fileMeta.textContent = labels.join(" | ");
  elements.dropZoneLabel.textContent = primary && atlasCount && pngCount ? "文件组已就绪" : "还缺文件，继续补齐";
}

async function refreshStatus() {
  const response = await fetch("/api/status");
  const payload = await response.json();

  elements.executablePathInput.value = payload.config.executablePath || "";
  elements.argumentsTemplateInput.value = (payload.config.argumentsTemplate || []).join(" ");
  elements.workingDirectoryInput.value = payload.config.workingDirectory || "";
  elements.lockOutputVersionInput.checked = Boolean(payload.config.lockOutputVersion);
  elements.outputVersionInput.value = payload.config.outputVersion || "";
  elements.modelApiEndpointInput.value = payload.config.modelApiEndpoint || "";
  elements.modelNameInput.value = payload.config.modelName || "";
  elements.modelApiKeyInput.value = payload.config.modelApiKey || "";
  elements.modelSystemPromptInput.value = payload.config.modelSystemPrompt || "";
  setStatus(payload.converterReady, payload.executableExists);

  elements.recommendationsList.innerHTML = payload.recommendations
    .map(
      (item) => `
        <article class="recommendation">
          <strong>${item.name}</strong>
          <span>${item.fit}</span>
          <span>License: ${item.license}</span>
          <a href="${item.repo}" target="_blank" rel="noreferrer">打开仓库</a>
        </article>
      `
    )
    .join("");
}

async function saveConfig() {
  const body = {
    executablePath: elements.executablePathInput.value.trim(),
    argumentsTemplate: splitArgumentsTemplate(elements.argumentsTemplateInput.value.trim()),
    workingDirectory: elements.workingDirectoryInput.value.trim(),
    lockOutputVersion: elements.lockOutputVersionInput.checked,
    outputVersion: elements.outputVersionInput.value.trim(),
    modelApiEndpoint: elements.modelApiEndpointInput.value.trim(),
    modelName: elements.modelNameInput.value.trim(),
    modelApiKey: elements.modelApiKeyInput.value.trim(),
    modelSystemPrompt: elements.modelSystemPromptInput.value.trim()
  };

  const response = await fetch("/api/config", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(body)
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error || "保存配置失败");
  }

  await refreshStatus();
  setLog("配置已保存。");
}

function setMode(mode) {
  state.mode = mode;
  for (const segment of elements.segments) {
    segment.classList.toggle("is-active", segment.dataset.mode === mode);
  }
  state.output = null;
  elements.downloadButton.disabled = true;
}

async function fileToBase64(file) {
  const buffer = await file.arrayBuffer();
  let binary = "";
  const bytes = new Uint8Array(buffer);
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function base64ToBlob(base64, mimeType) {
  const binary = atob(base64);
  const chunkSize = 0x8000;
  const chunks = [];

  for (let i = 0; i < binary.length; i += chunkSize) {
    const slice = binary.slice(i, i + chunkSize);
    const bytes = new Uint8Array(slice.length);
    for (let j = 0; j < slice.length; j += 1) {
      bytes[j] = slice.charCodeAt(j);
    }
    chunks.push(bytes);
  }

  return new Blob(chunks, { type: mimeType || "application/octet-stream" });
}

async function convertSelectedFile() {
  const { primary, atlases, pngs } = state.files;
  if (!primary || atlases.length === 0 || pngs.length === 0) {
    throw new Error("请同时选择主文件、至少一个 atlas 和至少一个 png。");
  }

  setLog("正在调用本地转换器…");
  setPreview("处理中…");

  const response = await fetch("/api/convert", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      mode: state.mode,
      filename: primary.name,
      fileBase64: await fileToBase64(primary),
      companionFiles: [
        ...(await Promise.all(
          atlases.map(async (atlas) => ({
            filename: atlas.webkitRelativePath || atlas.name,
            fileBase64: await fileToBase64(atlas)
          }))
        )),
        ...(await Promise.all(
          pngs.map(async (png) => ({
            filename: png.webkitRelativePath || png.name,
            fileBase64: await fileToBase64(png)
          }))
        ))
      ]
    })
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error || "转换失败");
  }

  state.output = payload;
  state.generatedOutput = null;
  const bundleText = Array.isArray(payload.bundledFiles) ? `\n\nZIP 包含:\n${payload.bundledFiles.join("\n")}` : "";
  setPreview((payload.preview || "无预览") + bundleText);
  setLog(`stdout:\n${payload.logs.stdout || "(empty)"}\n\nstderr:\n${payload.logs.stderr || "(empty)"}`);
  elements.downloadButton.disabled = false;
  elements.downloadGeneratedButton.disabled = true;
}

function downloadPayload(payload) {
  if (!payload) {
    return;
  }

  const blob = base64ToBlob(payload.outputBase64, payload.outputMimeType);
  const objectUrl = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = objectUrl;
  link.download = payload.outputFilename;
  link.rel = "noopener";
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => {
    URL.revokeObjectURL(objectUrl);
  }, 1000);
}

function downloadOutput() {
  downloadPayload(state.output);
}

function downloadGeneratedOutput() {
  downloadPayload(state.generatedOutput);
}

function expectedPrimaryExtension() {
  return state.mode === "json_to_skel" ? ".json" : ".skel";
}

function fileIdentity(file) {
  return file?.webkitRelativePath || file?.name || "";
}

function classifyFiles(files) {
  const nextFiles = {
    primary: state.files.primary,
    atlases: [...state.files.atlases],
    pngs: [...state.files.pngs]
  };
  const primaryExtension = expectedPrimaryExtension();

  for (const file of files) {
    const lower = file.name.toLowerCase();
    if (lower.endsWith(primaryExtension)) {
      nextFiles.primary = file;
    } else if (lower.endsWith(".atlas")) {
      const existingIndex = nextFiles.atlases.findIndex((atlas) => fileIdentity(atlas) === fileIdentity(file));
      if (existingIndex >= 0) {
        nextFiles.atlases[existingIndex] = file;
      } else {
        nextFiles.atlases.push(file);
      }
    } else if (lower.endsWith(".png")) {
      const existingIndex = nextFiles.pngs.findIndex((png) => fileIdentity(png) === fileIdentity(file));
      if (existingIndex >= 0) {
        nextFiles.pngs[existingIndex] = file;
      } else {
        nextFiles.pngs.push(file);
      }
    }
  }

  return nextFiles;
}

function handleFilesUpdate(files) {
  state.files = files;
  state.output = null;
  state.generatedOutput = null;
  elements.downloadButton.disabled = true;
  elements.downloadGeneratedButton.disabled = true;
  updateFileMeta();
  setPreview("等待转换结果…");
}

async function generateAnimation() {
  const { primary, atlases, pngs } = state.files;
  if (!primary || atlases.length === 0 || pngs.length === 0) {
    throw new Error("请同时选择主文件、至少一个 atlas 和至少一个 png。");
  }

  const prompt = elements.animationPromptInput.value.trim();
  if (!prompt) {
    throw new Error("请先填写动作提示词。");
  }

  setLog("正在调用模型生成动作…");
  setPreview("模型生成中…");

  const response = await fetch("/api/generate-animation", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      filename: primary.name,
      fileBase64: await fileToBase64(primary),
      animationName: elements.animationNameInput.value.trim(),
      prompt,
      companionFiles: [
        ...(await Promise.all(
          atlases.map(async (atlas) => ({
            filename: atlas.webkitRelativePath || atlas.name,
            fileBase64: await fileToBase64(atlas)
          }))
        )),
        ...(await Promise.all(
          pngs.map(async (png) => ({
            filename: png.webkitRelativePath || png.name,
            fileBase64: await fileToBase64(png)
          }))
        ))
      ]
    })
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error || "动作生成失败");
  }

  state.generatedOutput = payload;
  state.output = null;
  const notes = payload.modelNotes ? `\n\n模型备注:\n${payload.modelNotes}` : "";
  const bundleText = Array.isArray(payload.bundledFiles) ? `\n\nZIP 包含:\n${payload.bundledFiles.join("\n")}` : "";
  setPreview(`${payload.preview || "无预览"}${notes}${bundleText}`);
  setLog(
    `生成动作: ${payload.animationName}\n` +
      `来源主文件类型: ${payload.sourceWasSkel ? ".skel -> json -> model" : ".json"}\n\n` +
      `stdout:\n${payload.logs.stdout || "(empty)"}\n\nstderr:\n${payload.logs.stderr || "(empty)"}`
  );
  elements.downloadButton.disabled = true;
  elements.downloadGeneratedButton.disabled = false;
}

elements.saveConfigButton.addEventListener("click", async () => {
  try {
    await saveConfig();
  } catch (error) {
    setLog(error.message);
  }
});

elements.refreshStatusButton.addEventListener("click", async () => {
  try {
    await refreshStatus();
    setLog("状态已刷新。");
  } catch (error) {
    setLog(error.message);
  }
});

elements.fileInput.addEventListener("change", (event) => {
  handleFilesUpdate(classifyFiles(Array.from(event.target.files || [])));
});

elements.primaryFileInput.addEventListener("change", (event) => {
  handleFilesUpdate({
    ...state.files,
    primary: event.target.files?.[0] || null
  });
});

elements.atlasFileInput.addEventListener("change", (event) => {
  handleFilesUpdate({
    ...state.files,
    atlases: Array.from(event.target.files || [])
  });
});

elements.projectDirInput.addEventListener("change", (event) => {
  handleFilesUpdate(classifyFiles(Array.from(event.target.files || [])));
});

elements.pngFileInput.addEventListener("change", (event) => {
  handleFilesUpdate({
    ...state.files,
    pngs: Array.from(event.target.files || [])
  });
});

elements.dropZone.addEventListener("dragover", (event) => {
  event.preventDefault();
  elements.dropZone.classList.add("dragover");
});

elements.dropZone.addEventListener("dragleave", () => {
  elements.dropZone.classList.remove("dragover");
});

elements.dropZone.addEventListener("drop", (event) => {
  event.preventDefault();
  elements.dropZone.classList.remove("dragover");
  handleFilesUpdate(classifyFiles(Array.from(event.dataTransfer.files || [])));
});

elements.convertButton.addEventListener("click", async () => {
  try {
    await convertSelectedFile();
  } catch (error) {
    setPreview("转换失败");
    setLog(error.message);
  }
});

elements.downloadButton.addEventListener("click", downloadOutput);
elements.generateAnimationButton.addEventListener("click", async () => {
  try {
    await generateAnimation();
  } catch (error) {
    setPreview("动作生成失败");
    setLog(error.message);
  }
});
elements.downloadGeneratedButton.addEventListener("click", downloadGeneratedOutput);

for (const segment of elements.segments) {
  segment.addEventListener("click", () => {
    setMode(segment.dataset.mode);
    handleFilesUpdate({
      primary: null,
      atlases: state.files.atlases,
      pngs: state.files.pngs
    });
  });
}

refreshStatus().catch((error) => {
  setLog(error.message);
});
