#!/bin/bash
set -euo pipefail
trap 'echo -e "\033[31mError occurred at line $LINENO. Exiting...\033[0m"; exit 1' ERR

# 美化输出函数
success() { echo -e "\033[32m[✓] $1\033[0m"; }
info() { echo -e "\033[34m[i] $1\033[0m"; }
error() { echo -e "\033[31m[✗] $1\033[0m"; exit 1; }

# 1. 系统更新
update_system() {
  info "开始系统更新..."
  if command -v apt-get &> /dev/null; then
    apt-get -qq update > /dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get -qq upgrade -y > /dev/null 2>&1
  elif command -v dnf &> /dev/null; then
    dnf -q -y update > /dev/null 2>&1
  elif command -v yum &> /dev/null; then
    yum -q -y update > /dev/null 2>&1
  else
    error "不支持的包管理器"
  fi
  success "系统更新完成"
}

# 2. 安装必要组件
install_packages() {
  info "开始安装必要组件..."
  declare -A packages=(
    ["apt"]="wget curl vim mtr ufw ntpdate sudo unzip lvm2"
    ["yum"]="wget curl vim mtr ufw ntp sudo unzip lvm2"
    ["dnf"]="wget curl vim mtr ufw ntp sudo unzip lvm2"
  )
  
  if command -v apt-get &> /dev/null; then
    for pkg in ${packages["apt"]}; do
      if ! dpkg -s "$pkg" &> /dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get -qq install -y "$pkg" > /dev/null 2>&1
      fi
    done
  elif command -v dnf &> /dev/null; then
    for pkg in ${packages["dnf"]}; do
      if ! rpm -q "$pkg" &> /dev/null; then
        dnf -q -y install "$pkg" > /dev/null 2>&1
      fi
    done
  elif command -v yum &> /dev/null; then
    for pkg in ${packages["yum"]}; do
      if ! rpm -q "$pkg" &> /dev/null; then
        yum -q -y install "$pkg" > /dev/null 2>&1
      fi
    done
  fi
  success "组件安装完成"
}

# 3. 设置时区和时间同步
setup_time() {
  info "设置时区和时间同步..."
  timedatectl set-timezone Asia/Shanghai > /dev/null 2>&1
  if command -v ntpdate &> /dev/null; then
    ntpdate -u pool.ntp.org > /dev/null 2>&1
    echo "0 * * * * /usr/sbin/ntpdate pool.ntp.org > /dev/null 2>&1" | crontab -
  else
    systemctl enable chronyd > /dev/null 2>&1
    systemctl restart chronyd > /dev/null 2>&1
  fi
  success "时间设置完成"
}

# 4. 配置防火墙
setup_ufw() {
  info "配置UFW防火墙..."
  ufw --force reset > /dev/null 2>&1
  while read -r rule; do
    ufw $rule > /dev/null 2>&1
  done << EOF
allow 22/tcp
allow 22/udp
allow 80/tcp
allow 80/udp
allow 88/tcp
allow 88/udp
allow 443/tcp
allow 443/udp
allow 5555/tcp
allow 5555/udp
allow 8008/tcp
allow 8008/udp
allow 32767/tcp
allow 32767/udp
allow 32768/tcp
allow 32768/udp
deny from 162.142.125.0/24
deny from 167.94.138.0/24
deny from 167.94.145.0/24
deny from 167.94.146.0/24
deny from 167.248.133.0/24
deny from 199.45.154.0/24
deny from 199.45.155.0/24
deny from 206.168.34.0/24
deny from 2602:80d:1000:b0cc:e::/80
deny from 2620:96:e000:b0cc:e::/80
deny from 2602:80d:1003::/112
deny from 2602:80d:1004::/112
EOF
  ufw --force enable > /dev/null 2>&1
  success "防火墙配置完成"
}

