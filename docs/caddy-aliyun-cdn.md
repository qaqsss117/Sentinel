# Sentinel / XBoard 场景下使用海外 Caddy 源站 + 阿里云 CDN 中国内地节点的可行性调研

更新时间：2026-08-31

## 结论先行

结论：可以设计成“海外 Caddy 反向代理作为源站，阿里云 CDN 作为面向中国内地用户的加速入口”，但前提条件非常明确：

1. 如果加速区域选择“仅中国内地”或“全球”，加速域名必须完成 ICP 备案；这一要求与源站部署在海外还是中国内地无关。
2. 海外站点可以作为阿里云 CDN 的回源站，因为阿里云 CDN 支持把源站域名或公网 IP 作为源站；官方文档没有要求源站必须在中国内地。
3. 这类架构更适合“静态配置文件、安装包、图片、小文件下载”之类可缓存内容，不适合把所有动态 API 或长连接都强行走中国内地 CDN 来替代专门的动态加速产品。
4. 对当前仓库而言，远程配置 JSON、订阅下载、登录后 XBoard API、在线客服 HTTP API、状态上报 WebSocket 这几类流量应该拆分策略：
   - 远程配置 JSON：可经 CDN，短缓存。
   - 订阅接口：建议经 CDN，但默认不缓存；若做加密订阅静态化，才考虑非常短的可控缓存。
  - 登录后 API、客服 API：应视为动态请求并禁止缓存；因为客户端存在 DELETE 请求，完整承载时优先使用 ESA，而不是普通 CDN。
  - WebSocket：Caddy 官方明确支持；阿里云 CDN 在本次可检索到的一手文档中没有找到足够直接的 WebSocket 官方页，因此优先使用 ESA 或保留海外直连入口，不应在未验证前假定普通 CDN 可以承载关键长连接。
5. 合规边界很明确：不能把该方案描述成规避备案或规避监管。若业务面向中国内地且要使用阿里云 CDN 的中国内地节点，就按官方要求完成备案与合规审查。

## 本仓库当前客户端行为摘要

以下内容来自仓库代码，用来约束后文的架构建议。

### 1. 远程配置获取行为

- 客户端远程配置源是纯 GET 拉取，默认超时 10 秒。
- redirect 源读取 JSON；gitee 源读取加密文本后解密。
- 代码位置：
  - lib/xboard/config/fetchers/remote_config_manager.dart
  - assets/config/xboard.config.example.yaml
  - assets/config/remote.config.example.json

当前示例里 redirect 源形如：

```yaml
xboard:
  remote_config:
    sources:
      - name: redirect
        url: https://your-redirect-domain.com/api/v1/redirect/domains
      - name: gitee
        url: https://gitee.com/your-username/your-repo/raw/branch/config.txt
```

### 2. 订阅下载行为

- 订阅 User-Agent 固定为 FlClash。
- 加密订阅会从登录返回的 subscribeUrl 中提取 token，token 可能在查询参数中，也可能在路径里。
- 订阅下载超时 30 秒，并支持多 URL 竞速。
- 代码位置：
  - lib/xboard/infrastructure/http/user_agent_config.dart
  - lib/xboard/features/subscription/services/encrypted_subscription_service.dart
  - lib/xboard/features/subscription/utils/subscription_url_helper.dart

### 3. XBoard 面板 API 行为

- SDK 登录后请求会自动补 Authorization 请求头；如果 token 没有 Bearer 前缀，SDK 会自动补成 Bearer token。
- SDK 既有 GET，也有 POST、PUT、DELETE 请求封装。
- 代码位置：
  - lib/sdk/flutter_xboard_sdk/lib/src/core/auth/auth_interceptor.dart
  - lib/sdk/flutter_xboard_sdk/lib/src/core/http/http_service.dart
  - lib/xboard/infrastructure/http/xboard_http_client.dart

### 4. 工单与 WebSocket 行为

- 工单列表、详情、创建、回复和关闭请求复用面板域名与 Authorization 请求头。
- 工单详情接口会带 id 查询参数。
- 状态上报 WebSocket 会在连接时追加 nodeId 到路径，并可带 Authorization: Bearer token。
- 代码位置：
   - lib/sdk/flutter_xboard_sdk/lib/src/panels/xboard/apis/xboard_ticket_api.dart
  - lib/xboard/features/remote_task/services/status_reporting_service.dart

