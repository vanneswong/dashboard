#!/bin/bash
# ============================================================================
# 服务仪表盘安装脚本 v3.9
# ============================================================================

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        服务仪表盘安装程序 v3.9          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用root用户或sudo运行此脚本${NC}"
    exit 1
fi

# ============================================================================
# 步骤1: 检查依赖
# ============================================================================
echo -e "${BLUE}[1/7]${NC} 检查系统依赖..."
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${YELLOW}  ⚠ $1 未安装${NC}"
        return 1
    fi
    echo -e "${GREEN}  ✓ $1${NC}"
    return 0
}

MISSING_DEPS=0
check_command "curl" || MISSING_DEPS=1
check_command "ss" || check_command "netstat" || MISSING_DEPS=1
check_command "nginx" || echo -e "${YELLOW}  提示: Nginx未安装，仪表盘将使用独立模式${NC}"

if [ "$MISSING_DEPS" -eq 1 ]; then
    echo -e "${YELLOW}  建议安装缺失的依赖: apt install curl net-tools${NC}"
fi

# ============================================================================
# 步骤2: 选择仪表盘端口
# ============================================================================
echo ""
echo -e "${BLUE}[2/7]${NC} 配置仪表盘端口..."
echo -e "${CYAN}  请选择仪表盘使用的端口:${NC}"
echo ""
echo -e "  ${GREEN}1)${NC} 80   - 默认HTTP端口（推荐，无需加端口号访问）"
echo -e "  ${GREEN}2)${NC} 8080 - 常用Web服务端口"
echo -e "  ${GREEN}3)${NC} 8081 - 备用端口"
echo -e "  ${GREEN}4)${NC} 自定义端口"
echo ""

while true; do
    read -p "  请选择 [1-4]: " port_choice
    case $port_choice in
        1)
            DASHBOARD_PORT=80
            break
            ;;
        2)
            DASHBOARD_PORT=8080
            break
            ;;
        3)
            DASHBOARD_PORT=8081
            break
            ;;
        4)
            while true; do
                read -p "  请输入端口号 (1024-65535): " custom_port
                if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1024 ] && [ "$custom_port" -le 65535 ]; then
                    DASHBOARD_PORT=$custom_port
                    break 2
                else
                    echo -e "${RED}  无效端口号，请输入1024-65535之间的数字${NC}"
                fi
            done
            ;;
        *)
            echo -e "${RED}  无效选择，请重新选择${NC}"
            ;;
    esac
done

echo -e "${GREEN}  ✓ 已选择端口: $DASHBOARD_PORT${NC}"

# 检查端口是否被占用
if ss -tlnp 2>/dev/null | grep -qE "[: ]${DASHBOARD_PORT}[[:space:]]" || \
   netstat -tlnp 2>/dev/null | grep -qE "[: ]${DASHBOARD_PORT}[[:space:]]"; then
    echo -e "${YELLOW}  ⚠ 端口 $DASHBOARD_PORT 已被占用${NC}"
    read -p "  是否继续安装？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}  安装已取消${NC}"
        exit 0
    fi
fi

# ============================================================================
# 步骤3: 创建目录
# ============================================================================
echo ""
echo -e "${BLUE}[3/7]${NC} 创建目录结构..."
mkdir -p /var/www/dashboard
mkdir -p /var/log
echo -e "${GREEN}  ✓ 目录创建完成${NC}"

# ============================================================================
# 步骤4: 配置文件处理
# ============================================================================
echo ""
echo -e "${BLUE}[4/7]${NC} 处理配置文件..."
if [ ! -f "$SCRIPT_DIR/conf/services.conf" ]; then
    echo -e "${CYAN}  未检测到配置文件，将使用自动发现模式${NC}"
    echo -e "${CYAN}  自动发现将扫描本机运行的服务并生成仪表盘${NC}"
    echo ""
    read -p "  是否要手动配置服务？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -f "$SCRIPT_DIR/conf/services.conf.example" ]; then
            cp "$SCRIPT_DIR/conf/services.conf.example" "$SCRIPT_DIR/conf/services.conf"
            echo -e "${GREEN}  ✓ 已创建配置文件${NC}"
            echo -e "${YELLOW}  请编辑: $SCRIPT_DIR/conf/services.conf${NC}"
        fi
    else
        echo -e "${GREEN}  ✓ 将使用自动发现模式${NC}"
        # 创建空配置文件，表示使用自动发现
        touch "$SCRIPT_DIR/conf/services.conf"
    fi
