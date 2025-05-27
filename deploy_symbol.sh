#!/bin/bash

# 检查并安装/更新 Node.js
setup_nodejs() {
    echo "检查 Node.js 环境..."
    
    if command -v node &> /dev/null; then
        current_version=$(node -v | cut -d"v" -f2 | cut -d"." -f1)
        if [ $current_version -lt 22 ]; then
            echo "Node.js 版本过低 ($(node -v))，正在更新..."
            curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
            apt-get install -y nodejs
        else
            echo "Node.js 版本符合要求 ($(node -v))"
        fi
    else
        echo "未安装 Node.js，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
        apt-get install -y nodejs
    fi
}

# 创建package.json
create_package_json() {
    echo "创建 package.json..."
    cat > package.json << EOL
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
}

# 安装依赖
install_dependencies() {
    echo "安装依赖..."
    # 如果package.json不存在，先创建它
    if [ ! -f package.json ]; then
        create_package_json
    fi
    npm install --no-audit --no-fund
}

# 配置系统服务
setup_service() {
    echo "配置系统服务..."
    current_dir=$(pwd)
    
    # 创建systemd服务文件
    cat > /etc/systemd/system/symbol-server.service << EOL
[Unit]
Description=Symbol Server Service
After=network.target

[Service]
Type=simple
WorkingDirectory=${current_dir}
ExecStart=${current_dir}/run_symbol_server.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOL

    # 设置执行权限
    chmod +x run_symbol_server.sh

    # 重新加载systemd配置并启用服务
    systemctl daemon-reload
    systemctl enable symbol-server
    systemctl restart symbol-server
}

# 主程序
echo "开始部署 Symbol Server..."

# 检查并安装/更新 Node.js
setup_nodejs

# 安装依赖
install_dependencies

# 配置并启动服务
setup_service

echo "部署完成! Symbol Server 已设置为开机启动"
echo "使用以下命令管理服务："
echo "  启动: systemctl start symbol-server"
echo "  停止: systemctl stop symbol-server"
echo "  状态: systemctl status symbol-server"
echo "  日志: journalctl -u symbol-server" 