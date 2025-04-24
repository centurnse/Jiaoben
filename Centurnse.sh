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
BG_DARK="${ESC}48;5;232m"

# ======================
# 标题生成函数
# ======================
print_header() {
    clear
    local title="Powered By BitsFlowCloud"
    local title_length=${#title}
    local total_width=56
    local padding=$(( (total_width - title_length) / 2 ))
    
    # 构建渐变标题
    local gradient=""
    for ((i=0; i<title_length; i++)); do
        color_code=$(( 33 + (93-33)*i/title_length ))
        gradient+="${ESC}38;5;${color_code}m${title:$i:1}"
    done

    echo -e "${BG_DARK}${WHITE}"
    echo " _________________________________________________________________"
    echo "|                                                                 |"
    printf "|%${padding}s${gradient}%$((total_width - title_length - padding))s${WHITE}|\n" "" ""
    echo "|_______________________________________________________________${RESET}${BG_DARK}|${RESET}"
    echo -e "\n${BOLD}${WHITE}系统初始化检测通过 ➤ 开始自动化配置流程${RESET}\n"
}

# ======================
# 进度显示函数
# ======================
show_progress() {
    print_header
    
    case $current_step in
        1) desc="正在更新软件源数据..." ;;
        2) desc="安装系统工具套件..." ;;
        3) desc="配置时区与时间同步..." ;;
        4) desc="设置防火墙规则..." ;;
        5) desc="优化SWAP配置..." ;; 
        6) desc="调整网络参数..." ;;
        7) desc="部署日志清理方案..." ;;
        8) desc="强化SSH安全配置..." ;;
    esac

    echo -e "${BOLD}${WHITE}▛${BLUE} 阶段 ${current_step}/8 ${WHITE}» ${CYAN}${desc}${RESET}"
    echo -e "${BLUE}▌${RESET}"
    
    # 显示当前步骤详情
    case $current_step in
        1) echo -e "${YELLOW}» 正在刷新软件仓库索引...${RESET}" ;;
        2) echo -e "${YELLOW}» 正在安装: vim curl wget mtr sudo ufw...${RESET}" ;;
        3) echo -e "${YELLOW}» 设置时区为Asia/Shanghai...${RESET}" ;;
        4) echo -e "${YELLOW}» 放行端口: 22,80,88,443,5555,8008,32767,32768${RESET}" ;;
        5) echo -e "${YELLOW}» 根据内存大小自动配置SWAP...${RESET}" ;;
        6) echo -e "${YELLOW}» 优化TCP/IP网络参数...${RESET}" ;;
        7) echo -e "${YELLOW}» 配置每日日志清理任务...${RESET}" ;;
        8) echo -e "${YELLOW}» 禁用密码登录，启用密钥认证...${RESET}" ;;
    esac
    
    echo -e "${BLUE}▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔${RESET}"
}

# ======================
# 系统初始化检查
# ======================
[ "$(id -u)" != "0" ] && { 
    echo -e "\n${RED}${BOLD}✗ 必须使用root权限运行此脚本${RESET}" 
    exit 1
}

# ======================
# 包管理器检测
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

# ======================
# 功能模块实现
# ======================
update_system() {
    echo -e "${BLUE}[1/3]${WHITE} 刷新软件仓库索引...${RESET}"
    case $DISTRO in
        ubuntu|debian) $PM update -yqq ;;
        centos|rhel|fedora) $PM makecache --quiet ;;
        arch) pacman -Sy --noconfirm --quiet ;;
        opensuse) zypper --non-interactive refresh ;;
    esac

    echo -e "${BLUE}[2/3]${WHITE} 升级系统组件...${RESET}"
    case $DISTRO in
        ubuntu|debian) $PM upgrade -yqq ;;
        centos|rhel|fedora) $PM update -y --quiet ;;
        arch) pacman -Su --noconfirm --quiet ;;
        opensuse) zypper --non-interactive update -y ;;
    esac

    echo -e "${BLUE}[3/3]${WHITE} 清理过期软件包...${RESET}"
    case $DISTRO in
        ubuntu|debian) $PM autoremove -yqq ;;
        centos|rhel|fedora) $PM autoremove -y --quiet ;;
    esac
}

install_components() {
    local components=(vim curl wget mtr sudo ufw)
    echo -e "${GREEN}安装核心工具套件：${YELLOW}${components[*]}${RESET}"
    
    case $DISTRO in
        ubuntu|debian)
            $PM install -yqq "${components[@]}" ;;
        centos|rhel|fedora)
            $PM install -y -q epel-release
            $PM install -y -q "${components[@]}" ;;
        arch)
            pacman -S --noconfirm --quiet "${components[@]}" ;;
        opensuse)
            zypper --non-interactive install -y "${components[@]}" ;;
    esac
}

adjust_time() {
    echo -e "${CYAN}» 设置时区为Asia/Shanghai...${RESET}"
    timedatectl set-timezone Asia/Shanghai
    
    echo -e "${CYAN}» 部署时间同步服务...${RESET}"
    case $DISTRO in
        ubuntu|debian|centos|rhel|fedora)
            $PM install -y -q chrony
            systemctl enable --now chronyd
            chronyc makestep
            echo "0 * * * * chronyc makestep > /dev/null" | crontab - ;;
        arch|opensuse)
            timedatectl set-ntp true
            echo "0 * * * * timedatectl set-ntp true" | crontab - ;;
    esac
}

