#!/bin/bash

# 美化输出设置
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
SUCCESS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"

# 错误处理函数
error_exit() {
    echo -e "${FAIL} 错误发生在第 $1 行"
    echo -e "错误信息: $2"
    exit 1
}

trap 'error_exit $LINENO "$BASH_COMMAND"' ERR

# 进度条函数
progress_bar() {
    local duration=$1
    echo -ne "进度：[........................] 0%\r"
    for ((i=0; i<=duration; i++)); do
        sleep 1
        percent=$(( (i * 100) / duration ))
        filled=$(( (i * 20) / duration ))
        bar=$(printf "%0.s#" $(seq 1 $filled))
        space=$(printf "%0.s " $(seq 1 $((20 - filled))))
        echo -ne "进度：[$bar$space] $percent%\r"
    done
    echo -e "\n"
}

# 1. 系统更新
update_system() {
    echo -e "\n${SUCCESS} 步骤1/7: 正在更新系统..."
    if command -v apt &> /dev/null; then
        apt update -y > /dev/null && apt upgrade -y > /dev/null
    elif command -v yum &> /dev/null; then
        yum update -y > /dev/null
    elif command -v apk &> /dev/null; then
        apk update > /dev/null && apk upgrade > /dev/null
    elif command -v pacman &> /dev/null; then
        pacman -Syu --noconfirm > /dev/null
    else
        echo -e "${FAIL} 不支持的包管理器"
        exit 1
    fi
    progress_bar 3
}

# 2. 安装组件
install_components() {
    echo -e "${SUCCESS} 步骤2/7: 正在安装必要组件..."
    packages=(wget curl vim mtr ufw ntpdate sudo unzip lvm2)
    
    if command -v apt &> /dev/null; then
        for pkg in "${packages[@]}"; do
            dpkg -s $pkg >/dev/null 2>&1 || apt install -y $pkg >/dev/null
        done
    elif command -v yum &> /dev/null; then
        for pkg in "${packages[@]}"; do
            rpm -q $pkg >/dev/null 2>&1 || yum install -y $pkg >/dev/null
        done
    fi
    progress_bar 3
}

# 3. 时区设置
set_timezone() {
    echo -e "${SUCCESS} 步骤3/7: 正在设置时区..."
    timedatectl set-timezone Asia/Shanghai
    ntpdate pool.ntp.org >/dev/null
    echo "0 * * * * /usr/sbin/ntpdate pool.ntp.org > /dev/null 2>&1" | crontab -
    progress_bar 3
}

# 4. 防火墙配置
configure_ufw() {
    echo -e "${SUCCESS} 步骤4/7: 正在配置防火墙..."
    ufw --force reset >/dev/null
    while read -r rule; do
        ufw $rule >/dev/null
    done << EOF
allow 22/tcp
allow 22/udp
allow 80/tcp
allow 80/udp
allow 88/tcp
allow 88/udp
allow 443/tcp
allow 443/udp
allow 5555/tcp
allow 5555/udp
allow 8008/tcp
allow 8008/udp
allow 32767/tcp
allow 32767/udp
allow 32768/tcp
allow 32768/udp
deny from 162.142.125.0/24
deny from 167.94.138.0/24
deny from 167.94.145.0/24
deny from 167.94.146.0/24
deny from 167.248.133.0/24
deny from 199.45.154.0/24
deny from 199.45.155.0/24
deny from 206.168.34.0/24
deny from 2602:80d:1000:b0cc:e::/80
deny from 2620:96:e000:b0cc:e::/80
deny from 2602:80d:1003::/112
deny from 2602:80d:1004::/112
EOF
    ufw --force enable >/dev/null
    progress_bar 3
}

# 5. SWAP管理
manage_swap() {
    echo -e "${SUCCESS} 步骤5/7: 正在优化SWAP配置..."
    swap_targets=$(swapon --show=NAME --noheadings)
    for target in $swap_targets; do
        swapoff $target >/dev/null
        [[ $target =~ ^/dev/mapper/ ]] && lvremove -fy $target >/dev/null || rm -f $target
    done
    
    mem_total=$(free -m | awk '/Mem:/ {print $2}')
    disk_available=$(df -m / | awk 'NR==2 {print $4}')
    
    if (( mem_total <= 1024 )) && (( disk_available >= 3072 )); then
        swap_size=512M
    elif (( mem_total > 1024 && mem_total <= 2048 )) && (( disk_available >= 10240 )); then
        swap_size=1G
    elif (( mem_total > 2048 && mem_total <= 4096 )) && (( disk_available >= 20480 )); then
        swap_size=2G
    else
        swap_size=0
    fi
    
    if (( swap_size > 0 )); then
        fallocate -l $swap_size /swapfile
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null
        swapon /swapfile
        echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    fi
    progress_bar 3
}

# 6. 定时清理任务
set_cronjob() {
    echo -e "${SUCCESS} 步骤6/7: 正在设置定时清理任务..."
    cat << EOF > /etc/cron.daily/system-cleanup
#!/bin/bash
journalctl --vacuum-time=1d
find /var/log -type f -regex ".*\.gz$" -delete
find /var/log -type f -exec truncate -s 0 {} \;
if command -v apt &> /dev/null; then
    apt clean
elif command -v yum &> /dev/null; then
    yum clean all
fi
EOF
    chmod +x /etc/cron.daily/system-cleanup
    progress_bar 3
}

# 7. SSH配置
configure_ssh() {
    echo -e "${SUCCESS} 步骤7/7: 正在配置SSH安全设置..."
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" > /root/.ssh/id_ed25519.pub
    touch /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    grep
