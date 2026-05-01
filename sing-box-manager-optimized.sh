#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG="/etc/sing-box/config.json"
SERVICE="sing-box"
BACKUP_DIR="/etc/sing-box/backups"

REAL_USER="${SUDO_USER:-${USER:-root}}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6 || true)"
if [ -z "${REAL_HOME:-}" ]; then
  REAL_HOME="$HOME"
fi
PUBKEY_FILE="$REAL_HOME/.sb_public_key"

need_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "请用 sudo 运行：sudo bash $0"
    exit 1
  fi
}

check_deps() {
  local missing=0
  for cmd in python3 sing-box systemctl ss grep sed awk date cp mkdir ls head curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "缺少依赖：$cmd"
      missing=1
    fi
  done

  if [ "$missing" -eq 1 ]; then
    echo "请先安装缺失依赖后再运行。"
    exit 1
  fi
}

check_config_exists() {
  if [ ! -f "$CONFIG" ]; then
    echo "没有找到配置文件：$CONFIG"
    echo "请确认 sing-box 已安装，并且配置文件路径正确。"
    exit 1
  fi
}

get_json_value() {
python3 - "$1" "$CONFIG" <<'PY'
import json, sys

key = sys.argv[1]
path = sys.argv[2]

try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print("")
    sys.exit(0)

def get(d, keys, default=""):
    cur = d
    for k in keys:
        try:
            cur = cur[k]
        except Exception:
            return default
    return cur

mapping = {
    "port": ["inbounds", 0, "listen_port"],
    "uuid": ["inbounds", 0, "users", 0, "uuid"],
    "flow": ["inbounds", 0, "users", 0, "flow"],
    "server_name": ["inbounds", 0, "tls", "server_name"],
    "short_id": ["inbounds", 0, "tls", "reality", "short_id", 0],
    "private_key": ["inbounds", 0, "tls", "reality", "private_key"],
    "type": ["inbounds", 0, "type"],
    "tag": ["inbounds", 0, "tag"],
    "log_level": ["log", "level"]
}

if key not in mapping:
    print("")
else:
    value = get(data, mapping[key], "")
    if isinstance(value, (dict, list)):
        print(json.dumps(value, ensure_ascii=False))
    else:
        print(value)
PY
}

set_json_port() {
python3 - "$1" "$CONFIG" <<'PY'
import json, sys

port = int(sys.argv[1])
path = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

data["inbounds"][0]["listen_port"] = port

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}

pause() {
  echo
  read -rp "按回车继续..."
}

make_backup() {
  mkdir -p "$BACKUP_DIR"
  local backup="$BACKUP_DIR/config.$(date +%F-%H%M%S).json.bak"
  cp -a "$CONFIG" "$backup"
  echo "$backup"
}

show_overview() {
  local port type sni sid active
  port="$(get_json_value port)"
  type="$(get_json_value type)"
  sni="$(get_json_value server_name)"
  sid="$(get_json_value short_id)"
  active="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"

  echo "当前状态: ${active:-unknown} | 协议: ${type:-未知} | 端口: ${port:-未知} | SNI: ${sni:-未设置} | ShortID: ${sid:-未设置}"
}

show_menu() {
  clear
  echo "=================================="
  echo "      sing-box 管理脚本 优化版"
  echo "=================================="
  show_overview
  echo "=================================="
  echo "1) 查看配置文件"
  echo "2) 编辑配置文件"
  echo "3) 检查配置文件"
  echo "4) 重启 sing-box"
  echo "5) 查看 sing-box 状态"
  echo "6) 查看监听端口"
  echo "7) 查看最近日志"
  echo "8) 备份当前配置"
  echo "9) 恢复最近备份"
  echo "10) 生成 UUID"
  echo "11) 生成 Reality 密钥"
  echo "12) 显示客户端参数/分享链接"
  echo "13) 修改监听端口"
  echo "14) 放行端口到 ufw"
  echo "15) 保存/更新 PublicKey"
  echo "16) 安全检查"
  echo "17) 退出"
  echo "=================================="
}

view_config() {
  sed -n '1,260p' "$CONFIG"
}

