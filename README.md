# 服务仪表盘

一个轻量级的服务监控仪表盘，自动发现服务、进行健康检查并生成美观的Web界面。

## 功能特性

- 🔍 **自动服务发现** - 从配置文件和Nginx配置自动发现服务
- 💓 **健康检查** - 自动检测服务运行状态（端口监听 + HTTP检查）
- 🎨 **美观界面** - 现代化响应式设计，支持移动端
- 📊 **统计面板** - 实时显示服务总数、健康率等统计信息
- 🔧 **易于配置** - 简单的配置文件格式，支持自定义颜色
- 🚀 **轻量级** - 纯静态HTML，无需额外依赖

## 快速开始

### 1. 安装

```bash
# 进入项目目录
cd /root/dashboard

# 运行安装脚本
sudo ./install.sh
```

### 2. 配置服务

编辑配置文件：

```bash
vim /root/dashboard/conf/services.conf
```

配置格式：
```
端口|服务名称|访问权限|描述|卡片颜色|按钮颜色
```

示例：
```bash
# Web服务
80|公司官网|global|公司官方网站|linear-gradient(135deg, #3498db 0%, #2980b9 100%)|#3498db

# 管理工具
8080|管理后台|local|系统管理后台|linear-gradient(135deg, #9b59b6 0%, #8e44ad 100%)|#9b59b6
```

### 3. 生成仪表盘

```bash
# 运行更新脚本
/root/dashboard/update_dashboard.sh
```

### 4. 访问仪表盘

打开浏览器访问：`http://你的服务器IP`

## 目录结构

```
/root/dashboard/
├── README.md              # 本文档
├── install.sh             # 安装脚本
├── uninstall.sh           # 卸载脚本
├── update_dashboard.sh    # 主更新脚本
├── conf/
│   ├── services.conf      # 服务配置文件（运行时生成）
│   └── services.conf.example  # 配置模板
└── nginx/
    └── dashboard.conf     # Nginx配置模板
```

## 配置说明

### 服务配置格式

```
端口|服务名称|访问权限|描述|卡片颜色|按钮颜色
```

| 字段 | 说明 | 示例 |
|------|------|------|
| 端口 | 服务监听的端口号 | 80, 8080, 3000 |
| 服务名称 | 显示在仪表盘上的名称 | 公司官网 |
| 访问权限 | `global`(公网) 或 `local`(局域网) | local |
| 描述 | 服务的详细描述 | 公司官方网站 |
| 卡片颜色 | CSS渐变或十六进制颜色值 | linear-gradient(135deg, #3498db 0%, #2980b9 100%) |
| 按钮颜色 | 按钮的背景颜色 | #3498db |

### 颜色参考

```bash
# 蓝色系
linear-gradient(135deg, #3498db 0%, #2980b9 100%)

# 紫色系
linear-gradient(135deg, #9b59b6 0%, #8e44ad 100%)

# 红色系
linear-gradient(135deg, #e74c3c 0%, #c0392b 100%)

# 橙色系
linear-gradient(135deg, #f39c12 0%, #e67e22 100%)

# 绿色系
linear-gradient(135deg, #27ae60 0%, #2ecc71 100%)

# 青色系
linear-gradient(135deg, #1abc9c 0%, #16a085 100%)
```

### 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `DASHBOARD_CONFIG` | 配置文件路径 | `./conf/services.conf` |
| `DASHBOARD_DIR` | 输出目录 | `/var/www/dashboard` |
| `DASHBOARD_LOG` | 日志文件路径 | `/var/log/dashboard_update.log` |
| `DASHBOARD_IP` | 服务器IP地址（自动检测） | 自动检测 |
| `DASHBOARD_TIMEOUT` | HTTP检查超时时间（秒） | 3 |
| `SCAN_NGINX` | 是否扫描Nginx配置 | true |

示例：
```bash
# 使用自定义配置
DASHBOARD_CONFIG=/path/to/my/services.conf ./update_dashboard.sh

# 指定输出目录
DASHBOARD_DIR=/var/www/mysite ./update_dashboard.sh
```

## 定时任务

设置定时更新（每5分钟）：

```bash
# 编辑crontab
crontab -e

# 添加以下行
*/5 * * * * /root/dashboard/update_dashboard.sh > /dev/null 2>&1
```

## Nginx配置

### 独立站点（推荐）

```bash
# 复制配置文件
cp /root/dashboard/nginx/dashboard.conf /etc/nginx/sites-available/dashboard

# 创建符号链接
ln -sf /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/dashboard

# 测试配置
nginx -t

# 重载Nginx
systemctl reload nginx
```

### 作为子目录

如果要将仪表盘作为现有网站的子目录（如 `/dashboard`）：

```nginx
location /dashboard {
    alias /var/www/dashboard;
    index index.html;
    try_files $uri $uri/ =404;
}
```

## 故障排除

### 1. 服务状态显示"未运行"

检查服务是否正在监听指定端口：
```bash
ss -tlnp | grep 端口号
```

### 2. HTTP检查失败

检查服务是否响应HTTP请求：
```bash
curl -I http://127.0.0.1:端口号
```

### 3. 仪表盘无法访问

检查Nginx配置和防火墙：
```bash
# 检查Nginx状态
systemctl status nginx

# 检查端口监听
ss -tlnp | grep :80

# 检查防火墙（如果有）
ufw status
iptables -L -n
```

### 4. 查看日志

```bash
tail -f /var/log/dashboard_update.log
```

## 版本历史

- **v3.3** - 绿色主题、优化间距和圆角
- **v3.2** - 移除卡片边框颜色、改进健康检查逻辑
- **v3.1** - 添加自动服务发现
- **v3.0** - 初始版本

## 许可证

MIT License
