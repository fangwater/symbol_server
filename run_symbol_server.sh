#!/bin/bash

# 清理函数
cleanup() {
    echo "清理 exchange 目录..."
    rm -rf ./exchange/*
}

# 检查进程是否在运行
check_process() {
    # 检查PID文件
    if [ -f ./symbol_server.pid ]; then
        pid=$(cat ./symbol_server.pid)
        if ps -p $pid > /dev/null 2>&1; then
            # 检查是否确实是symbol.js进程
            if ps -p $pid -o cmd= | grep -q "node.*symbol.js"; then
                echo "Symbol server 正在运行 (PID: $pid)"
                return 0
            fi
        fi
        # PID文件存在但进程不存在或不匹配，清理PID文件
        rm -f ./symbol_server.pid
    fi

    # 检查是否有其他symbol.js进程在运行
    existing_pid=$(pgrep -f "node.*symbol.js")
    if [ ! -z "$existing_pid" ]; then
        echo $existing_pid > ./symbol_server.pid
        echo "发现运行中的 symbol.js 进程 (PID: $existing_pid)"
        return 0
    fi

    return 1
}

# 主程序
cd "$(dirname "$0")"  # 确保在脚本所在目录

# 检查进程状态
if check_process; then
    echo "服务已在运行，无需重启"
    exit 0
fi

# 清理环境
cleanup

# 启动服务
echo "启动 symbol server..."
node ./symbol.js > symbol_server.log 2>&1 &
echo $! > ./symbol_server.pid

echo "Symbol server started with PID: $(cat ./symbol_server.pid)"
