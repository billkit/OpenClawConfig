#!/bin/bash

###############################################################################
# OpenClaw Nginx 反向代理一键配置脚本
# 功能：
#   1. 检测 OpenClaw 和 Nginx 是否已安装
#   2. 如果没有 Nginx，先安装 Nginx
#   3. 让用户输入域名
#   4. 强制开启 HTTPS，自动生成 Let's Encrypt 证书
#   5. 每步都有日志输出
###############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    log_info "检查运行权限..."
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        log_info "使用方法: sudo $0"
        exit 1
    fi
    log_success "运行权限检查通过"
}

# 检查 OpenClaw 是否已安装
check_openclaw() {
    log_info "检查 OpenClaw 是否已安装..."
    
    if command -v openclaw &> /dev/null; then
        log_success "OpenClaw 已安装"
        return 0
    elif [ -f "/usr/bin/openclaw" ] || [ -f "/usr/local/bin/openclaw" ]; then
        log_success "OpenClaw 已安装"
        return 0
    else
        log_error "OpenClaw 未安装"
        log_info "请先安装 OpenClaw后再运行此脚本"
        log_info "安装教程: https://docs.openclaw.ai"
        exit 1
    fi
}

# 检查 Nginx 是否已安装，如果没有则安装
check_and_install_nginx() {
    log_info "检查 Nginx 是否已安装..."
    
    if command -v nginx &> /dev/null; then
        log_success "Nginx 已安装"
        nginx -v
        return 0
    fi
    
    log_warning "Nginx 未安装，正在安装..."
    
    # 检测系统类型
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        log_error "无法检测操作系统类型"
        exit 1
    fi
    
    case "$OS" in
        ubuntu|debian)
            log_info "检测到 $OS 系统，更新软件包列表..."
            apt-get update -y
            
            log_info "安装 Nginx..."
            apt-get install -y nginx certbot python3-certbot-nginx
            
            if [ $? -eq 0 ]; then
                log_success "Nginx 安装完成"
            else
                log_error "Nginx 安装失败"
                exit 1
            fi
            ;;
        centos|rhel|fedora)
            log_info "检测到 $OS 系统，安装 Nginx..."
            yum install -y epel-release
            yum install -y nginx certbot python3-certbot-nginx
            
            if [ $? -eq 0 ]; then
                log_success "Nginx 安装完成"
            else
                log_error "Nginx 安装失败"
                exit 1
            fi
            ;;
        *)
            log_error "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
}

# 获取 OpenClaw Gateway 端口
get_gateway_port() {
    log_info "获取 OpenClaw Gateway 配置..."
    
    # 尝试从配置文件获取端口
    CONFIG_FILE="$HOME/.openclaw/openclaw.json"
    
    if [ -f "$CONFIG_FILE" ]; then
        PORT=$(grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG_FILE" | head -1 | grep -o '[0-9]*')
        if [ -n "$PORT" ]; then
            log_success "从配置文件获取到 Gateway 端口: $PORT"
            GATEWAY_PORT=$PORT
            return 0
        fi
    fi
    
    # 默认端口
    GATEWAY_PORT=18789
    log_warning "无法从配置获取端口，使用默认端口: $GATEWAY_PORT"
}

# 获取用户输入域名
get_domain() {
    log_info "请输入您的域名 (例如: example.com)"
    read -p "请输入域名: " DOMAIN
    
    if [ -z "$DOMAIN" ]; then
        log_error "域名不能为空"
        get_domain
        return
    fi
    
    # 简单的域名格式验证
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*(\.[a-zA-Z0-9][a-zA-Z0-9-]*)+$ ]]; then
        log_error "域名格式不正确"
        get_domain
        return
    fi
    
    log_success "域名输入: $DOMAIN"
}

# 检查域名是否解析到本机
check_domain_dns() {
    log_info "检查域名 $DOMAIN 是否解析到本机..."
    
    # 获取本机公网 IP
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    
    # 尝试获取域名解析的 IP
    if command -v dig &> /dev/null; then
        RESOLVED_IP=$(dig +short $DOMAIN A | tail -n1)
    elif command -v nslookup &> /dev/null; then
        RESOLVED_IP=$(nslookup $DOMAIN | grep -A1 "Name:" | tail -1 | awk '{print $2}')
    else
        log_warning "无法检测域名解析，将继续配置（可能会导致证书申请失败）"
        return 0
    fi
    
    if [ -z "$RESOLVED_IP" ]; then
        log_error "域名 $DOMAIN 无法解析"
        log_error "请确保域名已正确解析到服务器 IP"
        exit 1
    fi
    
    log_info "域名解析到: $RESOLVED_IP，本机IP: $LOCAL_IP"
    
    if [ "$RESOLVED_IP" != "$LOCAL_IP" ]; then
        log_warning "域名解析的 IP 与本机 IP 不一致"
        log_warning "如果继续，Let's Encrypt 证书申请可能会失败"
        read -p "是否继续? (y/n): " CONTINUE
        if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
            log_info "已退出"
            exit 0
        fi
    fi
    
    log_success "域名解析检查通过"
}

