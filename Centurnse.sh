#!/bin/bash

# 美化输出函数
print_msg() {
  echo -e "\033[1;34m[INFO]\033[0m $1"
}
print_error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
  exit 1
}
show_progress() {
  for i in {3..1}; do
    echo -ne "\033[1;32mProceeding in $i...\033[0m\r"
    sleep 1
  done
  echo -ne "\033[0K\r"
}

# 错误处理函数
handle_error() {
  print_error "An error occurred. Exiting."
}
trap handle_error ERR

# 隐藏命令输出
exec &>/tmp/script.log

# 1. 根据系统进行更新
print_msg "Updating system packages..."
if [[ -f /etc/debian_version ]]; then
  apt-get update && apt-get upgrade -y
elif [[ -f /etc/redhat-release ]]; then
  yum update -y
else
  print_error "Unsupported system."
fi
print_msg "System updated successfully."
show_progress

# 2. 安装必要组件
print_msg "Installing necessary packages..."
packages=(wget curl vim mtr ufw ntpdate sudo unzip lvm2)
for pkg in "${packages[@]}"; do
  if ! command -v $pkg &>/dev/null; then
    [[ -f /etc/debian_version ]] && apt-get install -y $pkg
    [[ -f /etc/redhat-release ]] && yum install -y $pkg
  fi
done
print_msg "All packages installed successfully."
show_progress

# 3. 设置时区并同步时间
print_msg "Configuring timezone and syncing time..."
timedatectl set-timezone Asia/Shanghai
timedatectl set-ntp true
ntpdate cn.pool.ntp.org
(crontab -l 2>/dev/null; echo "0 * * * * /usr/sbin/ntpdate cn.pool.ntp.org") | crontab -
print_msg "Timezone set and time synchronized successfully."
show_progress

# 4. 配置防火墙
print_msg "Configuring firewall rules..."
ufw --force reset
rules=(
  "allow 22/tcp" "allow 22/udp" "allow 80/tcp" "allow 80/udp"
  "allow 88/tcp" "allow 88/udp" "allow 443/tcp" "allow 443/udp"
  "allow 5555/tcp" "allow 5555/udp" "allow 8008/tcp" "allow 8008/udp"
  "allow 32767/tcp" "allow 32767/udp" "allow 32768/tcp" "allow 32768/udp"
  "deny from 162.142.125.0/24" "deny from 167.94.138.0/24"
  "deny from 167.94.145.0/24" "deny from 167.94.146.0/24"
  "deny from 167.248.133.0/24" "deny from 199.45.154.0/24"
  "deny from 199.45.155.0/24" "deny from 206.168.34.0/24"
  "deny from 2602:80d:1000:b0cc:e::/80" "deny from 2620:96:e000:b0cc:e::/80"
  "deny from 2602:80d:1003::/112" "deny from 2602:80d:1004::/112"
)
for rule in "${rules[@]}"; do
  ufw $rule
done
ufw --force enable
print_msg "Firewall rules configured successfully."
show_progress

# 5. 检测并配置SWAP
print_msg "Configuring SWAP space..."
mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
disk_avail=$(df / | tail -1 | awk '{print $4}')
swapoff -a
lvremove -y $(lvs --noheadings -o lv_path 2>/dev/null | grep swap) 2>/dev/null || true
rm -f /swapfile

if (( mem_total <= 1048576 && disk_avail >= 3145728 )); then
  fallocate -l 512M /swapfile
elif (( mem_total > 1048576 && mem_total <= 2097152 && disk_avail >= 10485760 )); then
  fallocate -l 1G /swapfile
elif (( mem_total > 2097152 && mem_total <= 4194304 && disk_avail >= 20971520 )); then
  fallocate -l 2G /swapfile
fi
if [[ -f /swapfile ]]; then
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi
print_msg "SWAP space configured successfully."
show_progress

# 6. 设置定时任务
print_msg "Setting up cron job for log cleaning..."
(crontab -l 2>/dev/null; echo "0 0 * * * rm -rf /var/log/* /var/log/journal/* /var/cache/*") | crontab -
print_msg "Cron job configured successfully."
show_progress

# 7. 配置SSH
print_msg "Configuring SSH access..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" > /root/.ssh/id_ed25519.pub
chmod 600 /root/.ssh/id_ed25519.pub
cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
sed -i 's/#\?PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#\?PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd
print_msg "SSH access configured successfully."
show_progress

print_msg "All tasks completed successfully!"
