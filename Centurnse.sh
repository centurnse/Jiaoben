#!/bin/bash
set -eo pipefail
trap 'echo -e "\033[31m[ERR] 在 $BASH_SOURCE 第 $LINENO 行发生错误\033[0m"; exit 1' ERR

# 美化输出函数
print_success() { echo -e "\033[32m[✓] $1\033[0m"; }
print_info() { echo -e "\033[34m[i] $1\033[0m"; }
progress_countdown() {
  echo -ne "\033[36m等待 "
  for i in {3..1}; do
    echo -n "$i..."
    sleep 1
  done
  echo -e "\033[0m"
}

# 1. 系统更新
system_update() {
  print_info "正在执行系统更新..."
  if command -v apt-get &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get -qq update > /dev/null
    DEBIAN_FRONTEND=noninteractive apt-get -qq upgrade -y > /dev/null
  elif command -v dnf &>/dev/null; then
    dnf -q -y update > /dev/null
  elif command -v yum &>/dev/null; then
    yum -q -y update > /dev/null
  else
    echo -e "\033[31m[✗] 不支持的包管理器\033[0m"
    exit 1
  fi
  print_success "系统更新完成"
  progress_countdown
}

# 2. 安装必要组件
install_components() {
  print_info "正在安装必要组件..."
  declare -A pkg_map=(
    ["apt"]="wget curl vim mtr ufw ntpdate sudo unzip lvm2"
    ["yum"]="wget curl vim mtr ufw ntp sudo unzip lvm2"
    ["dnf"]="wget curl vim mtr ufw ntp sudo unzip lvm2"
  )

  install_pkg() {
    if command -v apt-get &>/dev/null; then
      for pkg in ${pkg_map[apt]}; do
        dpkg -s "$pkg" &>/dev/null || DEBIAN_FRONTEND=noninteractive apt-get -qq install -y "$pkg" > /dev/null
      done
    elif command -v dnf &>/dev/null; then
      for pkg in ${pkg_map[dnf]}; do
        rpm -q "$pkg" &>/dev/null || dnf -q -y install "$pkg" > /dev/null
      done
    elif command -v yum &>/dev/null; then
      for pkg in ${pkg_map[yum]}; do
        rpm -q "$pkg" &>/dev/null || yum -q -y install "$pkg" > /dev/null
      done
    fi
  }

  install_pkg
  print_success "组件安装完成"
  progress_countdown
}

# 3. 时间配置
configure_time() {
  print_info "正在配置时区和时间同步..."
  timedatectl set-timezone Asia/Shanghai > /dev/null
  if command -v ntpdate &>/dev/null; then
    ntpdate -u pool.ntp.org > /dev/null
    (crontab -l 2>/dev/null; echo "0 * * * * /usr/sbin/ntpdate pool.ntp.org >/dev/null 2>&1") | crontab -
  else
    systemctl enable --now chronyd > /dev/null
  fi
  print_success "时间配置完成"
  progress_countdown
}

# 4. 防火墙配置
configure_firewall() {
  print_info "正在配置防火墙..."
  ufw --force reset > /dev/null
  while read -r rule; do
    ufw $rule > /dev/null
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
  ufw --force enable > /dev/null
  print_success "防火墙配置完成"
  progress_countdown
}

# 5. SWAP配置
configure_swap() {
  print_info "正在配置SWAP..."
  swapoff -a > /dev/null
  if lsblk -o FSTYPE | grep -q swap; then
    lvremove -y $(lsblk -o NAME,FSTYPE | grep swap | awk '{print $1}') > /dev/null 2>&1 || true
  fi
  rm -f /swapfile*

  mem_total=$(free -m | awk '/Mem:/ {print $2}')
  disk_space=$(df -m / | awk 'NR==2 {print $4}')

  declare -A swap_rules=(
    ["512"]="1024 3072"
    ["1024"]="1025 10240"
    ["2048"]="2049 20480"
  )

  for size in "${!swap_rules[@]}"; do
    IFS=' ' read -r min_mem min_disk <<< "${swap_rules[$size]}"
    if (( mem_total <= min_mem && disk_space >= min_disk )); then
      fallocate -l "${size}M" /swapfile > /dev/null
      chmod 600 /swapfile
      mkswap /swapfile > /dev/null
      swapon /swapfile
      echo "/swapfile none swap sw 0 0" >> /etc/fstab
      print_success "已创建 ${size}MB SWAP"
      progress_countdown
      return
    fi
  done
  print_info "跳过SWAP创建"
  progress_countdown
}

# 6. 清理任务
setup_cleanup() {
  print_info "正在设置清理任务..."
  cat << EOF | crontab -
0 0 * * * journalctl --vacuum-time=1d >/dev/null 2>&1
0 0 * * * find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; >/dev/null 2>&1
0 0 * * * (command -v apt-get >/dev/null && apt-get clean) || (command -v dnf >/dev/null && dnf clean all) || (command -v yum >/dev/null && yum clean all) >/dev/null 2>&1
EOF
  print_success "清理任务设置完成"
  progress_countdown
}

# 7. SSH配置
configure_ssh() {
  print_info "正在配置SSH..."
  ssh_dir="/root/.ssh"
  auth_file="$ssh_dir/authorized_keys"
  pubkey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcz1QIr900sswIHYwkkdeYK0BSP7tufSe0XeyRq1Mpj centurnse@Centurnse-I"

  # 创建或修复目录
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  
  # 处理密钥文件
  echo "$pubkey" > "$ssh_dir/id_ed25519.pub"
  touch "$auth_file"
  chmod 600 "$auth_file"
  grep -qxF "$pubkey" "$auth_file" || echo "$pubkey" >> "$auth_file"

  # 配置SSH服务
  sed -i '/^#*PasswordAuthentication/c\PasswordAuthentication no' /etc/ssh/sshd_config
  sed -i '/^#*PubkeyAuthentication/c\PubkeyAuthentication yes' /etc/ssh/sshd_config

  # Ubuntu 24+特殊处理
  if [[ -f /etc/os-release ]] && grep -q 'VERSION_ID="24' /etc/os-release; then
    find /etc/ssh/sshd_config.d/ -name '*.conf' -exec sed -i '/^#*PasswordAuthentication/c\PasswordAuthentication no' {} \;
  fi

  # 重启服务
  if systemctl is-active ssh &>/dev/null; then
    systemctl restart ssh
  elif systemctl is-active sshd &>/dev/null; then
    systemctl restart sshd
  fi
  print_success "SSH配置完成"
  progress_countdown
}

# 主执行流程
main() {
  system_update
  install_components
  configure_time
  configure_firewall
  configure_swap
  setup_cleanup
  configure_ssh
  echo -e "\n\033[32m[+] 所有任务已完成！\033[0m"
}

main
