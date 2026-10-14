#!/bin/bash
# 启动 DC-S5 无线监看（含 LUT 实时套用）
#
# 为什么需要这个脚本：
#   macOS 自带的 /usr/bin/python3 或 Xcode 的 python3.9 **没有 numpy/Pillow**，
#   LUT 实时套用面板会因此被禁用。本脚本按优先级挑一个带依赖的解释器。

cd "$(dirname "$0")" || exit 1

CAM="${1:-192.168.1.131}"     # 第一个参数：相机 IP
PORT="${2:-8080}"             # 第二个参数：本机端口

# 按优先级找解释器（第一个能 import numpy+PIL 的胜出）
CANDIDATES=(
  "/Users/wuwilliam/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3"
  "$(command -v python3)"
  "/opt/homebrew/bin/python3"
  "/usr/local/bin/python3"
  "/usr/bin/python3"
)

PY=""
for c in "${CANDIDATES[@]}"; do
  [ -x "$c" ] || continue
  if "$c" -c "import numpy, PIL" >/dev/null 2>&1; then PY="$c"; break; fi
  [ -z "$PY" ] && PY="$c"          # 记下第一个可用的作为兜底
done

if [ -z "$PY" ]; then
  echo "❌ 找不到可用的 python3"; exit 1
fi

if "$PY" -c "import numpy, PIL" >/dev/null 2>&1; then
  echo "✅ 解释器：$PY（含 numpy/Pillow ⇒ LUT 面板可用）"
else
  echo "⚠️  解释器：$PY（缺 numpy/Pillow ⇒ LUT 面板将禁用，监看/对焦/拍照不受影响）"
  echo "    想启用 LUT：$PY -m pip install numpy pillow"
fi

echo "🎥 相机 $CAM    本机 http://127.0.0.1:$PORT"
echo "   ↳ 启动后请【盯着相机屏幕】：若弹出「允许连接？」请按【允许】"
echo

exec "$PY" -u s5monitor.py --host "$CAM" --port "$PORT" --device-name "LUMIX Sync"
