#!/bin/bash

# 设置日志目录
LOG_DIR="/var/log"

# 设置保留的日志文件天数
RETENTION_DAYS=1

# 删除1天前的日志文件
find $LOG_DIR -type f -name "*.log" -mtime +$RETENTION_DAYS -exec rm -f {} \;

# 清理systemd日志
journalctl --vacuum-time=1d

echo "系统日志清理完成！"

