# OpenClawConfig

OpenClaw Nginx 反向代理一键配置脚本，自动完成 HTTPS 证书申请和安全配置。

## 功能特性

- ✅ 自动检测 OpenClaw 是否已安装，未安装则终止脚本
- ✅ 自动检测并安装 Nginx（支持 Ubuntu/Debian/CentOS/RHEL）
- ✅ 交互式输入域名
- ✅ 自动申请 Let's Encrypt 免费 SSL 证书
- ✅ 强制 HTTPS 跳转
- ✅ WebSocket 支持
- ✅ 静态资源缓存
- ✅ SSL 证书自动续期
- ✅ 每步详细日志输出

## 快速开始

```bash
# 下载脚本
wget https://raw.githubusercontent.com/billkit/OpenClawConfig/main/openclaw-nginx-proxy.sh

# 添加执行权限
chmod +x openclaw-nginx-proxy.sh

# 使用 root 权限运行
sudo ./openclaw-nginx-proxy.sh
```

## 前置要求

- 已安装 [OpenClaw](https://docs.openclaw.ai)
- 拥有一个域名，并已将 A 记录解析到服务器 IP
- 服务器开放 80 和 443 端口

## 使用示例

```bash
$ sudo ./openclaw-nginx-proxy.sh

==============================================
OpenClaw Nginx 反向代理配置脚本
==============================================

[INFO] 检查运行权限...
[SUCCESS] 运行权限检查通过
[INFO] 检查 OpenClaw 是否已安装...
[SUCCESS] OpenClaw 已安装
[INFO] 检查 Nginx 是否已安装...
[SUCCESS] Nginx 已安装
[INFO] 获取 OpenClaw Gateway 配置...
[SUCCESS] 从配置文件获取到 Gateway 端口: 18789
[INFO] 请输入您的域名 (例如: example.com)
请输入域名: your-domain.com
[SUCCESS] 域名输入: your-domain.com
[INFO] 检查域名 your-domain.com 是否解析到本机...
[SUCCESS] 域名解析检查通过
[INFO] 生成 Nginx 配置文件...
[SUCCESS] Nginx 配置文件已生成
[INFO] 测试 Nginx 配置...
[SUCCESS] Nginx 配置测试通过
[INFO] 申请 Let's Encrypt SSL 证书...
[SUCCESS] SSL 证书申请成功
[INFO] 设置 SSL 证书自动续期...
[SUCCESS] 自动续期任务已添加

==============================================
配置完成！
==============================================

访问地址: https://your-domain.com
```

## 配置说明

脚本生成的 Nginx 配置包含以下安全特性：

| 配置项 | 说明 |
|--------|------|
| TLS 1.2/1.3 | 仅允许安全的 TLS 协议版本 |
| HSTS | 强制浏览器使用 HTTPS 访问 |
| X-Frame-Options | 防止点击劫持 |
| X-Content-Type-Options | 防止 MIME 嗅探 |
| X-XSS-Protection | XSS 过滤器 |
| WebSocket | 自动升级 WebSocket 连接 |
| 静态资源缓存 | 30 天浏览器缓存 |

## 常用命令

```bash
# 查看 Nginx 状态
systemctl status nginx

# 重载 Nginx 配置
systemctl reload nginx

# 查看 SSL 证书信息
certbot certificates

# 手动续期证书
certbot renew

# 查看证书自动续期任务
crontab -l
```

## 文件结构

```
/etc/nginx/
├── sites-available/
│   └── openclaw-ssl          # Nginx 站点配置
├── sites-enabled/
│   └── openclaw-ssl -> ../sites-available/openclaw-ssl
└── ...

/etc/letsencrypt/live/
└── your-domain.com/
    ├── fullchain.pem          # SSL 证书
    └── privkey.pem            # SSL 私钥
```

## 故障排除

### 页面显示 "Service unavailable"

检查 OpenClaw Gateway 是否运行：
```bash
openclaw gateway status
```

### 证书申请失败

1. 确认域名已正确解析到服务器 IP
2. 确认 80 端口未被占用
3. 手动申请：`certbot --nginx -d your-domain.com`

### WebSocket 连接失败

检查 Nginx 配置中的 WebSocket 代理头是否正确：
```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

## 许可证

MIT License