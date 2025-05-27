#!/bin/bash

primary_ip=38.55.198.59
secondary_ip=68.64.176.133

# 检查并安装/更新 Node.js
setup_nodejs() {
    local server=$1
    echo "检查 $server 的 Node.js 环境..."
    
    # 检查当前Node.js版本
    ssh root@$server "bash -c '
        if command -v node &> /dev/null; then
            current_version=\$(node -v | cut -d\"v\" -f2 | cut -d\".\" -f1)
            if [ \$current_version -lt 20 ]; then
                echo \"Node.js 版本过低 (\$(node -v))，正在更新...\"
                curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
                apt-get install -y nodejs
            else
                echo \"Node.js 版本符合要求 (\$(node -v))\"
            fi
        else
            echo \"未安装 Node.js，正在安装...\"
            curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
            apt-get install -y nodejs
        fi
    '"
}

# 安装依赖
install_dependencies() {
    local server=$1
    echo "在 $server 安装依赖..."
    
    # 创建package.json（如果不存在）
    ssh root@$server "cd /home/crypto_mkt/symbol_server && cat > package.json << 'EOL'
{
  \"name\": \"symbol-server\",
  \"version\": \"1.0.0\",
  \"private\": true,
  \"dependencies\": {
    \"tardis-dev\": \"^11.0.3\",
    \"axios\": \"^1.4.0\",
    \"minimist\": \"^1.2.8\"
  }
}
EOL"
    
    # 安装依赖
    ssh root@$server "cd /home/crypto_mkt/symbol_server && npm install --no-audit --no-fund"
}

# 检查远程连接
check_connection() {
    if ! ssh root@$1 "exit" 2>/dev/null; then
        echo "无法连接到服务器 $1"
        exit 1
    fi
}

# 检查两台服务器的连接
echo "检查服务器连接..."
check_connection $primary_ip
check_connection $secondary_ip

# 在远程服务器创建必要的目录并设置权限
echo "创建远程目录..."
for server in $primary_ip $secondary_ip; do
    echo "配置服务器: $server"
    
    # 检查并安装/更新 Node.js
    setup_nodejs $server
    
    # 创建目录
    ssh root@$server "mkdir -p /home/crypto_mkt/symbol_server && chmod 755 /home/crypto_mkt/symbol_server"
    
    # 复制文件
    echo "复制文件到 $server..."
    scp ./symbol.js root@$server:/home/crypto_mkt/symbol_server/ || { echo "复制 symbol.js 失败"; exit 1; }
    scp ./run_symbol_server.sh root@$server:/home/crypto_mkt/symbol_server/ || { echo "复制 run_symbol_server.sh 失败"; exit 1; }
    scp ../script/binance-futures_snapshot.js root@$server:/home/crypto_mkt/symbol_server/ || { echo "复制 binance-futures_snapshot.js 失败"; exit 1; }
    
    # 设置执行权限
    ssh root@$server "chmod +x /home/crypto_mkt/symbol_server/run_symbol_server.sh"
    
    # 安装依赖
    install_dependencies $server
    
    # 创建systemd服务文件
    echo "配置系统服务..."
    ssh root@$server "cat > /etc/systemd/system/symbol-server.service << 'EOL'
[Unit]
Description=Symbol Server Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/crypto_mkt/symbol_server
ExecStart=/home/crypto_mkt/symbol_server/run_symbol_server.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOL"

    # 重新加载systemd配置并启用服务
    ssh root@$server "systemctl daemon-reload && systemctl enable symbol-server && systemctl restart symbol-server"
    
    echo "服务器 $server 配置完成"
done

echo "部署完成! Symbol Server 已设置为开机启动" 