#!/bin/bash

# 检查并安装 bc
if ! command -v bc &> /dev/null; then
    echo "bc 命令未找到，正在安装..."
    if [ -f /etc/debian_version ]; then
        apt update && apt install -y bc
    elif [ -f /etc/redhat-release ]; then
        yum install -y bc
    elif [ -f /etc/centos-release ]; then
        dnf install -y bc
    else
        echo "无法识别的Linux发行版，跳过 bc 安装"
    fi
fi

# 隐藏命令执行进度
function run_command {
    "$@" > /dev/null 2>&1
}

# 显示进度条
function progress_bar {
    local duration=$1
    local interval=0.1
    local total_steps=$(echo "$duration/$interval" | bc)
    echo -n "["
    for ((i = 0; i <= total_steps; i++)); do
        echo -n "#"
        sleep $interval
    done
    echo "] 完成"
}

# 1. 系统更新
echo -e "\033[1;32m正在进行系统更新...\033[0m"
if [ -f /etc/debian_version ]; then
    run_command apt update && run_command apt upgrade -y
elif [ -f /etc/redhat-release ]; then
    run_command yum update -y
elif [ -f /etc/centos-release ]; then
    run_command dnf update -y
else
    echo "无法识别的Linux发行版，跳过更新"
fi
progress_bar 3

# 2. 安装必要软件
echo -e "\033[1;32m正在安装 wget, curl, vim, mtr, ufw, ntpdate, sudo, unzip, lvm2...\033[0m"
if [ -f /etc/debian_version ]; then
    run_command apt install -y wget curl vim mtr ufw ntpdate sudo unzip lvm2
elif [ -f /etc/redhat-release ]; then
    run_command yum install -y wget curl vim mtr ufw ntpdate sudo unzip lvm2
elif [ -f /etc/centos-release ]; then
    run_command dnf install -y wget curl vim mtr ufw ntpdate sudo unzip lvm2
else
    echo "无法识别的Linux发行版，跳过安装"
fi
progress_bar 3

# 3. 设置时区为中国/上海并同步时间
echo -e "\033[1;32m正在设置时区为中国/上海并同步时间...\033[0m"
run_command timedatectl set-timezone Asia/Shanghai
run_command timedatectl set-ntp true
progress_bar 3

# 4. 配置 ufw 防火墙规则并启用 ufw
function add_ufw_rule {
    local rule=$1
    if ! ufw status | grep -q "$rule"; then
        ufw -f $rule > /dev/null 2>&1
    fi
}

echo -e "\033[1;32m正在配置 ufw 防火墙规则...\033[0m"

# 添加规则
add_ufw_rule "allow 22/tcp"
add_ufw_rule "allow 22/udp"
add_ufw_rule "allow 80/tcp"
add_ufw_rule "allow 80/udp"
add_ufw_rule "allow 88/tcp"
add_ufw_rule "allow 88/udp"
add_ufw_rule "allow 443/tcp"
add_ufw_rule "allow 443/udp"
add_ufw_rule "allow 5555/tcp"
add_ufw_rule "allow 5555/udp"
add_ufw_rule "allow 8008/tcp"
add_ufw_rule "allow 8008/udp"
add_ufw_rule "allow 32767/tcp"
add_ufw_rule "allow 32767/udp"
add_ufw_rule "allow 32768/tcp"
add_ufw_rule "allow 32768/udp"
add_ufw_rule "deny from 162.142.125.0/24"
add_ufw_rule "deny from 167.94.138.0/24"
add_ufw_rule "deny from 167.94.145.0/24"
add_ufw_rule "deny from 167.94.146.0/24"
add_ufw_rule "deny from 167.248.133.0/24"
add_ufw_rule "deny from 199.45.154.0/24"
add_ufw_rule "deny from 199.45.155.0/24"
add_ufw_rule "deny from 206.168.34.0/24"
add_ufw_rule "deny from 2602:80d:1000:b0cc:e::/80"
add_ufw_rule "deny from 2620:96:e000:b0cc:e::/80"
add_ufw_rule "deny from 2602:80d:1003::/112"
add_ufw_rule "deny from 2602:80d:1004::/112"

# 启用ufw
run_command ufw --force enable
echo -e "\033[1;32m基础防护已添加完成！\033[0m"
progress_bar 3

# 5. 检查并配置 SWAP
echo -e "\033[1;32m正在配置 SWAP...\033[0m"
memory=$(free -m | awk '/Mem:/ {print $2}')
disk_space=$(df / | awk 'NR==2 {print $4}')
swap=$(swapon --show)

if [ -n "$swap" ]; then
    run_command swapoff -a
    run_command rm -f /swapfile
fi

if [ "$memory" -le 1024 ] && [ "$disk_space" -gt 3072 ]; then
    run_command fallocate -l 512M /swapfile
elif [ "$memory" -gt 1024 ] && [ "$memory" -le 2048 ] && [ "$disk_space" -gt 10240 ]; then
    run_command fallocate -l 1G /swapfile
elif [ "$memory" -gt 2048 ] && [ "$memory" -le 4096 ] && [ "$disk_space" -gt 20480 ]; then
    run_command fallocate -l 2G /swapfile
elif [ "$memory" -gt 4096 ]; then
    echo "内存大于4G，不分配SWAP"
    exit 0
fi

run_command chmod 600 /swapfile
run_command mkswap /swapfile
run_command swapon /swapfile
progress_bar 3

# 6. 创建定时任务清理日志
echo -e "\033[1;32m正在创建定时任务清理日志...\033[0m"
(crontab -l 2>/dev/null; echo "0 23 * * * /usr/bin/find /var/log -type f -exec rm -f {} \;") | crontab -
progress_bar 3

echo -e "\033[1;32m脚本执行完毕！\033[0m"