edit_config() {
  local editor="${EDITOR:-nano}"
  if ! command -v "$editor" >/dev/null 2>&1; then
    editor="vi"
  fi
  "$editor" "$CONFIG"
}

check_config() {
  echo "检查配置中..."
  sing-box check -c "$CONFIG"
  echo "配置检查通过"
}

restart_service() {
  echo "重启前先检查配置..."
  sing-box check -c "$CONFIG"
  echo "重启 sing-box..."
  systemctl restart "$SERVICE"
  systemctl status "$SERVICE" --no-pager
}

show_status() {
  systemctl status "$SERVICE" --no-pager
}

show_ports() {
  echo "当前 sing-box 相关监听："
  ss -tulpn | grep -E 'sing-box|:8443|:443|:9443|:22' || true
  echo
  echo "全部监听端口："
  ss -tulpn | sed -n '1,120p'
}

show_logs() {
  journalctl -u "$SERVICE" -n 80 --no-pager
}

backup_config() {
  local backup
  backup="$(make_backup)"
  echo "已备份到: $backup"
}

restore_latest_backup() {
  mkdir -p "$BACKUP_DIR"

  local latest=""
  latest="$(ls -1t "$BACKUP_DIR"/config.*.json.bak "$CONFIG".*.bak 2>/dev/null | head -n 1 || true)"

  if [ -z "$latest" ]; then
    echo "没有找到备份文件"
    return
  fi

  echo "找到最近备份: $latest"
  read -rp "确认恢复? (y/n): " ans

  if [ "$ans" = "y" ]; then
    cp -a "$CONFIG" "$BACKUP_DIR/config.before-restore.$(date +%F-%H%M%S).json.bak"
    cp -a "$latest" "$CONFIG"
    echo "已恢复: $latest"

    if sing-box check -c "$CONFIG"; then
      read -rp "配置检查通过，是否立即重启 sing-box? (y/n): " restart_ans
      if [ "$restart_ans" = "y" ]; then
        systemctl restart "$SERVICE"
        systemctl status "$SERVICE" --no-pager
      fi
    else
      echo "警告：恢复后的配置检查失败，请手动检查。"
    fi
  else
    echo "已取消"
  fi
}

generate_uuid() {
  sing-box generate uuid
}

generate_reality_keypair() {
  local out public_key ans
  out="$(sing-box generate reality-keypair)"
  echo "$out"

  public_key="$(echo "$out" | awk -F': ' '/PublicKey/ {print $2}' | head -n 1 || true)"
  if [ -n "$public_key" ]; then
    echo
    read -rp "是否把 PublicKey 保存到客户端参数文件? (y/n): " ans
    if [ "$ans" = "y" ]; then
      echo "$public_key" > "$PUBKEY_FILE"
      chmod 600 "$PUBKEY_FILE"
      chown "$REAL_USER":"$REAL_USER" "$PUBKEY_FILE" 2>/dev/null || true
      echo "已保存 PublicKey 到: $PUBKEY_FILE"
    fi
  fi

  echo
  echo "提醒：PrivateKey 需要写入服务端 config.json；PublicKey 用于客户端。"
}

save_public_key() {
  read -rp "请输入 PublicKey: " pbk
  if [ -z "$pbk" ]; then
    echo "PublicKey 不能为空"
    return
  fi

  echo "$pbk" > "$PUBKEY_FILE"
  chmod 600 "$PUBKEY_FILE"
  chown "$REAL_USER":"$REAL_USER" "$PUBKEY_FILE" 2>/dev/null || true
  echo "已保存到: $PUBKEY_FILE"
}

get_server_ip() {
  local ip
  ip="$(curl -4 -s --max-time 5 ifconfig.me || true)"
  if [ -z "$ip" ]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  echo "${ip:-获取失败}"
}

