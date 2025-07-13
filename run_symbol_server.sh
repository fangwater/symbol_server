#!/bin/bash

# 切换到脚本所在目录
cd "$(dirname "$0")"

# 使用绝对路径确保可靠性
NODE_BIN=$(command -v node)
SCRIPT_PATH="./symbol.js"
LOG_FILE="symbol_server.log"
PID_FILE="symbol_server.pid"

# 检查Node.js是否可用
if [ -z "$NODE_BIN" ]; then
    echo "❌ 错误：未找到Node.js可执行文件" >&2
    exit 1
fi

# 检查symbol.js是否存在
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "❌ 错误：未找到symbol.js脚本" >&2
    exit 1
fi

# 后台运行 - 使用nohup
echo "启动 Symbol Server 后台进程..."
nohup "$NODE_BIN" "$SCRIPT_PATH" > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
echo "Symbol Server 已启动，PID: $(cat $PID_FILE)"