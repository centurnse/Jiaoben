#!/bin/bash
# Check root privileges
if [ $(id -u) -ne 0 ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# Common functions
countdown() {
    echo -n "下一步将在"
    for i in {3..1}; do
        echo -n " $i..."
        sleep 1
    done
    echo
}

# SSH安全配置函数（仅修改PasswordAuthentication）
secure_ssh() {
    echo ">>> 正在配置SSH安全设置 <<<"
    local sshd_config="/etc/ssh/sshd_config"
    
    # 主配置文件设置
    if [ -f "$sshd_config" ]; then
        cp "$sshd_config" "${sshd_config}.bak-$(date +%Y%m%d%H%M%S)"
        sed -i '/^#*PasswordAuthentication/c\PasswordAuthentication no' "$sshd_config"
        sed -i '/^#*PubkeyAuthentication/c\PubkeyAuthentication yes' "$sshd_config"
        sed -i '/^#*Port/c\Port 2333' "$sshd_config"
    fi

    # 仅处理sshd_config.d中的PasswordAuthentication
    if [ -d "/etc/ssh/sshd_config.d" ]; then
        find /etc/ssh/sshd_config.d -name "*.conf" -type f | while read conf; do
            echo "处理配置文件：$conf"
            [ -f "$conf" ] && {
                cp "$conf" "${conf}.bak"
                sed -i '/^#*PasswordAuthentication/c\PasswordAuthentication no' "$conf"
            }
        done
    fi

    # 根据服务名称重启SSH
    if systemctl list-unit-files --type=service | grep -q "^sshd.service"; then
        systemctl restart sshd
    else
        systemctl restart ssh
    fi
}

# Main menu
clear
echo "======================================"
echo "         服务器初始化配置脚本         "
echo "======================================"
echo "请选择配置类型："
echo "a) 物理服务器配置 (按A键)"
echo "b) 云服务器配置 (按B键)"
read -n1 -p "请输入选择 (A/B): " choice
echo

case ${choice^^} in
    A)
        echo "开始配置物理服务器..."
        
        # Step 1: Update system
        echo "[1/5] 正在更新系统..."
        apt-get update -qq >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq >/dev/null
        countdown
        
        # Step 2: Install packages
        echo "[2/5] 正在安装基础组件..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo curl wget mtr >/dev/null
        countdown
        
        # Step 3: Swap management
        echo "[3/5] 正在处理SWAP..."
        swapoff -a >/dev/null 2>&1
        sed -i '/swap/d' /etc/fstab
        
        # 处理LVM SWAP
        if command -v lvm >/dev/null; then
            lv_path=$(lvs -o lv_path,vg_name,lv_name | grep -i swap | awk '{print $1}')
            [ -n "$lv_path" ] && {
                lvchange -an "$lv_path" >/dev/null 2>&1
                lvremove -f "$lv_path" >/dev/null 2>&1
                root_lv=$(lvs -o lv_path,vg_name,lv_name | grep -i root | awk '{print $1}')
                [ -n "$root_lv" ] && {
                    lvextend -l +100%FREE "$root_lv" >/dev/null 2>&1
                    resize2fs "$root_lv" >/dev/null 2>&1
                }
            }
        fi
        
        update-initramfs -u -k all >/dev/null 2>&1
        
        read -p "是否建立新的SWAP？（输入YES继续，输入NO跳过）: " swap_choice
        if [[ "${swap_choice^^}" == "YES" ]]; then
            while :; do
                read -p "请输入SWAP大小（GB，0-9999）: " swap_size
                if [[ $swap_size =~ ^[0-9]+$ ]] && [ $swap_size -le 9999 ]; then
                    echo "正在配置 ${swap_size}GB 的SWAP..."
                    swapoff -a >/dev/null 2>&1
                    rm -f /swapfile >/dev/null 2>&1
                    dd if=/dev/zero of=/swapfile bs=1G count=$swap_size status=progress
                    chmod 600 /swapfile
                    mkswap /swapfile >/dev/null
                    swapon /swapfile
                    echo "/swapfile none swap sw 0 0" >> /etc/fstab
                    break
                else
                    echo "输入无效，请重新输入数字（0-9999）"
                fi
            done
        fi
        countdown
        
        # Step 4: Firewall configuration
        echo "[4/5] 正在配置防火墙..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw >/dev/null
        ufw --force reset >/dev/null
        ufw allow 22 >/dev/null
        ufw allow 2333 >/dev/null
        echo "y" | ufw enable >/dev/null
        countdown
        
        # Step 5: SSH configuration
        echo "[5/5] 正在配置SSH..."
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        touch /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" >> /root/.ssh/authorized_keys
        secure_ssh
        
        echo "======================================"
        echo "物理服务器配置已完成！"
        echo "请使用以下命令测试连接："
        echo "ssh -p 2333 root@您的服务器IP"
        echo "======================================"
        ;;
    
    B)
        echo "开始配置云服务器..."
        
        # Step 1: Update system
        echo "[1/9] 正在更新系统..."
        apt-get update -qq >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq >/dev/null
        countdown
        
        # Step 2: Install packages
        echo "[2/9] 正在安装组件..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq vim curl wget mtr sudo ufw >/dev/null
        countdown
        
        # Step 3: Time configuration
        echo "[3/9] 正在调整时间..."
        timedatectl set-timezone Asia/Shanghai
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq chrony >/dev/null
        systemctl restart chrony
        echo "0 * * * * /usr/bin/chronyc -a makestep >/dev/null 2>&1" > /etc/cron.d/timesync
        countdown
        
        # Step 4: Firewall rules
        echo "[4/9] 正在配置防火墙..."
        ufw --force disable >/dev/null
        ufw --force reset >/dev/null
        for port in 22 2333 80 88 443 5555 8008 32767 32768; do
            ufw allow "$port" >/dev/null
        done
        
        blocked_ips=(
            "162.142.125.0/24"
            "167.94.138.0/24"
            "167.94.145.0/24"
            "167.94.146.0/24"
            "167.248.133.0/24"
            "199.45.154.0/24"
            "199.45.155.0/24"
            "206.168.34.0/24"
        )
        
        for ip in "${blocked_ips[@]}"; do
            ufw deny from "$ip" >/dev/null
        done
        
        echo "y" | ufw enable >/dev/null
        countdown
        
        # Step 5: Swap configuration
        echo "[5/9] 正在配置SWAP..."
        swapoff -a >/dev/null 2>&1
        rm -f /swapfile >/dev/null 2>&1
        sed -i '/swapfile/d' /etc/fstab

        total_mem=$(free -m | awk '/Mem:/ {print $2}')
        free_space=$(df -m / | awk 'NR==2 {print $4}')

        if [ "$total_mem" -lt 512 ] && [ "$free_space" -gt 5120 ]; then
            echo "自动配置 512MB SWAP..."
            dd if=/dev/zero of=/swapfile bs=1M count=512 status=progress
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null
            swapon /swapfile
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        elif [ "$total_mem" -ge 512 ] && [ "$total_mem" -lt 1024 ] && [ "$free_space" -gt 8192 ]; then
            echo "自动配置 1024MB SWAP..."
            dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null
            swapon /swapfile
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        elif [ "$total_mem" -ge 1024 ] && [ "$total_mem" -lt 2048 ] && [ "$free_space" -gt 10240 ]; then
            echo "自动配置 1024MB SWAP..."
            dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null
            swapon /swapfile
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        else
            echo "内存充足，跳过SWAP配置"
        fi
        countdown
        
        # Step 6: Network tuning
        echo "[6/9] 正在网络调优..."
        cat > /etc/sysctl.d/99-custom.conf <<EOF
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
        sysctl -p /etc/sysctl.d/99-custom.conf >/dev/null
        countdown
        
        # Step 7: Log cleanup
        echo "[7/9] 正在配置日志清理..."
        echo "10 0 * * * find /var/log -type f -name \"*.log\" -exec truncate -s 0 {} \;" > /etc/cron.d/logclean
        countdown
        
        # Step 8: SSH configuration
        echo "[8/9] 正在配置SSH..."
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        touch /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" >> /root/.ssh/authorized_keys
        secure_ssh
        countdown
        
        # Step 9: Finalization
        echo "[9/9] 完成所有配置！"
        echo "======================================"
        echo "云服务器配置已完成！"
        echo "请使用以下命令测试连接："
        echo "ssh -p 2333 root@您的服务器IP"
        echo "======================================"
        ;;
    *)
        echo "无效选择！脚本退出。"
        exit 1
        ;;
esac