show_client_info() {
  local port uuid flow server_name short_id type log_level public_key server_ip flow_param link

  port="$(get_json_value port)"
  uuid="$(get_json_value uuid)"
  flow="$(get_json_value flow)"
  server_name="$(get_json_value server_name)"
  short_id="$(get_json_value short_id)"
  type="$(get_json_value type)"
  log_level="$(get_json_value log_level)"

  if [ -f "$PUBKEY_FILE" ]; then
    public_key="$(cat "$PUBKEY_FILE")"
  else
    public_key=""
  fi

  server_ip="$(get_server_ip)"

  echo "注意：以下信息包含客户端连接参数，请勿公开截图。"
  echo "================ 客户端参数 ================"
  echo "协议类型: ${type:-未知}"
  echo "服务器地址: $server_ip"
  echo "端口: ${port:-未读取到}"
  echo "UUID: ${uuid:-未读取到}"
  echo "Flow: ${flow:-空}"
  echo "TLS/Reality SNI: ${server_name:-未读取到}"
  echo "ShortID: ${short_id:-未读取到}"
  echo "PublicKey: ${public_key:-未保存，请先选 15 保存 PublicKey}"
  echo "日志级别: ${log_level:-未设置}"
  echo "==========================================="
  echo
  echo "手动填写建议:"
  echo "地址 = $server_ip"
  echo "端口 = $port"
  echo "UUID = $uuid"
  echo "flow = ${flow:-空}"
  echo "network = tcp"
  echo "security = reality"
  echo "SNI = $server_name"
  echo "ShortID = $short_id"
  echo "PublicKey = ${public_key:-未保存}"
  echo "Fingerprint = chrome"

  if [ -n "$public_key" ] && [ -n "$uuid" ] && [ -n "$port" ] && [ -n "$server_name" ]; then
    flow_param=""
    if [ -n "$flow" ]; then
      flow_param="&flow=$flow"
    fi

    link="vless://${uuid}@${server_ip}:${port}?type=tcp&security=reality&pbk=${public_key}&fp=chrome&sni=${server_name}&sid=${short_id}${flow_param}#sing-box-reality"

    echo
    echo "================ VLESS 分享链接 ================"
    echo "$link"
    echo "================================================"
  else
    echo
    echo "未生成分享链接：UUID、端口、SNI 或 PublicKey 信息不完整。"
  fi
}

valid_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

port_in_use() {
  local p="$1"
  ss -H -tulpn 2>/dev/null | awk '{print $5}' | grep -Eq "(:|\])${p}$"
}

change_port() {
  local current_port new_port backup ans

  current_port="$(get_json_value port)"
  echo "当前端口: ${current_port:-未读取到}"
  read -rp "请输入新端口: " new_port

  if ! valid_port "$new_port"; then
    echo "端口必须是 1-65535 的数字"
    return
  fi

  if [ "$new_port" = "$current_port" ]; then
    echo "新端口和当前端口相同，无需修改。"
    return
  fi

  if port_in_use "$new_port"; then
    echo "端口 $new_port 已被占用，请换一个端口。"
    return
  fi

  backup="$(make_backup)"
  echo "已自动备份到: $backup"

  set_json_port "$new_port"
  echo "已修改配置端口为: $new_port"

  echo "检查配置..."
  if ! sing-box check -c "$CONFIG"; then
    echo "配置检查失败，正在恢复备份..."
    cp -a "$backup" "$CONFIG"
    echo "已恢复原配置: $backup"
    return
  fi

  read -rp "是否立即重启 sing-box? (y/n): " ans
  if [ "$ans" = "y" ]; then
    if systemctl restart "$SERVICE"; then
      echo "sing-box 已重启"
      systemctl status "$SERVICE" --no-pager
    else
      echo "重启失败，正在恢复备份..."
      cp -a "$backup" "$CONFIG"
      systemctl restart "$SERVICE" || true
      echo "已尝试恢复并重启原配置，请查看状态和日志。"
      systemctl status "$SERVICE" --no-pager || true
      return
    fi
  fi

  echo
  echo "提醒："
  echo "1) 记得放行 ufw 端口"
  echo "2) 记得去 OCI 安全列表/安全组放行新端口"
  echo "3) 客户端端口也要同步修改"
}

allow_port_ufw() {
  local p proto

  if ! command -v ufw >/dev/null 2>&1; then
    echo "系统未安装 ufw，无法使用此功能。"
    return
  fi

  read -rp "请输入要放行的端口: " p
  if ! valid_port "$p"; then
    echo "端口必须是 1-65535 的数字"
    return
  fi

  read -rp "协议 tcp/udp/all，默认 tcp: " proto
  proto="${proto:-tcp}"

  case "$proto" in
    tcp)
      ufw allow "${p}/tcp"
      ;;
    udp)
      ufw allow "${p}/udp"
      ;;
    all)
      ufw allow "${p}/tcp"
      ufw allow "${p}/udp"
      ;;
    *)
      echo "协议只能是 tcp、udp 或 all"
      return
      ;;
  esac

  ufw status
}

