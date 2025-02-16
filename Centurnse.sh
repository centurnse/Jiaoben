#!/usr/bin/env bash
#set -eo pipefail  # 暂时注释以便调试
trap 'echo -e "\033[31m[ERR] 在 $LINENO 行执行失败 | 最后命令：$BASH_COMMAND\033[0m"; exit 1' ERR

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
NC='\033[0m'

# 诊断代码
declare -A ERROR_CODES=(
    [10]="不支持的Linux发行版"
    [20]="APT更新失败"
    [21]="APT升级失败"
    [30]="组件安装失败"
    [40]="时区设置失败"
    [50]="UFW配置错误"
    [60]="SWAP创建失败"
    [70]="SSH配置错误"
    [80]="网络优化失败"
)

# 进度跟踪
total_steps=8
current_step=0
steps_list=(
    "系统更新"
    "安装组件"
    "时区设置"
    "防火墙配置"
    "SWAP管理"
    "日志清理"
    "SSH配置"
    "网络优化"
)

debug_info() {
    echo -e "\n${CYAN}===== 诊断信息 =====${NC}"
    echo -e "当前步骤：${steps_list[$current_step-1]}"
    echo -e "发行版：$DISTRO"
    echo -e "错误代码：$1"
    echo -e "错误描述：${ERROR_CODES[$1]}"
    echo -e "${CYAN}====================${NC}\n"
    exit $1
}

display_progress() {
    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${GREEN}▶ 当前进度：$current_step/$total_steps ${NC}"
    echo -e "${BLUE}▷ 正在执行：${steps_list[$current_step-1]}${NC}"
    
    (( current_step < total_steps )) && echo -e "${YELLOW}▷ 后续任务：${steps_list[$current_step]}${NC}" || echo -e "${YELLOW}▷ 后续任务：完成所有配置${NC}"
    echo -e "${CYAN}==================================================${NC}\n"
}

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}错误：必须使用root权限运行本脚本${NC}"; exit 1; }

# 增强版系统检测
detect_distro() {
    echo -e "\n${BLUE}[信息] 开始系统检测...${NC}"
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO=$ID
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO="centos"
    elif [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
    else
        echo -e "${RED}错误：无法检测Linux发行版${NC}"
        debug_info 10
    fi
    
    echo -e "${BLUE}[信息] 检测到系统：$DISTRO ${NC}"
    echo -e "${YELLOW}[调试] 系统检测完成，等待3秒...${NC}"
    sleep 3  # 添加暂停观察
}

# 1. 系统更新
system_update() {
    ((current_step++))
    display_progress
    
    echo -e "${YELLOW}[调试] 进入系统更新函数${NC}"
    case $DISTRO in
        ubuntu|debian)
            echo -e "${BLUE}[信息] 准备APT更新...${NC}"
            if ! apt-get -o DPkg::Lock::Timeout=120 -qq update; then
                echo -e "${RED}错误：APT源更新失败${NC}"
                debug_info 20
            fi
            
            echo -e "${BLUE}[信息] 开始系统升级...${NC}"
            if ! apt-get -o DPkg::Lock::Timeout=600 -qq -y --allow-downgrades --allow-remove-essential --allow-change-held-packages upgrade; then
                echo -e "${RED}错误：系统升级失败${NC}"
                debug_info 21
            fi
            ;;
        centos|fedora|rhel)
            yum -y -q --nobest update || debug_info 20
            ;;
        alpine)
            apk -q update || debug_info 20
            apk -q upgrade || debug_info 21
            ;;
        *) debug_info 10 ;;
    esac
    
    echo -e "${GREEN}[✓] 系统更新完成${NC}"
    sleep 2
}

# 后续函数保持相同结构，每个关键操作添加调试输出和错误捕获
# [为节省篇幅，此处展示核心修复部分，完整函数结构保持与之前版本一致]

# 主执行流程
main() {
    detect_distro
    system_update
    install_essentials
    configure_timezone
    setup_firewall
    manage_swap
    configure_logclean
    harden_ssh
    optimize_network
    
    echo -e "\n${GREEN}✔ 所有优化配置已完成！${NC}"
    echo -e "${CYAN}==================================================${NC}"
}

# 执行入口（添加启动日志）
echo -e "${CYAN}==== 脚本启动 ====${NC}"
echo -e "启动时间：$(date)"
echo -e "当前用户：$(whoami)"
echo -e "工作目录：$PWD"
echo -e "${CYAN}==================${NC}\n"

main

# 恢复错误处理
#set -eo pipefail
