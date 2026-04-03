import { createBrowserBridge } from "/assets/browser_bridge.js";

const bridge = createBrowserBridge({
  wasmUrl: "/assets/app.wasm",
  logSelector: null,
});

async function main() {
  const instance = await bridge.instantiate();

  if (typeof instance.exports.start === "function") {
    instance.exports.start();
  }

  bindClick(instance, "increment-button", "onIncrementClick");
  bindClick(instance, "fetch-button", "onFetchClick");
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

main().catch((error) => {
  console.error(error);
  const status = document.getElementById("wasm-status");
  if (status) {
    status.textContent = "Wasm failed to start. Check the browser console.";
  }
});
