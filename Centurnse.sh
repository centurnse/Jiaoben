#!/usr/bin/env bash
set -eo pipefail
trap 'echo -e "\033[31m[ERR] 在 $LINENO 行执行失败 | 最后命令：$BASH_COMMAND\033[0m"; exit 1' ERR

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
    (( current_step < total_steps )) && echo -e "${YELLOW}▷ 后续任务：${steps_list[$current_step]}${NC}" || echo -e "${YELLOW}▷ 后续任务：完成所有配置${NC}"
    echo -e "${CYAN}==================================================${NC}\n"
}

progress_countdown() {
    for i in {3..1}; do
        echo -ne "${YELLOW}倒计时：${i} 秒\033[0K\r${NC}"
        sleep 1
    done
    echo
}

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}错误：必须使用root权限运行本脚本${NC}"; exit 1; }

# 系统检测
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
}

# 1. 系统更新
system_update() {
    ((current_step++))
    display_progress
    
    case $DISTRO in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get -o DPkg::Lock::Timeout=120 -qq update >/dev/null
            apt-get -o DPkg::Lock::Timeout=600 -qq -y upgrade >/dev/null
            ;;
        centos|fedora|rhel)
            yum -y -q update >/dev/null
            ;;
        alpine)
            apk -q update >/dev/null
            apk -q upgrade >/dev/null
            ;;
        *) exit 1 ;;
    esac
    
    echo -e "${GREEN}[✓] 系统更新完成${NC}"
    progress_countdown
}

# 2. 安装组件
install_essentials() {
    ((current_step++))
    display_progress
    
    pkg_list="wget curl vim mtr ufw ntpdate sudo unzip lvm2"
    
    case $DISTRO in
        ubuntu|debian)
            apt-get -qq -y install $pkg_list >/dev/null
            ;;
        centos|fedora|rhel)
            [[ "$DISTRO" == "centos" ]] && yum -y -q install epel-release >/dev/null
            yum -y -q install $pkg_list >/dev/null
            ;;
        alpine)
            apk add -q $pkg_list >/dev/null
            ;;
    esac
    
    echo -e "${GREEN}[✓] 组件安装完成${NC}"
    progress_countdown
}

# 3. 时区设置
configure_timezone() {
    ((current_step++))
    display_progress
    
    timedatectl set-timezone Asia/Shanghai 2>/dev/null || ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    ntpdate -u pool.ntp.org >/dev/null
    echo "0 * * * * /usr/sbin/ntpdate pool.ntp.org >/dev/null 2>&1" | crontab -
    
    echo -e "${GREEN}[✓] 时区设置完成${NC}"
    progress_countdown
}

# 4. 防火墙配置
setup_firewall() {
    ((current_step++))
    display_progress
    
    ufw --force reset >/dev/null
    ufw disable >/dev/null
    
    ports=(22 80 88 443 5555 8008 32767 32768)
    for port in "${ports[@]}"; do
        ufw allow $port/tcp >/dev/null
        ufw allow $port/udp >/dev/null
    done
    
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
        ufw deny from "$subnet" >/dev/null
    done
    
    echo "y" | ufw enable >/dev/null
    
    echo -e "${GREEN}[✓] 防火墙配置完成${NC}"
    progress_countdown
}

# 5. SWAP管理
manage_swap() {
    ((current_step++))
    display_progress
    
    if swapon --show | grep -q .; then
        swap_device=$(swapon --show=NAME --noheadings --raw | head -1)
        swapoff "$swap_device"
        [[ -f "$swap_device" ]] && rm -f "$swap_device"
        sed -i "\|^$swap_device|d" /etc/fstab
    fi

    mem_total=$(free -m | awk '/Mem:/ {print $2}')
    disk_space=$(df -m / | awk 'NR==2 {print $4}')

    if (( mem_total <= 1024 && disk_space >= 3072 )); then
        swap_size=512M
    elif (( mem_total > 1024 && mem_total <= 2048 && disk_space >= 10240 )); then
        swap_size=1G
    elif (( mem_total > 2048 && mem_total <= 4096 && disk_space >= 20480 )); then
        swap_size=2G
    else
        echo -e "${GREEN}[✓] 跳过SWAP配置${NC}"
        progress_countdown
        return
    fi

    fallocate -l "$swap_size" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    
    echo -e "${GREEN}[✓] SWAP配置完成${NC}"
    progress_countdown
}

# 6. 日志清理
configure_logclean() {
    ((current_step++))
    display_progress
    
    cat > /usr/local/bin/logclean <<'EOF'
#!/bin/bash
journalctl --vacuum-time=1d
find /var/log -type f \( -name "*.gz" -o -name "*.old" -o -name "*.log.*" \) -delete
[[ -f /etc/debian_version ]] && apt clean
[[ -f /etc/redhat-release ]] && yum clean all
[[ -f /etc/alpine-release ]] && apk cache clean
EOF

    chmod +x /usr/local/bin/logclean
    echo "0 0 * * * root /usr/local/bin/logclean >/dev/null" > /etc/cron.d/daily_logclean
    
    echo -e "${GREEN}[✓] 日志清理配置完成${NC}"
    progress_countdown
}

# 7. SSH加固
harden_ssh() {
    ((current_step++))
    display_progress
    
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

    if [[ -d /etc/ssh/sshd_config.d ]]; then
        for f in /etc/ssh/sshd_config.d/*.conf; do
            [[ -f "$f" ]] && sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' "$f"
        done
    fi

    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
    
    echo -e "${GREEN}[✓] SSH加固完成${NC}"
    progress_countdown
}

# 8. 网络优化
optimize_network() {
    ((current_step++))
    display_progress
    
    cat >> /etc/sysctl.conf <<'EOF'
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_ecn=0
net.ipv4.tcp_frto=0
net.ipv4.tcp_mtu_probing=0
net.ipv4.tcp_rfc1337=0
net.ipv4.tcp_sack=1
net.ipv4.tcp_fack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_adv_win_scale=1
net.ipv4.tcp_moderate_rcvbuf=1
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 16384 33554432
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.conf.all.route_localnet=1
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
EOF

    sysctl -p >/dev/null
    
    echo -e "${GREEN}[✓] 网络优化完成${NC}"
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
