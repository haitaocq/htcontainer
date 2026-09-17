import { readFileSync, writeFileSync } from "node:fs";

// 构建期脚本：修复 dsh ≥0.1.5 远程浏览器无法使用设置/模型页的问题。
//
// 背景：dsh 0.1.5 将 settings.describe 等配置类 RPC 的可用性改为「客户端判定」——
// 只有浏览器自身地址为 loopback（`window.location.hostname`）时才允许持久化设置，
// 否则设置作用域以 unavailable 起步并报 "settings are unavailable in this browser"。
// 该判定读取浏览器真实地址，服务器无法通过改写 Host/Origin 头部（Caddy 方案）影响它；
// 即便容器已内置令牌认证与会话 Cookie，远程访问设置/模型页依然被前端关闭。
// 因此这里对实际下发到浏览器的 client bundle（dsh-client-connection/lib/client.js，
// 经 /plugins/??.../client.js 原样伺服）打补丁，强制 isLoopback=true，
// 恢复远程访问设置/模型页并持久化配置的能力。
//
// 注意：这是有意的安全放宽（dsh 官方保持 loopback 钉死直到出现真正的认证层），
// 但本镜像已具备浏览器令牌认证，访问仍受令牌与 Host 信任栅栏保护。
const clientPath = process.env.DSH_CONNECTION_CLIENT;
if (!clientPath) {
  console.error("DSH_CONNECTION_CLIENT is required");
  process.exit(1);
}

const target =
  "isLoopback: transport?.ownsHost === true || pageLocation === void 0 || isLoopbackHostname(pageLocation.hostname),";
const replacement = "isLoopback: true,";

let src = readFileSync(clientPath, "utf8");
if (src.includes(replacement)) {
  console.log("[dsh] settings-loopback patch already present, skip");
  process.exit(0);
}

if (!src.includes(target)) {
  console.error("[dsh] unexpected client.js structure: isLoopback expression not found");
  console.error("[dsh]   dsh 内部实现已变化，请重新适配此补丁");
  process.exit(1);
}

src = src.replaceAll(target, replacement);
writeFileSync(clientPath, src);
console.log("[dsh] settings-loopback patch applied to " + clientPath);