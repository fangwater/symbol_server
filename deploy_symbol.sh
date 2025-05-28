#!/bin/bash

# 检查并安装/更新 Node.js
setup_nodejs() {
    echo "检查并安装必要的系统依赖..."
    
    # 确保系统包列表是最新的
    apt-get update
    
    # 安装必要的依赖
    apt-get install -y curl ca-certificates gnupg
    
    echo "检查 Node.js 环境..."
    
    # 检查是否需要安装或更新 Node.js
    local need_install=false
    local need_update=false
    
    if [ ! -x "/usr/bin/node" ]; then
        echo "未安装 Node.js"
        need_install=true
    else
        # 获取完整版本号（例如：v22.16.0）
        local version_str=$(/usr/bin/node --version)
        # 使用 awk 提取主版本号，移除 'v' 前缀
        local major_version=$(echo $version_str | awk -F. '{print substr($1,2)}')
        
        echo "检测到 Node.js: $version_str"
        
        if [[ ! "$major_version" =~ ^[0-9]+$ ]] || [ "$major_version" -lt 22 ]; then
            echo "Node.js 版本过低，需要更新"
            need_update=true
        else
            echo "Node.js 版本符合要求"
        fi
    fi

    # 安装或更新 Node.js
    if [ "$need_install" = true ] || [ "$need_update" = true ]; then
        echo "准备安装/更新 Node.js..."
        # 移除旧版本的 Node.js 源（如果存在）
        rm -f /etc/apt/sources.list.d/nodesource.list
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
        apt-get install -y nodejs
    fi
    
    # 最后验证安装
    if [ ! -x "/usr/bin/node" ]; then
        echo "Node.js 安装失败，请检查系统环境"
        exit 1
    fi
    
    echo "Node.js 安装/更新完成：$(/usr/bin/node --version)"
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