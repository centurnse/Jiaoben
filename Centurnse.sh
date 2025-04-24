#!/bin/bash

# ======================
# 视觉样式定义
# ======================
ESC="\033["
RESET="${ESC}0m"
BOLD="${ESC}1m"
CYAN="${ESC}38;5;51m"
MAGENTA="${ESC}38;5;200m"
BLUE="${ESC}38;5;27m"
YELLOW="${ESC}38;5;226m"
GREEN="${ESC}38;5;46m"
RED="${ESC}38;5;196m"
WHITE="${ESC}38;5;255m"
GRADIENT_START="${ESC}38;5;33m"
GRADIENT_END="${ESC}38;5;93m"
BG_DARK="${ESC}48;5;232m"

# 生成渐变色文本
gradient_text() {
    local text="Powered By BitsFlowCloud"
    local length=${#text}
    local gradient=""
    
    for ((i=0; i<length; i++)); do
        r=$(( 33 + (93-33)*i/length ))
        gradient+="${ESC}38;5;${r}m${text:$i:1}"
    done
    echo -e "${BOLD}${gradient}${RESET}"
}

# 打印现代风格标题
print_header() {
    clear
    echo -e "${BG_DARK}${WHITE}"
    echo " _________________________________________________________________"
    echo "|                                                                 |"
    echo -n "|   "
    gradient_text
    echo -e "   |"
    echo "|_____________________________________________________________${RESET}${BG_DARK}_${RESET}|"
    echo -e "${RESET}\n"
}

# ======================
# 系统初始化检查
# ======================
[ "$(id -u)" != "0" ] && { 
    echo -e "\n${RED}${BOLD}✗ 必须使用root权限运行此脚本${RESET}" 
    exit 1
}

# ======================
# 全局变量定义
# ======================
declare -A PKGMAP=(
    ["ubuntu"]="apt-get"
    ["debian"]="apt-get"
    ["centos"]="yum"
    ["rhel"]="yum"
    ["fedora"]="dnf"
    ["arch"]="pacman"
    ["opensuse"]="zypper"
)
DISTRO=$(awk -F= '/^ID=/{print $2}' /etc/os-release | tr -d '"')
PM=${PKGMAP[$DISTRO]}
total_steps=8
current_step=1

# ======================
# 进度显示系统
# ======================
show_progress() {
    print_header
    echo -e "${BOLD}${WHITE}▏${CYAN} 当前进度: ${GREEN}${current_step}/${total_steps}${RESET}"
    echo -e "${BLUE}▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔${RESET}"
    
    # 动态进度显示
    declare -a steps=(
        "系统更新       [${YELLOW}基础环境准备${RESET}]"
        "组件安装       [${CYAN}工具链部署${RESET}]" 
        "时间校准       [${MAGENTA}系统时钟管理${RESET}]"
        "防火墙配置     [${RED}网络安全加固${RESET}]"
        "SWAP优化      [${GREEN}内存管理${RESET}]"
        "网络参数调优   [${BLUE}性能优化${RESET}]"
        "日志清理设置   [${WHITE}存储管理${RESET}]"
        "SSH安全配置   [${YELLOW}访问控制${RESET}]"
    )
    
    for ((i=0; i<total_steps; i++)); do
        if (( i < current_step-1 )); then
            echo -e "${GREEN}✓ ${steps[$i]}${RESET}"
        elif (( i == current_step-1 )); then
            echo -e "${WHITE}◼ ${steps[$i]}${RESET}"
        else
            echo -e "${WHITE}◻ ${steps[$i]}${RESET}"
        fi
    done
    
    # 动态倒计时
    echo -e "\n${BOLD}${RED}⏳ 下一阶段准备中..."
    for i in {3..1}; do
        echo -ne "${RED}${BOLD}剩余等待时间: ${i}s${RESET}\r"
        sleep 1
    done
    ((current_step++))
}

# ======================
# 功能模块实现
# ======================

# 系统更新
update_system() {
    case $DISTRO in
        ubuntu|debian)
            $PM update -qq > /dev/null
            $PM upgrade -yqq > /dev/null
            ;;
        centos|rhel|fedora)
            $PM update -y --quiet > /dev/null
            ;;
        arch)
            pacman -Syu --noconfirm --needed --quiet > /dev/null
            ;;
        opensuse)
            zypper --non-interactive refresh > /dev/null
            zypper --non-interactive update -y > /dev/null
            ;;
    esac
}

# 组件安装
install_components() {
    local components=(vim curl wget mtr sudo ufw)
    case $DISTRO in
        ubuntu|debian)
            $PM install -yqq "${components[@]}" > /dev/null
            ;;
        centos|rhel|fedora)
            $PM install -y -q epel-release > /dev/null
            $PM install -y -q "${components[@]}" > /dev/null
            ;;
        arch)
            pacman -S --noconfirm --needed --quiet "${components[@]}" > /dev/null
            ;;
        opensuse)
            zypper --non-interactive install -y "${components[@]}" > /dev/null
            ;;
    esac
}

