#!/bin/bash
# ============================================================================
# 服务仪表盘更新脚本 v3.9
# 通用版本 - 适用于各类Linux服务器
# ============================================================================
# 功能：自动发现服务、健康检查、生成Web仪表盘
# 作者：MiMo
# 版本：v3.9
# 更新：访问权限改为按实际防火墙规则（UFW/firewalld/iptables/nftables）显示
#      支持Caddy反向代理发现、HTTPS协议自动识别、过滤未运行服务
# ============================================================================

set -euo pipefail

# ============================================================================
# 配置变量（可通过环境变量或配置文件覆盖）
# ============================================================================

# 解析符号链接获取真实脚本目录
resolve_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -L "$source" ]; do
        local dir
        dir=$(cd -P "$(dirname "$source")" && pwd)
        source=$(readlink "$source")
        [[ $source != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}

# 排除端口配置（不显示在仪表盘上的端口，空格分隔）
# Syncthing传输端口22000默认排除
EXCLUDE_PORTS="${EXCLUDE_PORTS:-22000}"

SCRIPT_DIR="$(resolve_script_dir)"

# 自动查找配置文件（优先查找TOML格式）
find_config_file() {
    local dir="$1"
    
    # 优先查找TOML格式
    for name in "service.toml" "services.toml" "config.toml"; do
        if [ -f "$dir/$name" ] && [ -s "$dir/$name" ]; then
            echo "$dir/$name"
            return 0
        fi
    done
    
    # 然后查找conf格式
    for name in "services.conf" "service.conf" "config.conf"; do
        if [ -f "$dir/$name" ] && [ -s "$dir/$name" ]; then
            echo "$dir/$name"
            return 0
        fi
    done
    
    return 1
}

CONFIG_FILE="${DASHBOARD_CONFIG:-$(find_config_file "$SCRIPT_DIR/conf" || echo "$SCRIPT_DIR/conf/services.conf")}"
DASHBOARD_DIR="${DASHBOARD_DIR:-/var/www/dashboard}"
DASHBOARD_FILE="$DASHBOARD_DIR/index.html"
TEMP_FILE="/tmp/dashboard_update.html"
LOG_FILE="${DASHBOARD_LOG:-/var/log/dashboard_update.log}"
TIMEOUT_SECONDS="${DASHBOARD_TIMEOUT:-3}"

# 颜色配置
COLOR_HEALTHY="${COLOR_HEALTHY:-linear-gradient(90deg, #27ae60, #2ecc71)|#27ae60}"
COLOR_STOPPED="${COLOR_STOPPED:-linear-gradient(90deg, #34495e, #2c3e50)|#34495e}"
COLOR_UNHEALTHY="${COLOR_UNHEALTHY:-linear-gradient(90deg, #e67e22, #d35400)|#e67e22}"

# 反向代理（Nginx/Caddy）端口 -> 协议映射（detect_scheme 使用）
declare -A PROXY_SCHEMES

# 获取服务器IP地址（自动检测）
get_ip_address() {
    local ip=""
    local default_iface
    default_iface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$default_iface" ]; then
        ip=$(ip -4 addr show "$default_iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    fi
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    if [ -z "$ip" ]; then
        ip="localhost"
    fi
    echo "$ip"
}

IP_ADDRESS="${DASHBOARD_IP:-$(get_ip_address)}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 已知服务名称映射
declare -A SERVICE_NAMES=(
    [80]="Web服务"
    [443]="服务仪表盘"
    [22]="SSH服务"
    [0]="公众号监控"
    [3000]="Grafana/Prometheus"
    [3306]="MySQL数据库"
    [5432]="PostgreSQL数据库"
    [6379]="Redis缓存"
    [8080]="Web服务(8080)"
    [8081]="Web服务(8081)"
    [8082]="Web服务(8082)"
    [8083]="Web服务(8083)"
    [8084]="Web服务(8084)"
    [8085]="Web服务(8085)"
    [8086]="InfluxDB"
    [8088]="Web服务(8088)"
    [8090]="Web服务(8090)"
    [8091]="Web服务(8091)"
    [8443]="HTTPS服务(8443)"
    [8888]="Jupyter Notebook"
    [9000]="Portainer/PHP-FPM"
    [9090]="Prometheus"
    [9091]="Transmission"
    [9092]="Kafka"
    [9200]="Elasticsearch"
    [9300]="Elasticsearch"
    [11211]="Memcached"
    [27017]="MongoDB"
    [5000]="Docker Registry"
    [5672]="RabbitMQ"
    [15672]="RabbitMQ管理"
    [6801]="Aria2/RPC"
    [6802]="PHP探针"
    [6803]="Adminer"
    [7681]="Web终端"
    [8989]="Sonarr"
    [7878]="Radarr"
    [6789]="Netdata"
)

# 常见服务描述
declare -A SERVICE_DESCS=(
    [80]="HTTP Web服务器，提供网页访问服务"
    [443]="服务监控仪表盘，提供系统服务状态总览"
    [22]="SSH远程登录服务，提供安全的远程管理"
    [0]="微信公众号监控服务，每2小时检查新文章"
    [3000]="监控可视化平台或API服务"
    [3306]="MySQL关系型数据库服务"
    [5432]="PostgreSQL关系型数据库服务"
    [6379]="Redis内存缓存数据库"
    [8080]="Web应用服务或管理后台"
    [8081]="Web应用服务或API服务"
    [9000]="容器管理平台或PHP-FPM服务"
    [9090]="Prometheus监控系统"
    [9091]="Transmission BT下载客户端"
    [9200]="Elasticsearch搜索引擎"
    [6801]="Aria2 RPC下载服务"
    [6802]="PHP服务器环境探测工具"
    [6803]="数据库管理工具"
    [7681]="基于Web的SSH终端客户端"
    [6789]="Netdata实时系统监控"
)

# ============================================================================
# 函数定义
# ============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE" 2>/dev/null || true
}

# 检查端口是否在监听
check_port() {
    local port="$1"
    if ss -tlnp 2>/dev/null | grep -qE "[: ]${port}[[:space:]]" || \
       netstat -tlnp 2>/dev/null | grep -qE "[: ]${port}[[:space:]]"; then
        return 0
    fi
    return 1
}

# 非HTTP服务端口列表（数据库、缓存、消息队列、代理、BT客户端等）
NON_HTTP_SERVICES="3306 33060 5432 6379 11211 27017 5672 9092 9300 5620 6800 10808 10809 16385 51413"

# 检查是否是非HTTP服务
is_non_http_service() {
    local port="$1"
    if echo "$NON_HTTP_SERVICES" | grep -qw "$port"; then
        return 0  # 是非HTTP服务
    fi
    return 1      # 是HTTP服务
}

# 非HTTP服务健康检查（数据库、缓存等）
check_non_http() {
    local port="$1"
    
    # MySQL端口 - 尝试TCP连接
    if [ "$port" -eq 3306 ] || [ "$port" -eq 33060 ]; then
        if command -v mysqladmin &>/dev/null; then
            # 使用mysqladmin ping检查
            if mysqladmin ping -h 127.0.0.1 -P "$port" --connect-timeout="$TIMEOUT_SECONDS" &>/dev/null; then
                return 0
            fi
        fi
        # 备用方案：检查TCP连接
        if timeout "$TIMEOUT_SECONDS" bash -c "echo > /dev/tcp/127.0.0.1/$port" &>/dev/null; then
            return 0
        fi
        return 1
    fi
    
    # PostgreSQL端口
    if [ "$port" -eq 5432 ]; then
        if command -v pg_isready &>/dev/null; then
            if pg_isready -h 127.0.0.1 -p "$port" -t "$TIMEOUT_SECONDS" &>/dev/null; then
                return 0
            fi
        fi
        if timeout "$TIMEOUT_SECONDS" bash -c "echo > /dev/tcp/127.0.0.1/$port" &>/dev/null; then
            return 0
        fi
        return 1
    fi
    
    # Redis端口
    if [ "$port" -eq 6379 ]; then
        if command -v redis-cli &>/dev/null; then
            if redis-cli -h 127.0.0.1 -p "$port" -t "$TIMEOUT_SECONDS" ping &>/dev/null; then
                return 0
            fi
        fi
        if timeout "$TIMEOUT_SECONDS" bash -c "echo > /dev/tcp/127.0.0.1/$port" &>/dev/null; then
            return 0
        fi
        return 1
    fi
    
    # MongoDB端口
    if [ "$port" -eq 27017 ]; then
        if timeout "$TIMEOUT_SECONDS" bash -c "echo > /dev/tcp/127.0.0.1/$port" &>/dev/null; then
            return 0
        fi
        return 1
    fi
    
    # qBittorrent BT端口 - 只检查TCP连接
    if [ "$port" -eq 5620 ]; then
        if timeout "$TIMEOUT_SECONDS" bash -c "echo > /dev/tcp/127.0.0.1/$port" &>/dev/null; then
            return 0
        fi
        return 1
    fi
    
    # Aria2 RPC端口 - 检查JSON-RPC接口
    if [ "$port" -eq 6800 ]; then
        # 尝试JSON-RPC调用
        if command -v curl &>/dev/null; then
            local rpc_response
            rpc_response=$(curl -s --max-time "$TIMEOUT_SECONDS" -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"aria2.getVersion","id":1}' "http://127.0.0.1:$port/jsonrpc" 2>/dev/null)
            if echo "$rpc_response" | grep -q '"result"' 2>/dev/null; then
                return 0
            fi
        fi
        # 备用方案：TCP连接检查
        if timeout "$TIMEOUT_SECONDS" bash -c "echo > /dev/tcp/127.0.0.1/$port" &>/dev/null; then
            return 0
        fi
        return 1
    fi
    
    # V2Ray SOCKS5代理端口 - 只检查TCP连接
    if [ "$port" -eq 10808 ]; then
        if timeout "$TIMEOUT_SECONDS" bash -c "echo > /dev/tcp/127.0.0.1/$port" &>/dev/null; then
            return 0
        fi
        return 1
    fi
    
    # V2Ray HTTP代理端口 - 检查HTTP代理响应
    if [ "$port" -eq 10809 ]; then
        # HTTP代理通常返回400或405给普通请求
        if command -v curl &>/dev/null; then
            local http_code
            http_code=$(curl -s --max-time "$TIMEOUT_SECONDS" -o /dev/null -w "%{http_code}" "http://127.0.0.1:$port" 2>/dev/null || echo "000")
            # 代理服务通常返回400/405/501等，说明服务正在运行
            if [[ "$http_code" =~ ^[45] ]]; then
                return 0
            fi
        fi
        # 备用方案：TCP连接检查
        if timeout "$TIMEOUT_SECONDS" bash -c "echo > /dev/tcp/127.0.0.1/$port" &>/dev/null; then
            return 0
        fi
        return 1
    fi
    
    # Transmission BT端口 - 只检查TCP连接
    if [ "$port" -eq 51413 ]; then
        if timeout "$TIMEOUT_SECONDS" bash -c "echo > /dev/tcp/127.0.0.1/$port" &>/dev/null; then
            return 0
        fi
        return 1
    fi
    
    # 未知非HTTP服务（如16385）- 只检查TCP连接
    if timeout "$TIMEOUT_SECONDS" bash -c "echo > /dev/tcp/127.0.0.1/$port" &>/dev/null; then
        return 0
    fi
    return 1
}

# HTTP健康检查
check_http() {
    local port="$1"
    local scheme="${2:-http}"
    local code body response
    local curl_args
    
    # 非HTTP服务使用专门的检查方法
    if is_non_http_service "$port"; then
        check_non_http "$port"
        return $?
    fi
    
    curl_args=(-s --max-time "$TIMEOUT_SECONDS" -w "\n%{http_code}")
    if [ "$scheme" = "https" ]; then
        curl_args+=(-k)
        response=$(curl "${curl_args[@]}" "https://127.0.0.1:$port" 2>/dev/null || echo -e "\n000")
    else
        response=$(curl "${curl_args[@]}" "http://127.0.0.1:$port" 2>/dev/null || echo -e "\n000")
    fi
    code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$code" =~ ^[23] ]]; then
        return 0
    elif [[ "$code" =~ ^3 ]]; then
        # 301/302/308 等重定向（如HTTP跳转HTTPS）也视为健康
        return 0
    elif [[ "$code" == "401" ]] || [[ "$code" == "403" ]]; then
        return 0
    elif [[ "$code" =~ ^[45] ]] && [ -n "$body" ]; then
        return 0
    fi
    return 1
}

# 检查 cron 服务状态（基于日志文件）
check_cron_service() {
    local log_file="$1"
    local max_age_hours="$2"
    
    # 检查日志文件是否存在
    if [ ! -f "$log_file" ]; then
        return 1
    fi
    
    # 检查日志文件最后更新时间
    local last_modified
    last_modified=$(stat -c %Y "$log_file" 2>/dev/null || echo 0)
    local current_time
    current_time=$(date +%s)
    local age_hours=$(( (current_time - last_modified) / 3600 ))
    
    if [ "$age_hours" -le "$max_age_hours" ]; then
        return 0
    fi
    return 1
}

# 获取服务名称
get_service_name() {
    local port="$1"
    local name=""
    
    # 首先尝试从Nginx配置获取
    if [ -d /etc/nginx/sites-available ]; then
        for f in /etc/nginx/sites-available/*; do
            [ -f "$f" ] || continue
            if grep -q "listen.*${port}" "$f" 2>/dev/null; then
                name=$(basename "$f" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')
                [ "$name" != "default" ] && echo "$name" && return
            fi
        done
    fi
    
    # 从已知服务映射获取
    name="${SERVICE_NAMES[$port]:-}"
    if [ -n "$name" ]; then
        echo "$name"
        return
    fi
    
    # 尝试从进程名获取
    local process_name
    process_name=$(ss -tlnp 2>/dev/null | grep ":${port}" | grep -oP 'users:\(\("([^"]+)' | head -1 | sed 's/users:(("//')
    if [ -n "$process_name" ]; then
        echo "$process_name 服务"
        return
    fi
    
    # 默认名称
    echo "服务($port)"
}

# 获取服务描述
get_service_desc() {
    local port="$1"
    local name="$2"
    
    # 从已知描述获取
    local desc="${SERVICE_DESCS[$port]:-}"
    if [ -n "$desc" ]; then
        echo "$desc"
        return
    fi
    
    # 默认描述
    echo "运行在端口 $port 的服务 - $name"
}

# ============================================================================
# 防火墙访问权限检测（以实际防火墙规则为准）
# ============================================================================
# 说明：卡片上的“访问权限”来自实际生效的防火墙规则，配置文件的 access
#       字段不再作为判断依据（仅保留字段兼容）。
# 支持：UFW / firewalld / iptables / nftables
# 返回值：global（公网可访问）/ local（仅内网可访问）/ unknown（无法读取规则）

FW_INITIALIZED=0
FW_BACKEND="none"            # ufw | firewalld | iptables | nftables | none | unknown
FW_DEFAULT_PUBLIC=0          # 防火墙默认是否放行入站
FW_ERROR=""
declare -A FW_PUBLIC_PORTS=() # 允许从公网访问的端口
declare -A FW_LOCAL_PORTS=()  # 仅允许内网访问的端口
declare -A FW_DENY_PUBLIC=()  # 从公网明确拒绝的端口
declare -A FW_APP_PORTS=()    # UFW 应用配置名 -> 端口
FW_PUBLIC_RANGES=()
FW_LOCAL_RANGES=()

# 在需要时以 root 或免密 sudo 执行只读命令
run_priv() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@" 2>/dev/null
    elif command -v sudo &>/dev/null && sudo -n "$@" 2>/dev/null; then
        return 0
    else
        "$@" 2>/dev/null
    fi
}

find_bin() {
    local name="$1"
    local p
    for p in "/usr/sbin/$name" "/sbin/$name" "/usr/bin/$name" "/bin/$name"; do
        if [ -x "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    command -v "$name" 2>/dev/null || true
}

# 来源地址是否仅限内网（Anywhere 视为公网）
is_private_source() {
    local src="$1"
    src="${src% (v6)}"
    src="${src%% *}"
    src="${src#[}"
    src="${src%]}"
    local addr="${src%/*}"

    case "$addr" in
        ""|any|Anywhere|0.0.0.0|0.0.0.0/0|::|::/0) return 1 ;;
        10.*|127.*|169.254.*|192.168.*) return 0 ;;
        172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 0 ;;
        ::1|fe80:*|fc*|fd*) return 0 ;;
        ::ffff:10.*|::ffff:127.*|::ffff:192.168.*) return 0 ;;
        *) return 1 ;;
    esac
}

mark_fw_port() {
    local port="$1"
    local public="$2"
    if [ "$public" = "1" ]; then
        FW_PUBLIC_PORTS["$port"]=1
    else
        FW_LOCAL_PORTS["$port"]=1
    fi
}

# 记录“从公网明确拒绝”的端口（用于默认放行策略下的 DROP/REJECT 规则）
mark_fw_deny() {
    local port="$1"
    case "$port" in
        ''|*[!0-9]*) return 0 ;;
    esac
    FW_DENY_PUBLIC["$port"]=1
}

add_fw_deny_ports() {
    local spec="$1"
    spec="${spec//,/ }"
    spec="${spec//|/ }"

    local item start end p
    for item in $spec; do
        item="${item% (v6)}"
        item="${item%%/*}"
        item="${item#[}"
        item="${item%]}"
        [ -z "$item" ] && continue

        if [[ "$item" =~ ^([0-9]+):([0-9]+)$ ]]; then
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"
            if [ $((end - start)) -le 2048 ]; then
                for ((p = start; p <= end; p++)); do
                    mark_fw_deny "$p"
                done
            fi
        else
            mark_fw_deny "$item"
        fi
    done
}

# 添加端口规则，支持 80 / 80,443 / 1000:2000 / 443/tcp
add_fw_ports() {
    local spec="$1"
    local public="$2"
    spec="${spec//,/ }"
    spec="${spec//|/ }"

    local item start end p
    for item in $spec; do
        item="${item% (v6)}"
        item="${item%%/*}"
        item="${item#[}"
        item="${item%]}"
        [ -z "$item" ] && continue

        if [[ "$item" =~ ^([0-9]+):([0-9]+)$ ]]; then
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"
            # 小范围直接展开，超大范围单独记录
            if [ $((end - start)) -le 2048 ]; then
                for ((p = start; p <= end; p++)); do
                    mark_fw_port "$p" "$public"
                done
            elif [ "$public" = "1" ]; then
                FW_PUBLIC_RANGES+=("${start}:${end}")
            else
                FW_LOCAL_RANGES+=("${start}:${end}")
            fi
        elif [[ "$item" =~ ^[0-9]+$ ]]; then
            mark_fw_port "$item" "$public"
        fi
    done
}

fw_port_in_ranges() {
    local port="$1"
    shift
    [ "$#" -gt 0 ] || return 1
    local range start end
    for range in "$@"; do
        start="${range%%:*}"
        end="${range##*:}"
        if [ "$port" -ge "$start" ] && [ "$port" -le "$end" ]; then
            return 0
        fi
    done
    return 1
}

# 加载 UFW 应用配置（如 Nginx Full -> 80,443/tcp）
load_ufw_app_ports() {
    local dir="/etc/ufw/applications.d"
    [ -d "$dir" ] || return 0

    local line app=""
    while IFS= read -r line; do
        line="${line%$'\r'}"
        case "$line" in
            \[*\])
                app="${line:1:${#line}-2}"
                ;;
            ports=*)
                [ -n "$app" ] && FW_APP_PORTS["$app"]="${line#ports=}"
                ;;
        esac
    done < <(cat "$dir"/* 2>/dev/null || true)
}

# 将 UFW 的 To 列转换为端口表达式
ufw_to_spec() {
    local to="$1"
    # `ufw status verbose` 会显示为 "80,443/tcp (Nginx Full)"，去掉尾部说明
    to=$(printf '%s' "$to" | sed -E 's/[[:space:]]+\(.*\)[[:space:]]*$//')
    to="${to% (v6)}"

    if [[ "$to" =~ ^[0-9]+(/[a-z]+)?$ ]] || \
       [[ "$to" =~ ^[0-9]+:[0-9]+(/[a-z]+)?$ ]] || \
       [[ "$to" =~ ^[0-9]+(,[0-9]+)+(/[a-z]+)?$ ]]; then
        echo "$to"
        return 0
    fi

    if [ -n "${FW_APP_PORTS[$to]:-}" ]; then
        echo "${FW_APP_PORTS[$to]}"
        return 0
    fi
    return 1
}

# 解析 `ufw status verbose`
parse_ufw_status() {
    local status="$1"
    load_ufw_app_ports

    local default_in
    default_in=$(printf '%s\n' "$status" | sed -n 's/^Default:[[:space:]]*\([a-z]*\)[[:space:]]*(incoming).*/\1/p' | head -1)
    # UFW 默认入站策略通常是 deny；只有明确 allow 时才视为默认放行
    [ "$default_in" = "allow" ] && FW_DEFAULT_PUBLIC=1

    local line normalized to action from spec
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in
            Status:*|Logging:*|Default:*|New\ profiles:*|To\ *|--\ *) continue ;;
        esac

        # UFW 用两个以上空格对齐各列；"Anywhere (v6)" 中间只有一个空格
        normalized=$(printf '%s' "$line" | sed -E 's/[[:space:]]{2,}/\t/g')
        to=$(printf '%s' "$normalized" | cut -f1)
        action=$(printf '%s' "$normalized" | cut -f2)
        from=$(printf '%s' "$normalized" | cut -f3-)
        [ -z "$to" ] || [ -z "$action" ] || [ -z "$from" ] && continue

        spec=$(ufw_to_spec "$to" 2>/dev/null || true)
        [ -z "$spec" ] && continue

        case "$action" in
            ALLOW*|allow*|LIMIT*|limit*)
                if is_private_source "$from"; then
                    add_fw_ports "$spec" 0
                else
                    add_fw_ports "$spec" 1
                fi
                ;;
            DENY*|deny*|REJECT*|reject*)
                if ! is_private_source "$from"; then
                    add_fw_deny_ports "$spec"
                fi
                ;;
        esac
    done <<< "$status"
}