这些行为直接决定了 CDN 规则必须正确处理：POST、Authorization、查询参数、WebSocket 升级请求、长连接、禁止缓存的动态路径。

## 已验证事实

本节只写已在官方一手文档中明确找到依据的事实。

### 1. 中国内地 CDN 节点的 ICP 备案 / 域名接入要求

1. 阿里云 CDN 官方“添加加速域名”文档写明：当目标加速区域为“仅中国内地”或“全球”时，域名需要完成备案。
   - 来源：https://help.aliyun.com/zh/cdn/getting-started/add-a-domain-name

2. 阿里云 CDN 官方“使用限制”文档进一步写明：如果加速区域为“全球或仅中国内地”，无论源站在哪里，域名都必须备案。
   - 来源：https://help.aliyun.com/zh/cdn/product-overview/limits

3. 阿里云 CDN 在新增域名流程中要求先拥有稳定运行的源站和用于加速的域名，域名首次接入时还要完成域名归属权验证。
   - 来源：https://help.aliyun.com/zh/cdn/getting-started/add-a-domain-name

4. 阿里云 CDN 所有接入域名都要经过内容审核，并受平台安全违规内容限制。
   - 来源：https://help.aliyun.com/zh/cdn/product-overview/limits

含义：

- “源站在海外”不等于“可以免备案后使用中国内地节点”。
- 只要你要让国内用户命中阿里云 CDN 的中国内地节点，就要按该加速域名完成备案与审核。

### 2. 海外源站是否可作为回源站，以及跨境回源的性能 / 稳定性边界

1. 阿里云 CDN 支持的源站类型包括：OSS 域名、IP、源站域名和函数计算域名。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-an-origin-server
   - 来源：https://help.aliyun.com/zh/cdn/getting-started/add-a-domain-name

2. 对 IP 源站，官方要求是公网 IP，不支持内网 IP；对域名源站，支持配置多个域名作为源站地址，且源站域名不能与加速域名相同。
   - 来源：https://help.aliyun.com/zh/cdn/product-overview/limits

3. 官方文档没有要求源站必须位于中国内地，因此从产品能力上看，海外公网域名或海外公网 IP 可以作为回源站。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-an-origin-server
   - 来源：https://help.aliyun.com/zh/cdn/product-overview/limits

4. 阿里云 CDN 对回源链路给出了默认时延边界：源站 TCP 建连超时默认 10 秒，源站写超时默认 30 秒，源站读超时默认 30 秒；收到源站 5xx 时会重试。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-an-origin-server
   - 来源：https://help.aliyun.com/zh/cdn/product-overview/limits

5. 多源站可以做主备和权重；当主源站连接失败时可切换备源站。
   - 来源：https://help.aliyun.com/zh/cdn/getting-started/add-a-domain-name
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-an-origin-server

工程含义：

- “能回源到海外”不等于“跨境回源一定稳定”。
- 中国内地节点命中缓存时用户体验取决于边缘节点；未命中缓存时仍受中国内地到海外源站的跨境链路质量影响。
- 因此该方案的上限取决于缓存命中率。命中率低的动态 API，不应把 CDN 当作根本加速手段。

### 3. 加速区域选择的影响

1. “仅中国内地”：用户访问被调度到中国内地就近节点。
   - 来源：https://help.aliyun.com/zh/cdn/getting-started/add-a-domain-name

2. “全球”：用户访问会择优调度到全球就近节点。
   - 来源：https://help.aliyun.com/zh/cdn/getting-started/add-a-domain-name

3. “全球（不包含中国内地）”：中国内地用户会被调度到日本、新加坡和中国香港的 CDN 节点；阿里云在“使用限制”页也写明，这种模式禁止用户访问中国内地节点。
   - 来源：https://help.aliyun.com/zh/cdn/getting-started/add-a-domain-name
   - 来源：https://help.aliyun.com/zh/cdn/product-overview/limits

