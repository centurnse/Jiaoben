#!/bin/bash
set -eo pipefail
trap 'echo -e "\033[1;31m错误: 脚本执行失败，请检查日志！\033[0m"; exit 1' ERR

# 美化输出颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

# 进度条函数
countdown() {
    echo -ne "${BLUE}等待3秒继续...  "
    for i in {1..10}; do
        echo -n "▇"
        sleep 0.3
    done
    echo -e "${NC}\n"
}

# 系统更新
update_system() {
    echo -e "${YELLOW}[1/7] 正在更新系统...${NC}"
    if grep -qi "ubuntu\|debian" /etc/os-release; then
        apt update > /dev/null 2>&1
        apt upgrade -y > /dev/null 2>&1
    elif grep -qi "centos\|redhat" /etc/os-release; then
        yum update -y > /dev/null 2>&1
    else
        echo -e "${RED}不支持的系统类型${NC}"
        exit 1
    fi
    echo -e "${GREEN}系统更新完成 ✔${NC}"
    countdown
}

# 安装组件
install_packages() {
    echo -e "${YELLOW}[2/7] 正在安装必要组件...${NC}"
    packages=("wget" "curl" "vim" "mtr" "ufw" "ntpdate" "sudo" "unzip" "lvm2")
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            if grep -qi "ubuntu\|debian" /etc/os-release; then
                apt install -y "$pkg" > /dev/null 2>&1
            else
                yum install -y "$pkg" > /dev/null 2>&1
            fi
        fi
    done
    echo -e "${GREEN}组件安装完成 ✔${NC}"
    countdown
}

# 设置时区
set_timezone() {
    echo -e "${YELLOW}[3/7] 正在配置时区...${NC}"
    timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1
    ntpdate cn.pool.ntp.org > /dev/null 2>&1
    echo "0 * * * * /usr/sbin/ntpdate cn.pool.ntp.org > /dev/null 2>&1" | crontab -
    echo -e "${GREEN}时区配置完成 ✔${NC}"
    countdown
}

# 防火墙配置
setup_ufw() {
    echo -e "${YELLOW}[4/7] 正在配置防火墙...${NC}"
    ufw --force reset > /dev/null 2>&1
    for port in 22 80 88 443 5555 8008 32767 32768; do
        ufw allow "$port/tcp" > /dev/null 2>&1
        ufw allow "$port/udp" > /dev/null 2>&1
    done
    for subnet in 162.142.125.0/24 167.94.138.0/24 167.94.145.0/24 167.94.146.0/24 \
                   167.248.133.0/24 199.45.154.0/24 199.45.155.0/24 206.168.34.0/24 \
                   2602:80d:1000:b0cc:e::/80 2620:96:e000:b0cc:e::/80 \
                   2602:80d:1003::/112 2602:80d:1004::/112; do
        ufw deny from "$subnet" > /dev/null 2>&1
    done
    echo "y" | ufw --force enable > /dev/null 2>&1
    echo -e "${GREEN}防火墙配置完成 ✔${NC}"
    countdown
}

# SWAP管理
manage_swap() {
    echo -e "${YELLOW}[5/7] 正在配置SWAP...${NC}"
    mem=$(free -m | awk '/Mem:/ {print $2}')
    disk=$(df -m / | awk 'NR==2 {print $4}')

    # 强制移除所有SWAP
    {
        swapoff -a >/dev/null 2>&1
        lvswap=$(swapon --show=NAME,TYPE | awk '/dev/ {print $1}')
        [ -n "$lvswap" ] && lvremove -f "$lvswap" >/dev/null 2>&1
        sed -i '/swap/d' /etc/fstab
        rm -f /swapfile
        sync && sleep 1
    } || {
        echo -e "${RED}错误: 无法清理旧SWAP${NC}"
        exit 1
    }

    # 创建新SWAP
    if [ "$mem" -le 1024 ] && [ "$disk" -ge 3072 ]; then
        swap_size=512
    elif [ "$mem" -gt 1024 ] && [ "$mem" -le 2048 ] && [ "$disk" -ge 10240 ]; then
        swap_size=1024
    elif [ "$mem" -gt 2048 ] && [ "$mem" -le 4096 ] && [ "$disk" -ge 20480 ]; then
        swap_size=2048
    else
        echo -e "${BLUE}跳过SWAP创建${NC}"
        return
    fi

    # 确保文件不存在
    rm -f /swapfile
    sync

    # 使用fallocate避免文件占用
    if ! fallocate -l ${swap_size}M /swapfile >/dev/null 2>&1; then
        dd if=/dev/zero of=/swapfile bs=1M count=${swap_size} status=none conv=fsync
    fi

    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    echo -e "${GREEN}SWAP配置完成 ✔${NC}"
    countdown
}

# 清理任务
setup_cleanup() {
    echo -e "${YELLOW}[6/7] 正在配置清理任务...${NC}"
    echo "0 0 * * * journalctl --rotate && journalctl --vacuum-time=1s >/dev/null 2>&1" > /tmp/cronjob
    echo "0 0 * * * find /var/log -type f -delete >/dev/null 2>&1" >> /tmp/cronjob
    if grep -qi "ubuntu\|debian" /etc/os-release; then
        echo "0 0 * * * apt clean >/dev/null 2>&1" >> /tmp/cronjob
    else
        echo "0 0 * * * yum clean all >/dev/null 2>&1" >> /tmp/cronjob
    fi
    crontab /tmp/cronjob
    rm /tmp/cronjob
    echo -e "${GREEN}清理任务配置完成 ✔${NC}"
    countdown
}

# SSH配置
setup_ssh() {
    echo -e "${YELLOW}[7/7] 正在配置SSH...${NC}"
    ssh_dir="/root/.ssh"
    auth_file="$ssh_dir/authorized_keys"
    pubkey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I"

    # 创建目录和文件
    [ ! -d "$ssh_dir" ] && mkdir -p "$ssh_dir"
    [ ! -f "$auth_file" ] && touch "$auth_file"

    # 设置权限
    chmod 700 "$ssh_dir"
    chmod 600 "$auth_file"

    # 生成密钥文件
    echo "$pubkey" > "$ssh_dir/id_ed25519.pub"
    if ! grep -q "$pubkey" "$auth_file"; then
        echo "$pubkey" >> "$auth_file"
    fi

    # 修改SSH配置
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl restart sshd > /dev/null 2>&1

    echo -e "${GREEN}SSH配置完成 ✔${NC}"
    countdown
}

# 主执行流程
main() {
    update_system
    install_packages
    set_timezone
    setup_ufw
    manage_swap
    setup_cleanup
    setup_ssh
    echo -e "${GREEN}所有任务已完成 ✔${NC}"
}

main