# 生成 Nginx 配置文件
generate_nginx_config() {
    log_info "生成 Nginx 配置文件..."
    
    CONFIG_FILE="/etc/nginx/sites-available/openclaw-ssl"
    
    cat > "$CONFIG_FILE" << EOF
# OpenClaw HTTPS Reverse-Proxy - Auto Generated
# Generated at: $(date)

server {
    listen 80;
    server_name $DOMAIN;

    # Let's Encrypt 证书申请验证
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # 重定向到 HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # SSL 证书配置
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # SSL 安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    
    # HSTS 配置（可选，首次配置建议注释）
    # add_header Strict-Transport-Security "max-age=63072000" always;

    # 通用安全 Header
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header Referrer-Policy "no-referrer-when-downgrade";
    add_header X-XSS-Protection "1; mode=block";

    # 静态资源缓存 - 转发到 Gateway
    location ~* \.(css|js|png|jpg|jpeg|svg|ico|gif|webp)$ {
        proxy_pass http://127.0.0.1:$GATEWAY_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # 主代理 - 转发到 OpenClaw Gateway
    location / {
        proxy_pass http://127.0.0.1:$GATEWAY_PORT;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Server \$host;

        # WebSocket 支持
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # 超时与缓冲
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_buffering off;
        client_max_body_size 50M;
    }

    # 健康检查
    location /healthz {
        proxy_pass http://127.0.0.1:$GATEWAY_PORT/healthz;
        internal;
    }
}
EOF

    log_success "Nginx 配置文件已生成: $CONFIG_FILE"
}

# 启用 Nginx 配置
enable_nginx_config() {
    log_info "启用 Nginx 配置..."
    
    # 创建符号链接
    if [ ! -L /etc/nginx/sites-enabled/openclaw-ssl ]; then
        ln -s /etc/nginx/sites-available/openclaw-ssl /etc/nginx/sites-enabled/openclaw-ssl
    fi
    
    # 移除默认配置（如果有）
    if [ -L /etc/nginx/sites-enabled/default ]; then
        rm -f /etc/nginx/sites-enabled/default
        log_info "已移除默认站点配置"
    fi
    
    # 测试 Nginx 配置
    log_info "测试 Nginx 配置..."
    if nginx -t; then
        log_success "Nginx 配置测试通过"
    else
        log_error "Nginx 配置测试失败"
        exit 1
    fi
    
    # 重新加载 Nginx
    log_info "重新加载 Nginx..."
    systemctl reload nginx
    log_success "Nginx 已重新加载"
}

# 获取 Let's Encrypt 证书
get_ssl_certificate() {
    log_info "申请 Let's Encrypt SSL 证书..."
    
    # 创建验证目录
    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R www-data:www-data /var/www/html
    
    # 申请证书
    log_info "正在申请证书（可能需要等待几分钟）..."
    
    if certbot certonly --webroot -w /var/www/html -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN 2>&1; then
        log_success "SSL 证书申请成功"
    else
        log_warning "证书申请失败，尝试使用standalone模式..."
        if certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN 2>&1; then
            log_success "SSL 证书申请成功（standalone模式）"
        else
            log_error "SSL 证书申请失败"
            log_info "可以稍后手动运行: certbot --nginx -d $DOMAIN"
            return 1
        fi
    fi
    
    # 检查证书是否成功生成
    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        log_success "SSL 证书已生成"
    else
        log_error "SSL 证书生成失败"
        return 1
    fi
}

# 设置自动续期
setup_auto_renew() {
    log_info "设置 SSL 证书自动续期..."
    
    # 添加 crontab 任务
    CRON_JOB="0 3 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'"
    
    # 检查是否已经存在
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        log_success "自动续期任务已添加"
    else
        log_warning "自动续期任务已存在，跳过"
    fi
    
    # 测试续期
    certbot renew --dry-run && log_success "自动续期测试通过" || log_warning "自动续期测试失败"
}

# 打印最终信息
print_summary() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}配置完成！${NC}"
    echo "=============================================="
    echo ""
    echo -e "${BLUE}访问地址:${NC} https://$DOMAIN"
    echo -e "${BLUE}控制面板:${NC} https://$DOMAIN/"
    echo -e "${BLUE}Gateway:${NC} http://127.0.0.1:$GATEWAY_PORT"
    echo ""
    echo "SSL 证书位置:"
    echo "  证书: /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    echo "  私钥: /etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo ""
    echo "证书将在 90 天后过期，已设置自动续期"
    echo ""
    echo "常用命令:"
    echo "  查看 Nginx 状态: systemctl status nginx"
    echo "  重载 Nginx: systemctl reload nginx"
    echo "  查看证书: certbot certificates"
    echo "  手动续期: certbot renew"
    echo ""
}

# 主函数
main() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}OpenClaw Nginx 反向代理配置脚本${NC}"
    echo "=============================================="
    echo ""
    
    # 1. 检查 root 权限
    check_root
    
    # 2. 检查 OpenClaw 是否已安装
    check_openclaw
    
    # 3. 检查并安装 Nginx
    check_and_install_nginx
    
    # 4. 获取 Gateway 端口
    get_gateway_port
    
    # 5. 获取用户输入域名
    get_domain
    
    # 6. 检查域名 DNS
    check_domain_dns
    
    # 7. 生成 Nginx 配置
    generate_nginx_config
    
    # 8. 启用 Nginx 配置
    enable_nginx_config
    
    # 9. 获取 SSL 证书
    get_ssl_certificate
    
    # 10. 设置自动续期
    setup_auto_renew
    
    # 11. 打印总结
    print_summary
}

# 运行主函数
main "$@"