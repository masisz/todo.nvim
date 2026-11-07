// Browser check of assets/roadmap.html against a real todo.nvim server.
//
//   node tests/e2e/viewer_check.js                  # Chromium
//   BROWSER=webkit node tests/e2e/viewer_check.js   # WebKit (Safari engine)  <- REAL-MACHINE CHECK on macOS
//   BROWSER=firefox node tests/e2e/viewer_check.js
//
// Needs `nvim` on PATH and the `playwright` package (WebKit/Firefox need `npx playwright install webkit firefox`).
// WebKit in Playwright is not Safari itself; also go through tests/MANUAL_CHECKS.md in real Safari.
"use strict";
const { spawn } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const assert = require("assert");
const playwright = require("playwright");

const root = path.resolve(__dirname, "..", "..");
const browserName = process.env.BROWSER || "chromium";

function fixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "todo-viewer-"));
  const roadmap = path.join(dir, "roadmap");
  fs.mkdirSync(path.join(roadmap, "done"), { recursive: true });
  const write = (rel, title, due, duration) =>
    fs.writeFileSync(path.join(roadmap, rel), `[Title]\r\n${title}\r\n[Memo]\r\n\r\n[Due]\r\n${due}\r\n[Duration]\r\n${duration}\r\n`);
  write("done/20261001-01.todo", "調査 <research>", "2026-10-31", "2w");
  write("20261101-01.todo", "設計 \"v1\": UI #1", "2026-11-30", "1M");
  write("20261101-02.todo", "実装", "2026-12-31", "1M");
  write("20261101-03.todo", "ドキュメント", "2026-12-10", "2w");
  write("20261101-04.todo", "レビュー", "2027-01-05", "2h");
  write("20261101-05.todo", "いつか", "", "1d");
  fs.writeFileSync(path.join(roadmap, "deps.txt"), [
    "# deps", "20261001-01 -> 20261101-01", "20261101-01 -> 20261101-02",
    "20261101-01 -> 20261101-03", "20261101-02 -> 20261101-04", "20261101-03 -> missing-id", "",
  ].join("\r\n"));
  return dir;
}

async function waitFor(fn, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const v = fn(); if (v) return v; await new Promise((r) => setTimeout(r, 100)); }
  throw new Error("timeout");
}

