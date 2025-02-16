#!/usr/bin/env bash
set -euo pipefail
trap 'echo -e "\033[31m[ERR] 在 $LINENO 行发生错误\033[0m"; exit 1' ERR

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

display_header() {
    echo -e "${CYAN}"
    echo "=================================================="
    echo " 自动化系统优化脚本"
    echo "=================================================="
    echo -e "${NC}"
}

display_progress() {
    display_header
    echo -e "${GREEN}▶ 当前进度：$current_step/$total_steps ${NC}"
    echo -e "${BLUE}▷ 正在执行：${steps_list[$current_step-1]}${NC}"
    
    if (( current_step < total_steps )); then
        echo -e "${YELLOW}▷ 下一步操作：${steps_list[$current_step]}${NC}"
    else
        echo -e "${YELLOW}▷ 下一步操作：完成所有配置${NC}"
    fi
    echo -e "${CYAN}--------------------------------------------------${NC}"
}

progress_bar() {
    echo -n "进度指示："
    for i in {1..3}; do
        echo -n "▉"
        sleep 0.5
    done
    echo -e "\n"
}

success() {
    echo -e "${GREEN}[✓] $* ${NC}"
    sleep 0.3
}

# 检查root权限
if [[ $(id -u) -ne 0 ]]; then
    echo -e "${RED}错误：必须使用root权限运行本脚本${NC}"
    exit 1
fi

# 检测发行版
detect_os() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        OS=$ID
    else
        echo -e "${RED}错误：无法检测操作系统类型${NC}"
        exit 1
    fi
}

# 1. 系统更新
update_system() {
    ((current_step++))
    display_progress
    case $OS in
        ubuntu|debian)
            echo -e "${BLUE}[信息] 正在更新APT源...${NC}"
            DEBIAN_FRONTEND=noninteractive apt update -qq
            echo -e "${BLUE}[信息] 正在升级系统...${NC}"
            DEBIAN_FRONTEND=noninteractive apt -y upgrade -qq
            ;;
        centos|fedora|rhel)
            echo -e "${BLUE}[信息] 正在更新YUM包...${NC}"
            yum -y -q update
            ;;
        alpine)
            echo -e "${BLUE}[信息] 正在更新APK包...${NC}"
            apk -q update
            apk -q upgrade
            ;;
        *)
            echo -e "${RED}错误：不支持的发行版 $OS${NC}"
            exit 1
            ;;
    esac
    success "系统更新完成"
    progress_bar
}

# 2. 安装必要组件
install_packages() {
    ((current_step++))
    display_progress
    pkg_list="wget curl vim mtr ufw ntpdate sudo unzip lvm2"
    
    case $OS in
        ubuntu|debian)
            echo -e "${BLUE}[信息] 正在安装组件...${NC}"
            DEBIAN_FRONTEND=noninteractive apt install -y -qq $pkg_list
            ;;
        centos|fedora|rhel)
            if [ "$OS" = "centos" ]; then
                yum install -y -q epel-release
            fi
            yum install -y -q $pkg_list
            ;;
        alpine)
            apk add -q $pkg_list
            ;;
    esac
    success "组件安装完成"
    progress_bar
}

# 3. 时区设置
setup_time() {
    ((current_step++))
    display_progress
    echo -e "${BLUE}[信息] 设置上海时区...${NC}"
    timedatectl set-timezone Asia/Shanghai 2>/dev/null || (
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        hwclock --systohc
    )
    
    echo -e "${BLUE}[信息] 同步网络时间...${NC}"
    ntpdate pool.ntp.org
    
    echo -e "${BLUE}[信息] 设置定时同步任务...${NC}"
    echo "0 * * * * /usr/sbin/ntpdate pool.ntp.org >/dev/null 2>&1" | crontab -
    
    if systemctl is-active cron >/dev/null 2>&1; then
        systemctl restart cron
    else
        systemctl start cron
    fi
    
    success "时区设置完成"
    progress_bar
}

