#!/usr/bin/env bash
set -eo pipefail
trap 'echo -e "\033[31m[ERR] 在 $LINENO 行执行失败 | 最后命令：$BASH_COMMAND\033[0m"; exit 1' ERR

# ==================== 配置部分 ====================
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
NC='\033[0m'

# ==================== 功能函数 ====================
display_progress() {
    clear
    echo -e "${CYAN}=================================================="
    echo " 自动化系统优化脚本"
    echo -e "==================================================${NC}"
    echo -e "${GREEN}▶ 当前进度：$1/$2"
    echo -e "${BLUE}▷ 正在执行：${3}"
    echo -e "${YELLOW}▷ 后续任务：${4}"
    echo -e "${CYAN}==================================================${NC}"
    echo
}

progress_countdown() {
    for i in {3..1}; do
        echo -ne "${YELLOW}倒计时：${i} 秒\033[0K\r"
        sleep 1
    done
    echo -e "${NC}"
}

# ==================== 核心功能 ====================
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO=$ID
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO="centos"
    elif [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
    else
        echo -e "${RED}错误：无法检测Linux发行版" >&2
        exit 1
    fi
}

system_update() {
    case $DISTRO in
        ubuntu|debian)
            DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 -qq update >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 -qq -y upgrade >/dev/null 2>&1
            ;;
        centos|fedora|rhel)
            yum -y -q update >/dev/null 2>&1
            ;;
        alpine)
            apk -q update >/dev/null 2>&1
            apk -q upgrade >/dev/null 2>&1
            ;;
        *) exit 1 ;;
    esac
}

install_essentials() {
    pkg_list="wget curl vim mtr ufw ntpdate sudo unzip lvm2"
    
    case $DISTRO in
        ubuntu|debian)
            DEBIAN_FRONTEND=noninteractive apt-get -qq -y install $pkg_list >/dev/null 2>&1
            ;;
        centos|fedora|rhel)
            [[ "$DISTRO" == "centos" ]] && yum -y -q install epel-release >/dev/null 2>&1
            yum -y -q install $pkg_list >/dev/null 2>&1
            ;;
        alpine)
            apk add -q $pkg_list >/dev/null 2>&1
            ;;
    esac
}

configure_timezone() {
    timedatectl set-timezone Asia/Shanghai 2>/dev/null || ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    ntpdate -u pool.ntp.org >/dev/null 2>&1
    echo "0 * * * * /usr/sbin/ntpdate pool.ntp.org >/dev/null" | crontab -
}

setup_firewall() {
    ufw --force reset >/dev/null 2>&1
    ufw disable >/dev/null 2>&1

    for port in 22 80 88 443 5555 8008 32767 32768; do
        ufw allow $port/tcp >/dev/null 2>&1
        ufw allow $port/udp >/dev/null 2>&1
    done

    for subnet in \
        162.142.125.0/24 \
        167.94.138.0/24 \
        167.94.145.0/24 \
        167.94.146.0/24 \
        167.248.133.0/24 \
        199.45.154.0/24 \
        199.45.155.0/24 \
        206.168.34.0/24 \
        2602:80d:1000:b0cc:e::/80 \
        2620:96:e000:b0cc:e::/80 \
        2602:80d:1003::/112 \
        2602:80d:1004::/112
    do
        ufw deny from $subnet >/dev/null 2>&1
    done

    echo "y" | ufw enable >/dev/null 2>&1
}

manage_swap() {
    if swapon --show | grep -q .; then
        swap_device=$(swapon --show=NAME --noheadings --raw | head -1)
        swapoff "$swap_device" >/dev/null 2>&1
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
        return
    fi

    fallocate -l $swap_size /swapfile >/dev/null 2>&1
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile >/dev/null 2>&1
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
}

configure_logclean() {
    cat > /usr/local/bin/logclean <<'EOF'
#!/bin/bash
journalctl --vacuum-time=1d
find /var/log -type f \( -name "*.gz" -o -name "*.old" -o -name "*.log.*" \) -delete
[[ -f /etc/debian_version ]] && apt clean
[[ -f /etc/redhat-release ]] && yum clean all
[[ -f /etc/alpine-release ]] && apk cache clean
EOF

    chmod +x /usr/local/bin/logclean >/dev/null 2>&1
    echo "0 0 * * * root /usr/local/bin/logclean" > /etc/cron.d/daily_logclean
    chmod 644 /etc/cron.d/daily_logclean
}

harden_ssh() {
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

    systemctl restart sshd >/dev/null 2>&1 || systemctl restart ssh >/dev/null 2>&1
}

optimize_network() {
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

    sysctl -p >/dev/null 2>&1
}

# ==================== 主流程 ====================
main() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}必须使用root权限运行" >&2; exit 1; }

    local total_steps=8
    local current_step=0
    local steps=(
        "系统更新"
        "安装组件"
        "时区设置"
        "防火墙配置"
        "SWAP管理"
        "日志清理"
        "SSH配置"
        "网络优化"
    )

    detect_distro

    for step in "${!steps[@]}"; do
        current_step=$((step+1))
        next_step=$((current_step+1))
        display_progress $current_step $total_steps "${steps[$step]}" "${steps[$next_step]:-完成}"
        
        case $current_step in
            1) system_update ;;
            2) install_essentials ;;
            3) configure_timezone ;;
            4) setup_firewall ;;
            5) manage_swap ;;
            6) configure_logclean ;;
            7) harden_ssh ;;
            8) optimize_network ;;
        esac

        echo -e "${GREEN}[✓] ${steps[$step]} 完成"
        progress_countdown
    done

    echo -e "\n${CYAN}=================================================="
    echo -e "${GREEN}✔ 所有优化配置已完成！"
    echo -e "${CYAN}==================================================${NC}"
}

main "$@"
