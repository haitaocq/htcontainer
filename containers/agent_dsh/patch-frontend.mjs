import { readFileSync, writeFileSync } from "node:fs";

// 构建期脚本：向 dsh Web 前端 dist/index.html 注入 crypto.randomUUID polyfill。
//
// 背景：dsh 前端（dsh-client-connection 等插件）在浏览器端直接调用
// `crypto.randomUUID()`。该 API 仅在安全上下文（HTTPS 或 localhost）中暴露，
// 通过 `http://<IP>:3080` 访问时浏览器报 "crypto.randomUUID is not a function"。
// 这里在 <head> 中注入基于 `crypto.getRandomValues`（所有上下文均可用）的
// RFC 4122 v4 UUID 实现，仅在原生方法缺失时生效，不影响安全上下文。
const distIndex = process.env.DSH_FRONTEND_INDEX;
if (!distIndex) {
  console.error("DSH_FRONTEND_INDEX is required");
  process.exit(1);
}

const marker = "crypto.randomUUID=function";
const polyfill =
  '<script>if(typeof crypto!=="undefined"&&!crypto.randomUUID&&crypto.getRandomValues){crypto.randomUUID=function(){var b=crypto.getRandomValues(new Uint8Array(16));b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;var h=Array.from(b,function(x){return x.toString(16).padStart(2,"0")});return h[0]+h[1]+h[2]+h[3]+"-"+h[4]+h[5]+"-"+h[6]+h[7]+"-"+h[8]+h[9]+"-"+h[10]+h[11]+h[12]+h[13]+h[14]+h[15]}};</script>';

let html = readFileSync(distIndex, "utf8");
if (html.includes(marker)) {
  console.log("[dsh] crypto.randomUUID polyfill already present, skip");
  process.exit(0);
}

if (!html.includes("<head>")) {
  console.error("[dsh] unexpected dist/index.html structure: <head> not found");
  process.exit(1);
}

html = html.replace("<head>", "<head>" + polyfill);
writeFileSync(distIndex, html);
console.log("[dsh] crypto.randomUUID polyfill injected into " + distIndex);
