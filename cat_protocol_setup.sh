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

# 检查 curl 是否安装
function check_curl() {
    if ! [ -x "$(command -v curl)" ]; then
        echo "curl 未安装。正在安装 curl..."
        sudo apt-get update
        sudo apt-get install -y curl
        if ! [ -x "$(command -v curl)" ]; then
            log_error "curl 安装失败。请手动安装 curl。"
            return 1
        else
            echo "curl 安装成功。"
        fi
    fi
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

        # 先尝试通过官方包管理器安装 docker-compose-plugin
        sudo apt-get install -y docker-compose-plugin

        # 如果 docker-compose 仍然不可用，回退到使用 curl 安装
        if ! [ -x "$(command -v docker-compose)" ]; then
            log_error "docker-compose 插件安装失败，正在尝试使用 curl 安装 docker-compose。"
            check_curl
            sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        fi

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

    # 安装最新版本的 docker-compose
    check_curl
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

    # 安装项目依赖
    sudo yarn install
    sudo yarn build

    # 安装兼容版本的 bip39 和 bitcoinjs-lib 依赖
    echo "安装 bip39, bip32 和 bitcoinjs-lib..."
    npm install bip39@3.0.4 bitcoinjs-lib@6.1.0 bip32@2.0.6 secp256k1@4.0.2 tiny-secp256k1@^1.0.0

    if [ $? -ne 0 ]; then
        log_error "npm 依赖安装失败。请手动检查。"
        return 1
    fi

    echo "bip39 和 bitcoinjs-lib 依赖安装成功。"

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

    # 保存初始目录
    initial_dir=$(pwd)

    # 确保 cat-token-box/packages/tracker/ 目录存在
    if [ ! -d "cat-token-box/packages/tracker/" ]; then
        log_error "找不到 packages/tracker/ 目录，请检查仓库是否正确克隆。"
        return 1
    fi

    echo "运行 Fractal 节点和 CAT 索引器..."

    # 切换到 tracker 目录
    cd ./cat-token-box/packages/tracker/ || exit

    # 修改文件权限
    sudo chmod 777 docker/data
    sudo chmod 777 docker/pgdata

    # 使用 docker-compose 启动服务
    sudo docker-compose up -d

    # 返回到 cat-token-box 目录并构建 Docker 镜像
    cd ../../
    sudo docker build -t tracker:latest .

    # 运行tracker 容器
    sudo docker run -d \
        --name tracker \
        --add-host="host.docker.internal:host-gateway" \
        -e DATABASE_HOST="host.docker.internal" \
        -e RPC_HOST="host.docker.internal" \
        -p 3000:3000 \
        tracker:latest

    # 返回到初始目录
    cd "$initial_dir"

    # 标记节点已运行
    touch "$NODE_RUNNING_FLAG"

    echo "Fractal 节点和 CAT 索引器已启动。"
}


