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

# Fix locale issues
fix_locale() {
    echo ">>> 正在修复locale设置 <<<"
    # 检查是否存在locale问题
    if grep -q "Can't set locale" /var/log/apt/term.log 2>/dev/null || \
       grep -q "Setting locale failed" /var/log/apt/term.log 2>/dev/null || \
       locale 2>&1 | grep -q "Cannot set LC" || \
       [ -z "$LANG" ] || [ "$LANG" = "C" ] || [ "$LANG" = "POSIX" ]; then
        
        echo "检测到locale问题，正在修复..."
        
        # 安装必要的locale包
        apt-get update -qq >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y locales locales-all >/dev/null
        
        # 生成并设置en_US.UTF-8为默认locale
        sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen
        sed -i '/zh_CN.UTF-8/s/^# //g' /etc/locale.gen
        locale-gen en_US.UTF-8 zh_CN.UTF-8 >/dev/null
        
        # 设置系统默认locale
        update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US:en
        
        # 设置当前shell的环境变量
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        export LANGUAGE=en_US:en
        
        # 验证修复
        if locale 2>&1 | grep -q "Cannot set LC"; then
            echo "警告: 部分locale问题可能仍然存在，建议检查系统日志"
            return 1
        else
            echo "locale问题已成功修复"
            return 0
        fi
    else
        echo "未检测到locale问题，跳过修复"
        return 0
    fi
}