# 解析 iptables -S（含 UFW 未启用时的普通规则）
parse_iptables_rules() {
    local rules="$1"
    local line spec src target

    while IFS= read -r line; do
        case "$line" in
            "-P INPUT DROP"|"-P INPUT REJECT") FW_DEFAULT_PUBLIC=0; continue ;;
            "-P INPUT ACCEPT") FW_DEFAULT_PUBLIC=1; continue ;;
            "-A "*) ;;
            *) continue ;;
        esac

        target=""
        if [[ "$line" =~ -j[[:space:]]+(ACCEPT|DROP|REJECT) ]]; then
            target="${BASH_REMATCH[1]}"
        else
            continue
        fi

        spec=""
        if [[ "$line" =~ --dports?[[:space:]]+([^[:space:]]+) ]]; then
            spec="${BASH_REMATCH[1]}"
        fi

        src=""
        if [[ "$line" =~ (^|[[:space:]])-s[[:space:]]+([^[:space:]]+) ]]; then
            src="${BASH_REMATCH[2]}"
        fi

        if [ -z "$spec" ]; then
            # 无端口限制的规则：INPUT 链且不限来源时影响默认策略
            if [[ "$line" == "-A INPUT "* ]] && [ -z "$src" ]; then
                if [ "$target" = "ACCEPT" ]; then
                    FW_DEFAULT_PUBLIC=1
                else
                    FW_DEFAULT_PUBLIC=0
                fi
            fi
            continue
        fi

        if [ "$target" = "ACCEPT" ]; then
            if [ -n "$src" ] && is_private_source "$src"; then
                add_fw_ports "$spec" 0
            else
                add_fw_ports "$spec" 1
            fi
        else
            # DROP/REJECT：仅记录来自公网的拒绝
            if [ -z "$src" ] || ! is_private_source "$src"; then
                add_fw_deny_ports "$spec"
            fi
        fi
    done <<< "$rules"
}