configure_firewall() {
    echo -e "${RED}» 初始化防火墙规则...${RESET}"
    ufw --force disable
    ufw --force reset

    declare -a ports=(22 80 88 443 5555 8008 32767 32768)
    echo -e "${YELLOW}放行端口：${WHITE}${ports[*]}${RESET}"
    for port in "${ports[@]}"; do
        ufw allow "$port"/tcp
    done

    declare -a blocked_subnets=(
        162.142.125.0/24 167.94.138.0/24 167.94.145.0/24 
        167.94.146.0/24 167.248.133.0/24 199.45.154.0/24
        199.45.155.0/24 206.168.34.0/24 2602:80d:1000:b0cc:e::/80
        2620:96:e000:b0cc:e::/80 2602:80d:1003::/112 2602:80d:1004::/112
    )
    echo -e "${RED}» 封锁高危IP段：${RESET}"
    printf "${WHITE}%s${RESET}\n" "${blocked_subnets[@]}" | column -c 80
    for subnet in "${blocked_subnets[@]}"; do
        ufw deny from "$subnet"
    done

    ufw default deny incoming
    ufw default allow outgoing
    ufw --force enable
}

setup_swap() {
    local mem_total=$(free -m | awk '/Mem:/{print $2}')
    local disk_free=$(df -BG / | awk 'NR==2{gsub(/[^0-9]/,"",$4); print $4}')
    local swapfile="/swapfile"

    [ -f "$swapfile" ] && {
        echo -e "${YELLOW}» 移除现有SWAP文件...${RESET}"
        swapoff "$swapfile"
        rm -f "$swapfile"
    }

    echo -e "${GREEN}» 内存检测：${WHITE}${mem_total}MB | ${WHITE}磁盘剩余：${disk_free}GB${RESET}"
    
    if (( mem_total < 512 && disk_free >= 5 )); then
        echo -e "${BLUE}» 创建512MB SWAP文件${RESET}"
        dd if=/dev/zero of="$swapfile" bs=1M count=512 status=none
    elif (( mem_total >= 512 && mem_total < 1024 && disk_free >= 8 )); then
        echo -e "${BLUE}» 创建1GB SWAP文件${RESET}"
        dd if=/dev/zero of="$swapfile" bs=1M count=1024 status=none
    elif (( mem_total >= 1024 && mem_total < 2048 && disk_free >= 10 )); then
        echo -e "${BLUE}» 创建1GB SWAP文件${RESET}"
        dd if=/dev/zero of="$swapfile" bs=1M count=1024 status=none
    else
        echo -e "${CYAN}» 跳过SWAP设置${RESET}"
        return 0
    fi

    chmod 600 "$swapfile"
    mkswap "$swapfile"
    swapon "$swapfile"
    echo "$swapfile none swap sw 0 0" >> /etc/fstab
}

optimize_network() {
    echo -e "${MAGENTA}» 应用网络性能优化参数${RESET}"
    cat > /etc/sysctl.d/99-network.conf <<'EOF'
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
    sysctl -p /etc/sysctl.d/99-network.conf
}

setup_logrotate() {
    echo -e "${WHITE}» 配置每日日志清理任务${RESET}"
    cat > /etc/cron.daily/logclean <<'EOF'
#!/bin/bash
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
journalctl --vacuum-time=1d > /dev/null
find /var/log -type f -name "*.1" -delete
EOF
    chmod +x /etc/cron.daily/logclean
}

configure_ssh() {
    echo -e "${YELLOW}» 加固SSH服务配置${RESET}"
    local ssh_dir="/root/.ssh"
    local auth_file="$ssh_dir/authorized_keys"

    [ ! -d "$ssh_dir" ] && {
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    }

    [ ! -f "$auth_file" ] && {
        touch "$auth_file"
        chmod 600 "$auth_file"
    }

    grep -q "centurnse@Centurnse-I" "$auth_file" || \
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" >> "$auth_file"

    sed -i '/^#*PasswordAuthentication/s/.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i '/^#*PubkeyAuthentication/s/.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    
    systemctl restart sshd
}

# ======================
# 主执行流程
# ======================
main() {
    print_header
    for current_step in {1..8}; do
        show_progress
        case $current_step in
            1) update_system ;;
            2) install_components ;;
            3) adjust_time ;;
            4) configure_firewall ;;
            5) setup_swap ;;
            6) optimize_network ;;
            7) setup_logrotate ;;
            8) configure_ssh ;;
        esac
        sleep 1
    done

    echo -e "\n${GREEN}${BOLD}✅ 所有配置已完成！${RESET}"
    echo -e "${BLUE}系统将在5秒后重启以应用所有更改...${RESET}"
    for i in {5..1}; do
        echo -ne "${BOLD}剩余时间: ${i}s${RESET}\r"
        sleep 1
    done
    reboot
}

main
