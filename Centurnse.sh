#!/bin/bash

# Function to display a progress bar for countdown
progress_bar() {
    local duration=$1
    local bar_length=30
    for ((i=0; i<=duration; i++)); do
        local filled=$((i * bar_length / duration))
        printf "\r["
        for ((j=0; j<filled; j++)); do printf "="; done
        for ((j=filled; j<bar_length; j++)); do printf " "; done
        printf "] %d/%d seconds" $i $duration
        sleep 1
    done
    echo ""
}

# Detect the Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        echo -e "\033[1;31m无法检测到 Linux 发行版。请手动检查。\033[0m"
        exit 1
    fi
}

# Step 1: Install dependencies
step1_install_dependencies() {
    detect_distro

    echo -e "\033[1;31m****************************************\033[0m"
    echo -e "\033[1;31m*      正在安装基础依赖...          *\033[0m"
    echo -e "\033[1;31m****************************************\033[0m"

    case $DISTRO in
        ubuntu|debian)
            sudo apt update || { echo "更新失败，清理 apt 缓存并重试"; sudo apt-get clean; sudo apt-get update; }
            sudo apt install -y wget curl vim mtr ufw ntpdate sudo unzip
            ;;
        centos|rocky|almalinux)
            sudo yum clean all
            sudo yum update -y || { echo "更新失败，清理 yum 缓存并重试"; sudo yum clean all; sudo yum update -y; }
            ;;
        *)
            echo -e "\033[1;31m不支持的 Linux 发行版：$DISTRO\033[0m"
            exit 1
            ;;
    esac

    echo -e "\033[1;31m基础依赖已经安装完成，3秒后进行下一步操作\033[0m"
    progress_bar 3
}

# Step 2: Update the system
step2_update_system() {
    echo -e "\033[1;33m****************************************\033[0m"
    echo -e "\033[1;33m*         正在更新系统...             *\033[0m"
    echo -e "\033[1;33m****************************************\033[0m"

    case $DISTRO in
        ubuntu|debian)
            sudo apt update && sudo apt upgrade -y
            ;;
        centos|rocky|almalinux)
            sudo yum update -y
            ;;
    esac

    echo -e "\033[1;33m当前系统已应用最新的更新，3秒后进行下一步操作\033[0m"
    progress_bar 3
}

# Step 3: Set timezone and sync time
step3_set_timezone_and_sync_time() {
    echo -e "\033[1;34m****************************************\033[0m"
    echo -e "\033[1;34m*   设置时区为亚洲/上海...            *\033[0m"
    echo -e "\033[1;34m****************************************\033[0m"

    sudo timedatectl set-timezone Asia/Shanghai

    echo -e "\033[1;34m****************************************\033[0m"
    echo -e "\033[1;34m*     正在同步时间...                 *\033[0m"
    echo -e "\033[1;34m****************************************\033[0m"

    sudo ntpdate cn.pool.ntp.org

    echo -e "\033[1;34m时间/时区已设置/校准完成，3秒后进行下一步操作\033[0m"
    progress_bar 3
}

# Step 4: Configure and enable UFW
step4_configure_ufw() {
    echo -e "\033[1;35m****************************************\033[0m"
    echo -e "\033[1;35m*   配置并启用 UFW...                  *\033[0m"
    echo -e "\033[1;35m****************************************\033[0m"

    # Set up UFW rules
    sudo ufw allow 22/tcp
    sudo ufw allow 22/udp
    sudo ufw allow 80/tcp
    sudo ufw allow 80/udp
    sudo ufw allow 88/tcp
    sudo ufw allow 88/udp
    sudo ufw allow 443/tcp
    sudo ufw allow 443/udp
    sudo ufw allow 5555/tcp
    sudo ufw allow 5555/udp
    sudo ufw allow 8008/tcp
    sudo ufw allow 8008/udp
    sudo ufw allow 32767/tcp
    sudo ufw allow 32767/udp
    sudo ufw allow 32768/tcp
    sudo ufw allow 32768/udp

    sudo ufw deny from 162.142.125.0/24
    sudo ufw deny from 167.94.138.0/24
    sudo ufw deny from 167.94.145.0/24
    sudo ufw deny from 167.94.146.0/24
    sudo ufw deny from 167.248.133.0/24
    sudo ufw deny from 199.45.154.0/24
    sudo ufw deny from 199.45.155.0/24
    sudo ufw deny from 206.168.34.0/24
    sudo ufw deny from 2602:80d:1000:b0cc:e::/80
    sudo ufw deny from 2620:96:e000:b0cc:e::/80
    sudo ufw deny from 2602:80d:1003::/112
    sudo ufw deny from 2602:80d:1004::/112

    sudo ufw --force enable

    echo -e "\033[1;35m基础端口防护已部署，3秒后进行下一步操作\033[0m"
    progress_bar 3
}