# 解析 nft list ruleset（作为 iptables 不可用时的后备）
parse_nft_ruleset() {
    local rules="$1"
    local chain="" line rest spec src target

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*chain[[:space:]]+([^[:space:]]+) ]]; then
            chain="${BASH_REMATCH[1]}"
            continue
        fi

        case "$chain" in
            input|ufw-user-input) ;;
            *) continue ;;
        esac

        # 去掉行首空白
        line="${line#"${line%%[![:space:]]*}"}"
        if [[ "$line" == *"policy accept"* ]]; then
            [ "$chain" = "input" ] && FW_DEFAULT_PUBLIC=1
            continue
        fi
        if [[ "$line" == *"policy drop"* ]] || [[ "$line" == *"policy reject"* ]]; then
            [ "$chain" = "input" ] && FW_DEFAULT_PUBLIC=0
            continue
        fi

        case "$line" in
            *accept*) target="ACCEPT" ;;
            *reject*) target="REJECT" ;;
            *drop*) target="DROP" ;;
            *) continue ;;
        esac

        spec=""
        if [[ "$line" == *dport* ]]; then
            rest="${line#*dport}"
            rest="${rest%%counter*}"
            rest="${rest%%accept*}"
            rest="${rest%%reject*}"
            rest="${rest%%drop*}"
            spec=$(printf '%s' "$rest" | grep -oE '[0-9]+([-:][0-9]+)?' | sed 's/-/:/g' | tr '\n' ' ')
        fi

        src=""
        if [[ "$line" =~ saddr[[:space:]]+([^[:space:]]+) ]]; then
            src="${BASH_REMATCH[1]}"
        fi

        if [ -z "$spec" ]; then
            # 无端口限制的规则：仅无限定来源的 input 链规则影响默认策略
            if [ "$chain" = "input" ] && [ -z "$src" ]; then
                if [ "$target" = "ACCEPT" ]; then
                    FW_DEFAULT_PUBLIC=1
                else
                    FW_DEFAULT_PUBLIC=0
                fi
            fi
            continue
        fi

        if [ "$target" = "ACCEPT" ]; then
            if [ -n "$src" ] && is_private_source "$src"; then
                add_fw_ports "$spec" 0
            else
                add_fw_ports "$spec" 1
            fi
        else
            if [ -z "$src" ] || ! is_private_source "$src"; then
                add_fw_deny_ports "$spec"
            fi
        fi
    done <<< "$rules"
}

