#!/bin/bash

# 确保脚本以root权限运行
if [ "$(id -u)" != "0" ]; then
   echo "该脚本必须以root权限运行" 1>&2
   exit 1
fi

# 函数：打印错误并退出
error_exit() {
    echo "错误：$1"
    echo "脚本终止."
    exit 1
}

# 函数：倒计时
countdown() {
    local s="$1"
    while [ $s -gt 0 ]; do
        echo -ne "倒数 $s 秒...\r"
        sleep 1
        s=$((s - 1))
    done
    echo
}

# 1. 更新系统
if [ -f /etc/debian_version ]; then
    apt-get update > /dev/null 2>&1 || error_exit "更新系统错误"
    apt-get upgrade -y > /dev/null 2>&1 || error_exit "系统升级错误"
else
    yum update -y > /dev/null 2>&1 || error_exit "更新系统错误"
fi
echo "系统更新完毕."
countdown 3

# 2. 安装组件
packages=(wget curl vim mtr ufw ntpdate sudo unzip lvm2)
for pkg in "${packages[@]}"; do
    if ! rpm -q "$pkg" &> /dev/null; then
        yum install -y "$pkg" > /dev/null 2>&1 || error_exit "安装$pkg失败"
    else
        echo "$pkg 已安装."
    fi
done
echo "组件安装完毕."
countdown 3

# 3. 设置时区并同步时间
timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1 || error_exit "设置时区失败"
timedatectl set-ntp true > /dev/null 2>&1 || error_exit "设置NTP同步失败"
echo "时区设置并同步时间完毕."
countdown 3

# 4. 设置ufw防火墙规则
ufw reset > /dev/null 2>&1 || error_exit "重置ufw失败"
for proto in tcp udp; do
    for port in 22 80 88 443 5555 8008 32767 32768; do
        ufw allow "${port}/${proto}" > /dev/null 2>&1 || error_exit "添加ufw规则失败"
    done
done
for ip in "162.142.125.0/24" "167.94.138.0/24" "167.94.145.0/24" "167.94.146.0/24" "167.248.133.0/24" "199.45.154.0/24" "199.45.155.0/24" "206.168.34.0/24"; do
    ufw deny from "$ip" > /dev/null 2>&1 || error_exit "添加ufw规则失败"
done
for ip6 in "2602:80d:1000:b0cc:e::/80" "2620:96:e000:b0cc:e::/80" "2602:80d:1003::/112" "2602:80d:1004::/112"; do
    ufw deny from "$ip6" > /dev/null 2>&1 || error_exit "添加ufw规则失败"
done
ufw enable > /dev/null 2>&1 || error_exit "启用ufw失败"
echo "ufw防火墙设置完毕."
countdown 3

# 5. 检测和设置SWAP
# 此部分脚本需要根据您的系统环境进行调整，以下仅为示例
if [ -f /sbin/lvdisplay ]; then
    swap_dev=$(lvdisplay | grep -oP 'LV Path\s+:\s+/dev/\S+' | awk '{print $3}')
elif [ -f /sbin/blkid ]; then
    swap_dev=$(blkid | grep swap | awk '{print $1}')
fi

if [ -n "$swap_dev" ]; then
    # 删除旧的swap
    swapoff "$swap_dev" > /dev/null 2>&1 || error_exit "停止swap失败"
    dd if=/dev/zero of
