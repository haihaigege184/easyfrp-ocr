# easyfrp-ocr

> EasyFrp 验证码识别服务（Docker 化）—— 基于 ddddocr 的「双通道 + 高置信门控」方案。

[![Docker Image](https://img.shields.io/badge/ghcr.io-easyfrp--ocr-blue)](https://github.com/haihaigege184/easyfrp-ocr/pkgs/container/easyfrp-ocr)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## 这是什么

[easyfrp.sian.one](https://easyfrp.sian.one) 的登录与每日签到都需要**图形验证码**（4 位数字 + 密集彩色干扰线）。

青龙面板容器通常是 **Alpine musl**，`onnxruntime` 没有对应的二进制 wheel，`ddddocr` 根本无法安装。
本项目把 OCR 这个"重活"独立成一个容器：**青龙侧只做一次 HTTP 调用**，把重依赖全部关进镜像里。

## 核心思路：高置信门控，而不是追求单次全对

实测发现 ddddocr 在**这类**高密度干扰线上的输出可以二分：

| 输出形态 | 占比 | 该条件下的准确率 |
|---|---|---|
| **4 位纯数字**（如 `0443`） | 75% ~ 90% | **≈100%**（raw 24/24、bright 28/29） |
| 其他（含字母 / 位数不对，如 `117o`、`171`） | 10% ~ 25% | **0%** |

也就是说，**"能不能给出 4 位纯数字"本身就是一个免费的高置信信号**。

所以本服务不赌单次识别，而是：

1. 同一张图跑两条通道 —— `raw`（原图）与 `bright`（亮度门限去除彩色干扰线）
2. 任一通道给出 4 位纯数字 → `clean=true`，调用方**放心提交**
3. 都不行 → `clean=false`，调用方**直接换图重试**（验证码 key 一次性但可重复提交，换图成本极低）

实测：**clean 率 93.3%，clean 时命中率 100%，平均只需 1.07 张图**。

## 快速开始

### 方式一：直接拉镜像（推荐）

```bash
docker run -d \
  --name ef-ocr \
  --restart unless-stopped \
  -p 13003:13003 \
  ghcr.io/haihaigege184/easyfrp-ocr:latest
```

### 方式二：compose

```bash
docker compose up -d
```

### 方式三：本地构建

```bash
docker build -t easyfrp-ocr .
docker run -d --name ef-ocr --restart unless-stopped -p 13003:13003 easyfrp-ocr
```

> 首次启动需加载 ddddocr 模型，约 20~60 秒后 `/health` 才返回 `ok:true`。

## API

### `GET /health`

```json
{"ok": true, "engine": "ddddocr", "channels": ["raw", "bright"],
 "loaded": true, "error": null, "uptimeSec": 31.2}
```

> `uptimeSec` = 引擎加载完成至今的秒数（不是加载耗时）。

### `POST /ocr`

请求：

```json
{"imageBase64": "<base64，可带 data:image/png;base64, 前缀>"}
```

响应：

```json
{
  "ok": true,
  "text": "0443",
  "clean": true,
  "channels": {
    "raw":    {"text": "0443", "clean": true},
    "bright": {"text": "0443", "clean": true}
  },
  "ms": 221,
  "bytes": 6081
}
```

| 字段 | 说明 |
|---|---|
| `text` | 建议提交的验证码。`clean=true` 时才值得提交 |
| `clean` | **是否高置信**。`false` 表示建议换图重试，不要浪费提交轮次 |
| `channels` | 两条通道各自的原始结果，便于排查 |

```bash
curl -s http://127.0.0.1:13003/ocr \
  -H 'Content-Type: application/json' \
  -d "{\"imageBase64\":\"$(base64 -w0 captcha.png)\"}"
```

## 在青龙里接入

同宿主机上的青龙容器，直接用 Docker 网桥网关地址访问宿主机端口：

```bash
# /ql/data/config/env.sh
export EF_OCR_URL=http://172.17.0.1:13003/ocr
export EF_CAPTCHA_MODE=auto
```

> 注意：青龙的 **task 不会注入「环境变量」表里的变量**，必须写进 `/ql/data/config/env.sh`。

## 构建参数

| build-arg | 默认值 | 说明 |
|---|---|---|
| `APT_MIRROR` | `mirrors.tuna.tsinghua.edu.cn` | Debian 源镜像 |
| `PIP_INDEX` | `https://pypi.tuna.tsinghua.edu.cn/simple` | pip 索引 |

```bash
docker build --build-arg PIP_INDEX=https://pypi.org/simple -t easyfrp-ocr .
```

## 技术栈

- Python 3.11 (slim-bookworm)
- [ddddocr](https://github.com/sml2h3/ddddocr) 1.6.1 + onnxruntime 1.31.0
- numpy / pillow，`bright` 通道为纯 numpy 亮度门限（无 OpenCV 依赖）

## 免责声明

本项目仅用于**自动化管理本人自有账号**的登录 / 签到流程，不涉及任何数据抓取或绕过付费。
请遵守目标站点的服务条款，使用者自行承担相应责任。

## License

[MIT](LICENSE)
