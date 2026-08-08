#!/bin/bash
# ============================================================================
# 服务仪表盘安装脚本
# ============================================================================

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        服务仪表盘安装程序               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用root用户或sudo运行此脚本${NC}"
    exit 1
fi

# 检查依赖
echo -e "${BLUE}[1/5]${NC} 检查系统依赖..."
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${YELLOW}警告: $1 未安装${NC}"
        return 1
    fi
    return 0
}

MISSING_DEPS=0
check_command "curl" || MISSING_DEPS=1
check_command "ss" || check_command "netstat" || MISSING_DEPS=1
check_command "nginx" || echo -e "${YELLOW}提示: Nginx未安装，仪表盘将使用独立模式${NC}"

if [ "$MISSING_DEPS" -eq 1 ]; then
    echo -e "${YELLOW}建议安装缺失的依赖: apt install curl net-tools${NC}"
fi

# 创建目录
echo -e "${BLUE}[2/5]${NC} 创建目录结构..."
mkdir -p /var/www/dashboard
mkdir -p /var/log
echo -e "${GREEN}  ✓ 目录创建完成${NC}"

# 复制配置文件
echo -e "${BLUE}[3/5]${NC} 安装配置文件..."
if [ ! -f "$SCRIPT_DIR/conf/services.conf" ]; then
    if [ -f "$SCRIPT_DIR/conf/services.conf.example" ]; then
        cp "$SCRIPT_DIR/conf/services.conf.example" "$SCRIPT_DIR/conf/services.conf"
        echo -e "${GREEN}  ✓ 已创建默认配置文件${NC}"
        echo -e "${YELLOW}  提示: 请编辑 $SCRIPT_DIR/conf/services.conf 添加您的服务${NC}"
    else
        echo -e "${RED}  错误: 配置模板文件不存在${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}  ✓ 配置文件已存在${NC}"
fi

# 设置权限
echo -e "${BLUE}[4/5]${NC} 设置文件权限..."
chmod +x "$SCRIPT_DIR/update_dashboard.sh"
chmod 644 "$SCRIPT_DIR/conf/services.conf"
echo -e "${GREEN}  ✓ 权限设置完成${NC}"

# 配置Nginx（可选）
echo -e "${BLUE}[5/5]${NC} 配置Nginx..."
if command -v nginx &> /dev/null; then
    read -p "是否配置Nginx？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 备份现有配置
        if [ -f /etc/nginx/sites-available/default ]; then
            cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup.$(date +%Y%m%d%H%M%S)
        fi
        
        # 复制仪表盘配置
        cp "$SCRIPT_DIR/nginx/dashboard.conf" /etc/nginx/sites-available/dashboard
        
        # 禁用default配置
        rm -f /etc/nginx/sites-enabled/default
        
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

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            安装完成！                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}●${NC} 脚本目录:   $SCRIPT_DIR"
echo -e "  ${BLUE}●${NC} 配置文件:   $SCRIPT_DIR/conf/services.conf"
echo -e "  ${BLUE}●${NC} 输出目录:   /var/www/dashboard"
echo -e "  ${BLUE}●${NC} 日志文件:   /var/log/dashboard_update.log"
echo ""
echo -e "  ${YELLOW}下一步操作:${NC}"
echo -e "  1. 编辑配置文件: ${BLUE}vim $SCRIPT_DIR/conf/services.conf${NC}"
echo -e "  2. 运行更新脚本: ${BLUE}$SCRIPT_DIR/update_dashboard.sh${NC}"
echo -e "  3. 设置定时任务: ${BLUE}crontab -e${NC} 添加以下行:"
echo -e "     ${BLUE}*/5 * * * * $SCRIPT_DIR/update_dashboard.sh > /dev/null 2>&1${NC}"
echo ""