else
    echo -e "${GREEN}  ✓ 配置文件已存在${NC}"
fi

# ============================================================================
# 步骤5: 设置权限
# ============================================================================
echo ""
echo -e "${BLUE}[5/7]${NC} 设置文件权限..."
chmod +x "$SCRIPT_DIR/update_dashboard.sh"
chmod 644 "$SCRIPT_DIR/conf/services.conf" 2>/dev/null || true

echo -e "  ${CYAN}配置防火墙状态只读权限（供定时任务读取实际访问权限）...${NC}"
DASHBOARD_RUN_USER="${SUDO_USER:-}"
if [ -n "$DASHBOARD_RUN_USER" ] && [ "$DASHBOARD_RUN_USER" != "root" ]; then
    SUDOERS_FILE="/etc/sudoers.d/dashboard-firewall"
    FW_CMDS=()

    # 只授权仪表盘实际使用的只读查询命令
    fw_bin() {
        local name="$1" p
        for p in "/usr/sbin/$name" "/sbin/$name" "/usr/bin/$name" "/bin/$name"; do
            [ -x "$p" ] && { echo "$p"; return 0; }
        done
        return 1
    }

    UFW_BIN=$(fw_bin ufw || true)
    FIREWALLD_BIN=$(fw_bin firewall-cmd || true)
    IPTABLES_BIN=$(fw_bin iptables || true)
    NFT_BIN=$(fw_bin nft || true)

    [ -n "$UFW_BIN" ] && FW_CMDS+=("$UFW_BIN status" "$UFW_BIN status verbose")
    [ -n "$FIREWALLD_BIN" ] && FW_CMDS+=("$FIREWALLD_BIN --state" "$FIREWALLD_BIN --get-default-zone" "$FIREWALLD_BIN --zone=* --list-all")
    [ -n "$IPTABLES_BIN" ] && FW_CMDS+=("$IPTABLES_BIN -S")
    [ -n "$NFT_BIN" ] && FW_CMDS+=("$NFT_BIN list ruleset")

    if [ ${#FW_CMDS[@]} -gt 0 ]; then
        {
            echo "# 服务仪表盘：允许定时任务只读查询防火墙状态"
            echo "# 由 install.sh 自动生成，请勿手动修改"
            printf '%s ALL=(root) NOPASSWD: ' "$DASHBOARD_RUN_USER"
            printf '%s' "${FW_CMDS[0]}"
            for ((i = 1; i < ${#FW_CMDS[@]}; i++)); do
                printf ', %s' "${FW_CMDS[$i]}"
            done
            echo
        } > "$SUDOERS_FILE"
        chmod 440 "$SUDOERS_FILE"

        if ! visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
            rm -f "$SUDOERS_FILE"
            echo -e "${YELLOW}  ⚠ 防火墙 sudoers 规则校验失败，已跳过（访问权限可能显示为未知）${NC}"
        else
            echo -e "${GREEN}  ✓ 已允许用户 $DASHBOARD_RUN_USER 读取防火墙状态${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ 未找到可用的防火墙工具，跳过${NC}"
    fi
else
    echo -e "${GREEN}  ✓ 以 root 运行，无需额外配置${NC}"
fi
echo -e "${GREEN}  ✓ 权限设置完成${NC}"

# ============================================================================
# 步骤6: 配置Nginx
# ============================================================================
echo ""
echo -e "${BLUE}[6/7]${NC} 配置Nginx..."
if command -v nginx &> /dev/null; then
    read -p "  是否配置Nginx？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 生成Nginx配置
        cat > /tmp/dashboard_nginx.conf << NGINXEOF
server {
    listen ${DASHBOARD_PORT} default_server;
    listen [::]:${DASHBOARD_PORT} default_server;
    
    root /var/www/dashboard;
    index index.html;
    
    server_name _;
    
    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
    }
    
    # 静态资源缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # 启用gzip压缩
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # 日志配置
    access_log /var/log/nginx/dashboard_access.log;
    error_log /var/log/nginx/dashboard_error.log;
}
NGINXEOF

        # 备份现有配置
        if [ -f /etc/nginx/sites-available/default ]; then
            cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup.$(date +%Y%m%d%H%M%S)
        fi
        
        # 复制仪表盘配置
        cp /tmp/dashboard_nginx.conf /etc/nginx/sites-available/dashboard
        rm -f /tmp/dashboard_nginx.conf
        
        # 禁用default配置（如果端口冲突）
        if [ "$DASHBOARD_PORT" = "80" ]; then
            rm -f /etc/nginx/sites-enabled/default
        fi
        
        # 启用仪表盘配置
        ln -sf /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/dashboard
        
        # 测试并重载Nginx
        if nginx -t 2>/dev/null; then
            systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
            echo -e "${GREEN}  ✓ Nginx配置完成${NC}"
        else
            echo -e "${RED}  Nginx配置测试失败，请手动检查${NC}"
            # 恢复原配置
            rm -f /etc/nginx/sites-enabled/dashboard
            if [ -f /etc/nginx/sites-available/default.backup.* ]; then
                ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
            fi
        fi
    else
        echo -e "${YELLOW}  跳过Nginx配置${NC}"
    fi
else
    echo -e "${YELLOW}  Nginx未安装，跳过配置${NC}"
fi

# ============================================================================
# 生成仪表盘页面
# ============================================================================
echo ""
echo -e "${BLUE}[7/7]${NC} 生成仪表盘页面..."
if [ -x "$SCRIPT_DIR/update_dashboard.sh" ]; then
    "$SCRIPT_DIR/update_dashboard.sh" 2>&1 | tail -15
else
    echo -e "${YELLOW}  跳过页面生成，请手动运行: $SCRIPT_DIR/update_dashboard.sh${NC}"
fi

# 让运行定时任务的普通用户能够更新仪表盘和日志
DASHBOARD_RUN_USER="${SUDO_USER:-}"
if [ -n "$DASHBOARD_RUN_USER" ] && [ "$DASHBOARD_RUN_USER" != "root" ]; then
    chown -R "$DASHBOARD_RUN_USER":"$DASHBOARD_RUN_USER" /var/www/dashboard 2>/dev/null || true
    if [ -f "${DASHBOARD_LOG:-/var/log/dashboard_update.log}" ]; then
        chown "$DASHBOARD_RUN_USER":"$DASHBOARD_RUN_USER" "${DASHBOARD_LOG:-/var/log/dashboard_update.log}" 2>/dev/null || true
    fi
    echo -e "${GREEN}  ✓ 已设置 $DASHBOARD_RUN_USER 对仪表盘目录和日志的写权限${NC}"
fi

# ============================================================================
# 安装完成
# ============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            安装完成！                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}●${NC} 脚本目录:   $SCRIPT_DIR"
echo -e "  ${BLUE}●${NC} 配置文件:   $SCRIPT_DIR/conf/services.conf"
echo -e "  ${BLUE}●${NC} 输出目录:   /var/www/dashboard"
echo -e "  ${BLUE}●${NC} 日志文件:   /var/log/dashboard_update.log"
echo -e "  ${BLUE}●${NC} 仪表盘端口: $DASHBOARD_PORT"
echo ""

# 获取IP地址
IP_ADDRESS=$(ip -4 addr show $(ip route | grep default | awk '{print $5}' | head -1) 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ -z "$IP_ADDRESS" ]; then
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
fi
if [ -z "$IP_ADDRESS" ]; then
    IP_ADDRESS="localhost"
fi

echo -e "  ${YELLOW}访问地址:${NC} ${BLUE}http://${IP_ADDRESS}:${DASHBOARD_PORT}${NC}"
echo ""
echo -e "  ${YELLOW}下一步操作:${NC}"
if [ -f "$SCRIPT_DIR/conf/services.conf" ] && [ -s "$SCRIPT_DIR/conf/services.conf" ]; then
    echo -e "  1. 编辑配置文件: ${BLUE}vim $SCRIPT_DIR/conf/services.conf${NC}"
fi
echo -e "  2. 运行更新脚本: ${BLUE}$SCRIPT_DIR/update_dashboard.sh${NC}"
echo -e "  3. 设置定时任务: ${BLUE}crontab -e${NC} 添加以下行:"
echo -e "     ${BLUE}*/5 * * * * $SCRIPT_DIR/update_dashboard.sh > /dev/null 2>&1${NC}"
echo ""
echo -e "  ${CYAN}提示: 不配置服务时，脚本会自动发现本机运行的服务${NC}"
echo ""