# 5. 配置SWAP
setup_swap() {
  info "配置SWAP..."
  swapoff -a > /dev/null 2>&1
  if lsblk -o NAME,FSTYPE | grep -q swap; then
    lvremove -y $(lsblk -o NAME,FSTYPE | grep swap | awk '{print $1}') > /dev/null 2>&1 || true
  fi
  rm -f /swapfile*

  mem=$(free -m | awk '/Mem:/ {print $2}')
  disk_space=$(df -m / | awk 'NR==2 {print $4}')

  if [ $mem -le 1024 ] && [ $disk_space -ge 3072 ]; then
    swap_size=512M
  elif [ $mem -gt 1024 ] && [ $mem -le 2048 ] && [ $disk_space -ge 10240 ]; then
    swap_size=1G
  elif [ $mem -gt 2048 ] && [ $mem -le 4096 ] && [ $disk_space -ge 20480 ]; then
    swap_size=2G
  else
    info "跳过SWAP创建"
    return
  fi

  fallocate -l $swap_size /swapfile > /dev/null 2>&1
  chmod 600 /swapfile
  mkswap /swapfile > /dev/null 2>&1
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
  success "SWAP配置完成 ($swap_size)"
}

# 6. 定时清理任务
setup_cleanup() {
  info "设置定时清理任务..."
  cat << EOF | crontab -
0 0 * * * journalctl --vacuum-time=1d > /dev/null 2>&1
0 0 * * * find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; > /dev/null 2>&1
0 0 * * * (command -v apt-get > /dev/null && apt-get clean) || (command -v dnf > /dev/null && dnf clean all) || (command -v yum > /dev/null && yum clean all) > /dev/null 2>&1
EOF
  success "定时任务设置完成"
}

# 7. 强化SSH配置
setup_ssh() {
  info "配置SSH..."
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys

  # 主配置文件设置
  sed -i '/^#*PasswordAuthentication/c\PasswordAuthentication no' /etc/ssh/sshd_config
  sed -i '/^#*PubkeyAuthentication/c\PubkeyAuthentication yes' /etc/ssh/sshd_config
  sed -i '/^#*ChallengeResponseAuthentication/c\ChallengeResponseAuthentication no' /etc/ssh/sshd_config
  sed -i '/^#*UsePAM/c\UsePAM no' /etc/ssh/sshd_config

  # Ubuntu 24+专项处理
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "$ID" == "ubuntu" && "$VERSION_ID" =~ ^24 ]]; then
      info "检测到Ubuntu 24+系统，处理SSH子配置文件..."
      
      # 检查配置文件目录是否存在
      if [[ -d /etc/ssh/sshd_config.d ]]; then
        # 处理所有.conf文件
        find /etc/ssh/sshd_config.d/ -name '*.conf' | while read -r conf_file; do
          info "处理配置文件: $conf_file"
          # 移除已有配置并添加新配置
          grep -v '^#*PasswordAuthentication' "$conf_file" > "${conf_file}.tmp"
          echo "PasswordAuthentication no" >> "${conf_file}.tmp"
          mv "${conf_file}.tmp" "$conf_file"
          
          # 确保配置正确性
          sed -i '/^PasswordAuthentication/c\PasswordAuthentication no' "$conf_file"
          sed -i '/^PubkeyAuthentication/c\PubkeyAuthentication yes' "$conf_file"
        done
        
        # 强制重启SSH服务
        info "重启SSH服务..."
        systemctl restart ssh
      fi
    fi
  fi

  # 通用服务重启
  if systemctl is-active ssh &> /dev/null; then
    systemctl restart ssh
  elif systemctl is-active sshd &> /dev/null; then
    systemctl restart sshd
  else
    error "无法找到SSH服务"
  fi
  success "SSH配置完成（已强制禁用密码登录）"
}

# 主执行流程（其他函数保持不变）
main() {
  update_system
  install_packages
  setup_time
  setup_ufw
  setup_swap
  setup_cleanup
  setup_ssh
  echo -e "\n\033[32m所有任务已完成！\033[0m"
  echo -e "\033[33m[重要] 请立即测试SSH连接！\033[0m"
}

# 以下其他函数与之前版本保持一致，此处省略以节省篇幅
# update_system(), install_packages() 等函数保持不变...

main