# firewalld 服务名 -> 端口
get_firewalld_service_ports() {
    local name="$1"
    local f
    for f in "/usr/lib/firewalld/services/$name.xml" "/etc/firewalld/services/$name.xml"; do
        if [ -f "$f" ]; then
            grep -oE 'port="[0-9]+(-[0-9]+)?"' "$f" | sed -E 's/port="([^"]+)"/\1/' | tr '\n' ' '
            return 0
        fi
    done
    # 常见服务兜底
    case "$name" in
        http) echo "80" ;;
        https) echo "443" ;;
        ssh) echo "22" ;;
        samba) echo "137 138 139 445" ;;
    esac
}

parse_firewalld_zone() {
    local zone="$1"
    local list
    list=$(run_priv "$FIREWALL_CMD" --zone="$zone" --list-all 2>/dev/null || true)
    [ -z "$list" ] && return 1

    local target
    target=$(printf '%s\n' "$list" | sed -n 's/^[[:space:]]*target:[[:space:]]*//p' | head -1)
    [ "$target" = "ACCEPT" ] && FW_DEFAULT_PUBLIC=1

    local ports services spec svc svc_ports
    ports=$(printf '%s\n' "$list" | sed -n 's/^[[:space:]]*ports:[[:space:]]*//p' | head -1)
    [ -n "$ports" ] && add_fw_ports "$ports" 1

    services=$(printf '%s\n' "$list" | sed -n 's/^[[:space:]]*services:[[:space:]]*//p' | head -1)
    for svc in $services; do
        svc_ports=$(get_firewalld_service_ports "$svc")
        [ -n "$svc_ports" ] && add_fw_ports "$svc_ports" 1
    done
    return 0
}

# 初始化防火墙信息（每次运行只执行一次）
fw_init() {
    [ "$FW_INITIALIZED" = "1" ] && return 0
    FW_INITIALIZED=1

    local ufw_bin iptables_bin nft_bin
    ufw_bin=$(find_bin ufw)
    iptables_bin=$(find_bin iptables)
    nft_bin=$(find_bin nft)
    FIREWALL_CMD=$(find_bin firewall-cmd)

    # 1. UFW
    if [ -n "$ufw_bin" ]; then
        local ufw_status=""
        ufw_status=$(run_priv "$ufw_bin" status verbose 2>/dev/null || true)
        if printf '%s\n' "$ufw_status" | grep -q '^Status: active'; then
            FW_BACKEND="ufw"
            parse_ufw_status "$ufw_status"
            return 0
        fi

        # UFW 已启用但普通用户读不到规则：不要误判为“无防火墙”
        if [ -z "$ufw_status" ] && [ -f /etc/ufw/ufw.conf ] && \
           grep -qE '^[[:space:]]*ENABLED[[:space:]]*=[[:space:]]*yes' /etc/ufw/ufw.conf 2>/dev/null; then
            FW_BACKEND="unknown"
            FW_ERROR="UFW 已启用，但当前用户无权读取规则（请使用 root 运行，或配置免密 sudo）"
            return 0
        fi
    fi

    # 2. firewalld
    if [ -n "$FIREWALL_CMD" ]; then
        local fw_state
        fw_state=$(run_priv "$FIREWALL_CMD" --state 2>/dev/null || true)
        if [ "$fw_state" = "running" ]; then
            local zone
            zone=$(run_priv "$FIREWALL_CMD" --get-default-zone 2>/dev/null || true)
            [ -z "$zone" ] && zone="public"
            if parse_firewalld_zone "$zone"; then
                FW_BACKEND="firewalld"
                return 0
            fi
            FW_BACKEND="unknown"
            FW_ERROR="firewalld 正在运行，但当前用户无权读取规则"
            return 0
        fi
    fi

    # 3. iptables
    if [ -n "$iptables_bin" ]; then
        local ipt_rules
        ipt_rules=$(run_priv "$iptables_bin" -S 2>/dev/null || true)
        if [ -n "$ipt_rules" ]; then
            FW_BACKEND="iptables"
            parse_iptables_rules "$ipt_rules"
            return 0
        fi
    fi

    # 4. nftables
    if [ -n "$nft_bin" ]; then
        local nft_rules
        nft_rules=$(run_priv "$nft_bin" list ruleset 2>/dev/null || true)
        if [ -n "$nft_rules" ]; then
            FW_BACKEND="nftables"
            parse_nft_ruleset "$nft_rules"
            return 0
        fi
    fi

    # 5. 没有可用的只读权限：若系统存在防火墙工具，保守标记为未知
    if [ -n "$ufw_bin" ] || [ -n "$FIREWALL_CMD" ] || [ -n "$iptables_bin" ]; then
        FW_BACKEND="unknown"
        FW_ERROR="检测到防火墙工具，但当前用户无权读取规则"
        return 0
    fi

    # 6. 确实没有任何防火墙
    FW_BACKEND="none"
    return 0
}

# 自动检测端口访问权限（以实际防火墙规则为准）
detect_access_type() {
    local port="$1"

    # 非网络服务（如 cron 监控）没有对应端口
    [ "$port" = "0" ] && { echo "local"; return 0; }

    fw_init

    case "$FW_BACKEND" in
        unknown)
            echo "unknown"
            return 0
            ;;
        none)
            echo "global"
            return 0
            ;;
    esac

    if [ -n "${FW_PUBLIC_PORTS[$port]:-}" ]; then
        echo "global"
        return 0
    fi

    if [ "${#FW_PUBLIC_RANGES[@]}" -gt 0 ] && \
       fw_port_in_ranges "$port" "${FW_PUBLIC_RANGES[@]}"; then
        echo "global"
        return 0
    fi

    # 默认放行且没有针对性拒绝
    if [ "$FW_DEFAULT_PUBLIC" = "1" ] && [ -z "${FW_DENY_PUBLIC[$port]:-}" ]; then
        echo "global"
        return 0
    fi

    echo "local"
}