4. 若加速区域是“仅中国内地”或“全球”，域名都必须备案；“全球（不包含中国内地）”不在该条官方备案要求内。
   - 来源：https://help.aliyun.com/zh/cdn/getting-started/add-a-domain-name
   - 来源：https://help.aliyun.com/zh/cdn/product-overview/limits

对本项目的直接影响：

- 如果目标是“给中国内地用户用中国内地节点加速”，只能选“仅中国内地”或“全球”，因此必须备案。
- 如果不备案，只能保守考虑“全球（不包含中国内地）”，那中国内地用户会被调度到中国香港、日本、新加坡节点，效果与“内地节点加速”不是一回事。

### 4. 动态 API、POST、Authorization / Cookie、查询参数的 CDN 支持与配置边界

1. 阿里云 CDN 官方“使用限制”明确写明，常见 HTTP 请求方式里，CDN 支持 GET、PUT、POST、HEAD、OPTIONS；DELETE 和 PATCH 需要 ESA。
   - 来源：https://help.aliyun.com/zh/cdn/product-overview/limits

2. 阿里云 CDN 官方“应用场景”把 API 接口、数据库交互请求归类为动态内容，并明确建议静态内容使用阿里云 CDN，加速动态内容则使用阿里云边缘安全加速 ESA。
   - 来源：https://help.aliyun.com/zh/cdn/product-overview/scenarios

3. 阿里云 CDN 官方“配置 CDN 缓存过期时间”文档明确建议：动态内容如 PHP、JSP 设为 0 秒不缓存；并建议动静分离，例如 /static/ 长缓存、/api/ 不缓存。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-the-cdn-cache-expiration-time

4. 阿里云 CDN 官方“远程鉴权”文档表明，CDN 可以把用户请求的 URL 参数和请求头转发给鉴权服务器，保留指定或全部参数，并能保留 cookies、user_agent 等请求头；远程鉴权支持 GET、HEAD、POST。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-remote-authentication

5. 阿里云 CDN 官方“修改出站请求头”文档表明，CDN 回源时可以携带和改写回源请求头，默认就会带上 Host、X-Forwarded-For、Ali-Cdn-Real-Ip 等头，也可以自定义增加、删除、变更或替换回源请求头。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-custom-request-headers

6. 阿里云 CDN 官方“配置 CDN 缓存过期时间”文档表明，缓存规则支持按目录或文件后缀设置，并能基于 Header、URL 参数等规则条件进一步限制规则生效范围。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-the-cdn-cache-expiration-time

7. 阿里云 CDN 官方“远程鉴权”文档表明，URL 参数可以选择保留所有、保留指定、删除所有；请求头也可以按同样思路处理。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-remote-authentication

对当前仓库的映射：

- XBoard 登录后 API 使用 Authorization 头，没有问题，CDN 可以转发。
- 在线客服接口使用 Authorization 头和查询参数 limit / offset，没有问题，CDN 可以转发，但应视为动态内容不缓存。
- 加密订阅 token 既可能在 path，也可能在 query；如果错误配置了忽略参数、重写路径或缓存键，容易把不同用户订阅混淆，因此应按用户隔离并默认不缓存。

### 5. HTTPS 到边缘、HTTPS 回源、回源 Host / SNI、源站访问控制

1. 阿里云 CDN 支持在加速域名上配置 HTTPS 证书，以实现客户端到 CDN 节点的 HTTPS。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/https

2. 若要实现全链路 HTTPS，需要源站也支持 HTTPS，并在 CDN 侧启用 HTTPS 回源。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/https
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-the-origin-protocol-policy

3. 阿里云 CDN 的回源协议可配置为 HTTP、HTTPS 或“跟随”；如果启用 HTTPS 回源，CDN 会与源站做 TLS 握手并校验证书，证书无效或过期会导致回源失败。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-the-origin-protocol-policy

4. 阿里云 CDN 官方明确提示：当回源协议配置为 HTTPS 时，应同时检查默认回源 HOST 与回源 SNI；若配置不正确，可能导致 Bad Request、502 或回源失败。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-the-origin-protocol-policy
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-the-default-origin-host

5. 默认回源 HOST 可选加速域名、源站域名或自定义域名；源站若用虚拟主机，多站点监听时必须与源站证书和站点配置一致。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-the-default-origin-host

