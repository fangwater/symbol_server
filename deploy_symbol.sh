#!/bin/bash

# 完整的 Symbol Server 部署脚本
# 修复了 Node.js 检测、依赖安装和 systemd 服务问题
# 用法: sudo ./deploy_symbol.sh

# 检查并安装/更新 Node.js
setup_nodejs() {
    echo "===== 检查 Node.js 环境 ====="
    local need_action=false
    local node_path=""
    local npm_path=""

    # 更可靠的 Node.js 检测方式
    if command -v node &> /dev/null; then
        node_path=$(command -v node)
        echo "检测到 Node.js 已安装: $node_path"
        
        # 获取 Node.js 版本
        version_str=$("$node_path" --version 2>/dev/null)
        
        # 验证版本号格式
        if [[ "$version_str" =~ ^v([0-9]+)\. ]]; then
            major_version=${BASH_REMATCH[1]}
            echo "当前版本: $version_str (主版本: $major_version)"
            
            if [ "$major_version" -lt 22 ]; then
                echo "Node.js 版本过低 (需要 v22.x)"
                need_action=true
            else
                echo "Node.js 版本符合要求"
            fi
        else
            echo "⚠️ 无法解析 Node.js 版本: '$version_str'"
            need_action=true
        fi
    else
        echo "未检测到 Node.js"
        need_action=true
    fi

    # 仅在需要时处理 Node.js
    if [ "$need_action" = true ]; then
        echo "准备安装/更新 Node.js v22.x..."
        
        # 安装系统依赖
        echo "安装必要的系统依赖..."
        apt-get update
        apt-get install -y curl ca-certificates gnupg
        
        # 清理旧版本和源
        echo "清理旧版本..."
        apt-get purge -y nodejs npm &> /dev/null
        rm -rf /etc/apt/sources.list.d/nodesource.list*
        
        # 添加 NodeSource 源
        echo "添加 NodeSource 源..."
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
        echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
        
        # 安装 Node.js
        echo "安装 Node.js..."
        apt-get update
        apt-get install -y nodejs
        
        # 验证安装
        if ! command -v node &> /dev/null; then
            echo "❌ Node.js 安装失败！"
            exit 1
        fi
        
        # 设置新安装的路径
        node_path=$(command -v node)
        npm_path=$(command -v npm)
        echo "Node.js 安装成功: $($node_path --version)"
        echo "NPM 安装成功: $($npm_path --version)"
    fi
    
    # 确保 NPM 可用
    if ! command -v npm &> /dev/null; then
        echo "❌ NPM 不可用，安装失败！"
        exit 1
    fi
}

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
Type=simple
WorkingDirectory=${current_dir}
ExecStart=${script_path}
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
    
    # 仅在需要时更新系统
    setup_nodejs
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