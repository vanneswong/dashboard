# 服务仪表盘

一个轻量级的服务监控仪表盘，支持自动发现服务、健康检查并生成美观的Web界面。

## 功能特性

- 🔍 **自动服务发现** - 无需手动配置，自动扫描本机运行的服务
- 💓 **健康检查** - 自动检测服务运行状态（端口监听 + HTTP检查）
- 🎨 **美观界面** - 现代化响应式设计，支持移动端
- 📊 **统计面板** - 实时显示服务总数、健康率等统计信息
- 🔧 **灵活配置** - 支持手动配置或自动发现模式
- 🚀 **轻量级** - 纯静态HTML，无需额外依赖
- 🎯 **智能颜色** - 健康服务绿色，停止服务深蓝色

## 快速开始

### 1. 安装

```bash
# 克隆仓库
git clone git@github.com:vanneswong/dashboard.git
cd dashboard

# 运行安装脚本
sudo ./install.sh
```

安装过程中会提示：
- 选择仪表盘端口（80/8080/8081/自定义）
- 是否手动配置服务（选择否则使用自动发现）
- 是否配置Nginx

### 2. 自动发现模式

如果不配置服务文件，脚本会自动：
- 扫描本机所有监听的TCP端口
- 识别常见服务（Web、数据库、缓存等）
- 自动获取服务名称和描述
- 健康服务显示绿色，停止服务显示深蓝色

### 3. 手动配置模式

如需自定义服务，编辑配置文件：

```bash
# TOML格式（推荐）
vim conf/service.toml

# 或旧格式
vim conf/services.conf
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

# 使用自动颜色（健康绿色，停止深蓝色）
3000|Grafana|local|监控可视化平台|auto|auto
```

**配置文件查找顺序**：
1. TOML格式：`service.toml` → `services.toml` → `config.toml`
2. 旧格式：`services.conf` → `service.conf` → `config.conf`

**注意**：脚本会自动查找第一个存在的配置文件，无需手动指定格式。

### 4. 更新仪表盘

```bash
# 运行更新脚本
./update_dashboard.sh

# 或使用全局命令（安装后可用）
dashboard-update
```

### 5. 访问仪表盘

打开浏览器访问：`http://你的服务器IP:端口`

## 目录结构

```
dashboard/
├── README.md              # 本文档
├── .gitignore             # Git忽略文件
├── install.sh             # 安装脚本
├── uninstall.sh           # 卸载脚本
├── update_dashboard.sh    # 主更新脚本
├── conf/
│   ├── service.toml       # TOML格式配置文件（推荐）
│   ├── services.conf      # 旧格式配置文件（兼容）
│   └── services.conf.example  # 配置模板
└── nginx/
    └── dashboard.conf     # Nginx配置模板
```

## 配置说明

### 配置文件

脚本会自动查找配置文件，优先级如下：

#### TOML格式（推荐）

1. `conf/service.toml`
2. `conf/services.toml`
3. `conf/config.toml`

#### 旧格式（兼容）

4. `conf/services.conf`
5. `conf/service.conf`
6. `conf/config.conf`

**注意**：
- 脚本会自动识别配置文件格式（TOML或旧格式）
- 无需手动指定格式，只需将配置文件放在 `conf/` 目录下即可
- 如果存在多个配置文件，优先使用TOML格式
- 可以通过环境变量 `DASHBOARD_CONFIG` 手动指定配置文件路径

### 服务配置格式

现在支持两种配置格式：

#### 1. TOML格式（推荐）

TOML格式更加易读和维护，示例：

```toml
# 全局配置（可选）
[global]
exclude_ports = [22000]

# 服务配置
[[services]]
port = 80
name = "主网站"
desc = "公司官网，提供产品展示和联系方式"

# 完整配置
[[services]]
port = 443
name = "服务仪表盘"
desc = "服务监控面板"
access = "local"           # 访问权限: global(公网) 或 local(局域网)
color = "auto"             # 卡片颜色: auto 或 CSS渐变/十六进制颜色
btn_color = "auto"         # 按钮颜色: auto 或 十六进制颜色
```

#### 2. 旧格式（兼容）

```
端口|服务名称|访问权限|描述|卡片颜色|按钮颜色
```

| 字段 | 说明 | 示例 |
|------|------|------|
| 端口 | 服务监听的端口号 | 80, 8080, 3000 |
| 服务名称 | 显示在仪表盘上的名称 | 公司官网 |
| 访问权限 | `global`(公网) 或 `local`(局域网) | local |
| 描述 | 服务的详细描述 | 公司官方网站 |
| 卡片颜色 | CSS渐变、十六进制颜色值或`auto` | auto |
| 按钮颜色 | 按钮的背景颜色或`auto` | auto |