6. 阿里云 CDN 支持 UA 黑白名单、IP 黑白名单、远程鉴权，也支持给源站添加自定义回源请求头。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-a-user-agent-blacklist-or-whitelist
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-an-ip-blacklist-or-whitelist
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-remote-authentication
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-custom-request-headers

对当前项目的安全含义：

- CDN 前置后，源站 Caddy 不应只信任任意传入的 X-Forwarded-For。
- 源站侧应至少校验“来自 CDN 的回源约束”，例如：回源 Host / SNI 正确、只放行 CDN 回源路径、对关键动态接口继续做应用层鉴权。
- 如果要在 Caddy 上读取真实客户端 IP，需要按可信代理模型配置，不能盲信任外部头部。

### 6. 缓存规则

1. 阿里云 CDN 缓存规则支持按目录或后缀设置缓存时长，并支持 0 秒不缓存。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-the-cdn-cache-expiration-time

2. 若源站返回 Cache-Control: no-cache、no-store、max-age=0 或 Pragma: no-cache，CDN 默认不缓存。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-the-cdn-cache-expiration-time

3. 动静分离是官方推荐做法，典型示例就是 /static/ 长缓存、/api/ 不缓存。
   - 来源：https://help.aliyun.com/zh/cdn/user-guide/configure-the-cdn-cache-expiration-time

可直接落到当前项目的规则建议：

- /api/ 下登录、用户信息、支付、工单、在线客服 HTTP API：0 秒，不缓存。
- 订阅下载接口：0 秒，不缓存。
- WebSocket 入口：不缓存，并保持升级链路透传。
- redirect 远程配置 JSON：短缓存，例如 30 到 120 秒，根据更新频率调优。
- 静态远程配置文件、安装包、图片、字体：短到中等缓存，结合版本号或主动刷新。

## 需要用户在控制台或工单中确认的项目

本节不是“无法实现”，而是“本次研究中没有找到足够直接的一手官方文档，不能替你擅自下结论”。

### 1. 阿里云 CDN 对 WebSocket 的官方支持细节

已知事实：

- Caddy 官方 reverse_proxy 文档明确支持 WebSocket，代理会处理 HTTP Upgrade 并进入双向隧道模式。
  - 来源：https://caddyserver.com/docs/caddyfile/directives/reverse_proxy

本次未直接核实到的阿里云 CDN 一手事实：

- 阿里云 CDN 普通产品页中，未在本次检索到的官方文档里找到足够直接的“WebSocket 支持范围、限制、控制台开关、超时行为、是否区分 CDN 与 DCDN / ESA”的明确页面。

因此建议：

1. 在阿里云 CDN 控制台目标域名上做一次最小化验证：使用 wss 地址通过中国内地节点连接，并观察 Upgrade 是否成功。
2. 同时核对该能力是否属于普通 CDN、DCDN 或 ESA 范围，避免买错产品形态。
3. 若 WebSocket 是关键链路，优先保留“直连海外 Caddy / 就近境外入口”的兜底方案，不要在未验证前把它设计成唯一通路。

### 2. 是否需要 ESA 而不是普通 CDN 来承接主要动态 API

已验证事实：

- 阿里云官方“应用场景”明确把动态内容建议到 ESA。
  - 来源：https://help.aliyun.com/zh/cdn/product-overview/scenarios

需要你结合业务确认的项目：

- 如果 XBoard 主站对登录后 API 的性能很敏感、未命中缓存占比高、还需要更多动态安全能力，那么应该评估 ESA，而不是继续把普通 CDN 当作动态加速主方案。

## 工程判断

以下内容是基于上面的已验证事实、再结合本仓库代码行为做出的工程建议，不是官方原文。

### 1. 这套方案“可用”，但不要把它理解成“所有业务都会被中国内地节点显著加速”

因为海外源站可回源，只要缓存命中率高，国内用户访问静态配置和静态资源会明显受益；但对必须频繁回源的动态 API，瓶颈仍然是内地边缘到海外源站的跨境链路。

### 2. 对当前仓库最适合的拆分是“三域名或三路径分层”

