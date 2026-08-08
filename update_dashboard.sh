#!/bin/bash
# ============================================================================
# 服务仪表盘更新脚本 v3.3
# 通用版本 - 适用于各类Linux服务器
# ============================================================================
# 功能：自动发现服务、健康检查、生成Web仪表盘
# 作者：MiMo
# 版本：v3.3
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

SCRIPT_DIR="$(resolve_script_dir)"
CONFIG_FILE="${DASHBOARD_CONFIG:-$SCRIPT_DIR/conf/services.conf}"
DASHBOARD_DIR="${DASHBOARD_DIR:-/var/www/dashboard}"
DASHBOARD_FILE="$DASHBOARD_DIR/index.html"
TEMP_FILE="/tmp/dashboard_update.html"
LOG_FILE="${DASHBOARD_LOG:-/var/log/dashboard_update.log}"
TIMEOUT_SECONDS="${DASHBOARD_TIMEOUT:-3}"

# 获取服务器IP地址（自动检测）
get_ip_address() {
    local ip=""
    # 尝试从默认网关接口获取
    local default_iface
    default_iface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$default_iface" ]; then
        ip=$(ip -4 addr show "$default_iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    fi
    # 备用方案
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
NC='\033[0m'

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

# HTTP健康检查
check_http() {
    local port="$1"
    local code body
    
    response=$(curl -s --max-time "$TIMEOUT_SECONDS" -w "\n%{http_code}" "http://127.0.0.1:$port" 2>/dev/null || echo -e "\n000")
    code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')
    
    # 健康判断逻辑：
    # - 2xx/3xx: 健康
    # - 401/403: 正常（需要认证）
    # - 有响应内容的4xx/5xx: 服务运行中
    if [[ "$code" =~ ^[23] ]]; then
        return 0
    elif [[ "$code" == "401" ]] || [[ "$code" == "403" ]]; then
        return 0
    elif [[ "$code" =~ ^[45] ]] && [ -n "$body" ]; then
        return 0
    fi
    return 1
}

# 扫描Nginx配置发现服务
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
        
        echo "$port|$name|local|Nginx服务|linear-gradient(135deg, #667eea 0%, #764ba2 100%)|#667eea"
    done
}

# 生成服务卡片HTML
generate_card() {
    local port="$1" name="$2" access="$3" desc="$4" color="$5" btn_color="$6" status="$7"
    
    [ -z "$color" ] || [ "$color" = "auto" ] && color="linear-gradient(135deg, #667eea 0%, #764ba2 100%)"
    [ -z "$btn_color" ] && btn_color="#667eea"
    
    local access_text access_class
    if [ "$access" = "global" ]; then
        access_text="公网"
        access_class="access-global"
    else
        access_text="局域网"
        access_class="access-local"
    fi
    
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
    
    local service_url
    if [ "$access" = "global" ]; then
        service_url="http://${IP_ADDRESS}:${port}"
    else
        service_url="http://${IP_ADDRESS}:${port}"
    fi
    
    cat << CARD
        <div class="card">
            <div class="card-header" style="background: $color;">
                <div class="card-title">
                    <span>$name</span>
                    $status_badge
                </div>
                <div class="card-port">端口: $port</div>
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
                <a href="$service_url" class="card-btn" style="background: $btn_color;" target="_blank">
                    访问服务 →
                </a>
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
    local VERSION="v3.3"
    
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
    
    # 检查配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        echo -e "${RED}错误: 配置文件不存在，请先创建配置文件${NC}"
        echo -e "配置文件路径: $CONFIG_FILE"
        echo -e "参考模板: $SCRIPT_DIR/conf/services.conf.example"
        exit 1
    fi
    
    # 获取服务列表
    log_info "获取服务列表..."
    local -A seen_ports
    local services=()
    
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        if [[ "$line" =~ ^[0-9]+\| ]]; then
            local port
            port=$(echo "$line" | cut -d'|' -f1)
            if [ -z "${seen_ports[$port]:-}" ]; then
                seen_ports["$port"]=1
                services+=("$line")
            fi
        fi
    done < "$CONFIG_FILE"
    log_info "从配置文件加载了 ${#services[@]} 个服务"
    
    # 扫描Nginx配置（可选）
    if [ "${SCAN_NGINX:-true}" = "true" ]; then
        log_info "扫描Nginx配置..."
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local port
            port=$(echo "$line" | cut -d'|' -f1)
            if [ -z "${seen_ports[$port]:-}" ]; then
                seen_ports["$port"]=1
                services+=("$line")
                log_info "从Nginx发现: $(echo "$line" | cut -d'|' -f2) (端口 $port)"
            fi
        done <<< "$(scan_nginx)"
    fi
    
    log_info "共找到 ${#services[@]} 个服务"
    
    # 健康检查
    log_info "执行健康检查..."
    local -A status_map
    local healthy=0 unhealthy=0 stopped=0
    
    for service in "${services[@]}"; do
        local port name
        port=$(echo "$service" | cut -d'|' -f1)
        name=$(echo "$service" | cut -d'|' -f2)
        
        if check_port "$port"; then
            if check_http "$port"; then
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
        local port name access desc color btn_color
        IFS='|' read -r port name access desc color btn_color <<< "$service"
        local status="${status_map[$port]:-unknown}"
        cards+="$(generate_card "$port" "$name" "$access" "$desc" "$color" "$btn_color" "$status")"
    done
    
    # 生成完整HTML
    generate_html "$cards" "$total" "$healthy" "$unhealthy" "$stopped" "$health_rate" "$update_time" "$VERSION" > "$TEMP_FILE"
    
    # 备份并更新
    if [ -f "$DASHBOARD_FILE" ]; then
        cp "$DASHBOARD_FILE" "$DASHBOARD_FILE.backup.$(date +%Y%m%d%H%M%S)"
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
    
    log_info "仪表盘更新完成，耗时 ${duration} 秒"
}

# 运行主程序
main "$@"
