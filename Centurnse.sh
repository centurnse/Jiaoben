
#!/bin/bash

# Function to display a progress bar for countdown
progress_bar() {
    local duration=$1
    local bar_length=30 # Adjust the length of the progress bar
    for ((i=0; i<=duration; i++)); do
        local filled=$((i * bar_length / duration))
        printf "
["
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
        printf "[1;31m无法检测到 Linux 发行版。请手动检查。[0m
"
        exit 1
    fi
}

# Step 1: Install dependencies
step1_install_dependencies() {
    detect_distro

    printf "[1;31m****************************************[0m
"
    printf "[1;31m*      正在安装基础依赖...          *[0m
"
    printf "[1;31m****************************************[0m
"

    case $DISTRO in
        ubuntu|debian)
            sudo apt update
            sudo apt install -y wget curl vim mtr ufw ntpdate sudo unzip
            ;;
        centos|rocky|almalinux)
            sudo yum install -y epel-release
            sudo yum install -y wget curl vim mtr ufw ntpdate sudo unzip
            ;;
        *)
            printf "[1;31m不支持的 Linux 发行版：$DISTRO[0m
"
            exit 1
            ;;
    esac

    printf "[1;31m基础依赖已经安装完成，3秒后进行下一步操作[0m
"
    progress_bar 3
}

# Step 2: Update the system
step2_update_system() {
    printf "[1;33m****************************************[0m
"
    printf "[1;33m*         正在更新系统...             *[0m
"
    printf "[1;33m****************************************[0m
"

    case $DISTRO in
        ubuntu|debian)
            sudo apt update && sudo apt upgrade -y
            ;;
        centos|rocky|almalinux)
            sudo yum update -y
            ;;
    esac

    printf "[1;33m当前系统已应用最新的更新，3秒后进行下一步操作[0m
"
    progress_bar 3
}

# Step 3: Set timezone and sync time
step3_set_timezone_and_sync_time() {
    printf "[1;34m****************************************[0m
"
    printf "[1;34m*   设置时区为亚洲/上海...            *[0m
"
    printf "[1;34m****************************************[0m
"

    sudo timedatectl set-timezone Asia/Shanghai

    printf "[1;34m****************************************[0m
"
    printf "[1;34m*     正在同步时间...                 *[0m
"
    printf "[1;34m****************************************[0m
"

    sudo ntpdate cn.pool.ntp.org

    printf "[1;34m时间/时区已设置/校准完成，3秒后进行下一步操作[0m
"
    progress_bar 3
}

# Step 4: Configure and enable UFW
step4_configure_ufw() {
    printf "[1;35m****************************************[0m
"
    printf "[1;35m*   配置并启用 UFW...                  *[0m
"
    printf "[1;35m****************************************[0m
"

    # Set up UFW rules
    sudo ufw allow 22/tcp
    sudo ufw allow 22/udp
    sudo ufw allow 80/tcp
    sudo ufw allow 80/udp
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

    printf "[1;35m基础端口防护已部署，3秒后进行下一步操作[0m
"
    progress_bar 3
}

# Step 5: Finish and exit
step5_finish() {
    printf "[1;32m****************************************[0m
"
    printf "[1;32m*       全部操作已完成！               *[0m
"
    printf "[1;32m*       脚本将自动退出...             *[0m
"
    printf "[1;32m****************************************[0m
"
    progress_bar 3
    exit 0
}

# Main execution
step1_install_dependencies
step2_update_system
step3_set_timezone_and_sync_time
step4_configure_ufw
step5_finish
