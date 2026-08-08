#!/bin/bash
# ============================================================================
# 服务仪表盘卸载脚本
# ============================================================================

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        服务仪表盘卸载程序               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用root用户或sudo运行此脚本${NC}"
    exit 1
fi

# 确认卸载
read -p "确定要卸载服务仪表盘吗？(y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}已取消卸载${NC}"
    exit 0
fi

echo -e "${BLUE}[1/3]${NC} 移除Nginx配置..."
if [ -L /etc/nginx/sites-enabled/dashboard ]; then
    rm -f /etc/nginx/sites-enabled/dashboard
    echo -e "${GREEN}  ✓ 已移除Nginx符号链接${NC}"
fi

if [ -f /etc/nginx/sites-available/dashboard ]; then
    rm -f /etc/nginx/sites-available/dashboard
    echo -e "${GREEN}  ✓ 已移除Nginx配置文件${NC}"
fi

# 重载Nginx
if command -v nginx &> /dev/null; then
    systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
fi

echo -e "${BLUE}[2/3]${NC} 移除仪表盘文件..."
read -p "是否删除仪表盘网页文件？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d /var/www/dashboard ]; then
        rm -rf /var/www/dashboard
        echo -e "${GREEN}  ✓ 已删除仪表盘目录${NC}"
    fi
else
    echo -e "${YELLOW}  保留仪表盘目录${NC}"
fi

echo -e "${BLUE}[3/3]${NC} 移除日志文件..."
if [ -f /var/log/dashboard_update.log ]; then
    rm -f /var/log/dashboard_update.log
    echo -e "${GREEN}  ✓ 已删除日志文件${NC}"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            卸载完成！                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${YELLOW}注意:${NC}"
echo -e "  - 脚本和配置文件未删除，可手动删除: ${BLUE}rm -rf /root/dashboard${NC}"
echo -e "  - 如需恢复Nginx默认配置，请手动操作"
echo ""