# 4. 创建新钱包
function create_wallet() {
    echo "正在创建钱包，请稍候..."

    # 检查比特币 RPC 服务是否运行
    if ! nc -z 127.0.0.1 8332; then
        echo "无法连接到比特币节点 (127.0.0.1:8332)。请确保比特币节点已启动。"
        return 1
    fi

    # 导航到 cli 目录
    cd /root/cat-token-box/packages/cli || exit

    # 检查并生成 config.json 文件
    if [ ! -f config.json ]; then
        echo "config.json 文件未找到，正在创建..."

        # 提示用户输入比特币 RPC 用户名，默认值为 'bitcoin'
        read -p "请输入比特币 RPC 用户名 [默认: bitcoin]: " rpc_username
        rpc_username=${rpc_username:-bitcoin}

        # 提示用户输入比特币 RPC 密码，默认值为 'opcatAwesome'
        read -p "请输入比特币 RPC 密码 [默认: opcatAwesome]: " rpc_password
        rpc_password=${rpc_password:-opcatAwesome}

        # 生成 config.json 文件
        cat > config.json <<EOL
{
  "network": "fractal-mainnet",
  "tracker": "http://127.0.0.1:3000",
  "dataDir": ".",
  "maxFeeRate": 30,
  "rpc": {
      "url": "http://127.0.0.1:8332",
      "username": "$rpc_username",
      "password": "$rpc_password"
  }
}
EOL
        echo "config.json 文件已创建。"
    else
        echo "config.json 文件已存在，跳过创建。"
    fi

    # 创建新钱包并捕获输出
    echo "钱包生成成功！"
    WALLET_OUTPUT=$(sudo -E yarn cli wallet create 2>&1)

    if [ $? -ne 0 ]; then
        echo "创建钱包失败: $WALLET_OUTPUT"
        return 1
    fi

    # 提取 wallet.json 文件内容
    if [ ! -f wallet.json ]; then
        echo "未找到 wallet.json 文件，钱包创建失败。"
        return 1
    fi

    # 读取 wallet.json 文件
    ACCOUNT_PATH=$(jq -r '.accountPath' wallet.json)
    WALLET_NAME=$(jq -r '.name' wallet.json)
    MNEMONIC=$(jq -r '.mnemonic' wallet.json)

    if [ -z "$MNEMONIC" ]; then
        echo "未能从 wallet.json 提取助记词，钱包创建失败。"
        return 1
    fi

    echo "助记词: $MNEMONIC"

    # 使用助记词生成私钥和 Taproot 地址
    echo "正在通过助记词生成私钥和 Taproot 地址..."

    # 生成私钥和地址的代码
    PRIVATE_KEY=$(node -e "
      (async () => {
          const bip39 = require('bip39');
          const ecc = require('tiny-secp256k1');  // 使用正确的 secp256k1 实现
          const BIP32Factory = require('bip32').default;

          const bip32 = BIP32Factory(ecc);   // 创建 bip32 工厂
          const bitcoin = require('bitcoinjs-lib');
          
          const { mnemonicToSeedSync } = bip39;
          const mnemonic = '$MNEMONIC';
          const seed = mnemonicToSeedSync(mnemonic);
          const root = bip32.fromSeed(seed);
          const account = root.derivePath('m/86\'/0\'/0\'/0/0');  // 导出路径
          
          console.log(account.toWIF());  // 输出私钥
      })().catch(console.error);
    ")

    ADDRESS=$(node -e "
      (async () => {
          const bip39 = require('bip39');
          const ecc = require('tiny-secp256k1');  // 使用 tiny-secp256k1 作为 ECC 库
          const BIP32Factory = require('bip32').default;
          const bitcoin = require('bitcoinjs-lib');
          
          // 初始化 ECC 库
          bitcoin.initEccLib(ecc);

          const bip32 = BIP32Factory(ecc);
          const { mnemonicToSeedSync } = bip39;
          const { payments } = bitcoin;
          
          const mnemonic = '$MNEMONIC';
          const seed = mnemonicToSeedSync(mnemonic);
          const root = bip32.fromSeed(seed);
          const account = root.derivePath('m/86\'/0\'/0\'/0/0');  // 导出路径
          
          // 取公钥的后 32 字节作为 x-only 公钥
          const xOnlyPubKey = account.publicKey.slice(1);  
          
          // 使用 x-only 公钥生成 Taproot 地址
          const { address } = payments.p2tr({ internalPubkey: xOnlyPubKey });
          
          console.log(address);  // 输出地址
      })().catch(console.error);
    ")

    # 打印输出结果
    if [ -n "$PRIVATE_KEY" ]; then
        echo "私钥: $PRIVATE_KEY"
    else
        echo "私钥未生成或无法提取."
    fi

    if [ -n "$ADDRESS" ]; then
        echo "地址（Taproot）: $ADDRESS"
    else
        echo "地址未生成或无法提取."
    fi

    # 如果私钥和地址都没有生成，则退出函数
    if [ -z "$PRIVATE_KEY" ] && [ -z "$ADDRESS" ]; then
        echo "未能生成任何钱包信息，钱包创建失败。"
        return 1
    fi

    # 记录钱包信息到文件，带有时间戳
    WALLET_LOG="wallet_creation_log.txt"
    echo "钱包信息已保存到：$(pwd)/$WALLET_LOG; $(pwd)/wallet.json"
    {
        echo "钱包创建时间: $(date)"
        echo "钱包名称: $WALLET_NAME"
        echo "助记词: $MNEMONIC"
        echo "私钥: $PRIVATE_KEY"
        echo "地址 (Taproot格式): $ADDRESS"
        echo "--------------------------"
    } >> "$WALLET_LOG"

    # 返回上级目录
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

    cd /root/cat-token-box/packages/cli || exit

    # 自动加载钱包文件，不再手动选择
    WALLET_FILE="/root/cat-token-box/packages/cli/wallet.json"
    if [ ! -f "$WALLET_FILE" ]; then
        log_error "未找到 wallet.json 文件，请先创建钱包。"
        return 1
    fi

    echo "已找到钱包：$WALLET_FILE"

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

    # 输入 mint 操作的执行次数
    read -p "请输入要执行 mint 操作的次数: " mint_attempts
    if ! [[ "$mint_attempts" =~ ^[0-9]+$ ]]; then
        log_error "无效的次数，请输入一个正整数。"
        return 1
    fi

    # 定义颜色
    GREEN='\033[0;32m'  # 绿色
    RED='\033[0;31m'    # 红色
    NC='\033[0m'        # 无颜色

    # 开始执行 mint 操作共 $mint_attempts 次
    count=0
    while [ $count -lt $mint_attempts ]; do
        # 执行 mint 操作并捕获返回信息
        command="sudo yarn cli mint -i ${txid}_${index} $mint_amount"
        
        # 捕获命令的输出并存储到 OUTPUT 变量
        OUTPUT=$($command 2>&1)

        # 检查 mint 操作的输出中是否包含 "mint failed"
        if echo "$OUTPUT" | grep -q "mint failed"; then
            # 如果 mint 操作失败，打印红色错误信息
            echo -e "${RED}第 $((count + 1)) 次 mint 失败: $OUTPUT${NC}"
        else
            # 如果 mint 操作成功，打印绿色成功信息
            echo -e "${GREEN}第 $((count + 1)) 次 mint 成功: $OUTPUT${NC}"
        fi

        # 增加计数器，不管成功还是失败
        count=$((count + 1))
        
        # 为了避免过快的连续请求，可以加一个短暂的暂停
        sleep 1
    done

    echo "已完成 $mint_attempts 次 mint 操作。"

    cd ../../
}

# 6. 查看 Fractal 节点运行情况
function check_node_status() {
    echo "查看 Fractal 节点运行情况..."

    # 检查 docker-compose 是否安装
    if ! check_docker; then
        return 1
    fi

    cd cat-token-box/packages/tracker || exit
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