推荐拆分：

1. 配置域名：给 redirect 远程配置 JSON 和其他静态配置文件使用。
2. 面板 / API 域名：给 XBoard API 使用，优先经 ESA 并全量不缓存；若使用普通 CDN，必须确认业务不会调用 DELETE / PATCH。
3. 订阅 / WebSocket 域名：订阅下载独立域名；WebSocket 优先经 ESA，并预留直连海外 Caddy 的兜底入口。

原因：

- 当前客户端里订阅、登录 API、在线客服和 WebSocket 的行为差异很大，混在一个域名下容易误配缓存和规则引擎。
- 动静分离也与阿里云官方缓存最佳实践一致。

### 3. 不建议继续依赖“弱混淆”替代正式鉴权

当前仓库示例里有：

- 通过 User-Agent 携带约定字符串。
- 通过响应前缀做简单混淆。

这些可以作为兼容历史客户端的附加措施，但不应代替：

- XBoard 本身的 Authorization 鉴权。
- CDN 的远程鉴权或接入控制。
- 源站的最小暴露面。

### 4. 源站访问控制的合理做法

推荐顺序：

1. CDN / ESA 边缘做 HTTPS，并覆盖写入高熵回源校验头，例如 X-Origin-Verify。
2. Caddy 校验回源头后再代理到 XBoard；条件允许时，防火墙进一步只允许阿里云回源地址访问 443 端口。
3. XBoard 应用层继续依赖 Authorization 和会话逻辑，不因为前面有边缘节点就放松鉴权。

不推荐：

- 仅依赖可伪造的 X-Forwarded-For 做安全边界。
- 仅依赖 User-Agent 白名单充当主鉴权。

## 适合当前仓库的推荐架构

### 推荐架构 A：备案可做，目标是让中国内地用户命中中国内地节点

适用条件：

- 你愿意对 config.example.com、api.example.com、sub.example.com 之类加速域名完成 ICP 备案。
- 主要收益诉求是“远程配置和静态下载更快”，而不是“所有动态 API 都像内地源站一样快”。

拓扑：

```text
Flutter 客户端
  -> config.example.com  -> 阿里云 CDN（仅中国内地 或 全球） -> 海外 Caddy -> redirect JSON / 静态配置
  -> api.example.com     -> 阿里云 ESA                           -> 海外 Caddy -> XBoard API
  -> sub.example.com     -> 阿里云 CDN（仅中国内地 或 全球） -> 海外 Caddy -> XBoard 订阅接口
  -> ws.example.com      -> 阿里云 ESA 或海外直连入口            -> 海外 Caddy -> XBoard WebSocket
```

推荐理由：

- 与当前仓库的 redirect 源、订阅源、登录 API、WebSocket 行为一致。
- 可为 config.example.com 单独设置短缓存，不影响 api.example.com 和 sub.example.com。

### 备选架构 B：暂时不备案

适用条件：

- 当前无法完成备案，但又希望先提供境外就近节点。

拓扑：

```text
Flutter 客户端
  -> 域名 -> 阿里云 CDN 全球（不包含中国内地） -> 中国香港 / 日本 / 新加坡节点 -> 海外 Caddy
```

限制：

- 这不是“中国内地节点加速”。
- 中国内地用户会被调度到境外近邻节点，效果通常好于直接跨洋，但不等于使用中国内地边缘节点。

## 阿里云 CDN 规则建议

### 1. 域名与区域

- config.example.com：仅中国内地 或 全球；必须备案。
- api.example.com：仅中国内地 或 全球；必须备案。
- sub.example.com：仅中国内地 或 全球；必须备案。
- ws.example.com：是否接入普通 CDN，先做最小验证；未验证前不要强依赖。

### 2. 缓存建议

config.example.com：

- /api/v1/redirect/domains：30 到 120 秒。
- 静态 JSON / TXT 配置：1 到 10 分钟，视发布频率调整。

api.example.com：

