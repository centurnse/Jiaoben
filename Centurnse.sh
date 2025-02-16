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
    apt update > /dev/null 2>&1
    apt upgrade -y > /dev/null 2>&1
    echo -e "${GREEN}系统更新完成 ✔${NC}"
    countdown
}

# 安装组件
install_packages() {
    echo -e "${YELLOW}[2/7] 正在安装必要组件...${NC}"
    packages=("wget" "curl" "vim" "mtr" "ufw" "unzip" "lvm2" "ntpdate")
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            apt install -y "$pkg" > /dev/null 2>&1
        fi
    done
    echo -e "${GREEN}组件安装完成 ✔${NC}"
    countdown
}

# 设置时区
set_timezone() {
    echo -e "${YELLOW}[3/7] 正在配置时区...${NC}"

    # 检查并安装 ntpdate 或 chrony
    if ! command -v ntpdate &> /dev/null; then
        apt install -y chrony > /dev/null 2>&1
        systemctl enable --now chrony > /dev/null 2>&1
    fi

    # 设置时区为上海
    timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1 || {
        echo -e "${RED}错误: 无法设置时区，请检查 systemd 是否运行${NC}"
        exit 1
    }

    # 同步时间
    if command -v chrony &> /dev/null; then
        chronyc makestep > /dev/null 2>&1
    else
        ntpdate cn.pool.ntp.org > /dev/null 2>&1 || {
            echo -e "${RED}错误: 时间同步失败，请检查网络或 ntpdate 是否安装${NC}"
            exit 1
        }
    fi

    # 添加每小时同步任务
    if ! crontab -l | grep -q "ntpdate\|chronyc"; then
        echo "0 * * * * $(command -v chronyc || command -v ntpdate) >/dev/null 2>&1" | crontab -
    fi

    echo -e "${GREEN}时区配置完成 ✔${NC}"
    countdown
}

# 主执行流程
main() {
    update_system
    install_packages
    set_timezone
    echo -e "${GREEN}所有任务已完成 ✔${NC}"
}

main
