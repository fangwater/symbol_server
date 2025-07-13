#!/bin/bash

# 完整的 Symbol Server 部署脚本
# 修复了 Node.js 检测、依赖安装和 systemd 服务问题
# 用法: sudo ./deploy_symbol.sh


# 创建 package.json
create_package_json() {
    echo "===== 创建 package.json ====="
    cat > package.json << 'EOL'
{
  "name": "symbol-server",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "tardis-dev": "*",
    "axios": "*",
    "minimist": "*"
  }
}
EOL
    echo "package.json 创建成功"
}

# 安装依赖
install_dependencies() {
    echo "===== 安装 npm 依赖 ====="
    
    # 确保在正确目录
    if [ ! -f package.json ]; then
        create_package_json
    fi
    
    # 清理可能的旧依赖
    echo "清理旧依赖..."
    rm -rf node_modules package-lock.json
    
    # 安装依赖
    echo "安装依赖..."
    npm install --no-audit --no-fund --loglevel=error
    
    if [ $? -ne 0 ]; then
        echo "❌ 依赖安装失败！"
        exit 1
    fi
    echo "依赖安装成功"
}

# 创建 systemd 兼容的启动脚本
create_run_script() {
    echo "===== 创建 systemd 兼容的启动脚本 ====="
    
    local script_path="run_symbol_server.sh"
    
    cat > "$script_path" << 'EOL'
#!/bin/bash

# 切换到脚本所在目录
cd "$(dirname "$0")"

# 使用绝对路径确保可靠性
NODE_BIN=$(command -v node)
SCRIPT_PATH="./symbol.js"
LOG_FILE="symbol_server.log"

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

# 主进程 - 前台运行（关键修改！）
exec "$NODE_BIN" "$SCRIPT_PATH" > "$LOG_FILE" 2>&1
EOL

    chmod +x "$script_path"
    echo "启动脚本创建成功: $script_path"
    echo "脚本内容:"
    cat "$script_path"
}

# 配置系统服务
setup_service() {
    echo "===== 配置系统服务 ====="
    local current_dir=$(pwd)
    local script_path="$current_dir/run_symbol_server.sh"

    # 验证启动脚本存在
    if [ ! -f "$script_path" ]; then
        echo "❌ 错误：未找到启动脚本 run_symbol_server.sh"
        exit 1
    fi

    # 创建 systemd 服务文件
    cat > /etc/systemd/system/symbol-server.service << EOL
[Unit]
Description=Symbol Server Service
After=network.target

[Service]
Type=forking
WorkingDirectory=${current_dir}
ExecStart=${script_path}
PIDFile=${current_dir}/symbol_server.pid
Restart=always
RestartSec=10
User=root

# 设置环境变量
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/node/bin
Environment=NODE_ENV=production

# 日志重定向到系统日志
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=symbol-server

# 安全限制
NoNewPrivileges=yes
ProtectSystem=strict
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOL

    chmod 644 /etc/systemd/system/symbol-server.service
    chmod +x "$script_path"

    systemctl daemon-reload
    systemctl enable symbol-server
    systemctl restart symbol-server
    
    # 检查服务状态
    sleep 2
    echo -e "\n===== 服务状态 ====="
    systemctl status symbol-server --no-pager
    
    # 显示日志查看提示
    echo -e "\n===== 日志查看命令 ====="
    echo "实时日志: journalctl -u symbol-server -f"
    echo "完整日志: journalctl -u symbol-server -b"
}

# 主程序
main() {
    # 确保以root运行
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ 请使用 root 用户运行此脚本"
        exit 1
    fi

    echo "===== 开始部署 Symbol Server ====="
    
    # 获取当前工作目录
    echo "当前工作目录: $(pwd)"
    install_dependencies
    create_run_script
    setup_service

    echo -e "\n✅ 部署完成! Symbol Server 已设置为开机启动"
    echo "===== 服务管理命令 ====="
    echo "  启动: systemctl start symbol-server"
    echo "  停止: systemctl stop symbol-server"
    echo "  状态: systemctl status symbol-server"
    echo "  日志: journalctl -u symbol-server -f"
    
    # 重要提示
    echo -e "\n===== 重要提示 ====="
    echo "1. 确保 symbol.js 文件存在于当前目录"
    echo "2. 首次启动可能需要一些时间初始化"
    echo "3. 如果服务未运行，请检查日志: journalctl -u symbol-server"
    echo "4. 服务日志同时保存在: $current_dir/symbol_server.log"
    
    # 显示当前目录内容
    echo -e "\n===== 当前目录内容 ====="
    ls -l
}

main