# 4. 防火墙设置
setup_ufw() {
    ((current_step++))
    display_progress
    echo -e "${BLUE}[信息] 初始化防火墙配置...${NC}"
    ufw --force disable
    
    ports=(22 80 88 443 5555 8008 32767 32768)
    for port in "${ports[@]}"; do
        ufw allow ${port}/tcp
        ufw allow ${port}/udp
    done
    
    deny_list=(
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
    
    for subnet in "${deny_list[@]}"; do
        ufw deny from "$subnet"
    done
    
    echo "y" | ufw enable
    success "防火墙配置完成"
    progress_bar
}

# 5. SWAP管理
setup_swap() {
    ((current_step++))
    display_progress
    echo -e "${BLUE}[信息] 检测现有SWAP...${NC}"
    if swapon --show | grep -q .; then
        swap_device=$(swapon --show=NAME --noheadings --raw | head -1)
        echo -e "${YELLOW}[警告] 发现现有SWAP: $swap_device${NC}"
        swapoff "$swap_device"
        [ -f "$swap_device" ] && rm -f "$swap_device"
        sed -i "\|^$swap_device|d" /etc/fstab
    fi

    mem_total=$(free -m | awk '/Mem:/ {print $2}')
    disk_space=$(df -m / | awk 'NR==2 {print $4}')

    echo -e "内存总量: ${mem_total}MB"
    echo -e "可用空间: ${disk_space}MB"

    swap_size=""
    if (( mem_total <= 1024 )) && (( disk_space >= 3072 )); then
        swap_size=512M
    elif (( mem_total > 1024 && mem_total <= 2048 )) && (( disk_space >= 10240 )); then
        swap_size=1G
    elif (( mem_total > 2048 && mem_total <= 4096 )) && (( disk_space >= 20480 )); then
        swap_size=2G
    else
        echo -e "${YELLOW}[信息] 当前配置无需创建SWAP${NC}"
        progress_bar
        return
    fi

    echo -e "${BLUE}[信息] 创建 ${swap_size} SWAP文件...${NC}"
    fallocate -l $swap_size /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    
    success "SWAP配置完成"
    progress_bar
}

# 6. 日志清理任务
setup_cleanup() {
    ((current_step++))
    display_progress
    echo -e "${BLUE}[信息] 创建清理脚本...${NC}"
    cat > /usr/local/bin/cleanup.sh <<'EOF'
#!/bin/bash
journalctl --vacuum-time=1d
find /var/log -name "*.gz" -delete
find /var/log -name "*.old" -delete
find /var/log -name "*.log.*" -delete

# 清理包缓存
if [ -f /etc/debian_version ]; then
    apt clean
elif [ -f /etc/redhat-release ]; then
    yum clean all
elif [ -f /etc/alpine-release ]; then
    apk cache clean
fi
EOF

    chmod +x /usr/local/bin/cleanup.sh
    echo "0 0 * * * root /usr/local/bin/cleanup.sh" > /etc/cron.d/daily_cleanup
    chmod 644 /etc/cron.d/daily_cleanup
    
    success "日志清理任务设置完成"
    progress_bar
}

# 7. SSH配置
setup_ssh() {
    ((current_step++))
    display_progress
    echo -e "${BLUE}[信息] 配置SSH密钥...${NC}"
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    key_content="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I"
    key_file="/root/.ssh/id_ed25519.pub"
    
    echo "$key_content" > $key_file
    if ! grep -qF "$key_content" /root/.ssh/authorized_keys; then
        cat $key_file >> /root/.ssh/authorized_keys
    fi

    echo -e "${BLUE}[信息] 更新SSH配置...${NC}"
    sed -i 's/^#*\(PasswordAuthentication\s*\).*$/\1no/' /etc/ssh/sshd_config
    sed -i 's/^#*\(PubkeyAuthentication\s*\).*$/\1yes/' /etc/ssh/sshd_config

    # 处理Ubuntu24+配置
    if [ -d /etc/ssh/sshd_config.d ]; then
        for f in /etc/ssh/sshd_config.d/*.conf; do
            [ -f "$f" ] && sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' "$f"
        done
    fi

    echo -e "${BLUE}[信息] 重启SSH服务...${NC}"
    if systemctl is-active sshd >/dev/null; then
        systemctl restart sshd
    elif systemctl is-active ssh >/dev/null; then
        systemctl restart ssh
    else
        echo -e "${YELLOW}[警告] 未找到运行的SSH服务${NC}"
    fi
    
    success "SSH配置完成"
    progress_bar
}

# 8. 网络优化
setup_network() {
    ((current_step++))
    display_progress
    echo -e "${BLUE}[信息] 优化TCP网络参数...${NC}"
    declare -A sysctl_params=(
        ["net.ipv4.tcp_no_metrics_save"]="1"
        ["net.ipv4.tcp_ecn"]="0"
        ["net.ipv4.tcp_frto"]="0"
        ["net.ipv4.tcp_mtu_probing"]="0"
        ["net.ipv4.tcp_rfc1337"]="0"
        ["net.ipv4.tcp_sack"]="1"
        ["net.ipv4.tcp_fack"]="1"
        ["net.ipv4.tcp_window_scaling"]="1"
        ["net.ipv4.tcp_adv_win_scale"]="1"
        ["net.ipv4.tcp_moderate_rcvbuf"]="1"
        ["net.core.rmem_max"]="33554432"
        ["net.core.wmem_max"]="33554432"
        ["net.ipv4.tcp_rmem"]="4096 87380 33554432"
        ["net.ipv4.tcp_wmem"]="4096 16384 33554432"
        ["net.ipv4.udp_rmem_min"]="8192"
        ["net.ipv4.udp_wmem_min"]="8192"
        ["net.core.default_qdisc"]="fq"
        ["net.ipv4.tcp_congestion_control"]="bbr"
        ["net.ipv4.conf.all.route_localnet"]="1"
        ["net.ipv4.ip_forward"]="1"
        ["net.ipv4.conf.all.forwarding"]="1"
        ["net.ipv4.conf.default.forwarding"]="1"
    )

    for param in "${!sysctl_params[@]}"; do
        sed -i "/^${param}\s*=/d" /etc/sysctl.conf
        echo "${param}=${sysctl_params[$param]}" >> /etc/sysctl.conf
    done

    echo -e "${BLUE}[信息] 应用新的内核参数...${NC}"
    if ! sysctl -p; then
        echo -e "${RED}[错误] 应用sysctl配置失败${NC}"
        exit 1
    fi
    sysctl --system >/dev/null
    
    success "网络优化完成"
    progress_bar
}

# 主流程
main() {
    detect_os
    update_system
    install_packages
    setup_time
    setup_ufw
    setup_swap
    setup_cleanup
    setup_ssh
    setup_network
    
    display_header
    echo -e "${GREEN}✔ 所有配置已完成！${NC}"
    echo -e "${CYAN}==================================================${NC}"
}

main
