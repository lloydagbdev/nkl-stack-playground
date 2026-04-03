import { createBrowserBridge } from "/assets/browser_bridge.js";

const bridge = createBrowserBridge({
  wasmUrl: "/assets/svg_app.wasm",
  logSelector: null,
});

function sendLocation(instance) {
  if (typeof instance.exports.onLocationChange !== "function") {
    return;
  }
  bridge.withWasmString(window.location.search, (ptr, len) => {
    instance.exports.onLocationChange(ptr, len);
  });
}

function bindClick(instance, id, exportName) {
  const element = document.getElementById(id);
  const handler = instance.exports[exportName];
  if (!(element instanceof HTMLButtonElement) || typeof handler !== "function") {
    return;
  }
  element.addEventListener("click", () => {
    handler();
  });
}

async function main() {
  const instance = await bridge.instantiate();

  if (typeof instance.exports.start === "function") {
    instance.exports.start();
  }

  bindClick(instance, "svg-nav-wave", "onNavigateWave");
  bindClick(instance, "svg-nav-dots", "onNavigateDots");
  bindClick(instance, "svg-highlight", "onToggleHighlight");

  window.addEventListener("popstate", () => {
    sendLocation(instance);
  });

  sendLocation(instance);
}

main().catch((error) => {
  console.error(error);
  const status = document.getElementById("svg-status");
  if (status) {
    status.textContent = "Wasm failed to start. Check the browser console.";
  }
});
