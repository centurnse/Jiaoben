#!/bin/bash

# 初始化设置
exec 2>&1
set -eo pipefail
BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
NC="\033[0m"
SUCCESS_LIST=()
ERROR_LIST=()

# 进度条函数
countdown() {
    echo -ne "${YELLOW}等待3秒...${NC}"
    for i in {3..1}; do
        echo -ne "${YELLOW}\r等待${i}秒...${NC}"
        sleep 1
    done
    echo -e "\n"
}

# 错误处理函数
error_handler() {
    local exit_code=$?
    echo -e "\n${RED}${BOLD}[错误] 在步骤: $1${NC}"
    echo -e "${RED}错误代码: $exit_code${NC}"
    exit $exit_code
}

# 系统更新函数
system_update() {
    trap 'error_handler "系统更新"' ERR
    echo -e "${GREEN}正在检测系统类型...${NC}"
    
    if [ -f /etc/debian_version ]; then
        echo -e "${GREEN}检测到 Debian/Ubuntu 系统${NC}"
        apt-get -qq update > /dev/null
        apt-get -qq -y upgrade > /dev/null
    elif [ -f /etc/redhat-release ]; then
        echo -e "${GREEN}检测到 RHEL/CentOS 系统${NC}"
        yum -q -y update > /dev/null
    elif [ -f /etc/alpine-release ]; then
        echo -e "${GREEN}检测到 Alpine 系统${NC}"
        apk update --quiet
        apk upgrade --quiet
    else
        echo -e "${RED}不支持的Linux发行版${NC}"
        exit 1
    fi
    
    SUCCESS_LIST+=("系统更新完成")
    countdown
}

# 组件安装函数
install_components() {
    trap 'error_handler "组件安装"' ERR
    components=("wget" "curl" "vim" "mtr" "ufw" "ntpdate" "sudo" "unzip" "lvm2")
    
    if [ -f /etc/debian_version ]; then
        for pkg in "${components[@]}"; do
            if ! dpkg -l | grep -q "^ii  $pkg "; then
                apt-get -qq -y install $pkg > /dev/null
            fi
        done
    elif [ -f /etc/redhat-release ]; then
        for pkg in "${components[@]}"; do
            if ! rpm -qa | grep -q "^$pkg"; then
                yum -q -y install $pkg > /dev/null
            fi
        done
    fi
    
    SUCCESS_LIST+=("必要组件安装完成")
    countdown
}

# 时间设置函数
time_config() {
    trap 'error_handler "时间设置"' ERR
    timedatectl set-timezone Asia/Shanghai
    ntpdate -u pool.ntp.org > /dev/null
    echo "0 * * * * /usr/sbin/ntpdate pool.ntp.org > /dev/null 2>&1" | crontab -
    
    SUCCESS_LIST+=("时区设置和时间同步完成")
    countdown
}

# 防火墙配置函数（已修复自动确认问题）
configure_firewall() {
    trap 'error_handler "防火墙配置"' ERR
    yes | ufw --force reset > /dev/null
    
    declare -a rules=(
        "allow 22/tcp" "allow 22/udp" "allow 80/tcp" "allow 80/udp"
        "allow 88/tcp" "allow 88/udp" "allow 443/tcp" "allow 443/udp"
        "allow 5555/tcp" "allow 5555/udp" "allow 8008/tcp" "allow 8008/udp"
        "allow 32767/tcp" "allow 32767/udp" "allow 32768/tcp" "allow 32768/udp"
        "deny from 162.142.125.0/24" "deny from 167.94.138.0/24"
        "deny from 167.94.145.0/24" "deny from 167.94.146.0/24"
        "deny from 167.248.133.0/24" "deny from 199.45.154.0/24"
        "deny from 199.45.155.0/24" "deny from 206.168.34.0/24"
        "deny from 2602:80d:1000:b0cc:e::/80" "deny from 2620:96:e000:b0cc:e::/80"
        "deny from 2602:80d:1003::/112" "deny from 2602:80d:1004::/112"
    )
    
    for rule in "${rules[@]}"; do
        yes | ufw $rule > /dev/null
    done
    
    yes | ufw --force enable > /dev/null
    SUCCESS_LIST+=("防火墙配置完成")
    countdown
}

# SWAP管理函数
manage_swap() {
    trap 'error_handler "SWAP管理"' ERR
    mem_total=$(free -m | awk '/Mem:/ {print $2}')
    disk_space=$(df -m / | awk 'NR==2 {print $4}')
    
    # 删除现有SWAP
    if swapon --show | grep -q .; then
        swapoff -a
        sed -i '/swap/d' /etc/fstab
    fi
    
    # 根据条件创建新SWAP
    if [ $mem_total -le 1024 ] && [ $disk_space -ge 3072 ]; then
        dd if=/dev/zero of=/swapfile bs=1M count=512
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
    elif [ $mem_total -gt 1024 ] && [ $mem_total -le 2048 ] && [ $disk_space -ge 10240 ]; then
        dd if=/dev/zero of=/swapfile bs=1M count=1024
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
    elif [ $mem_total -gt 2048 ] && [ $mem_total -le 4096 ] && [ $disk_space -ge 20480 ]; then
        dd if=/dev/zero of=/swapfile bs=1M count=2048
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
    fi
    
    SUCCESS_LIST+=("SWAP优化完成")
    countdown
}

# 日志清理任务
setup_log_clean() {
    trap 'error_handler "日志清理设置"' ERR
    echo "0 0 * * * journalctl --rotate --vacuum-time=1s && rm -rf /var/log/*.log.* && apt clean" | crontab -
    
    SUCCESS_LIST+=("日志清理任务设置完成")
    countdown
}

# SSH配置函数
configure_ssh() {
    trap 'error_handler "SSH配置"' ERR
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" > /root/.ssh/id_ed25519.pub
    
    if [ ! -f /root/.ssh/authorized_keys ]; then
        touch /root/.ssh/authorized_keys
    fi
    chmod 600 /root/.ssh/authorized_keys
    cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys
    
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    systemctl restart sshd
    
    SUCCESS_LIST+=("SSH安全配置完成")
    countdown
}

# 主执行流程
main() {
    system_update
    install_components
    time_config
    configure_firewall
    manage_swap
    setup_log_clean
    configure_ssh
    
    echo -e "\n${GREEN}${BOLD}所有任务已完成:${NC}"
    printf "• %s\n" "${SUCCESS_LIST[@]}"
    countdown
}

main
