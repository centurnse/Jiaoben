#!/bin/bash

# 设置日志目录
LOG_DIR="/var/log"

# 设置保留的日志文件天数
RETENTION_DAYS=1

# 删除过期的系统日志文件
echo "正在删除 $RETENTION_DAYS 天前的系统日志文件..."
find $LOG_DIR -type f -name "*.log" -mtime +$RETENTION_DAYS -exec rm -f {} \;

# 清理 systemd 日志
echo "正在清理 systemd 日志..."
sudo journalctl --vacuum-time=1d

# 输出清理完成信息
echo "系统日志和 systemd 日志清理完成！"
