#!/usr/bin/env bash
 set -eo pipefail
 trap 'echo -e "\033[31m[ERR] 在 $LINENO 行执行失败 | 最后命令：$BASH_COMMAND\033[0m"; exit 1' ERR
 
 # ==================== 配置部分 ====================
 RED='\033[31m'
 GREEN='\033[32m'
 YELLOW='\033[33m'
 BLUE='\033[34m'
 CYAN='\033[36m'
 NC='\033[0m'
 
 # ==================== 界面引擎 ====================
 interface_lock=false  # 界面渲染锁
 
 # 初始化界面
 init_interface() {
 # ==================== 功能函数 ====================
 display_progress() {
     clear
     echo -e "${CYAN}=================================================="
     echo " 自动化系统优化脚本"
     echo -e "==================================================${NC}"
     echo -e "${GREEN}▶ 当前进度：0/8"
     echo -e "${BLUE}▷ 正在执行：初始化"
     echo -e "${YELLOW}▷ 后续任务：系统检测"
     echo -e "${CYAN}=================================================="
     echo -e "${YELLOW}⏳ 初始化界面..." 
 }
 
 # 更新进度信息
 update_progress() {
     # 加锁防止渲染冲突
     while $interface_lock; do sleep 0.01; done
     interface_lock=true
     
     # 使用ANSI转义码精确控制光标
     echo -ne "\033[3A"  # 上移3行到进度信息开始处
     echo -e "\033[K${GREEN}▶ 当前进度：$1/$2"
     echo -e "\033[K${BLUE}▷ 正在执行：${3}"
     echo -e "\033[K${YELLOW}▷ 后续任务：${4}"
     echo -ne "\033[3B"  # 移回原光标位置
     
     interface_lock=false
     echo -e "${GREEN}▶ 当前进度：$1/$2"
     echo -e "${BLUE}▷ 正在执行：${3}"
     echo -e "${YELLOW}▷ 后续任务：${4}"
     echo -e "${CYAN}==================================================${NC}"
     echo
 }
 
 # 倒计时显示器
 countdown() {
     local seconds=3
     # 初始化倒计时行
     echo -e "\n${CYAN}==================================================${NC}"
     echo -ne "${YELLOW}⏳ 将在${seconds}秒后继续\033[K\r"
     
     while (( seconds > 0 )); do
 progress_countdown() {
     for i in {3..1}; do
         echo -ne "${YELLOW}倒计时：${i} 秒\033[0K\r"
         sleep 1
         ((seconds--))
         echo -ne "${YELLOW}⏳ 将在${seconds}秒后继续\033[K\r"
     done
     # 清除倒计时区域
     echo -ne "\033[1A\033[2K\033[1A"
     echo -e "${NC}"
 }
 
 # ==================== 核心功能 ====================
 @@ -236,11 +209,9 @@
 main() {
     [[ $EUID -ne 0 ]] && { echo -e "${RED}必须使用root权限运行" >&2; exit 1; }
 
     # 初始化界面
     init_interface
     local total_steps=8
     local current_step=0
     local steps=(
         "系统检测"
         "系统更新"
         "安装组件"
         "时区设置"
 @@ -251,53 +222,29 @@
         "网络优化"
     )
 
     # 系统检测
     update_progress 1 $total_steps "系统检测" "系统更新"
     detect_distro
     countdown
 
     for ((step=1; step<=total_steps; step++)); do
         case $step in
             1) ;; # 已处理系统检测
             2) 
                 update_progress $step $total_steps "系统更新" "安装组件"
                 system_update
                 ;;
             3)
                 update_progress $step $total_steps "安装组件" "时区设置"
                 install_essentials
                 ;;
             4)
                 update_progress $step $total_steps "时区设置" "防火墙配置"
                 configure_timezone
                 ;;
             5)
                 update_progress $step $total_steps "防火墙配置" "SWAP管理"
                 setup_firewall
                 ;;
             6)
                 update_progress $step $total_steps "SWAP管理" "日志清理"
                 manage_swap
                 ;;
             7)
                 update_progress $step $total_steps "日志清理" "SSH配置"
                 configure_logclean
                 ;;
             8)
                 update_progress $step $total_steps "SSH配置" "网络优化"
                 harden_ssh
                 ;;
             9)
                 update_progress $step $total_steps "网络优化" "完成"
                 optimize_network
                 ;;
     for step in "${!steps[@]}"; do
         current_step=$((step+1))
         next_step=$((current_step+1))
         display_progress $current_step $total_steps "${steps[$step]}" "${steps[$next_step]:-完成}"
         
         case $current_step in
             1) system_update ;;
             2) install_essentials ;;
             3) configure_timezone ;;
             4) setup_firewall ;;
             5) manage_swap ;;
             6) configure_logclean ;;
             7) harden_ssh ;;
             8) optimize_network ;;
         esac
         (( step < total_steps )) && countdown
 
         echo -e "${GREEN}[✓] ${steps[$step]} 完成"
         progress_countdown
     done
 
     # 最终显示
     echo -ne "\033[2A\033[2K"
     echo -e "${CYAN}=================================================="
     echo -e "\n${CYAN}=================================================="
     echo -e "${GREEN}✔ 所有优化配置已完成！"
     echo -e "${CYAN}==================================================${NC}"
 }
