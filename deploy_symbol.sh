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

# 主程序
main() {
    echo "===== 开始部署 Symbol Server ====="
    # 获取当前工作目录
    echo "当前工作目录: $(pwd)"
    install_dependencies
    sh run_symbol_server.sh
    echo "===== 部署完成 ====="
}

main