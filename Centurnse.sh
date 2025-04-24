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

# Main menu
clear
echo "请选择配置类型："
echo "a) Use for Dedicated Server (按A键)"
echo "b) Use for VPS (按B键)"
read -n1 -p "请输入选择 (A/B): " choice
echo

case ${choice^^} in
    A)
        echo "开始配置物理服务器..."
        # ① Dedicated Server Configuration
        
        # [原有步骤1-4保持不变...]

        # Step 5: SSH configuration
        echo "[5/5] 正在配置SSH..."
        # SSH安全配置函数
        secure_ssh() {
            local sshd_config="/etc/ssh/sshd_config"
            cp "$sshd_config" "${sshd_config}.bak-$(date +%Y%m%d%H%M%S)"
            
            # 处理主配置文件
            sed -i '/^#*PasswordAuthentication/c\PasswordAuthentication no' $sshd_config
            sed -i '/^#*PubkeyAuthentication/c\PubkeyAuthentication yes' $sshd_config
            sed -i '/^#*ChallengeResponseAuthentication/c\ChallengeResponseAuthentication no' $sshd_config
            sed -i '/^#*Port/c\Port 2333' $sshd_config

            # 处理sshd_config.d目录
            if [ -d "/etc/ssh/sshd_config.d" ]; then
                find /etc/ssh/sshd_config.d -name "*.conf" -type f | while read conf; do
                    echo "处理配置文件：$conf"
                    cp "$conf" "${conf}.bak"
                    sed -i -E '/^#*PasswordAuthentication/c\PasswordAuthentication no' "$conf"
                done
            fi

            # 根据版本重载服务
            if systemctl is-active sshd &>/dev/null; then
                systemctl restart sshd
            else
                systemctl restart ssh
            fi
        }

        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        touch /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" >> /root/.ssh/authorized_keys
        secure_ssh
        ;;

    B)
        echo "开始配置云服务器..."
        # ② VPS Configuration
        
        # [原有步骤1-7保持不变...]

        # Step 8: SSH configuration
        echo "[8/9] 正在配置SSH..."
        # SSH安全配置函数
        secure_ssh() {
            local sshd_config="/etc/ssh/sshd_config"
            cp "$sshd_config" "${sshd_config}.bak-$(date +%Y%m%d%H%M%S)"
            
            # 处理主配置文件
            sed -i '/^#*PasswordAuthentication/c\PasswordAuthentication no' $sshd_config
            sed -i '/^#*PubkeyAuthentication/c\PubkeyAuthentication yes' $sshd_config
            sed -i '/^#*ChallengeResponseAuthentication/c\ChallengeResponseAuthentication no' $sshd_config
            sed -i '/^#*Port/c\Port 2333' $sshd_config

            # 处理sshd_config.d目录
            if [ -d "/etc/ssh/sshd_config.d" ]; then
                find /etc/ssh/sshd_config.d -name "*.conf" -type f | while read conf; do
                    echo "处理配置文件：$conf"
                    cp "$conf" "${conf}.bak"
                    sed -i -E '/^#*PasswordAuthentication/c\PasswordAuthentication no' "$conf"
                done
            fi

            # 根据版本重载服务
            if systemctl is-active sshd &>/dev/null; then
                systemctl restart sshd
            else
                systemctl restart ssh
            fi
        }

        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        touch /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" >> /root/.ssh/authorized_keys
        secure_ssh
        countdown
        
        # Step 9: Finalization
        echo "[9/9] 完成所有配置！"
        ;;
    *)
        echo "无效选择！"
        exit 1
        ;;
esac

echo "所有配置已完成！"
