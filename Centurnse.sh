#!/usr/bin/env bash
set -eo pipefail
trap 'echo -e "\033[31m[错误] 在 $LINENO 行执行失败\033[0m"; exit 1' ERR

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
NC='\033[0m'

# 进度跟踪
total_steps=8
current_step=0
steps_list=(
    "系统更新"
    "安装组件"
    "时区设置"
    "防火墙配置"
    "SWAP管理"
    "日志清理"
    "SSH配置"
    "网络优化"
)

display_progress() {
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${GREEN}▶ 当前进度：$current_step/$total_steps ${NC}"
    echo -e "${BLUE}▷ 正在执行：${steps_list[$current_step-1]}${NC}"
    
    if (( current_step < total_steps )); then
        echo -e "${YELLOW}▷ 后续任务：${steps_list[$current_step]}${NC}"
    else
        echo -e "${YELLOW}▷ 后续任务：完成所有配置${NC}"
    fi
    echo -e "${CYAN}==================================================${NC}\n"
}

progress_countdown() {
    echo -ne "${YELLOW}倒计时："
    for i in {3..1}; do
        echo -ne " $i 秒"
        sleep 1
        echo -ne "\033[2K\r"
    done
    echo -e "${NC}"
}

success_alert() {
    echo -e "${GREEN}[✓] $* ${NC}"
}

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}错误：必须使用root权限运行本脚本${NC}"; exit 1; }

# 检测发行版
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO=$ID
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO="centos"
    elif [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
    else
        echo -e "${RED}错误：无法检测Linux发行版${NC}"
        exit 1
    fi
    echo -e "${BLUE}[信息] 检测到系统：$DISTRO ${NC}"
}

# 1. 系统更新
system_update() {
    ((current_step++))
    display_progress
    case $DISTRO in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get -qq update
            apt-get -qq -y upgrade
            ;;
        centos|fedora|rhel)
            yum -y -q update
            ;;
        alpine)
            apk -q update
            apk -q upgrade
            ;;
        *)
            echo -e "${RED}错误：不支持的发行版${NC}"
            exit 1
            ;;
    esac
    success_alert "系统更新完成"
    progress_countdown
}

# 2. 安装必要组件
install_essentials() {
    ((current_step++))
    display_progress
    case $DISTRO in
        ubuntu|debian)
            apt-get -qq -y install wget curl vim mtr ufw ntpdate sudo unzip lvm2
            ;;
        centos|fedora|rhel)
            yum -y -q install wget curl vim mtr ufw ntpdate sudo unzip lvm2
            systemctl enable --now ufw
            ;;
        alpine)
            apk add -q wget curl vim mtr ufw ntpdate sudo unzip lvm2
            rc-service ufw start
            ;;
    esac
    success_alert "组件安装完成"
    progress_countdown
}

# 3. 时区设置
configure_timezone() {
    ((current_step++))
    display_progress
    # 设置时区
    if command -v timedatectl &>/dev/null; then
        timedatectl set-timezone Asia/Shanghai
    else
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        hwclock --systohc
    fi
    
    # 时间同步
    ntpdate -u pool.ntp.org
    # 定时任务
    echo "0 * * * * /usr/sbin/ntpdate pool.ntp.org >/dev/null 2>&1" | crontab -
    
    success_alert "时区设置完成"
    progress_countdown
}

# 4. 防火墙配置
setup_firewall() {
    ((current_step++))
    display_progress
    # 重置防火墙
    ufw --force reset
    
    # 放行端口
    ports=(22 80 88 443 5555 8008 32767 32768)
    for port in "${ports[@]}"; do
        ufw allow $port/tcp
        ufw allow $port/udp
    done
    
    # 封禁子网
    deny_subnets=(
        162.142.125.0/24
        167.94.138.0/24
        167.94.145.0/24
        167.94.146.0/24
        167.248.133.0/24
        199.45.154.0/24
        199.45.155.0/24
        206.168.34.0/24
        2602:80d:1000:b0cc:e::/80
        2620:96:e000:b0cc:e::/80
        2602:80d:1003::/112
        2602:80d:1004::/112
    )
    for subnet in "${deny_subnets[@]}"; do
        ufw deny from "$subnet"
    done
    
    # 启用防火墙
    yes | ufw enable
    success_alert "防火墙配置完成"
    progress_countdown
}

