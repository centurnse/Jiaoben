#!/usr/bin/env bash
set -euo pipefail
trap 'echo -e "\033[31mError at line $LINENO\033[0m"; exit 1' ERR

# 美化输出函数
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
NC='\033[0m'
sep() { printf "%s\n" "--------------------------------------------------"; }
info() { echo -e "${BLUE}[INFO] $* ${NC}"; }
success() { echo -e "${GREEN}[SUCCESS] $* ${NC}"; }
error() { echo -e "${RED}[ERROR] $* ${NC}"; exit 1; }

# 进度条函数
progress_bar() {
    for i in {3..1}; do
        printf "\r下一步将在 ${YELLOW}%s${NC} 秒后继续..." "$i"
        sleep 1
    done
    printf "\r%-40s\n" " "
}

# 检查root权限
[[ $(id -u) -ne 0 ]] && error "必须使用root权限运行脚本"

# 检测发行版
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        error "无法检测操作系统"
    fi
}
detect_os

# 1. 系统更新
update_system() {
    info "开始系统更新..."
    case $OS in
        ubuntu|debian)
            apt update >/dev/null && apt -y upgrade >/dev/null ;;
        centos|fedora|rhel)
            [ "$OS" = "centos" ] && yum -y update >/dev/null ;;
        alpine)
            apk update >/dev/null && apk upgrade >/dev/null ;;
        *)
            error "不支持的发行版: $OS" ;;
    esac
    success "系统更新完成"
    progress_bar
}

# 2. 安装必要组件
install_packages() {
    info "开始安装必要组件..."
    pkg_list="wget curl vim mtr ufw ntpdate sudo unzip lvm2"
    
    case $OS in
        ubuntu|debian)
            apt install -y $pkg_list >/dev/null ;;
        centos|fedora|rhel)
            [ "$OS" = "centos" ] && yum install -y epel-release >/dev/null
            yum install -y $pkg_list >/dev/null ;;
        alpine)
            apk add $pkg_list >/dev/null ;;
    esac
    success "组件安装完成"
    progress_bar
}

# 3. 时区设置
setup_time() {
    info "设置时区和时间同步..."
    timedatectl set-timezone Asia/Shanghai || ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    ntpdate pool.ntp.org >/dev/null
    
    # 每小时同步
    echo "0 * * * * /usr/sbin/ntpdate pool.ntp.org >/dev/null 2>&1" | crontab -
    systemctl restart cron >/dev/null 2>&1 || true
    
    success "时区设置完成"
    progress_bar
}

# 4. 防火墙设置
setup_ufw() {
    info "配置防火墙规则..."
    ufw disable >/dev/null
    
    # 添加允许规则
    for port in 22 80 88 443 5555 8008 32767 32768; do
        ufw allow ${port}/tcp >/dev/null
        ufw allow ${port}/udp >/dev/null
    done
    
    # 添加拒绝规则
    for subnet in 162.142.125.0/24 167.94.138.0/24 167.94.145.0/24 167.94.146.0/24 \
                  167.248.133.0/24 199.45.154.0/24 199.45.155.0/24 206.168.34.0/24 \
                  2602:80d:1000:b0cc:e::/80 2620:96:e000:b0cc:e::/80 \
                  2602:80d:1003::/112 2602:80d:1004::/112; do
        ufw deny from $subnet >/dev/null
    done
    
    echo "y" | ufw enable >/dev/null
    success "防火墙配置完成"
    progress_bar
}

# 5. SWAP管理
setup_swap() {
    info "配置SWAP..."
    # 检测现有SWAP
    if swapon --show | grep -q .; then
        swap_device=$(swapon --show=NAME --noheadings --raw | head -1)
        swapoff "$swap_device"
        [ -f "$swap_device" ] && rm -f "$swap_device"
        sed -i "\|^$swap_device|d" /etc/fstab
    fi

    # 计算内存和磁盘空间
    mem_total=$(free -m | awk '/Mem:/ {print $2}')
    disk_space=$(df -m / | awk 'NR==2 {print $4}')

    # 创建新SWAP
    if (( mem_total <= 1024 )) && (( disk_space >= 3072 )); then
        swap_size=512M
    elif (( mem_total > 1024 && mem_total <= 2048 )) && (( disk_space >= 10240 )); then
        swap_size=1G
    elif (( mem_total > 2048 && mem_total <= 4096 )) && (( disk_space >= 20480 )); then
        swap_size=2G
    else
        success "未创建SWAP"
        progress_bar
        return
    fi

    fallocate -l $swap_size /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    
    success "SWAP配置完成"
    progress_bar
}

# 6. 日志清理任务
setup_cleanup() {
    info "设置清理任务..."
    cat > /usr/local/bin/cleanup.sh <<'EOF'
#!/bin/bash
journalctl --vacuum-time=1d
find /var/log -type f -regex ".*\.gz$" -delete
find /var/log -type f -regex ".*\.[0-9]$" -delete
case $(id -u) in
    0) 
        [ -f /etc/debian_version ] && apt clean
        [ -f /etc/redhat-release ] && yum clean all
        [ -f /etc/alpine-release ] && apk cache clean
        ;;
esac
EOF

    chmod +x /usr/local/bin/cleanup.sh
    echo "0 0 * * * root /usr/local/bin/cleanup.sh" > /etc/cron.d/daily_cleanup
    
    success "清理任务设置完成"
    progress_bar
}

# 7. SSH配置
setup_ssh() {
    info "配置SSH..."
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    # 生成密钥
    key_file="/root/.ssh/id_ed25519.pub"
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" > $key_file
    grep -qFf $key_file /root/.ssh/authorized_keys || cat $key_file >> /root/.ssh/authorized_keys

    # 配置SSHD
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

    # 处理Ubuntu24+配置
    if [ -d /etc/ssh/sshd_config.d ]; then
        for f in /etc/ssh/sshd_config.d/*.conf; do
            [ -f "$f" ] && sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' "$f"
        done
    fi

    systemctl restart sshd >/dev/null || systemctl restart ssh >/dev/null
    
    success "SSH配置完成"
    progress_bar
}

# 主执行流程
main() {
    sep
    update_system
    install_packages
    setup_time
    setup_ufw
    setup_swap
    setup_cleanup
    setup_ssh
    sep
    success "所有配置已完成！"
}

main
