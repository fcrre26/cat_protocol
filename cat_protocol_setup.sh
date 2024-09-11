#!/bin/bash

# 自动化脚本菜单
# 记录文件路径
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
    # 检查 Docker 是否安装
    if ! [ -x "$(command -v docker)" ]; then
        log_error "Docker 未安装。请先选择 '1. 安装 Docker 和依赖' 选项。"
        return 1
    fi

    # 检查 Docker 守护进程是否正在运行
    if ! sudo systemctl is-active --quiet docker; then
        log_error "Docker 守护进程未运行。正在启动..."
        sudo systemctl start docker
        if ! sudo systemctl is-active --quiet docker; then
            log_error "无法启动 Docker 守护进程。请检查 Docker 安装。"
            return 1
        fi
        echo "Docker 守护进程已启动。"
    fi

    # 检查 docker-compose 是否安装
    if ! [ -x "$(command -v docker-compose)" ]; then
        log_error "docker-compose 未找到，正在安装 docker-compose 插件..."
        sudo apt-get update
        sudo apt-get install docker-compose-plugin -y
        if ! [ -x "$(command -v docker-compose)" ]; then
            log_error "docker-compose 安装失败。请手动检查并安装。"
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
    sudo apt-get install docker.io -y

    VERSION=$(curl --silent https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*\d')
    DESTINATION=/usr/local/bin/docker-compose
    sudo curl -L https://github.com/docker/compose/releases/download/${VERSION}/docker-compose-$(uname -s)-$(uname -m) -o $DESTINATION
    sudo chmod 755 $DESTINATION

    sudo apt-get install npm -y
    sudo npm install n -g
    sudo n stable
    sudo npm i -g yarn

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

    # 标记 Git 仓库已拉取并编译
    touch "$REPO_CLONED_FLAG"

    echo "Git 仓库拉取并编译完成。"
}

# 3. 运行 Fractal 节点和 CAT 索引器
function run_docker_containers() {
    if [ -f "$NODE_RUNNING_FLAG" ]; then
        echo "Fractal 节点和 CAT 索引器已运行，跳过此步骤。"
        return
    fi

    # 检查 Docker 和 docker-compose
    if ! check_docker; then
        return 1
    fi

    echo "运行 Fractal 节点和 CAT 索引器..."
    
    cd ./packages/tracker/ || exit
    sudo chmod 777 docker/data
    sudo chmod 777 docker/pgdata
    sudo docker-compose up -d

    cd ../../
    sudo docker build -t tracker:latest .
    sudo docker run -d \
        --name tracker \
        --add-host="host.docker.internal:host-gateway" \
        -e DATABASE_HOST="host.docker.internal" \
        -e RPC_HOST="host.docker.internal" \
        -p 3000:3000 \
        tracker:latest

    # 标记节点已运行
    touch "$NODE_RUNNING_FLAG"

    echo "Fractal 节点和 CAT 索引器已启动。"
}

# 4. 创建新钱包
function create_wallet() {
    echo "创建新钱包..."
    
    # 检查比特币 RPC 服务是否运行
    if ! nc -z 127.0.0.1 8332; then
        log_error "无法连接到比特币节点 (127.0.0.1:8332)。请确保比特币节点已启动。"
        return 1
    fi

    cd packages/cli || exit

    # 如果 config.json 不存在，创建一个新的配置文件
    if [ ! -f config.json ]; then
        cat > config.json <<EOL
{
  "network": "fractal-mainnet",
  "tracker": "http://127.0.0.1:3000",
  "dataDir": ".",
  "maxFeeRate": 30,
  "rpc": {
      "url": "http://127.0.0.1:8332",
      "username": "bitcoin",
      "password": "opcatAwesome"
  }
}
EOL
    fi

    # 创建新钱包并捕获输出
    WALLET_OUTPUT=$(sudo yarn cli wallet create)

    # 提取助记词、私钥和地址
    MNEMONIC=$(echo "$WALLET_OUTPUT" | grep -oP '(?<=Mnemonic: ).*')
    PRIVATE_KEY=$(echo "$WALLET_OUTPUT" | grep -oP '(?<=Private Key: ).*')
    ADDRESS=$(echo "$WALLET_OUTPUT" | grep -oP '(?<=Taproot Address: ).*')

    # 打印提取到的钱包信息
    echo "钱包创建成功:"
    echo "助记词: $MNEMONIC"
    echo "私钥: $PRIVATE_KEY"
    echo "地址 (Taproot格式): $ADDRESS"

    # 记录钱包信息到文件
    echo "钱包信息已保存到 $WALLET_LOG"
    {
        echo "钱包创建时间: $(date)"
        echo "助记词: $MNEMONIC"
        echo "私钥: $PRIVATE_KEY"
        echo "地址 (Taproot格式): $ADDRESS"
        echo "--------------------------"
    } >> ../../$WALLET_LOG

    cd ../../
}

# 5. 执行 mint
function execute_mint() {
    echo "执行 mint 操作..."
    
    # 检查比特币 RPC 服务是否运行
    if ! nc -z 127.0.0.1 8332; then
        log_error "无法连接到比特币节点 (127.0.0.1:8332)。请确保比特币节点已启动。"
        return 1
    fi

    cd packages/cli || exit

    # 显示已有的钱包信息
    echo "可用钱包:"
    cat ../../$WALLET_LOG

    # 钱包选择
    echo "请输入要使用的钱包索引 (例如 1):"
    read -r wallet_index

    # 输入交易哈希 (txid)
    read -p "请输入交易哈希 (txid): " txid
    if ! [[ "$txid" =~ ^[a-fA-F0-9]{64}$ ]]; then
        log_error "无效的交易哈希，请输入正确的 64 位十六进制字符串。"
        return 1
    fi

    # 输入交易索引 (index)
    read -p "请输入交易索引 (index): " index
    if ! [[ "$index" =~ ^[0-9]+$ ]]; then
        log_error "无效的交易索引，请输入一个正整数。"
        return 1
    fi

    # 输入 mint 数量
    read -p "请输入要 mint 的数量: " mint_amount
    if ! [[ "$mint_amount" =~ ^[0-9]+$ ]]; then
        log_error "无效的 mint 数量，请输入一个正整数。"
        return 1
    fi

    # 开始 mint 操作
    command="sudo yarn cli mint -i ${txid}_${index} $mint_amount"

    while true; do
        $command

        if [ $? -ne 0 ]; then
            echo "mint 失败，继续下一次..."
        else
            echo "mint 成功"
        fi

        sleep 1
    done

    cd ../../
}

# 6. 查看 Fractal 节点运行情况
function check_node_status() {
    echo "查看 Fractal 节点运行情况..."

    # 检查 docker-compose 是否安装
    if ! check_docker; then
        return 1
    fi

    cd packages/tracker || exit
    while true; do
        sudo docker-compose logs --tail=10
        sleep 5
        clear
    done

    cd ../../
}

# 菜单循环
while true; do
    print_menu
    read -rp "请输入选项: " choice

    case $choice in
        1)
            install_dependencies
            ;;
        2)
            pull_and_build_repo
            ;;
        3)
            run_docker_containers
            ;;
        4)
            create_wallet
            ;;
        5)
            execute_mint
            ;;
        6)
            check_node_status
            ;;
        7)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效选项，请重试。"
            ;;
    esac
done