# 解析TOML格式的配置文件
parse_toml_config() {
    local config_file="$1"
    local -n services_ref=$2
    
    # 检查是否为TOML格式（包含[[services]]）
    if ! grep -q '\[\[services\]\]' "$config_file"; then
        return 1  # 不是TOML格式
    fi
    
    local port name access desc color btn_color scheme
    local in_service=false
    local line_num=0
    
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        
        # 跳过注释和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # 检查是否是新的服务配置块
        if [[ "$line" =~ ^\[\[services\]\] ]]; then
            # 保存上一个服务（如果存在）
            if [ "$in_service" = true ] && [ -n "$port" ]; then
                [ -z "$access" ] && access=$(detect_access_type "$port")
                [ -z "$color" ] && color="auto"
                [ -z "$btn_color" ] && btn_color="auto"
                [ -z "$scheme" ] && scheme="auto"
                services_ref+=("${port}|${name}|${access}|${desc}|${color}|${btn_color}|${scheme}")
            fi
            
            # 重置变量
            port=""
            name=""
            access=""
            desc=""
            color="auto"
            btn_color="auto"
            scheme="auto"
            in_service=true
            continue
        fi
        
        # 解析配置项
        if [ "$in_service" = true ]; then
            # 提取键值对
            if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                
                # 去除首尾空白
                value="${value#"${value%%[![:space:]]*}"}"
                value="${value%"${value##*[![:space:]]}"}"

                # 去掉引号和行内注释（TOML 支持 `key = "value" # 注释`）
                if [[ "$value" == \"* ]]; then
                    value="${value#\"}"
                    value="${value%%\"*}"
                elif [[ "$value" == \'* ]]; then
                    value="${value#\'}"
                    value="${value%%\'*}"
                else
                    value="${value%%#*}"
                    value="${value%"${value##*[![:space:]]}"}"
                fi
                
                case "$key" in
                    port)
                        port="$value"
                        ;;
                    name)
                        name="$value"
                        ;;
                    desc)
                        desc="$value"
                        ;;
                    access)
                        access="$value"
                        ;;
                    color)
                        color="$value"
                        ;;
                    btn_color)
                        btn_color="$value"
                        ;;
                    scheme|protocol)
                        scheme="$value"
                        ;;
                    https)
                        case "$value" in
                            true|1|yes|on) scheme="https" ;;
                            false|0|no|off) scheme="http" ;;
                            *) scheme="$value" ;;
                        esac
                        ;;
                esac
            fi
        fi
    done < "$config_file"
    
    # 保存最后一个服务
    if [ "$in_service" = true ] && [ -n "$port" ]; then
        [ -z "$access" ] && access=$(detect_access_type "$port")
        [ -z "$color" ] && color="auto"
        [ -z "$btn_color" ] && btn_color="auto"
        [ -z "$scheme" ] && scheme="auto"
        services_ref+=("${port}|${name}|${access}|${desc}|${color}|${btn_color}|${scheme}")
    fi
    
    return 0
}

