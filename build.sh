#!/usr/bin/env bash
# 一键构建并（可选）推送镜像到 ghcr.io
#
#   ./build.sh              # 仅本地构建
#   ./build.sh push         # 构建 + 推送 ghcr.io
#
# 推送前需先登录:
#   echo "<GitHub PAT, 需 write:packages>" | docker login ghcr.io -u <user> --password-stdin
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/haihaigege184/easyfrp-ocr}"
TAG="${TAG:-latest}"

echo "==> building ${IMAGE}:${TAG}"
docker build -t "${IMAGE}:${TAG}" .

if [ "${1:-}" = "push" ]; then
  echo "==> pushing ${IMAGE}:${TAG}"
  docker push "${IMAGE}:${TAG}"
  echo "==> done. 拉取: docker pull ${IMAGE}:${TAG}"
else
  echo "==> build only. 推送请执行: $0 push"
fi