### 配置字段说明

| 字段 | 说明 | 示例 | 默认值 |
|------|------|------|--------|
| `port` | 服务监听的端口号 | 80, 8080, 3000 | 必填 |
| `name` | 显示在仪表盘上的名称 | 公司官网 | 必填 |
| `desc` | 服务的详细描述 | 公司官方网站 | 可选 |
| `access` | 访问权限 | `global`(公网) 或 `local`(局域网) | 自动检测 |
| `color` | 卡片颜色 | CSS渐变、十六进制颜色值或`auto` | `auto` |
| `btn_color` | 按钮颜色 | 十六进制颜色值或`auto` | `auto` |

### 自动颜色模式

使用 `auto` 关键字可启用自动颜色：
- **健康服务**: 绿色渐变 `linear-gradient(90deg, #27ae60, #2ecc71)`
- **停止服务**: 深蓝色 `linear-gradient(90deg, #34495e, #2c3e50)`
- **异常服务**: 橙色渐变 `linear-gradient(90deg, #e67e22, #d35400)`

### 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `DASHBOARD_CONFIG` | 配置文件路径（手动指定时优先） | 自动查找 |
| `DASHBOARD_DIR` | 输出目录 | `/var/www/dashboard` |
| `DASHBOARD_LOG` | 日志文件路径 | `/var/log/dashboard_update.log` |
| `DASHBOARD_IP` | 服务器IP地址 | 自动检测 |
| `DASHBOARD_TIMEOUT` | HTTP检查超时时间（秒） | 3 |
| `SCAN_NGINX` | 是否扫描Nginx配置 | true |
| `EXCLUDE_PORTS` | 排除的端口列表（空格分隔） | `22000` |
| `COLOR_HEALTHY` | 健康服务颜色 | `linear-gradient(90deg, #27ae60, #2ecc71)\|#27ae60` |
| `COLOR_STOPPED` | 停止服务颜色 | `linear-gradient(90deg, #34495e, #2c3e50)\|#34495e` |
| `COLOR_UNHEALTHY` | 异常服务颜色 | `linear-gradient(90deg, #e67e22, #d35400)\|#e67e22` |

**排除端口说明**：
- `EXCLUDE_PORTS` 用于排除不需要显示在仪表盘上的端口
- 多个端口用空格分隔，例如：`EXCLUDE_PORTS="22000 22001 22067"`
- 常见需要排除的端口：
  - Syncthing传输端口：22000、22067、21027
  - BT下载端口：51413等
  - 其他内部传输端口

## 定时任务

设置定时更新（每5分钟）：

```bash
# 编辑crontab
crontab -e

# 添加以下行
*/5 * * * * /path/to/dashboard/update_dashboard.sh > /dev/null 2>&1
```

## 自动发现的服务

脚本会自动识别以下常见服务：

| 端口 | 服务名称 |
|------|----------|
| 80 | Web服务 |
| 443 | HTTPS服务 |
| 22 | SSH服务 |
| 3000 | Grafana/Prometheus |
| 3306 | MySQL数据库 |
| 5432 | PostgreSQL数据库 |
| 6379 | Redis缓存 |
| 8080-8085 | Web服务 |
| 9000 | Portainer/PHP-FPM |
| 9090 | Prometheus |
| 9200 | Elasticsearch |
| 7681 | Web终端 |
| 6789 | Netdata |

## 故障排除

### 1. 未发现服务

```bash
# 检查是否有服务在运行
ss -tlnp

# 手动运行脚本查看详细输出
./update_dashboard.sh
```

### 2. 仪表盘无法访问

```bash
# 检查端口监听
ss -tlnp | grep :80

# 检查Nginx状态
systemctl status nginx

# 检查防火墙
ufw status
```

### 3. 查看日志

```bash
tail -f /var/log/dashboard_update.log
```

## 版本历史

- **v3.7** - 支持自动查找配置文件，优先TOML格式
- **v3.6** - 支持TOML格式配置，更加易读和维护
- **v3.5** - 支持排除端口配置，默认排除Syncthing传输端口22000
- **v3.4** - 支持自动发现服务，智能颜色配置
- **v3.3** - 绿色主题、优化间距和圆角
- **v3.2** - 移除卡片边框颜色、改进健康检查逻辑
- **v3.1** - 添加自动服务发现
- **v3.0** - 初始版本

## 许可证

MIT License

## GitHub仓库

- **SSH:** `git@github.com:vanneswong/dashboard.git`
- **HTTPS:** `https://github.com/vanneswong/dashboard.git`