# SSH安全配置函数
secure_ssh() {
    echo ">>> 正在配置SSH安全设置 <<<"
    local sshd_config="/etc/ssh/sshd_config"
    [ -f "$sshd_config" ] || { echo "SSH配置文件不存在"; return 1; }
    
    # 备份原始配置
    cp "$sshd_config" "${sshd_config}.bak-$(date +%Y%m%d%H%M%S)"
    
    # 主配置文件设置
    sed -i '/^#*PasswordAuthentication/c\PasswordAuthentication no' "$sshd_config"
    sed -i '/^#*PubkeyAuthentication/c\PubkeyAuthentication yes' "$sshd_config"
    sed -i '/^#*Port/c\Port 2333' "$sshd_config"
    sed -i '/^#*PermitRootLogin/c\PermitRootLogin prohibit-password' "$sshd_config"

    # 仅处理sshd_config.d中的PasswordAuthentication
    if [ -d "/etc/ssh/sshd_config.d" ]; then
        find /etc/ssh/sshd_config.d -name "*.conf" -type f | while read conf; do
            echo "处理配置文件：$conf"
            cp "$conf" "${conf}.bak"
            sed -i '/^#*PasswordAuthentication/c\PasswordAuthentication no' "$conf"
        done
    fi

    # 根据服务名称重启SSH
    if systemctl list-unit-files --type=service | grep -q "^sshd.service"; then
        echo "检测到sshd服务，正在重启..."
        systemctl restart sshd
    else
        echo "检测到ssh服务，正在重启..."
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

# 第一步总是修复locale问题
echo "[1] 正在检查并修复locale设置..."
fix_locale || {
    echo "无法修复locale问题，脚本终止"
    exit 1
}
countdown

case ${choice^^} in
    A)
        echo "开始配置物理服务器..."
        
        # Step 2: Update system
        echo "[2/6] 正在更新系统..."
        apt-get update -qq >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq >/dev/null
        countdown
        
        # Step 3: Install packages
        echo "[3/6] 正在安装基础组件..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo curl wget mtr lvm2 >/dev/null
        countdown
        
        # Step 4: Swap management
        echo "[4/6] 正在处理SWAP..."
        swapoff -a >/dev/null 2>&1
        sed -i '/swap/d' /etc/fstab
        
        # 处理LVM SWAP
        if command -v lvm >/dev/null; then
            lv_path=$(lvs -o lv_path,vg_name,lv_name --noheadings 2>/dev/null | grep -i swap | awk '{print $1}')
            if [ -n "$lv_path" ]; then
                lvchange -an "$lv_path" >/dev/null 2>&1
                lvremove -f "$lv_path" >/dev/null 2>&1
                root_lv=$(lvs -o lv_path,vg_name,lv_name --noheadings 2>/dev/null | grep -i root | awk '{print $1}')
                if [ -n "$root_lv" ]; then
                    lvextend -l +100%FREE "$root_lv" >/dev/null 2>&1
                    resize2fs "$root_lv" >/dev/null 2>&1
                fi
            fi
        fi
        
        update-initramfs -u -k all >/dev/null 2>&1
        
        read -p "是否建立新的SWAP？（输入YES继续，输入NO跳过）: " swap_choice
        if [[ "${swap_choice^^}" == "YES" ]]; then
            while true; do
                read -p "请输入SWAP大小（GB，最小1GB，最大9999GB）: " swap_size
                if [[ $swap_size =~ ^[0-9]+$ ]] && [ $swap_size -ge 1 ] && [ $swap_size -le 9999 ]; then
                    echo "正在配置 ${swap_size}GB 的SWAP（这可能需要几分钟）..."
                    swapoff -a >/dev/null 2>&1
                    rm -f /swapfile >/dev/null 2>&1
                    # 使用更安全的方式创建大文件
                    if ! fallocate -l ${swap_size}G /swapfile 2>/dev/null; then
                        echo "fallocate失败，尝试使用dd方式创建swap文件..."
                        dd if=/dev/zero of=/swapfile bs=1M count=$(($swap_size * 1024)) status=progress
                    fi
                    chmod 600 /swapfile
                    mkswap /swapfile >/dev/null || { echo "SWAP文件创建失败，请检查磁盘空间"; exit 1; }
                    swapon /swapfile || { echo "SWAP激活失败，请检查日志"; exit 1; }
                    echo "/swapfile none swap sw 0 0" >> /etc/fstab
                    break
                else
                    echo "输入无效，请输入1-9999之间的整数"
                fi
            done
        fi
        countdown
        
        # Step 5: Firewall configuration
        echo "[5/6] 正在配置防火墙..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw >/dev/null
        ufw --force reset >/dev/null
        ufw allow 22 >/dev/null
        ufw allow 2333 >/dev/null
        echo "y" | ufw enable >/dev/null
        countdown
        
        # Step 6: SSH configuration
        echo "[6/6] 正在配置SSH..."
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
        
        # Step 2: Update system
        echo "[2/10] 正在更新系统..."
        apt-get update -qq >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq >/dev/null
        countdown
        
        # Step 3: Install packages
        echo "[3/10] 正在安装组件..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq vim curl wget mtr sudo ufw chrony >/dev/null
        countdown
        
        # Step 4: Time configuration
        echo "[4/10] 正在调整时间..."
        timedatectl set-timezone Asia/Shanghai
        systemctl restart chrony
        echo "0 * * * * /usr/bin/chronyc -a makestep >/dev/null 2>&1" > /etc/cron.d/timesync
        countdown
        
        # Step 5: Firewall rules
        echo "[5/10] 正在配置防火墙..."
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
            "2602:80d:1000:b0cc:e::/80"
            "2620:96:e000:b0cc:e::/80"
            "2602:80d:1003::/112"
            "2602:80d:1004::/112"
        )
        
        for ip in "${blocked_ips[@]}"; do
            ufw deny from "$ip" >/dev/null
        done
        
        echo "y" | ufw enable >/dev/null
        countdown
        
        # Step 6: Swap configuration
        echo "[6/10] 正在配置SWAP..."
        swapoff -a >/dev/null 2>&1
        rm -f /swapfile >/dev/null 2>&1
        sed -i '/swapfile/d' /etc/fstab

        total_mem=$(free -m | awk '/Mem:/ {print $2}' | tr -cd '0-9')
        free_space=$(df -m / | awk 'NR==2 {print $4}' | tr -cd '0-9')
        
        total_mem=${total_mem:-0}
        free_space=${free_space:-0}

        if [ "$total_mem" -lt 512 ] && [ "$free_space" -gt 5120 ]; then
            swap_size=512
            echo "自动配置 512MB SWAP..."
            if ! fallocate -l ${swap_size}M /swapfile 2>/dev/null; then
                dd if=/dev/zero of=/swapfile bs=1M count=$swap_size status=progress
            fi
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null || { echo "SWAP文件创建失败"; exit 1; }
            swapon /swapfile || { echo "SWAP激活失败"; exit 1; }
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        elif [ "$total_mem" -ge 512 ] && [ "$total_mem" -lt 1024 ] && [ "$free_space" -gt 8192 ]; then
            swap_size=1024
            echo "自动配置 1024MB SWAP..."
            if ! fallocate -l ${swap_size}M /swapfile 2>/dev/null; then
                dd if=/dev/zero of=/swapfile bs=1M count=$swap_size status=progress
            fi
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null || { echo "SWAP文件创建失败"; exit 1; }
            swapon /swapfile || { echo "SWAP激活失败"; exit 1; }
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        elif [ "$total_mem" -ge 1024 ] && [ "$total_mem" -lt 2048 ] && [ "$free_space" -gt 10240 ]; then
            swap_size=1024
            echo "自动配置 1024MB SWAP..."
            if ! fallocate -l ${swap_size}M /swapfile 2>/dev/null; then
                dd if=/dev/zero of=/swapfile bs=1M count=$swap_size status=progress
            fi
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null || { echo "SWAP文件创建失败"; exit 1; }
            swapon /swapfile || { echo "SWAP激活失败"; exit 1; }
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        else
            echo "内存充足，跳过SWAP配置"
        fi
        countdown
        
        # Step 7: Network tuning
        echo "[7/10] 正在网络调优..."
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
        
        # Step 8: Log cleanup
        echo "[8/10] 正在配置日志清理..."
        echo "10 0 * * * find /var/log -type f -name \"*.log\" -exec truncate -s 0 {} \;" > /etc/cron.d/logclean
        countdown
        
        # Step 9: SSH configuration
        echo "[9/10] 正在配置SSH..."
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        touch /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" >> /root/.ssh/authorized_keys
        secure_ssh
        countdown
        
        # Step 10: Finalization
        echo "[10/10] 完成所有配置！"
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