# 解析TOML配置中的全局配置（如exclude_ports）
parse_toml_global() {
    local config_file="$1"
    
    # 检查是否为TOML格式
    if ! grep -q '\[global\]' "$config_file"; then
        return 1
    fi
    
    local in_global=false
    
    while IFS= read -r line || [ -n "$line" ]; do
        # 跳过注释和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # 检查是否进入global配置块
        if [[ "$line" =~ ^\[global\] ]]; then
            in_global=true
            continue
        fi
        
        # 检查是否离开global配置块（进入其他配置块）
        if [[ "$line" =~ ^\[ ]] && [ "$in_global" = true ]; then
            in_global=false
            continue
        fi
        
        # 解析exclude_ports配置
        if [ "$in_global" = true ] && [[ "$line" =~ ^[[:space:]]*exclude_ports[[:space:]]*=[[:space:]]*\[(.*)\] ]]; then
            local ports_str="${BASH_REMATCH[1]}"
            # 移除引号和空格，转换为空格分隔的列表
            ports_str=$(echo "$ports_str" | sed 's/["\x27]//g' | tr ',' ' ')
            echo "$ports_str"
            return 0
        fi
    done < "$config_file"
    
    return 1
}

# 解析服务配置行（支持简化格式和完整格式）
parse_service_line() {
    local line="$1"
    local port name access desc color btn_color scheme
    
    # 计算字段数量
    local field_count
    field_count=$(echo "$line" | awk -F'|' '{print NF}')
    
    scheme="auto"
    if [ "$field_count" -eq 3 ]; then
        # 简化格式: 端口|标题|简介
        IFS='|' read -r port name desc <<< "$line"
        access=$(detect_access_type "$port")
        color="auto"
        btn_color="auto"
    elif [ "$field_count" -ge 6 ]; then
        # 完整格式: 端口|服务名称|访问权限|描述|卡片颜色|按钮颜色[|协议]
        IFS='|' read -r port name access desc color btn_color scheme <<< "$line"
        [ -z "$scheme" ] && scheme="auto"
    else
        # 字段数量不正确，尝试解析并填充默认值
        IFS='|' read -r port name desc <<< "$line"
        access=$(detect_access_type "$port")
        color="auto"
        btn_color="auto"
    fi
    
    echo "${port}|${name}|${access}|${desc}|${color}|${btn_color}|${scheme}"
}

# 自动发现服务
auto_discover_services() {
    local -A discovered_ports
    
    # 获取所有监听的TCP端口
    local ports
    ports=$(ss -tlnp 2>/dev/null | grep LISTEN | awk '{print $4}' | grep -oP '\d+$' | sort -n | uniq)
    
    if [ -z "$ports" ]; then
        # 备用方案
        ports=$(netstat -tlnp 2>/dev/null | grep LISTEN | awk '{print $4}' | grep -oP '\d+$' | sort -n | uniq)
    fi
    
    # 过滤掉一些系统端口和不常用端口
    local skip_ports="22 25 53 111 135 139 445 631 1433 1434 2019 3389 5355 5900 5938 6000 6001 6002 6003 6004 6005 $EXCLUDE_PORTS"
    
    for port in $ports; do
        # 跳过小于1024的端口（除了常见的）
        # 注意：80端口跳转到443，是同一个服务，只显示443即可
        if [ "$port" -lt 1024 ] && ! echo "443 21 25 53 3306 5432 6379 8080 8081 9000 9090 9091" | grep -qw "$port"; then
            continue
        fi
        
        # 跳过指定的端口
        if echo "$skip_ports" | grep -qw "$port"; then
            continue
        fi
        
        # 避免重复
        if [ -n "${discovered_ports[$port]:-}" ]; then
            continue
        fi
        discovered_ports["$port"]=1
        
        local name desc access
        name=$(get_service_name "$port")
        desc=$(get_service_desc "$port" "$name")
        access=$(detect_access_type "$port")
        
        echo "$port|$name|$access|$desc|auto|auto|auto"
    done
}

# 扫描Nginx配置
scan_nginx() {
    local dir="/etc/nginx/sites-available"
    [ -d "$dir" ] || return 0
    
    for f in "$dir"/*; do
        [ -f "$f" ] || continue
        grep -q "listen" "$f" || continue
        
        local port
        port=$(grep -E "listen\s+[0-9]+" "$f" | head -1 | awk '{print $2}' | sed 's/;//')
        [ -n "$port" ] && [ "$port" != "80" ] || continue
        
        local name
        name=$(basename "$f" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')
        [ "$name" = "default" ] && continue
        
        local scheme="http"
        if grep -qE "ssl_certificate|ssl_protocols|ssl[[:space:]]+on|listen[[:space:]]+[0-9]+[[:space:]]+ssl" "$f" 2>/dev/null; then
            scheme="https"
        fi
        
        echo "$port|$name|local|Nginx服务|auto|auto|$scheme"
    done
}

# 解析 Caddyfile：输出服务行（端口|名称|访问权限|描述|颜色|按钮颜色|协议），并记录端口协议
parse_caddyfile() {
    local file="$1"
    local in_block=false
    local nested=0
    local addr="" port="" scheme="" name="" desc=""
    local line
    
    while IFS= read -r line || [ -n "$line" ]; do
        # 从注释中提取服务名称/描述（例如： # 应用 1：jellyfin（媒体服务器））
        if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*应用[[:space:]]*[0-9]+：(.+)（(.+)）$ ]]; then
            name="${BASH_REMATCH[1]}"
            desc="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]*#[[:space:]]*应用[[:space:]]*[0-9]+：(.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
            desc=""
        fi
        
        # 去除行内注释和行尾空白
        line=$(echo "$line" | sed 's/#.*//' | sed 's/[[:space:]]*$//')
        [ -z "$line" ] && continue
        
        # 站点块开始（仅在顶层，即不在任何站点块内时）
        if [ "$in_block" = false ] && [[ "$line" =~ ^[[:space:]]*([^[:space:]{]+)[[:space:]]*\{[[:space:]]*$ ]]; then
            addr="${BASH_REMATCH[1]}"
            in_block=true
            nested=0
            scheme=""
            port=""
            case "$addr" in
                https://*) scheme="https"; port="443" ;;
                http://*)  scheme="http";  port="80" ;;
                :[0-9]*)   port="${addr#:}" ;;
                *)
                    if [[ "$addr" =~ ^(.+):([0-9]+)$ ]]; then
                        port="${BASH_REMATCH[2]}"
                    fi
                    ;;
            esac
            continue
        fi
        
        if [ "$in_block" = true ]; then
            # 嵌套块开始（如 reverse_proxy ... {）
            if [[ "$line" =~ \{[[:space:]]*$ ]]; then
                nested=$((nested + 1))
                continue
            fi
            
            # 块结束
            if [[ "$line" =~ ^[[:space:]]*}[[:space:]]*$ ]]; then
                if [ "$nested" -gt 0 ]; then
                    nested=$((nested - 1))
                else
                    in_block=false
                    if [ -n "$port" ]; then
                        if [ -z "$scheme" ]; then
                            if [ "$port" = "443" ]; then scheme="https"; else scheme="http"; fi
                        fi
                        PROXY_SCHEMES["$port"]="$scheme"
                        [ -z "$name" ] && name="Caddy服务($port)"
                        [ -z "$desc" ] && desc="Caddy反向代理服务"
                        echo "$port|$name|local|$desc|auto|auto|$scheme"
                    fi
                    name=""
                    desc=""
                fi
                continue
            fi
            
            # 检测 TLS 配置
            if [[ "$line" =~ ^[[:space:]]*tls([[:space:]]|$) ]]; then
                scheme="https"
                [ -z "$port" ] && port="443"
            fi
        fi
    done < "$file"
}

# 扫描 Caddy 配置
scan_caddy() {
    [ -f /etc/caddy/Caddyfile ] || return 0
    # 80端口仅为HTTP到HTTPS的跳转，与443是同一服务，仅显示443即可
    parse_caddyfile /etc/caddy/Caddyfile | grep -v '^80|' || true
}

# 加载反向代理（Nginx/Caddy）端口协议映射
load_proxy_schemes() {
    # Nginx
    local dir="/etc/nginx/sites-available"
    if [ -d "$dir" ]; then
        for f in "$dir"/*; do
            [ -f "$f" ] || continue
            grep -q "listen" "$f" || continue
            local port
            port=$(grep -E "listen\s+[0-9]+" "$f" | head -1 | awk '{print $2}' | sed 's/;//')
            [ -n "$port" ] || continue
            if grep -qE "ssl_certificate|ssl_protocols|ssl[[:space:]]+on|listen[[:space:]]+[0-9]+[[:space:]]+ssl" "$f" 2>/dev/null; then
                PROXY_SCHEMES["$port"]="https"
            else
                PROXY_SCHEMES["$port"]="http"
            fi
        done
    fi
    
    # Caddy（仅用于记录端口协议，服务发现由 scan_caddy 完成）
    if [ -f /etc/caddy/Caddyfile ]; then
        parse_caddyfile /etc/caddy/Caddyfile > /dev/null
    fi
}

# 自动检测服务访问协议（http/https）
detect_scheme() {
    local port="$1"
    
    # 1. 已知HTTPS端口
    local https_ports="443 8443 4443 9443"
    if echo "$https_ports" | grep -qw "$port"; then
        echo "https"
        return 0
    fi
    
    # 2. 反向代理配置（Nginx/Caddy）
    if [ -n "${PROXY_SCHEMES[$port]:-}" ]; then
        echo "${PROXY_SCHEMES[$port]}"
        return 0
    fi
    
    # 3. 实际测试HTTPS连通性
    if command -v curl &>/dev/null; then
        local code
        code=$(curl -sk --max-time "$TIMEOUT_SECONDS" -o /dev/null -w "%{http_code}" "https://127.0.0.1:$port" 2>/dev/null || true)
        code=$(echo "$code" | tail -1)
        if [ -n "$code" ] && [ "$code" != "000" ]; then
            echo "https"
            return 0
        fi
    fi
    
    echo "http"
}

# 生成服务卡片HTML
generate_card() {
    local port="$1" name="$2" access="$3" desc="$4" color="$5" btn_color="$6" status="$7"
    local scheme="${8:-http}"
    
    # 处理自动颜色
    if [ "$color" = "auto" ] || [ -z "$color" ]; then
        if [ "$status" = "healthy" ]; then
            color=$(echo "$COLOR_HEALTHY" | cut -d'|' -f1)
            btn_color=$(echo "$COLOR_HEALTHY" | cut -d'|' -f2)
        elif [ "$status" = "stopped" ]; then
            color=$(echo "$COLOR_STOPPED" | cut -d'|' -f1)
            btn_color=$(echo "$COLOR_STOPPED" | cut -d'|' -f2)
        else
            color=$(echo "$COLOR_UNHEALTHY" | cut -d'|' -f1)
            btn_color=$(echo "$COLOR_UNHEALTHY" | cut -d'|' -f2)
        fi
    fi
    [ -z "$btn_color" ] && btn_color="#667eea"
    
    local access_text access_class
    case "$access" in
        global)
            access_text="公网"
            access_class="access-global"
            ;;
        unknown)
            access_text="未知"
            access_class="access-unknown"
            ;;
        *)
            access_text="局域网"
            access_class="access-local"
            ;;
    esac
    
    local status_badge status_class
    case "$status" in
        "healthy")
            status_badge='<span class="status-badge status-healthy">● 健康</span>'
            status_class="status-healthy"
            ;;
        "unhealthy")
            status_badge='<span class="status-badge status-unhealthy">● 异常</span>'
            status_class="status-unhealthy"
            ;;
        "stopped")
            status_badge='<span class="status-badge status-stopped">● 未运行</span>'
            status_class="status-stopped"
            ;;
        *)
            status_badge='<span class="status-badge status-unknown">● 未知</span>'
            status_class="status-unknown"
            ;;
    esac
    
    # 生成服务URL（根据实际协议生成访问地址）
    local service_url
    [ -z "$scheme" ] && scheme="http"
    if [ "$scheme" = "https" ] && [ "$port" -eq 443 ]; then
        service_url="https://${IP_ADDRESS}"
    elif [ "$scheme" = "http" ] && [ "$port" -eq 80 ]; then
        service_url="http://${IP_ADDRESS}"
    else
        service_url="${scheme}://${IP_ADDRESS}:${port}"
    fi
    
    # 处理无端口的服务（如 cron 服务）
    local port_display="端口: $port"
    local link_html=""
    if [ "$port" -eq 0 ]; then
        port_display="定时任务"
        link_html="<span style=\"color: #666; font-size: 0.85rem;\">每2小时自动执行</span>"
    else
        link_html="<a href=\"$service_url\" class=\"card-btn\" style=\"background: $btn_color;\" target=\"_blank\">访问服务 →</a>"
    fi
    
    cat << CARD
        <div class="card">
            <div class="card-header" style="background: $color;">
                <div class="card-title">
                    <span>$name</span>
                    $status_badge
                </div>
                <div class="card-port">$port_display</div>
            </div>
            <div class="card-body">
                <div class="card-info">
                    <div class="info-row">
                        <span class="info-label">访问权限</span>
                        <span class="info-value $access_class">$access_text</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">运行状态</span>
                        <span class="info-value $status_class">$status</span>
                    </div>
                </div>
                <div class="card-desc">$desc</div>
            </div>
            <div class="card-footer">
                $link_html
            </div>
        </div>
CARD
}

# 生成完整HTML页面
generate_html() {
    local cards="$1"
    local total="$2" healthy="$3" unhealthy="$4" stopped="$5" health_rate="$6"
    local update_time="$7"
    local version="$8"
    
    cat << HTMLEOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>服务仪表盘 - 系统监控</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
            background: #f5f7fa;
            min-height: 100vh;
            color: #333;
        }
        
        .header {
            background: linear-gradient(135deg, #27ae60 0%, #2ecc71 100%);
            color: white;
            padding: 25px 20px 60px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2rem;
            font-weight: 600;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 16px;
            margin: -60px 20px 30px;
            position: relative;
            z-index: 10;
        }
        
        .stat-card {
            background: white;
            border-radius: 8px;
            padding: 20px;
            text-align: center;
            box-shadow: 0 2px 12px rgba(0,0,0,0.08);
            transition: transform 0.2s;
        }
        
        .stat-card:hover {
            transform: translateY(-2px);
        }
        
        .stat-value {
            font-size: 2rem;
            font-weight: 700;
            margin-bottom: 4px;
        }
        
        .stat-value.total { color: #333; }
        .stat-value.healthy { color: #52c41a; }
        .stat-value.unhealthy { color: #faad14; }
        .stat-value.stopped { color: #ff4d4f; }
        .stat-value.rate { color: #1890ff; }
        
        .stat-label {
            font-size: 0.85rem;
            color: #666;
        }
        
        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 20px;
            padding: 15px 20px 0;
        }
        
        .card {
            background: white;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 2px 8px rgba(0,0,0,0.06);
            transition: all 0.3s ease;
        }
        
        .card:hover {
            transform: translateY(-4px);
            box-shadow: 0 8px 24px rgba(0,0,0,0.12);
        }
        
        .card-header {
            padding: 20px;
            color: white;
            position: relative;
        }
        
        .card-title {
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 1.1rem;
            font-weight: 600;
        }
        
        .status-badge {
            font-size: 0.75rem;
            padding: 4px 10px;
            border-radius: 8px;
            font-weight: 500;
        }
        
        .status-badge.status-healthy { background: rgba(255,255,255,0.25); }
        .status-badge.status-unhealthy { background: rgba(255,255,255,0.25); }
        .status-badge.status-stopped { background: rgba(255,255,255,0.25); }
        .status-badge.status-unknown { background: rgba(255,255,255,0.25); }
        
        .card-port {
            font-size: 0.85rem;
            opacity: 0.9;
            margin-top: 8px;
        }
        
        .card-body {
            padding: 20px;
        }
        
        .card-info {
            display: flex;
            flex-direction: column;
            gap: 12px;
            margin-bottom: 16px;
        }
        
        .info-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .info-label {
            font-size: 0.85rem;
            color: #666;
        }
        
        .info-value {
            font-size: 0.85rem;
            padding: 4px 10px;
            border-radius: 4px;
            font-weight: 500;
        }
        
        .info-value.access-global { background: #f6ffed; color: #52c41a; }
        .info-value.access-local { background: #e6f7ff; color: #1890ff; }
        .info-value.access-unknown { background: #fafafa; color: #8c8c8c; }
        .info-value.status-healthy { background: #f6ffed; color: #52c41a; }
        .info-value.status-unhealthy { background: #fff7e6; color: #faad14; }
        .info-value.status-stopped { background: #fff2f0; color: #ff4d4f; }
        .info-value.status-unknown { background: #fafafa; color: #999; }
        
        .card-desc {
            font-size: 0.9rem;
            color: #666;
            line-height: 1.5;
            padding-top: 16px;
            border-top: 1px solid #f0f0f0;
        }
        
        .card-footer {
            padding: 16px 20px;
            background: #fafafa;
            border-top: 1px solid #f0f0f0;
        }
        
        .card-btn {
            display: inline-block;
            padding: 8px 20px;
            color: white;
            text-decoration: none;
            border-radius: 4px;
            font-size: 0.9rem;
            font-weight: 500;
            transition: opacity 0.2s;
        }
        
        .card-btn:hover {
            opacity: 0.9;
        }
        
        .footer {
            text-align: center;
            padding: 40px 20px;
            color: #999;
            font-size: 0.85rem;
        }
        
        @media (max-width: 768px) {
            .header h1 {
                font-size: 1.5rem;
            }
            
            .stats-grid {
                grid-template-columns: repeat(2, 1fr);
                margin: -40px 10px 20px;
            }
            
            .services-grid {
                grid-template-columns: 1fr;
                padding: 0 10px;
            }
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>服务仪表盘</h1>
    </div>
    
    <div class="container">
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-value total">$total</div>
                <div class="stat-label">总服务数</div>
            </div>
            <div class="stat-card">
                <div class="stat-value healthy">$healthy</div>
                <div class="stat-label">健康运行</div>
            </div>
            <div class="stat-card">
                <div class="stat-value unhealthy">$unhealthy</div>
                <div class="stat-label">运行异常</div>
            </div>
            <div class="stat-card">
                <div class="stat-value stopped">$stopped</div>
                <div class="stat-label">已停止</div>
            </div>
            <div class="stat-card">
                <div class="stat-value rate">$health_rate%</div>
                <div class="stat-label">健康率</div>
            </div>
        </div>
        
        <div class="services-grid">
            $cards
        </div>
    </div>
    
    <div class="footer">
        <p>服务仪表盘 $version · 更新于 $update_time · 服务器: $IP_ADDRESS</p>
    </div>
</body>
</html>
HTMLEOF
}

# ============================================================================
# 主程序
# ============================================================================

main() {
    local start_time
    start_time=$(date +%s)
    local VERSION="v3.9"
    
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        服务仪表盘更新脚本 $VERSION         ║${NC}"
    echo -e "${BLUE}║        智能服务发现 + 健康检查           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # 初始化
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null || true
    mkdir -p "$DASHBOARD_DIR" 2>/dev/null || true
    
    log_info "开始更新服务仪表盘..."
    log_info "服务器IP地址: $IP_ADDRESS"
    log_info "配置文件: $CONFIG_FILE"
    log_info "输出目录: $DASHBOARD_DIR"
    
    # 获取服务列表
    log_info "获取服务列表..."
    local -A seen_ports
    local services=()
    local config_count=0
    
    # 第一步：从配置文件加载服务（优先级最高）
    if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ]; then
        # 检测配置文件格式（TOML或旧格式）
        if grep -q '\[\[services\]\]' "$CONFIG_FILE" 2>/dev/null; then
            # TOML格式
            log_info "检测到TOML格式配置文件"
            
            # 解析全局配置（如exclude_ports）
            local toml_exclude_ports
            toml_exclude_ports=$(parse_toml_global "$CONFIG_FILE" 2>/dev/null || echo "")
            if [ -n "$toml_exclude_ports" ]; then
                EXCLUDE_PORTS="$EXCLUDE_PORTS $toml_exclude_ports"
                log_info "从TOML配置加载排除端口: $toml_exclude_ports"
            fi
            
            # 解析服务配置
            local toml_services=()
            if parse_toml_config "$CONFIG_FILE" toml_services; then
                for service in "${toml_services[@]}"; do
                    local port sname
                    port=$(echo "$service" | cut -d'|' -f1)
                    sname=$(echo "$service" | cut -d'|' -f2)
                    # 仅显示实际运行（端口正在监听）的配置服务
                    if [ "$port" -ne 0 ] && ! check_port "$port"; then
                        log_info "跳过未运行的配置服务: $sname (端口 $port 未监听)"
                        continue
                    fi
                    if [ -z "${seen_ports[$port]:-}" ]; then
                        seen_ports["$port"]=1
                        services+=("$service")
                        config_count=$((config_count + 1))
                        log_info "配置服务: $sname (端口 $port)"
                    fi
                done
                log_info "从TOML配置文件加载了 $config_count 个服务"
            fi
        else
            # 旧格式（兼容）
            log_info "检测到旧格式配置文件"
            local valid_lines
            valid_lines=$(grep -cE "^[0-9]+\|" "$CONFIG_FILE" 2>/dev/null || echo "0")
            
            if [ "$valid_lines" -gt 0 ]; then
                while IFS= read -r line; do
                    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
                    if [[ "$line" =~ ^[0-9]+\| ]]; then
                        local port
                        port=$(echo "$line" | cut -d'|' -f1)
                        # 仅显示实际运行（端口正在监听）的配置服务
                        if [ "$port" -ne 0 ] && ! check_port "$port"; then
                            log_info "跳过未运行的配置服务 (端口 $port 未监听)"
                            continue
                        fi
                        if [ -z "${seen_ports[$port]:-}" ]; then
                            seen_ports["$port"]=1
                            local parsed_line
                            parsed_line=$(parse_service_line "$line")
                            services+=("$parsed_line")
                            config_count=$((config_count + 1))
                            log_info "配置服务: $(echo "$parsed_line" | cut -d'|' -f2) (端口 $port)"
                        fi
                    fi
                done < "$CONFIG_FILE"
                log_info "从配置文件加载了 $config_count 个服务"
            fi
        fi
    fi
    
    # 第二步：自动发现本机运行的服务（与配置文件合并）
    echo -e "${CYAN}正在自动发现本机服务...${NC}"
    log_info "自动扫描本机运行的服务..."
    local auto_count=0
    
    while IFS= read -r service; do
        [ -z "$service" ] && continue
        local port name
        port=$(echo "$service" | cut -d'|' -f1)
        name=$(echo "$service" | cut -d'|' -f2)
        if [ -z "${seen_ports[$port]:-}" ]; then
            seen_ports["$port"]=1
            services+=("$service")
            auto_count=$((auto_count + 1))
            log_info "自动发现: $name (端口 $port)"
        fi
    done < <(auto_discover_services)
    
    if [ "$auto_count" -gt 0 ]; then
        log_info "自动发现了 $auto_count 个新服务"
    fi
    
    # 第三步：扫描Nginx配置（补充发现）
    if [ "${SCAN_NGINX:-true}" = "true" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local port
            port=$(echo "$line" | cut -d'|' -f1)
            if [ -z "${seen_ports[$port]:-}" ]; then
                seen_ports["$port"]=1
                services+=("$line")
                log_info "Nginx发现: $(echo "$line" | cut -d'|' -f2) (端口 $port)"
            fi
        done <<< "$(scan_nginx)"
    fi
    
    # 第四步：扫描Caddy配置（补充发现）
    if [ "${SCAN_CADDY:-true}" = "true" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local port
            port=$(echo "$line" | cut -d'|' -f1)
            if [ -z "${seen_ports[$port]:-}" ]; then
                seen_ports["$port"]=1
                services+=("$line")
                log_info "Caddy发现: $(echo "$line" | cut -d'|' -f2) (端口 $port)"
            fi
        done < <(scan_caddy)
    fi
    
    # 如果没有发现任何服务
    if [ ${#services[@]} -eq 0 ]; then
        log_warn "未发现任何服务"
        echo -e "${YELLOW}警告: 未发现任何运行中的服务${NC}"
        echo -e "请检查是否有服务正在运行，或手动编辑配置文件${NC}"
        services+=("80|无服务|local|未发现运行中的服务|auto|auto|auto")
    fi
    
    # 添加 cron 服务监控（公众号监控）
    local gzh_log="/root/gzh/monitor.log"
    if [ -f "$gzh_log" ]; then
        services+=("0|公众号监控|local|微信公众号监控服务，每2小时检查新文章|auto|auto|auto")
        log_info "添加公众号监控服务"
    fi
    
    log_info "共找到 ${#services[@]} 个服务"

    # 访问权限以实际防火墙规则为准（忽略配置文件中的 access 字段）
    log_info "检测防火墙规则（访问权限以实际规则为准）..."
    fw_init
    case "$FW_BACKEND" in
        ufw|firewalld|iptables|nftables)
            log_info "防火墙类型: $FW_BACKEND"
            ;;
        none)
            log_info "防火墙类型: 未检测到防火墙（所有监听端口视为公网可访问）"
            ;;
        unknown)
            log_warn "无法读取防火墙规则: ${FW_ERROR:-未知原因}"
            log_warn "访问权限将显示为“未知”，请用 root 运行或配置免密 sudo"
            ;;
    esac

    local i access_actual access_configured
    for i in "${!services[@]}"; do
        local s_port s_name s_access s_desc s_color s_btn s_scheme
        IFS='|' read -r s_port s_name s_access s_desc s_color s_btn s_scheme <<< "${services[$i]}"
        access_configured="$s_access"
        access_actual=$(detect_access_type "$s_port")
        if [ -n "$access_configured" ] && [ "$access_configured" != "$access_actual" ]; then
            log_info "  $s_name (端口 $s_port): 配置为 $access_configured，实际为 $access_actual（以实际为准）"
        fi
        services[$i]="${s_port}|${s_name}|${access_actual}|${s_desc}|${s_color}|${s_btn}|${s_scheme}"
    done
    
    # 加载反向代理配置并解析每个服务的访问协议（http/https）
    log_info "解析服务访问协议..."
    load_proxy_schemes
    local -A scheme_map
    for service in "${services[@]}"; do
        local port scheme
        port=$(echo "$service" | cut -d'|' -f1)
        scheme=$(echo "$service" | cut -d'|' -f7)
        [ -z "$scheme" ] && scheme="auto"
        if [ "$scheme" = "auto" ]; then
            scheme=$(detect_scheme "$port")
        fi
        scheme_map["$port"]="$scheme"
        log_info "  $(echo "$service" | cut -d'|' -f2) (端口 $port): $scheme"
    done
    
    # 健康检查
    log_info "执行健康检查..."
    local -A status_map
    local healthy=0 unhealthy=0 stopped=0
    
    for service in "${services[@]}"; do
        local port name scheme
        port=$(echo "$service" | cut -d'|' -f1)
        name=$(echo "$service" | cut -d'|' -f2)
        scheme="${scheme_map[$port]:-http}"
        
        # 特殊处理 cron 服务（端口0表示非网络服务）
        if [ "$port" -eq 0 ]; then
            local gzh_log="/root/gzh/monitor.log"
            if check_cron_service "$gzh_log" 2; then
                status_map["$port"]="healthy"
                log_info "  ✓ $name: 健康（最近有活动）"
                ((healthy++)) || true
            else
                status_map["$port"]="stopped"
                log_warn "  ✗ $name: 未运行（日志超过2小时未更新）"
                ((stopped++)) || true
            fi
        elif check_port "$port"; then
            if check_http "$port" "$scheme"; then
                status_map["$port"]="healthy"
                log_info "  ✓ $name (端口 $port): 健康"
                ((healthy++)) || true
            else
                status_map["$port"]="unhealthy"
                log_warn "  ⚠ $name (端口 $port): HTTP异常"
                ((unhealthy++)) || true
            fi
        else
            status_map["$port"]="stopped"
            log_warn "  ✗ $name (端口 $port): 未运行"
            ((stopped++)) || true
        fi
    done
    
    # 计算统计信息
    local total=${#services[@]}
    local health_rate=0
    [ "$total" -gt 0 ] && health_rate=$(( (healthy * 100) / total ))
    
    # 生成HTML
    log_info "生成仪表盘页面..."
    local update_time
    update_time=$(date +"%Y年%m月%d日 %H:%M")
    
    # 生成服务卡片
    local cards=""
    for service in "${services[@]}"; do
        local port name access desc color btn_color scheme
        IFS='|' read -r port name access desc color btn_color scheme <<< "$service"
        local status="${status_map[$port]:-unknown}"
        cards+="$(generate_card "$port" "$name" "$access" "$desc" "$color" "$btn_color" "$status" "${scheme_map[$port]:-http}")"
    done
    
    # 生成完整HTML
    generate_html "$cards" "$total" "$healthy" "$unhealthy" "$stopped" "$health_rate" "$update_time" "$VERSION" > "$TEMP_FILE"
    
    # 备份并更新
    if [ -f "$DASHBOARD_FILE" ]; then
        cp "$DASHBOARD_FILE" "$DASHBOARD_FILE.backup.$(date +%Y%m%d%H%M%S)"
        
        # 清理旧备份，只保留最近5份
        local backup_count
        backup_count=$(ls -1 "$DASHBOARD_FILE".backup.* 2>/dev/null | wc -l)
        if [ "$backup_count" -gt 5 ]; then
            ls -1t "$DASHBOARD_FILE".backup.* | tail -n +6 | xargs rm -f
            log_info "清理旧备份文件，保留最近5份"
        fi
    fi
    
    cp "$TEMP_FILE" "$DASHBOARD_FILE"
    chmod 644 "$DASHBOARD_FILE"
    rm -f "$TEMP_FILE"
    
    # 完成
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            更新完成！                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BLUE}●${NC} 总服务数:   $total"
    echo -e "  ${GREEN}●${NC} 健康运行:   $healthy"
    echo -e "  ${YELLOW}●${NC} 运行异常:   $unhealthy"
    echo -e "  ${RED}●${NC} 已停止:     $stopped"
    echo -e "  ${BLUE}●${NC} 健康率:     $health_rate%"
    echo -e "  ${BLUE}●${NC} 执行时间:   ${duration}秒"
    echo ""
    echo -e "  访问地址: ${BLUE}http://$IP_ADDRESS${NC}"
    echo ""
    
    if [ "$config_count" -gt 0 ]; then
        echo -e "  ${CYAN}配置服务: $config_count 个 | 自动发现: $auto_count 个${NC}"
    else
        echo -e "  ${CYAN}提示: 当前使用自动发现模式${NC}"
        echo -e "  ${CYAN}如需自定义服务名称，请编辑: $CONFIG_FILE${NC}"
    fi
    echo ""
    
    log_info "仪表盘更新完成，耗时 ${duration} 秒"
}

# 运行主程序
main "$@"
