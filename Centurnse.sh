#!/bin/bash

set -e  # 遇到错误时立即停止

# 美化输出
function print_info() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

function print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

function countdown() {
    for i in {3..1}; do
        echo -ne "\r继续下一步将在 $i 秒后..."
        sleep 1
    done
    echo -ne "\r                            \r"
}

# 隐藏输出并捕获错误
function run_cmd() {
    if ! output=$(eval "$1" 2>&1); then
        print_error "$output"
        exit 1
    fi
}

# 1. 根据系统更新
print_info "更新系统中..."
if [[ -f /etc/debian_version ]]; then
    run_cmd "apt update -y && apt upgrade -y"
elif [[ -f /etc/redhat-release ]]; then
    run_cmd "yum update -y"\else
    print_error "无法识别的操作系统"
    exit 1
fi
print_info "系统更新完成！"
countdown

# 2. 安装必要组件
print_info "安装必要组件..."
packages="wget curl vim mtr ufw ntpdate sudo unzip lvm2"
for pkg in $packages; do
    if ! command -v $pkg >/dev/null 2>&1; then
        run_cmd "apt install -y $pkg || yum install -y $pkg"
    fi
done
print_info "必要组件安装完成！"
countdown

# 3. 设置时区并同步时间
print_info "设置时区和同步时间..."
run_cmd "timedatectl set-timezone Asia/Shanghai"
run_cmd "ntpdate pool.ntp.org"
echo "0 * * * * /usr/sbin/ntpdate pool.ntp.org" > /etc/cron.d/ntp_sync
print_info "时区设置完成并同步时间！"
countdown

# 4. 设置防火墙
print_info "配置UFW防火墙..."
ufw allow 22
ufw allow 80
ufw allow 443
ufw enable
print_info "防火墙配置完成！"
countdown

# 5. 配置SWAP
print_info "检查和配置SWAP..."
swapoff -a
if [[ $(free -m | awk '/^Mem:/{print $2}') -le 1024 ]]; then
    swap_size=512
    disk_required=3000
elif [[ $(free -m | awk '/^Mem:/{print $2}') -le 2048 ]]; then
    swap_size=1024
    disk_required=10000
elif [[ $(free -m | awk '/^Mem:/{print $2}') -le 4096 ]]; then
    swap_size=2048
    disk_required=20000
else
    swap_size=0
fi

if [[ $swap_size -gt 0 ]]; then
    if [[ $(df / | awk '/\//{print $4}') -lt $disk_required ]]; then
        print_error "磁盘空间不足，无法创建SWAP"
        exit 1
    fi
    dd if=/dev/zero of=/swapfile bs=1M count=$swap_size
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
    print_info "SWAP设置完成：${swap_size}MB"
else
    print_info "内存大于4G，无需SWAP"
fi
countdown

# 6. 配置定时任务
print_info "配置清理日志的定时任务..."
echo "0 0 * * * root rm -rf /var/log/* /var/log/journal/* && apt clean || yum clean all" > /etc/cron.d/clean_logs
print_info "定时任务配置完成！"
countdown

# 7. 配置SSH
print_info "检查和配置SSH..."
if [[ ! -d ~/.ssh ]]; then
    mkdir ~/.ssh
fi
chmod 700 ~/.ssh

if [[ ! -f ~/.ssh/authorized_keys ]]; then
    touch ~/.ssh/authorized_keys
fi
chmod 600 ~/.ssh/authorized_keys

cat > ~/.ssh/id_ed25519.pub <<EOF
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I
EOF
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys

sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

run_cmd "systemctl restart sshd"
print_info "SSH配置完成！"
countdown

print_info "所有任务已完成！"
