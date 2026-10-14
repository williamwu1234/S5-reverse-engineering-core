#!/usr/bin/env bash
# 连相机热点 → 测「一边录制一边发送图像」是否导出内容 → 自动还原 Wi-Fi
#
# 为什么现在安全：
#   本机默认路由走 **有线 en9**（网络服务顺序里有线排在 Wi-Fi 之前），
#   所以把 Wi-Fi 拿去连相机热点**不会**断开远程会话/家庭网络。
#
# 用法：
#   ./ap_test.command              # 全程自动（测完自动断开热点）
#   ./ap_test.command --keep       # 测完保留热点连接
#   ./ap_test.command --ssid X --pass Y

set -u
cd "$(dirname "$0")"

SSID="S5-XXXXXX"
PASS="a70741470e23"
KEEP=0
PY="/Users/wuwilliam/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3"

while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP=1 ;;
    --ssid) SSID="$2"; shift ;;
    --pass) PASS="$2"; shift ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
  shift
done
[ -x "$PY" ] || PY="$(command -v python3)"

echo "════════════════════════════════════════════════════════════"
echo " 相机热点测试：$SSID"
echo "════════════════════════════════════════════════════════════"

echo
echo "【0】安全检查：确认默认路由不在 Wi-Fi 上"
DEF=$(route get default 2>/dev/null | awk '/interface:/{print $2}')
echo "    默认路由接口 = $DEF"
if [ "$DEF" = "en0" ]; then
  echo "    ❌ 默认路由在 Wi-Fi 上！切热点会断网。请先确认网线已插好、且服务顺序里有线优先。"
  exit 1
fi
echo "    ✅ 默认路由不在 Wi-Fi，可以安全切换"

echo
echo "【1】连接相机热点"
networksetup -setairportnetwork en0 "$SSID" "$PASS" 2>&1 | sed 's/^/    /'
sleep 6
CUR=$(networksetup -getairportnetwork en0 2>/dev/null | sed 's/.*: //')
echo "    当前 Wi-Fi = $CUR"
if [ "$CUR" != "$SSID" ]; then
  echo "    ❌ 连接失败。相机热点可能没开——请在相机上进入 Wi-Fi 发送图像界面。"
  exit 2
fi
GW=$(ipconfig getifaddr en0 2>/dev/null)
echo "    Wi-Fi 地址 = $GW"

echo
echo "【2】找相机（热点网关通常是 192.168.54.1）"
CAM=""
for c in 192.168.54.1 192.168.0.1 192.168.1.131; do
  R=$(curl -s -m 6 -A "LUMIX Sync" "http://$c/cam.cgi?mode=getstate" 2>/dev/null | grep -o "<result>[^<]*</result>" | head -1)
  echo "    $c -> ${R:-（无响应）}"
  [ -n "$R" ] && { CAM="$c"; break; }
done
[ -z "$CAM" ] && { echo "    ❌ 找不到相机"; [ $KEEP -eq 0 ] && networksetup -setairportpower en0 off; exit 3; }
echo "    ✅ 相机 = $CAM"

echo
echo "【3】相机状态"
curl -s -m 8 -A "LUMIX Sync" "http://$CAM/cam.cgi?mode=getstate" 2>/dev/null \
  | grep -oE "<result>[^<]*</result>|<cammode>[^<]*</cammode>|<batt>[^<]*</batt>" | sed 's/^/    /'

echo
echo "【4】★ 关键测试：DLNA 内容树"
"$PY" - "$CAM" <<'PYEOF'
import sys, time, re
sys.path.insert(0, ".")
try:
    import s5_content as C
except Exception as e:
    print("    导入失败:", e); raise SystemExit
CAM = sys.argv[1]
st, body = C.browse(CAM, "0", count=0)
items = C.parse_items(body); fault = C.parse_fault(body)
print(f"    BrowseDirectChildren -> HTTP {st}" + (f"  UPnP {fault}" if fault else ""))
print(f"    ★ 条目数 = {len(items)}")
for it in items[:10]:
    print(f"       {it['title']:16s} {it['cls'][:24]:26s} {it['res'][:56]}")
if st == 403:
    print("\n    ❌ 403 = accctrl 未达 ok（授权问题，不是模式问题）")
    print("       → 先在热点侧跑一次监看工具拿 ok，再重跑本脚本")
elif items:
    print("\n    🎉🎉 **拍摄模式下就有内容 ⇒「一边录制一边发送图像」生效！**")
    print("        ⇒ 可以做到「边录边取片边烧 LUT」")
    it = items[0]
    import os
    dst = os.path.join("downloads_ap", (it["title"] or "photo") + os.path.splitext(it["res"])[1])
    os.makedirs("downloads_ap", exist_ok=True)
    ok, n = C.download(CAM, it["res"], dst)
    print(f"        下载验证: {'✅' if ok else '❌'} {n:,} 字节 → {dst}")
else:
    print("\n    ⚠️ 热点下拍摄模式**仍然没有内容**")
    print("       ⇒ 该功能可能只在**回放模式**导出，或需要相机端另行触发")
    print("       → 试：在相机上按回放键，再重跑本脚本")
PYEOF

if [ $KEEP -eq 0 ]; then
  echo
  echo "【5】断开热点，还原 Wi-Fi"
  networksetup -setairportpower en0 off 2>&1 | sed 's/^/    /'
  echo "    ✅ 已断开"
fi
echo
echo "════════════════════════════════════════════════════════════"
