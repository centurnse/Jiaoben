#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$(id -u)" -ne "0" ]; then
	    echo "请使用 root 权限运行此脚本！"
	        exit 1
fi

# 输出彩色提示信息函数
function echo_color {
	    echo -e "\033[1;32m$1\033[0m"
    }

# 1. 系统更新
echo_color "查找当前系统的更新内容并将所有可用更新应用到本机"
echo_color "正在更新系统..."
if [[ -f /etc/debian_version ]]; then
	    apt update && apt upgrade -y && apt dist-upgrade -y
    elif [[ -f /etc/centos-release ]]; then
	        yum update -y
	else
		    echo_color "未知的操作系统，无法执行更新"
		        exit 1
fi
echo_color "系统更新完成！"

# 2. 安装常用依赖
echo_color "安装 wget curl vim mtr ufw ntpdate sudo unzip 到本机"
echo_color "正在安装常用依赖..."
if [[ -f /etc/debian_version ]]; then
	    apt install -y wget curl vim mtr ufw ntpdate sudo unzip
    elif [[ -f /etc/centos-release ]]; then
	        yum install -y wget curl vim mtr ufw ntpdate sudo unzip
	else
		    echo_color "未知的操作系统，无法安装依赖"
		        exit 1
fi
echo_color "常用依赖安装完成！"

# 3. 设置时区并同步时间
echo_color "设置时区为 Asia/Shanghai，设置时区完成之后进行时间同步"
echo_color "正在设置时区为 Asia/Shanghai..."
timedatectl set-timezone Asia/Shanghai
echo_color "时区设置完成！"

echo_color "正在同步时间..."
ntpdate cn.pool.ntp.org
echo_color "时间同步完成！"

# 4. 安装 UFW 并应用规则
echo_color "安装 UFW 并添加常用规则"
echo_color "正在安装 UFW..."
if [[ -f /etc/debian_version ]]; then
	    apt install -y ufw
    elif [[ -f /etc/centos-release ]]; then
	        yum install -y ufw
	else
		    echo_color "未知的操作系统，无法安装 ufw"
		        exit 1
fi

echo_color "正在应用 UFW 规则..."
ufw allow 22/tcp
ufw allow 22/udp
ufw allow 80/tcp
ufw allow 80/udp
ufw allow 88/tcp
ufw allow 88/udp
ufw allow 443/tcp
ufw allow 443/udp
ufw allow 5555/tcp
ufw allow 5555/udp
ufw allow 8008/tcp
ufw allow 8008/udp
ufw allow 32767/tcp
ufw allow 32767/udp
ufw allow 32768/tcp
ufw allow 32768/udp
ufw deny from 162.142.125.0/24
ufw deny from 167.94.138.0/24
ufw deny from 167.94.145.0/24
ufw deny from 167.94.146.0/24
ufw deny from 167.248.133.0/24
ufw deny from 199.45.154.0/24
ufw deny from 199.45.155.0/24
ufw deny from 206.168.34.0/24
ufw deny from 2602:80d:1000:b0cc:e::/80
ufw deny from 2620:96:e000:b0cc:e::/80
ufw deny from 2602:80d:1003::/112
ufw deny from 2602:80d:1004::/112

# 启用 UFW 防火墙，自动确认
echo "y" | ufw enable

echo_color "UFW 安全规则应用完成！"

# 5. 检测内存和硬盘空间并生成SWAP
echo_color "根据内存和硬盘剩余空间来生成合适的 SWAP 文件并调整优先级"

# 获取系统内存和硬盘空间信息
MEMORY=$(free -m | grep Mem | awk '{print $2}')
DISK_FREE=$(df / | grep / | awk '{print $4}')

echo_color "内存大小: ${MEMORY}MB"
echo_color "硬盘剩余空间: ${DISK_FREE}KB"

# 检查是否已经有 SWAP 文件
SWAP_EXIST=$(swapon --show | grep -c ^/swapfile)

if [ "$SWAP_EXIST" -gt 0 ]; then
	    echo_color "检测到已有 SWAP 文件，正在停用并删除当前 SWAP 文件..."
	        
	        # 停用当前的 SWAP 文件
		    swapoff /swapfile
		        
		        # 永久删除当前 SWAP 文件
			    rm -f /swapfile
			        
			        # 从 fstab 中删除对应的 SWAP 配置
				    sed -i '/\/swapfile/d' /etc/fstab
				        echo_color "当前 SWAP 文件已删除！"
fi

# 生成SWAP的大小和优先级
SWAP_SIZE=0
SWAP_PRIORITY=0

if [ "$MEMORY" -le 512 ]; then
	    if [ "$DISK_FREE" -gt 5120 ]; then  # 5GB
		            SWAP_SIZE=1024  # 1GB
			            SWAP_PRIORITY=100
				        fi
				elif [ "$MEMORY" -le 1024 ]; then
					    if [ "$DISK_FREE" -gt 10240 ]; then  # 10GB
						            SWAP_SIZE=2048  # 2GB
							            SWAP_PRIORITY=80
								        elif [ "$DISK_FREE" -gt 5120 ]; then  # 5GB
										        SWAP_SIZE=1024  # 1GB
											        SWAP_PRIORITY=60
												    fi
											    elif [ "$MEMORY" -gt 1024 ]; then
												        if [ "$DISK_FREE" -gt 10240 ]; then  # 10GB
														        SWAP_SIZE=2048  # 2GB
															        SWAP_PRIORITY=50
																    elif [ "$DISK_FREE" -gt 5120 ]; then  # 5GB
																	            SWAP_SIZE=1024  # 1GB
																		            SWAP_PRIORITY=50
																			        fi
fi

if [ "$SWAP_SIZE" -gt 0 ]; then
	    echo_color "正在创建 ${SWAP_SIZE}MB 的 SWAP 文件..."
	        
	        # 创建 SWAP 文件
		    dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE
		        chmod 600 /swapfile
			    mkswap /swapfile
			        swapon /swapfile

				    # 永久启用 SWAP
				        echo '/swapfile none swap sw 0 0' >> /etc/fstab

					    # 调整 SWAP 优先级
					        swapon -p $SWAP_PRIORITY /swapfile

						    echo_color "SWAP 文件已创建并启用，优先级为 ${SWAP_PRIORITY}！"
					    else
						        echo_color "内存和硬盘空间不足以创建 SWAP 文件。"
		    fi

		    # 结束
		    echo_color "所有操作已完成！"