# 时间校准
adjust_time() {
    timedatectl set-timezone Asia/Shanghai > /dev/null
    case $DISTRO in
        ubuntu|debian|centos|rhel|fedora)
            $PM install -y -q chrony > /dev/null
            systemctl enable --now chronyd > /dev/null
            chronyc makestep > /dev/null
            echo "0 * * * * chronyc makestep > /dev/null" | crontab -
            ;;
        arch|opensuse)
            timedatectl set-ntp true > /dev/null
            echo "0 * * * * timedatectl set-ntp true" | crontab -
            ;;
    esac
}

# 防火墙配置
configure_firewall() {
    ufw --force disable > /dev/null
    ufw --force reset > /dev/null
    
    # 端口放行规则
    declare -a ports=(22 80 88 443 5555 8008 32767 32768)
    for port in "${ports[@]}"; do
        ufw allow "$port"/tcp > /dev/null
    done
    
    # IP段封锁
    declare -a blocked_subnets=(
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
    
    for subnet in "${blocked_subnets[@]}"; do
        ufw deny from "$subnet" > /dev/null
    done
    
    ufw default deny incoming > /dev/null
    ufw default allow outgoing > /dev/null
    ufw --force enable > /dev/null
}

# SWAP管理
setup_swap() {
    local mem_total=$(free -m | awk '/Mem:/{print $2}')
    local disk_free=$(df -BG / | awk 'NR==2{gsub(/[^0-9]/,"",$4); print $4}')
    local swapfile="/swapfile"

    [ -f "$swapfile" ] && {
        swapoff "$swapfile" > /dev/null
        rm -f "$swapfile" > /dev/null
    }

    if (( mem_total < 512 && disk_free >= 5 )); then
        dd if=/dev/zero of="$swapfile" bs=1M count=512 status=none
    elif (( mem_total >= 512 && mem_total < 1024 && disk_free >= 8 )); then
        dd if=/dev/zero of="$swapfile" bs=1M count=1024 status=none
    elif (( mem_total >= 1024 && mem_total < 2048 && disk_free >= 10 )); then
        dd if=/dev/zero of="$swapfile" bs=1M count=1024 status=none
    else
        return 0
    fi

    chmod 600 "$swapfile" > /dev/null
    mkswap "$swapfile" > /dev/null
    swapon "$swapfile" > /dev/null
    echo "$swapfile none swap sw 0 0" >> /etc/fstab
}

# 网络优化
optimize_network() {
    cat > /etc/sysctl.d/99-network.conf <<'EOF'
# 内核基础优化
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_ecn=0
net.ipv4.tcp_frto=0
net.ipv4.tcp_mtu_probing=0
net.ipv4.tcp_rfc1337=0

# 流量控制优化
net.ipv4.tcp_sack=1
net.ipv4.tcp_fack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_adv_win_scale=1
net.ipv4.tcp_moderate_rcvbuf=1

# 内存缓冲区设置
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 16384 33554432
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192

# 拥塞控制算法
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# 网络转发配置
net.ipv4.conf.all.route_localnet=1
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
EOF
    sysctl -p /etc/sysctl.d/99-network.conf > /dev/null
}

# 日志清理
setup_logrotate() {
    cat > /etc/cron.daily/logclean <<'EOF'
#!/bin/bash
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
journalctl --vacuum-time=1d > /dev/null
EOF
    chmod +x /etc/cron.daily/logclean
}

# SSH安全配置
configure_ssh() {
    local ssh_dir="/root/.ssh"
    local auth_file="$ssh_dir/authorized_keys"

    # 目录权限管理
    [ ! -d "$ssh_dir" ] && {
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    }

    # 密钥文件管理
    [ ! -f "$auth_file" ] && {
        touch "$auth_file"
        chmod 600 "$auth_file"
    }

    # 写入公钥
    grep -q "centurnse@Centurnse-I" "$auth_file" || \
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" >> "$auth_file"

    # 配置修改
    sed -i '/^#*PasswordAuthentication/s/.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i '/^#*PubkeyAuthentication/s/.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    
    # 服务重启
    systemctl restart sshd > /dev/null
}

# ======================
# 主执行流程
# ======================
main() {
    print_header
    echo -e "${WHITE}${BOLD}▶ 初始化系统环境检测...${RESET}"
    sleep 2
    
    update_system && show_progress
    install_components && show_progress
    adjust_time && show_progress
    configure_firewall && show_progress
    setup_swap && show_progress
    optimize_network && show_progress
    setup_logrotate && show_progress
    configure_ssh && show_progress
    
    echo -e "\n${GREEN}${BOLD}✅ 所有配置已完成！${RESET}"
    echo -e "${BLUE}系统将在5秒后重启以应用所有更改...${RESET}"
    sleep 5
    reboot
}

# 执行入口
main
