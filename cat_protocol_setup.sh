#!/bin/bash

# 自动化脚本菜单
WALLET_LOG="wallet_info.txt"
DOCKER_INSTALLED_FLAG="/tmp/docker_installed"
REPO_CLONED_FLAG="/tmp/repo_cloned"
NODE_RUNNING_FLAG="/tmp/node_running"

# 打印菜单选项
function print_menu() {
    echo "请选择一个选项："
    echo "1. 安装 Docker 和依赖"
    echo "2. 拉取 Git 仓库并编译"
    echo "3. 运行 Fractal 节点和 CAT 索引器"
    echo "4. 创建新钱包"
    echo "5. 执行 mint"
    echo "6. 查看 Fractal 节点运行情况"
    echo "7. 退出"
}

# 错误日志函数
function log_error() {
    echo -e "\033[31m$1\033[0m"  # 红色输出错误信息
}

# 检查 docker 和 docker-compose 是否可用
function check_docker() {
    if ! [ -x "$(command -v docker)" ]; then
        log_error "Docker 未安装。请先选择 '1. 安装 Docker 和依赖' 选项。"
        return 1
    fi

    if ! sudo systemctl is-active --quiet docker; then
        log_error "Docker 守护进程未运行。正在启动..."
        sudo systemctl start docker
        if ! sudo systemctl is-active --quiet docker; then
            log_error "无法启动 Docker 守护进程。请检查 Docker 安装。"
            return 1
        fi
        echo "Docker 守护进程已启动。"
    fi

    if ! [ -x "$(command -v docker-compose)" ]; then
        log_error "docker-compose 未找到，正在安装 docker-compose 插件..."
        sudo apt-get update
        sudo apt-get install -y docker-compose-plugin
        if ! [ -x "$(command -v docker-compose)" ]; then
            log_error "docker-compose 安装失败。"
            return 1
        fi
        echo "docker-compose 安装成功。"
    fi
    return 0
}

# 1. 安装 Docker 和依赖
function install_dependencies() {
    if [ -f "$DOCKER_INSTALLED_FLAG" ]; then
        echo "Docker 和依赖已安装，跳过此步骤。"
        return
    fi

    echo "安装 Docker 和依赖..."
    sudo apt-get update
    sudo apt-get install -y docker.io npm
    sudo npm install -g yarn

    # 标记 Docker 已安装
    touch "$DOCKER_INSTALLED_FLAG"
    echo "Docker 和依赖安装完成。"
}

# 2. 拉取 Git 仓库并编译
function pull_and_build_repo() {
    if [ -f "$REPO_CLONED_FLAG" ]; then
        echo "Git 仓库已拉取并编译，跳过此步骤。"
        return
    fi

    echo "拉取 Git 仓库并编译..."
    git clone https://github.com/CATProtocol/cat-token-box
    cd cat-token-box || exit
    sudo yarn install
    sudo yarn build
    touch "$REPO_CLONED_FLAG"
    echo "Git 仓库拉取并编译完成。"
}

# 3. 运行 Fractal 节点和 CAT 索引器
function run_docker_containers() {
    if [ -f "$NODE_RUNNING_FLAG" ]; then
        echo "Fractal 节点和 CAT 索引器已运行，跳过此步骤。"
        return
    fi

    if ! check_docker; then
        return 1
    fi

    if [ ! -d "cat-token-box/packages/tracker/" ]; then
        log_error "找不到 packages/tracker/ 目录，请检查仓库是否正确克隆。"
        return 1
    fi

    echo "运行 Fractal 节点和 CAT 索引器..."
    cd cat-token-box/packages/tracker/ || exit
    sudo docker-compose up -d
    cd ../../
    sudo docker build -t tracker:latest .
    sudo docker run -d --name tracker -p 3000:3000 tracker:latest
    touch "$NODE_RUNNING_FLAG"
    echo "Fractal 节点和 CAT 索引器已启动。"
}

# 4. 创建新钱包
function create_wallet() {
    echo "创建新钱包..."
    if ! nc -z 127.0.0.1 8332; then
        log_error "无法连接到比特币节点 (127.0.0.1:8332)。请确保比特币节点已启动。"
        return 1
    fi

    cd cat-token-box/packages/cli || exit
    if [ ! -f config.json ]; then
        cat > config.json <<EOL
{
  "network": "fractal-mainnet",
  "tracker": "http://127.0.0.1:3000",
  "rpc": {
      "url": "http://127.0.0.1:8332",
      "username": "bitcoin",
      "password": "opcatAwesome"
  }
}
EOL
    fi

    # 捕获输出并调试
    WALLET_OUTPUT=$(sudo yarn cli wallet create 2>&1)
    echo "Wallet creation output: $WALLET_OUTPUT"

    MNEMONIC=$(echo "$WALLET_OUTPUT" | grep -oP '(?<=Mnemonic: ).*')
    PRIVATE_KEY=$(echo "$WALLET_OUTPUT" | grep -oP '(?<=Private Key: ).*')
    ADDRESS=$(echo "$WALLET_OUTPUT" | grep -oP '(?<=Taproot Address: ).*')

    if [ -z "$MNEMONIC" ] || [ -z "$PRIVATE_KEY" ] || [ -z "$ADDRESS" ]; then
        log_error "钱包创建失败。请检查比特币节点连接和 CLI 工具。"
        return 1
    fi

    echo "钱包创建成功:"
    echo "助记词: $MNEMONIC"
    echo "私钥: $PRIVATE_KEY"
    echo "地址: $ADDRESS"

    echo "钱包信息已保存到 $WALLET_LOG"
    {
        echo "钱包创建时间: $(date)"
        echo "助记词: $MNEMONIC"
        echo "私钥: $PRIVATE_KEY"
        echo "地址: $ADDRESS"
        echo "--------------------------"
    } >> ../../$WALLET_LOG
    cd ../../
}

# 6. 查看 Fractal 节点运行情况
function check_node_status() {
    if ! check_docker; then
        return 1
    fi

    if [ ! -d "cat-token-box/packages/tracker/" ]; then
        log_error "找不到 packages/tracker/ 目录，请检查仓库是否正确克隆。"
        return 1
    fi

    echo "查看 Fractal 节点运行情况..."
    cd cat-token-box/packages/tracker/ || exit
    sudo docker-compose logs --tail=10
    cd ../../
}

# 菜单循环
while true; do
    print_menu
    read -rp "请输入选项: " choice
    case $choice in
        1) install_dependencies ;;
        2) pull_and_build_repo ;;
        3) run_docker_containers ;;
        4) create_wallet ;;
        6) check_node_status ;;
        7) echo "退出脚本。" ; exit 0 ;;
        *) echo "无效选项，请重试。" ;;
    esac
done