function pngSize(buf) {
  assert.strictEqual(buf.slice(1, 4).toString("ascii"), "PNG", "not a PNG");
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

(async () => {
  const dir = fixture();
  const urlFile = path.join(dir, "url.txt");
  const nvim = spawn("nvim", ["-l", path.join(root, "tests/e2e/serve.lua"), dir, urlFile], { stdio: "inherit" });
  let browser;
  const results = [];
  const check = async (name, fn) => {
    try { await fn(); results.push(["ok  ", name]); } catch (err) { results.push(["FAIL", name + "\n     " + err.message]); }
  };
  try {
    const url = (await waitFor(() => fs.existsSync(urlFile) && fs.readFileSync(urlFile, "utf8").trim(), 10000));
    browser = await playwright[browserName].launch();
    const page = await browser.newPage({ viewport: { width: 1280, height: 860 } });
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
    await page.goto(url);
    await page.waitForSelector("#graph .n");

    await check("graph renders every milestone and dependency", async () => {
      assert.strictEqual(await page.locator("#graph .n").count(), 6);
      assert.strictEqual(await page.locator("#graph .e").count(), 4);
      assert.strictEqual(await page.locator("#graph .n.done").count(), 1);
      assert.ok(await page.locator("#graph .n.crit").count() >= 2);
    });
    await check("gantt renders bars, a milestone diamond and the undated section", async () => {
      assert.strictEqual(await page.locator("#gantt rect.bar").count(), 4);
      assert.strictEqual(await page.locator("#gantt path.bar").count(), 1);
      assert.ok((await page.locator("#gantt").textContent()).includes("No due date"));
    });
    await check("warnings list missing id, schedule conflict and undated", async () => {
      const text = await page.locator("#warnings").textContent();
      assert.ok(text.includes("missing-id"), text);
      assert.ok(text.includes("いつか"), text);
      assert.ok(await page.locator("#graph .e.bad").count() >= 1);
    });
    await check("titles are escaped", async () => {
      assert.ok((await page.locator("#graph").textContent()).includes("<research>"));
    });
    await check("click selects in both views and shows predecessors/successors", async () => {
      await page.locator('#graph .n[data-id="20261101-01"]').click();
      assert.strictEqual(await page.locator('#gantt .bar.sel[data-id="20261101-01"]').count(), 1);
      const detail = await page.locator("#detail").textContent();
      assert.ok(detail.includes("調査") && detail.includes("実装") && detail.includes("ドキュメント"), detail);
    });
    await check("keyboard: right/left follow successor/predecessor, j moves in order", async () => {
      await page.locator("body").press("Escape");
      await page.locator('#graph .n[data-id="20261101-01"]').click();
      await page.keyboard.press("ArrowRight");
      assert.strictEqual(await page.evaluate(() => document.querySelector("#graph .n.sel").dataset.id), "20261101-02");
      await page.keyboard.press("h");
      assert.strictEqual(await page.evaluate(() => document.querySelector("#graph .n.sel").dataset.id), "20261101-01");
      await page.keyboard.press("j");
      assert.notStrictEqual(await page.evaluate(() => document.querySelector("#graph .n.sel").dataset.id), "20261101-01");
    });
    await check("search selects by title", async () => {
      await page.keyboard.press("/");
      await page.keyboard.type("ドキュ");
      await page.keyboard.press("Enter");
      assert.strictEqual(await page.evaluate(() => document.querySelector("#graph .n.sel").dataset.id), "20261101-03");
    });
    await check("layout switch hides panes", async () => {
      await page.keyboard.press("2");
      assert.ok(!(await page.locator("#gantt-pane").isVisible()));
      await page.keyboard.press("1");
      assert.ok(await page.locator("#gantt-pane").isVisible());
    });

    const depsFile = path.join(dir, "roadmap", "deps.txt");
    async function dragConnection(from, to, cancel) {
      await page.locator('#graph .n[data-id="' + from + '"] .connector').scrollIntoViewIfNeeded();
      const a = await page.locator('#graph .n[data-id="' + from + '"] .connector').boundingBox();
      await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
      await page.mouse.down();
      if (to) {
        await page.locator('#graph .n[data-id="' + to + '"]').scrollIntoViewIfNeeded();
        const b = await page.locator('#graph .n[data-id="' + to + '"]').boundingBox();
        await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2, { steps: 8 });
      } else await page.mouse.move(5, 5);
      if (cancel) await page.keyboard.press("Escape");
      await page.mouse.up();
    }
    await check("drag connects successor and preserves unknown-id dependencies", async () => {
      await dragConnection("20261101-03", "20261101-04");
      await page.waitForFunction(() => document.getElementById("status").textContent === "Connection saved");
      const text = fs.readFileSync(depsFile, "utf8");
      assert.ok(text.includes("20261101-03 -> 20261101-04"));
      assert.ok(text.includes("20261101-03 -> missing-id"));
      assert.strictEqual(await page.locator("#graph .e").count(), 5);
    });
    await check("duplicate, self and cyclic drags do not write dependencies", async () => {
      const before = fs.readFileSync(depsFile, "utf8");
      for (const [from, to, message] of [
        ["20261101-03", "20261101-04", "already connected"],
        ["20261101-03", "20261101-03", "cycle"],
        ["20261101-04", "20261101-01", "cycle"],
      ]) {
        await dragConnection(from, to);
        assert.ok((await page.locator("#status").textContent()).includes(message));
        assert.strictEqual(fs.readFileSync(depsFile, "utf8"), before);
      }
    });
    await check("Escape and empty drops cancel, including at zoom", async () => {
      const before = fs.readFileSync(depsFile, "utf8");
      await page.keyboard.press("+");
      await dragConnection("20261101-03", "20261101-05", true);
      await dragConnection("20261101-03", null);
      assert.strictEqual(await page.locator(".connection-preview").count(), 0);
      assert.strictEqual(fs.readFileSync(depsFile, "utf8"), before);
      await page.keyboard.press("0");
    });
    await check("zoomed drag persists after page reload", async () => {
      await page.keyboard.press("+");
      await dragConnection("20261101-04", "20261101-05");
      await page.waitForFunction(() => document.getElementById("status").textContent === "Connection saved");
      await page.reload();
      await page.waitForSelector("#graph .n");
      assert.strictEqual(await page.locator("#graph .e").count(), 6);
    });

    const exportDir = path.join(dir, "roadmap", "export");
    for (const name of ["graph.png", "gantt.png", "roadmap.png", "graph.svg", "gantt.svg", "roadmap.svg", "mermaid"]) {
      await check(`export ${name}`, async () => {
        await page.evaluate((n) => window.roadmapExport(n), name);
        const status = await page.locator("#status").textContent();
        assert.ok(status.startsWith("Saved"), status);
        const file = path.join(exportDir, name === "mermaid" ? "roadmap.md" : name);
        const data = fs.readFileSync(file);
        if (name.endsWith(".png")) {
          const { width, height } = pngSize(data);
          assert.ok(width > 200 && height > 100, `${width}x${height}`);
        } else if (name.endsWith(".svg")) {
          const text = data.toString("utf8");
          assert.ok(text.startsWith("<svg") && text.includes("<style>") && !text.includes("foreignObject"));
          assert.ok(!text.includes(" sel"), "selection leaked into export");
        } else {
          assert.strictEqual((data.toString("utf8").match(/```mermaid/g) || []).length, 2);
        }
      });
    }
    await check("PNG export is not blank (has many distinct colours)", async () => {
      const b64 = fs.readFileSync(path.join(exportDir, "roadmap.png")).toString("base64");
      const colours = await page.evaluate(async (src) => {
        const img = new Image();
        await new Promise((ok, ng) => { img.onload = ok; img.onerror = ng; img.src = "data:image/png;base64," + src; });
        const c = document.createElement("canvas");
        c.width = img.width; c.height = img.height;
        const ctx = c.getContext("2d");
        ctx.drawImage(img, 0, 0);
        const data = ctx.getImageData(0, 0, c.width, c.height).data;
        const seen = new Set();
        for (let i = 0; i < data.length; i += 4 * 37) seen.add((data[i] << 16) | (data[i + 1] << 8) | data[i + 2]);
        return seen.size;
      }, b64);
      assert.ok(colours > 20, "only " + colours + " colours");
    });
    await check("viewer picks up external edits by polling", async () => {
      fs.writeFileSync(path.join(dir, "roadmap", "20261101-06.todo"), "[Title]\nNew\n[Due]\n2026-12-20\n[Duration]\n1w\n");
      await page.waitForSelector('#graph .n[data-id="20261101-06"]', { timeout: 6000 });
    });
    await check("no page errors", async () => {
      assert.deepStrictEqual(errors, []);
    });
    await page.screenshot({ path: path.join(dir, "viewer.png") });
    results.push(["info", "screenshot: " + path.join(dir, "viewer.png")]);
  } finally {
    fs.writeFileSync(urlFile + ".stop", "");
    if (browser) await browser.close();
    setTimeout(() => nvim.kill(), 2000).unref();
  }
  for (const [s, n] of results) console.log(s + " " + n);
  const failed = results.filter(([s]) => s === "FAIL").length;
  console.log(`\n${browserName}: ${results.filter(([s]) => s === "ok  ").length} passed, ${failed} failed`);
  process.exitCode = failed ? 1 : 0;
})().catch((err) => { console.error(err); process.exitCode = 1; });