# 5. SWAP管理
manage_swap() {
    ((current_step++))
    display_progress
    # 移除现有SWAP
    if swapon --show | grep -q .; then
        swap_device=$(swapon --show=NAME --noheadings --raw | head -1)
        swapoff "$swap_device"
        [[ -f "$swap_device" ]] && rm -f "$swap_device"
        sed -i "\|^$swap_device|d" /etc/fstab
    fi

    # 计算内存和磁盘
    mem_total=$(free -m | awk '/Mem:/ {print $2}')
    disk_space=$(df -m / | awk 'NR==2 {print $4}')

    # 创建新SWAP
    if (( mem_total <= 1024 && disk_space >= 3072 )); then
        swap_size=512M
    elif (( mem_total > 1024 && mem_total <= 2048 && disk_space >= 10240 )); then
        swap_size=1G
    elif (( mem_total > 2048 && mem_total <= 4096 && disk_space >= 20480 )); then
        swap_size=2G
    else
        success_alert "跳过SWAP配置"
        progress_countdown
        return
    fi

    # 创建swapfile
    fallocate -l "$swap_size" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    
    success_alert "SWAP配置完成"
    progress_countdown
}

# 6. 日志清理
configure_logclean() {
    ((current_step++))
    display_progress
    # 创建清理脚本
    cat > /usr/local/bin/logclean <<'EOF'
#!/bin/bash
journalctl --vacuum-time=1d
find /var/log -type f \( -name "*.gz" -o -name "*.old" -o -name "*.log.*" \) -delete
# 清理包缓存
if [[ -f /etc/debian_version ]]; then
    apt-get clean
elif [[ -f /etc/redhat-release ]]; then
    yum clean all
elif [[ -f /etc/alpine-release ]]; then
    apk cache clean
fi
EOF

    chmod +x /usr/local/bin/logclean
    # 设置定时任务
    echo "0 0 * * * root /usr/local/bin/logclean" > /etc/cron.d/daily_logclean
    chmod 0644 /etc/cron.d/daily_logclean
    
    success_alert "日志清理配置完成"
    progress_countdown
}

# 7. SSH加固
harden_ssh() {
    ((current_step++))
    display_progress
    # 创建.ssh目录
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    
    # 写入公钥
    pubkey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I"
    keyfile="/root/.ssh/authorized_keys"
    
    if ! grep -q "$pubkey" "$keyfile" 2>/dev/null; then
        echo "$pubkey" >> "$keyfile"
    fi
    chmod 600 "$keyfile"

    # 修改SSH配置
    sshd_config="/etc/ssh/sshd_config"
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"

    # 处理Ubuntu 24配置片段
    if [[ -d /etc/ssh/sshd_config.d ]]; then
        for f in /etc/ssh/sshd_config.d/*.conf; do
            [[ -f "$f" ]] && sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' "$f"
        done
    fi

    # 重启SSH服务
    if systemctl is-active sshd &>/dev/null; then
        systemctl restart sshd
    elif systemctl is-active ssh &>/dev/null; then
        systemctl restart ssh
    fi
    
    success_alert "SSH加固完成"
    progress_countdown
}

# 8. 网络优化
optimize_network() {
    ((current_step++))
    display_progress
    # TCP优化参数
    cat >> /etc/sysctl.conf <<'EOF'
# TCP优化
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_frto = 0
net.ipv4.tcp_mtu_probing = 0
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 开启转发
net.ipv4.conf.all.route_localnet = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
EOF

    # 应用配置
    sysctl -p &>/dev/null
    sysctl --system &>/dev/null
    success_alert "网络优化完成"
    progress_countdown
}

# 主执行流程
main() {
    detect_distro
    system_update
    install_essentials
    configure_timezone
    setup_firewall
    manage_swap
    configure_logclean
    harden_ssh
    optimize_network
    
    echo -e "\n${GREEN}✔ 所有优化配置已完成！${NC}"
    echo -e "${CYAN}==================================================${NC}"
}

main "$@"