# Step 5: Manage SWAP (newly added step)
step5_manage_swap() {
    echo -e "\033[1;36m****************************************\033[0m"
    echo -e "\033[1;36m*   管理并配置 SWAP 文件...            *\033[0m"
    echo -e "\033[1;36m****************************************\033[0m"

    # Swap management script
    install_lvm_tools() {
        if ! command -v lvscan &> /dev/null; then
            echo "LVM 工具未安装，正在安装 lvm2..."
            sudo apt-get update
            sudo apt-get install -y lvm2
        else
            echo "LVM 工具已安装。"
        fi
    }

    disable_swap() {
        swapon --show
        if [[ -z "$(swapon --show)" ]]; then
            echo "没有启用的 SWAP。"
            return 0
        fi
        for swap_device in $(swapon --show=NAME --noheadings); do
            echo "禁用 SWAP 设备: $swap_device"
            sudo swapoff "$swap_device"
        done
    }

    delete_swap_file() {
        if [[ -f /swapfile ]]; then
            echo "删除 SWAP 文件 /swapfile"
            sudo rm -f /swapfile
        else
            echo "未发现文件类型的 SWAP (/swapfile)。"
        fi
    }

    update_fstab() {
        echo "更新 /etc/fstab 文件，移除 SWAP 配置..."
        sudo sed -i '/swap/d' /etc/fstab
    }

    delete_swap_partition() {
        for swap_device in $(lsblk -o NAME,TYPE,SIZE | grep 'swap' | awk '{print $1}'); do
            if [[ -n "$swap_device" ]]; then
                echo "删除 SWAP 分区: /dev/$swap_device"
                sudo swapoff "/dev/$swap_device"
                sudo fdisk /dev/$(echo $swap_device | cut -d 'p' -f 1) <<EOF
d
$(echo $swap_device | sed 's/[^0-9]*//g')
w
EOF
            fi
        done
    }

    create_swap_file() {
        ram_size=$(free -g | awk '/^Mem:/{print $2}')
        available_disk_size=$(df / --output=avail -h | tail -n 1 | awk '{print $1}')
        available_disk_size_num=$(echo $available_disk_size | sed 's/[^0-9]*//g')

        if [[ $ram_size -ge 1 || $available_disk_size_num -gt 5 ]]; then
            echo "根据条件创建新的 SWAP 文件"
            sudo dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress
            sudo chmod 600 /swapfile
            sudo mkswap /swapfile
            sudo swapon /swapfile
            echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
        else
            echo "内存和磁盘空间不足，不创建 SWAP 文件。"
        fi
    }

    # Main swap management function
    install_lvm_tools
    disable_swap
    delete_swap_file
    delete_swap_partition
    update_fstab
    create_swap_file

    echo -e "\033[1;36mSWAP 删除操作完成，且根据条件创建了新的 SWAP（如适用）。\033[0m"
    progress_bar 3
}

# Step 6: Finish and exit
step6_finish() {
    echo -e "\033[1;32m****************************************\033[0m"
    echo -e "\033[1;32m*       全部操作已完成！               *\033[0m"
    echo -e "\033[1;32m*       脚本将自动退出...             *\033[0m"
    echo -e "\033[1;32m****************************************\033[0m"
    progress_bar 3
    exit 0
}

# Main execution
step1_install_dependencies
step2_update_system
step3_set_timezone_and_sync_time
step4_configure_ufw
step5_manage_swap
step6_finish