- /api/*：0 秒，不缓存。

sub.example.com：

- /api/v2/subscription-encrypt/*：0 秒，不缓存。
- 其他用户专属订阅路径：0 秒，不缓存。

ws.example.com：

- 全部不缓存。

### 3. 请求头与鉴权建议

- 保留 Authorization。
- 不要删除用户请求中的查询参数，特别是订阅 token 相关参数。
- 若使用远程鉴权，显式保留 Authorization、User-Agent、Cookie 以及关键 URL 参数。
- 在边缘覆盖写入 X-Origin-Verify 等高熵回源校验头，不要使用“追加”模式，以免客户端自带同名 Header 穿透。
- 若源站需要识别客户端来源，可利用 Ali-Cdn-Real-Ip 或 X-Forwarded-For，但只在可信代理模型下使用。

### 4. HTTPS / 回源建议

- 客户端到 CDN：开启 HTTPS。
- CDN 到海外 Caddy：开启 HTTPS 回源。
- 回源 HOST 与回源 SNI：都设置为源站实际证书匹配的域名。
- 若源站是 IP + 证书场景：阿里云 CDN 侧应正确配置回源 SNI；Caddy 侧也应保证证书 SAN 覆盖该域名。

## Caddy v2 配置示例

以下示例使用标准 Caddy v2 指令，并与本仓库 XBoard 默认在 `127.0.0.1:7001` 汇聚 HTTP 和 `/ws` 的部署方式一致。需在 Caddy 进程环境中设置高熵随机值 `ORIGIN_VERIFY`，并在阿里云侧使用“覆盖”方式写入同一个 `X-Origin-Verify` 回源请求头。

### 1. 海外 Caddy 作为源站入口

```caddyfile
config-origin.example.net {
    encode gzip zstd

  @config {
    header X-Origin-Verify {$ORIGIN_VERIFY}
    path /api/v1/redirect/domains /config.json
  }

  handle @config {
        header {
      Cache-Control "public, max-age=60, s-maxage=60"
        }
    reverse_proxy 127.0.0.1:7001
    }

  respond 403
}

api-origin.example.net, sub-origin.example.net, ws-origin.example.net {
    encode gzip zstd

  @edge header X-Origin-Verify {$ORIGIN_VERIFY}

  handle @edge {
    header {
      Cache-Control "private, no-store"
        }
    # Caddy 默认透传 Authorization、Cookie、查询参数、请求体和 WebSocket Upgrade。
    reverse_proxy 127.0.0.1:7001 {
            stream_timeout 24h
            stream_close_delay 5m
        }
    }

  respond 403
}
```

若外层 Caddy 与 XBoard 不在同一台机器，可将 `127.0.0.1:7001` 换成具有可信证书的 HTTPS 上游：

```caddyfile
reverse_proxy https://panel-origin.example.net {
  header_up Host panel-origin.example.net
  transport http {
    tls_server_name panel-origin.example.net
  }
}
```

不要照搬仓库内嵌 Caddy 的 `trusted_proxies static 0.0.0.0/0 ::/0` 到公网外层 Caddy。若确实需要解析真实客户端 IP，应获取并维护阿里云官方回源 CIDR，只信任这些网段，并启用 `trusted_proxies_strict`；在此之前保持默认不信任外部 X-Forwarded-For 更安全。

### 2. 若需要兼容当前仓库里的 UA 约定和响应混淆

只建议把它当兼容性措施，而不是主要安全边界。

```caddyfile
api-origin.example.net {
    @api path /api/*
    @ua header User-Agent *YOUR_ENCRYPTED_STRING_HERE*

    handle @api {
        handle @ua {
            reverse_proxy https://real-panel.example.net {
                header_up Host real-panel.example.net
                transport http {
                    tls_server_name real-panel.example.net
                }
            }
        }

        handle {
            respond "forbidden" 403
        }
    }
}
```

说明：

- 当前仓库代码确实存在基于 User-Agent 的约定，但 API、订阅、附件和域名竞速使用的 UA 并不相同，不能把该规则套在整个站点上。
- redirect 配置 JSON 的请求不会自动携带 `api_encrypted` UA，因此配置域名不能使用这条 UA 门禁。
- 更稳妥的安全边界仍应是高熵回源校验头、源站防火墙、XBoard 自身鉴权与 CDN / ESA 访问控制。
- 当前仓库的响应混淆前缀配置项是 xboard.security.obfuscation_prefix，可继续保留，但不建议把它当安全能力宣传。

## 面向当前仓库的配置落点建议

### 1. xboard.config.yaml

建议将现有配置拆成不同职责域名，例如：

```yaml
xboard:
  remote_config:
    sources:
      - name: redirect
        url: https://config.example.com/api/v1/redirect/domains
      - name: gitee
        url: https://raw.giteeusercontent.com/your/repo/raw/master/config.txt

  security:
    obfuscation_prefix: your_prefix_here
    user_agents:
      api_encrypted: Mozilla/5.0 (compatible; your_encrypted_marker)
      domain_racing_test: FlClash/1.0 (Domain Racing Test)
```

### 2. remote.config.example.json 对应的远端 JSON

建议：

- panels.mihomo 下的 url 使用 api.example.com 一类域名。
- subscription.urls 下的 url 使用 sub.example.com 一类域名。
- 远程任务的 ws 使用独立的 ws.example.com，并在上线前单独验证是否经 CDN；工单请求复用面板 API 域名。

原因：

- 这样最容易把缓存规则、HTTPS 回源和故障兜底分开治理。

## 合规边界

1. 本文不提供规避 ICP 备案、绕过中国内地接入要求、隐藏业务性质或规避网络监管的方案。
2. 阿里云 CDN 官方规则已经明确：选择“仅中国内地”或“全球”时，域名必须备案。
3. 接入中国内地节点前，还要接受阿里云内容审核与平台合规约束。

## 最终建议

### 可执行建议

1. 如果你的目标是“国内用户通过中国内地节点访问更快”，就按官方要求备案，并使用“仅中国内地”或“全球”区域。
2. 把远程配置、动态 API、订阅、WebSocket 分域名或至少分路径治理，避免缓存和访问控制互相污染。
3. 把“海外 Caddy + 阿里云 CDN”主要用于静态配置分发和下载链路优化；完整动态 API 优先使用 ESA，因为普通 CDN 不支持 DELETE / PATCH。
4. WebSocket 优先使用 ESA；若仍计划使用普通 CDN，上线前必须做控制台实测或工单确认，并保留海外直连兜底。
5. 全链路启用 HTTPS，并显式校准回源 Host / SNI。

### 不推荐的做法

1. 不备案却试图让中国内地用户命中中国内地 CDN 节点。
2. 把用户专属订阅或登录后 API 配成长缓存。
3. 把 User-Agent 混淆、响应前缀混淆当成主要安全策略。

## 官方来源清单

阿里云 CDN：

- 添加加速域名：https://help.aliyun.com/zh/cdn/getting-started/add-a-domain-name
- 使用限制：https://help.aliyun.com/zh/cdn/product-overview/limits
- 配置源站：https://help.aliyun.com/zh/cdn/user-guide/configure-an-origin-server
- 配置回源协议：https://help.aliyun.com/zh/cdn/user-guide/configure-the-origin-protocol-policy
- 配置默认回源 HOST：https://help.aliyun.com/zh/cdn/user-guide/configure-the-default-origin-host
- HTTPS 配置：https://help.aliyun.com/zh/cdn/user-guide/https
- 什么是缓存：https://help.aliyun.com/zh/cdn/user-guide/cache-settings
- 配置 CDN 缓存过期时间：https://help.aliyun.com/zh/cdn/user-guide/configure-the-cdn-cache-expiration-time
- 修改出站请求头：https://help.aliyun.com/zh/cdn/user-guide/configure-custom-request-headers
- 配置远程鉴权：https://help.aliyun.com/zh/cdn/user-guide/configure-remote-authentication
- 配置 UA 黑白名单：https://help.aliyun.com/zh/cdn/user-guide/configure-a-user-agent-blacklist-or-whitelist
- 配置 IP 黑白名单：https://help.aliyun.com/zh/cdn/user-guide/configure-an-ip-blacklist-or-whitelist
- 应用场景：https://help.aliyun.com/zh/cdn/product-overview/scenarios

Caddy 官方文档：

- reverse_proxy：https://caddyserver.com/docs/caddyfile/directives/reverse_proxy
- tls：https://caddyserver.com/docs/caddyfile/directives/tls

## Sentinel 应用层加密网关部署补充

本节对应 `Xboard/plugins/EncryptedGateway` 和 Sentinel 的 `security.encrypted_gateway`。它替代前文基于 User-Agent、响应前缀和旧订阅端点的弱混淆方案；前文 CDN 调研结论仍适用于配置分发和其他业务域名。

### 1. 域名与端口

推荐只新增一个 Sentinel 客户端子域名，例如 `client.example.com`：

```text
Sentinel -> HTTPS/ESA -> client.example.com/<随机路径> -> 宝塔 Nginx -> 127.0.0.1:7010 -> XBoard 插件
浏览器  -> HTTPS     -> panel.example.com              -> 原 XBoard 网页与 API
节点 WS -> WSS       -> ws.example.com/ws/              -> 127.0.0.1:8076
```

- `client.example.com` 仅接受配置的随机二进制 `POST`，不暴露面板首页、原 `/api/v1/*` 或订阅 URL。
- XBoard 原生 Octane 上游为 `127.0.0.1:7010`。
- WebSocket `127.0.0.1:8076` 本期不进入加密网关，继续使用独立域名或路径。
- 应用层加密不替代 TLS；边缘到源站也应使用 HTTPS 或可信内网。

### 2. 宝塔 Nginx 到 Octane 7010

先运行 `php plugins/EncryptedGateway/keygen.php 1`，将生成的随机路径分别写入服务端 `.env` 和 Sentinel 公共配置。以下示例中的路径必须替换成同一个真实随机值。

```nginx
server {
   listen 443 ssl http2;
   server_name client.example.com;

   client_max_body_size 4m;

   # 精确匹配随机入口，不要使用 /api/ 通配代理。
   location = /REPLACE_WITH_RANDOM_URL_SAFE_PATH {
      limit_except POST { deny all; }

      proxy_pass http://127.0.0.1:7010;
      proxy_http_version 1.1;
      proxy_set_header Connection "";
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;

      proxy_request_buffering on;
      proxy_buffering off;
      proxy_read_timeout 90s;
      proxy_send_timeout 90s;

      add_header Cache-Control "no-store, private" always;
      add_header X-Content-Type-Options "nosniff" always;

      # 不记录随机入口、请求体或响应体。需要指标时使用不含 $request_uri 的专用格式。
      access_log off;
   }

   location / {
      return 404;
   }
}
```

宝塔中修改配置后先执行 Nginx 配置测试，再 reload。插件或 `.env` 变更后必须清理 Laravel 配置缓存并重启 Octane；仅 reload Nginx 不会让 Octane 进程读取新密钥。

WebSocket 继续使用原配置：

```nginx
location /ws/ {
   proxy_pass http://127.0.0.1:8076;
   proxy_http_version 1.1;
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection "upgrade";
   proxy_set_header Host $host;
   proxy_read_timeout 60s;
}
```

### 3. CDN / ESA 规则

- 对随机入口强制 `POST` 透传，最大请求体至少 4 MiB。
- 缓存 TTL 设为 0，并保留源站的 `Cache-Control: no-store, private`。
- 不改写请求体、`Content-Type: application/octet-stream` 或路径。
- 限流按客户端 IP 做温和突发控制，建议先从每 IP 每秒 5 次、突发 20 次观察；登录、域名竞速和重试会产生短时并发。
- WAF 不应尝试按 JSON、表单或业务 URL 检查密文；可基于方法、大小、频率、TLS 和来源信誉判断。
- 边缘日志不得采集请求体或响应体。URI 中虽无 token，仍建议隐藏随机入口以减少暴露。

### 4. 密钥轮换与回滚

1. 服务端先把旧 current 移到 previous，再部署新的 current 私钥和 key id。
2. 重启 Octane，确认服务端同时接受两把密钥。
3. 再发布 Sentinel 的新公钥、key id 和随机路径。
4. 旧客户端退出窗口后删除 previous，并再次重启 Octane。

回滚时恢复旧 key id、公钥和路径。不得重新开放原 API 或明文订阅作为降级路径。详细命令见 `Xboard/plugins/EncryptedGateway/README.md`。