safety_check() {
  local port uuid server_name short_id private_key public_key active failed=0

  port="$(get_json_value port)"
  uuid="$(get_json_value uuid)"
  server_name="$(get_json_value server_name)"
  short_id="$(get_json_value short_id)"
  private_key="$(get_json_value private_key)"
  active="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"

  echo "================ 安全检查 ================"

  if [ "$active" = "active" ]; then
    echo "✅ 服务状态：运行中"
  else
    echo "❌ 服务状态：$active"
    failed=1
  fi

  if sing-box check -c "$CONFIG" >/dev/null 2>&1; then
    echo "✅ 配置检查：通过"
  else
    echo "❌ 配置检查：失败"
    failed=1
  fi

  if [ -n "$port" ] && port_in_use "$port"; then
    echo "✅ 监听端口：$port 正在监听"
  else
    echo "❌ 监听端口：$port 未检测到监听"
    failed=1
  fi

  if [ -n "$uuid" ]; then
    echo "✅ UUID：已设置"
  else
    echo "❌ UUID：未设置"
    failed=1
  fi

  if [ -n "$private_key" ]; then
    echo "✅ Reality PrivateKey：已设置"
  else
    echo "❌ Reality PrivateKey：未设置"
    failed=1
  fi

  if [ -n "$server_name" ]; then
    echo "✅ Reality SNI：$server_name"
  else
    echo "❌ Reality SNI：未设置"
    failed=1
  fi

  if [ -n "$short_id" ]; then
    echo "✅ ShortID：已设置"
  else
    echo "⚠️ ShortID：未读取到，部分客户端可能需要填写"
  fi

  if [ -f "$PUBKEY_FILE" ]; then
    public_key="$(cat "$PUBKEY_FILE")"
    if [ -n "$public_key" ]; then
      echo "✅ PublicKey：已保存到 $PUBKEY_FILE"
    else
      echo "⚠️ PublicKey 文件为空：$PUBKEY_FILE"
    fi
  else
    echo "⚠️ PublicKey：未保存，显示客户端参数时无法生成完整链接"
  fi

  if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -qi "Status: active"; then
      echo "✅ UFW：已开启"
      if [ -n "$port" ] && ufw status | grep -Eq "${port}/(tcp|udp)"; then
        echo "✅ UFW 端口：检测到 $port 放行规则"
      else
        echo "⚠️ UFW 端口：未检测到 $port 放行规则，请确认是否已放行"
      fi
    else
      echo "⚠️ UFW：未开启"
    fi
  else
    echo "⚠️ UFW：未安装"
  fi

  local mode owner
  mode="$(stat -c "%a" "$CONFIG" 2>/dev/null || true)"
  owner="$(stat -c "%U:%G" "$CONFIG" 2>/dev/null || true)"
  echo "配置文件权限：${mode:-未知}，属主：${owner:-未知}"

  echo "=========================================="
  if [ "$failed" -eq 0 ]; then
    echo "核心检查通过。"
  else
    echo "存在关键问题，请根据上面的 ❌ 项处理。"
  fi
}

need_root
check_deps
check_config_exists

while true; do
  show_menu
  read -rp "请输入选项: " choice

  case "$choice" in
    1) view_config ;;
    2) edit_config ;;
    3) check_config ;;
    4) restart_service ;;
    5) show_status ;;
    6) show_ports ;;
    7) show_logs ;;
    8) backup_config ;;
    9) restore_latest_backup ;;
    10) generate_uuid ;;
    11) generate_reality_keypair ;;
    12) show_client_info ;;
    13) change_port ;;
    14) allow_port_ufw ;;
    15) save_public_key ;;
    16) safety_check ;;
    17) echo "退出"; exit 0 ;;
    *) echo "无效选项，请重新输入" ;;
  esac

  pause
done
