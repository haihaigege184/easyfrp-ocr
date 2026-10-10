# EasyFrp 验证码 OCR 服务 —— 容器化镜像
#
# 为什么需要它:
#   EasyFrp (easyfrp.sian.one) 登录与签到都需要图形验证码（4 位数字 + 彩色干扰线）。
#   青龙面板容器通常是 Alpine musl，`onnxruntime` 没有 manylinux/musllinux wheel，
#   ddddocr 根本装不上。于是把 OCR 这个"重活"独立成一个容器，青龙侧只做 HTTP 调用。
#
# 核心策略（实测结论）:
#   ddddocr 的输出可二分 —— 给出「4 位纯数字」时准确率 ≈100%，给出其他形式时 ≈0%。
#   本服务对同一张图跑 raw / bright 两条通道，任一通道给出 4 位纯数字就置 clean=true，
#   调用方看到 clean=false 换图重试即可，不浪费验证码提交轮次。
#
# 构建:
#   docker build -t easyfrp-ocr .
FROM python:3.11-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# 国内镜像加速（可用 --build-arg 覆盖）
ARG APT_MIRROR=mirrors.tuna.tsinghua.edu.cn
ARG PIP_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple

# onnxruntime 需要 libgomp1；opencv-python-headless 需要 libglib2.0-0
RUN set -eux; \
    if [ -f /etc/apt/sources.list ]; then \
        sed -i "s|deb.debian.org|${APT_MIRROR}|g; s|security.debian.org|${APT_MIRROR}|g" /etc/apt/sources.list; \
    fi; \
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
        sed -i "s|deb.debian.org|${APT_MIRROR}|g; s|security.debian.org|${APT_MIRROR}|g" /etc/apt/sources.list.d/debian.sources; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends libgomp1 libglib2.0-0; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -i "${PIP_INDEX}" --trusted-host "$(echo "${PIP_INDEX}" | awk -F/ '{print $3}')" \
        -r requirements.txt

COPY app/ ./

EXPOSE 13003

# ddddocr 首次加载模型约需 20~60s，start-period 给足
HEALTHCHECK --interval=30s --timeout=15s --start-period=120s --retries=3 \
    CMD python -c "import json,urllib.request; \
d=json.load(urllib.request.urlopen('http://127.0.0.1:13003/health',timeout=10)); \
raise SystemExit(0 if d.get('ok') else 1)"

CMD ["python", "-u", "server.py", "--host", "0.0.0.0", "--port", "13003"]
