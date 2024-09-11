#!/bin/bash

# 定义颜色
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

# 日志文件路径
readonly LOG_FILE="cat_protocol.log"
# 钱包信息保存路径
readonly WALLETS_FILE="wallets.txt"
# 项目根目录
readonly PROJECT_DIR="$HOME/cat-token-box"

# 检查日志文件的写入权限
check_log_file_permissions() {
    if [ ! -w "$LOG_FILE" ]; then
        sudo chmod 664 "$LOG_FILE" || { log_error "无法设置日志文件权限。" ; exit 1; }
    fi
}

# 在脚本开始时检查日志文件权限
check_log_file_permissions

# 打印菜单
print_menu() {
    echo -e "${GREEN}请选择要执行的操作:${NC}"
    echo "1. 安装 Docker 和依赖"
    echo "2. 拉取 Git 仓库并编译"
    echo "3. 运行 Fractal 节点和 CAT 索引器"
    echo "4. 创建一个新钱包并导出信息"
    echo "5. 执行重复 mint（输入次数并确认）"
    echo "6. 查看日志信息（自动刷新）"
    echo "7. 查看 Fractal 节点运行情况"
    echo "8. 退出"
}

# 记录日志
log() {
    local message="$1"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') : $message" | tee -a $LOG_FILE
}

# 记录错误日志（红色）
log_error() {
    local message="$1"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') : ${RED}$message${NC}" | tee -a $LOG_FILE
}

# 检查并安装依赖
check_install_dependencies() {
    if [ ! -d "node_modules" ]; then
        log "${GREEN}node_modules 文件夹不存在，重新安装依赖...${NC}"
        yarn install || { log_error "依赖安装失败，请检查 yarn 配置。" ; exit 1; }
    fi
}

# 安装 Docker 和依赖
install_dependencies() {
    log "${GREEN}正在安装 Docker 和依赖...${NC}"
    
    if ! command -v docker &>/dev/null; then
        sudo apt-get update | tee -a $LOG_FILE
        sudo apt-get install docker.io -y | tee -a $LOG_FILE
    else
        log "${GREEN}Docker 已安装，跳过安装步骤。${NC}"
    fi

    if ! command -v npm &>/dev/null; then
        sudo apt-get install npm -y | tee -a $LOG_FILE
    else
        log "${GREEN}npm 已安装，跳过安装步骤。${NC}"
    fi

    if ! command -v yarn &>/dev/null; then
        sudo npm i -g yarn | tee -a $LOG_FILE
    else
        log "${GREEN}yarn 已安装，跳过安装步骤。${NC}"
    fi

    # 安装 docker-compose
    VERSION=$(curl --silent https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*\d')
    DESTINATION=/usr/local/bin/docker-compose
    if [ ! -f "$DESTINATION" ]; then
        sudo curl -L https://github.com/docker/compose/releases/download/${VERSION}/docker-compose-$(uname -s)-$(uname -m) -o $DESTINATION | tee -a $LOG_FILE
        sudo chmod 755 $DESTINATION | tee -a $LOG_FILE
    else
        log "${GREEN}Docker Compose 已安装，跳过安装步骤。${NC}"
    fi

    log "${GREEN}依赖安装完成。${NC}"
}

# 拉取 Git 仓库并编译
clone_and_build() {
    log "${GREEN}正在拉取 Git 仓库并进行编译...${NC}"
    if [ ! -d "$PROJECT_DIR" ]; then
        git clone https://github.com/CATProtocol/cat-token-box "$PROJECT_DIR" | tee -a $LOG_FILE
    else
        log "${GREEN}项目已存在，跳过克隆步骤。${NC}"
    fi
    cd "$PROJECT_DIR"
    sudo yarn install | tee -a $LOG_FILE || { log_error "依赖安装失败，请检查 yarn 配置。" ; exit 1; }
    sudo yarn build | tee -a $LOG_FILE || { log_error "项目编译失败。" ; exit 1; }
    log "${GREEN}编译完成。${NC}"
}

# 检查 .env 文件并同步 config.json
check_env_and_config() {
    local config_path="$1"
    local env_path="$2"  # 将 .env 文件路径作为参数

    # 检查 .env 文件是否存在
    if [ ! -f "$env_path" ]; then
        log_error ".env 文件不存在，请确保 tracker 目录下存在 .env 文件。"
        exit 1
    fi

    # 从 .env 文件中提取 username 和 password
    local rpc_username
    local rpc_password
    rpc_username=$(grep -E '^RPC_USERNAME=' "$env_path" | cut -d '=' -f2)
    rpc_password=$(grep -E '^RPC_PASSWORD=' "$env_path" | cut -d '=' -f2)

    # 检查 config.json 是否存在
    if [ ! -f "$config_path/config.json" ]; then
        log "${GREEN}config.json 文件不存在，自动创建...${NC}"

        # 自动生成 config.json 模板
        cat > "$config_path/config.json" <<EOL
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
        log "${GREEN}config.json 文件已创建，请根据需要修改。${NC}"
    else
        log "${GREEN}config.json 文件已存在，继续执行。${NC}"
    fi
}

# 运行 Fractal 节点和 CAT 索引器
run_fractal_node() {
    log "${GREEN}正在运行 Fractal 节点和 CAT 索引器...${NC}"
    
    # 检查 tracker 目录是否存在
    if [ ! -d "$PROJECT_DIR/packages/tracker" ]; then
        log_error "无法进入 $PROJECT_DIR/packages/tracker 目录，目录不存在。请确认仓库结构。"
        return 1
    fi

    cd "$PROJECT_DIR/packages/tracker/" || { log_error "无法进入 $PROJECT_DIR/packages/tracker/ 目录。"; return 1; }

    sudo chmod 777 docker/data
    sudo chmod 777 docker/pgdata

    sudo docker-compose up -d || { log_error "启动 Fractal 节点失败。请检查 docker-compose 的配置和日志。" ; exit 1; }
    
    log "${GREEN}Fractal 节点运行成功。${NC}"

    cd "$PROJECT_DIR"
    
    log "${GREEN}正在运行 CAT Protocol 本地索引器...${NC}"
    sudo docker build -t tracker:latest . | tee -a $LOG_FILE
    sudo docker run -d \
        --name tracker \
        --add-host="host.docker.internal:host-gateway" \
        -e DATABASE_HOST="host.docker.internal" \
        -e RPC_HOST="host.docker.internal" \
        -p 3000:3000 \
        tracker:latest | tee -a $LOG_FILE

    if [ $? -ne 0 ]; then
        log_error "运行 CAT Protocol 索引器失败。"
        return 1
    fi

    log "${GREEN}CAT Protocol 索引器运行成功。${NC}"
}

# 创建新钱包并导出信息
create_new_wallet() {
    log "${GREEN}正在创建新钱包...${NC}"

    cd "$PROJECT_DIR/packages/cli" || { log_error "无法进入 $PROJECT_DIR/packages/cli 目录。"; return 1; }

    check_install_dependencies

    check_env_and_config "$(pwd)" "$PROJECT_DIR/packages/tracker/.env"

    wallet_info=$(sudo yarn cli wallet create 2>&1)

    if [[ $? -ne 0 || -z "$wallet_info" ]]; then
        log_error "钱包生成失败，请检查配置或依赖。"
        return 1
    fi

    mnemonic=$(echo "$wallet_info" | grep "Mnemonic" | awk -F ': ' '{print $2}')
    private_key=$(echo "$wallet_info" | grep "Private Key" | awk -F ': ' '{print $2}')
    taproot_address=$(echo "$wallet_info" | grep "Taproot Address" | awk -F ': ' '{print $2}')

    if [[ -z "$taproot_address" ]]; then
        log_error "未找到钱包地址，请检查钱包生成过程。"
        return 1
    fi

    log "${GREEN}新钱包信息:${NC}"
    echo -e "助记词: $mnemonic"
    echo -e "私钥: $private_key"
    echo -e "地址（Taproot格式）: $taproot_address"

    wallet_file="wallet_info_$(date +%Y%m%d_%H%M%S).txt"
    echo -e "助记词: $mnemonic\n私钥: $private_key\n地址（Taproot格式）: $taproot_address" > "$wallet_file"
    echo "$taproot_address" >> "$WALLETS_FILE"

    log "${GREEN}钱包信息已保存到文件: $wallet_file，并将地址保存到 $WALLETS_FILE。${NC}"
}

# 执行重复 mint
repeated_mint() {
    log "${GREEN}执行重复 mint 操作...${NC}"

    cd "$PROJECT_DIR/packages/cli" || { log_error "无法进入 $PROJECT_DIR/packages/cli 目录。"; return 1; }

    check_env_and_config "$(pwd)" "$PROJECT_DIR/packages/tracker/.env"

    check_install_dependencies

    if [ ! -f "$WALLETS_FILE" ]; then
        log_error "钱包文件不存在，请先创建一个钱包。"
        return 1
    fi

    log "${GREEN}可用钱包列表:${NC}"
    wallets=($(cat "$WALLETS_FILE"))

    if [ ${#wallets[@]} -eq 0 ]; then
        log_error "未找到可用钱包，请先创建一个钱包。"
        return 1
    fi

    for i in "${!wallets[@]}"; do
        echo "$((i + 1)). ${wallets[$i]}"
    done

    read -p "请选择一个钱包 (输入对应的数字): " wallet_choice

    if ! [[ "$wallet_choice" =~ ^[0-9]+$ ]] || [ "$wallet_choice" -lt 1 ] || [ "$wallet_choice" -gt "${#wallets[@]}" ]; then
        log_error "无效的选择，请输入有效的数字。"
        return 1
    fi

    selected_wallet="${wallets[$((wallet_choice - 1))]}"
    log "${GREEN}已选择的钱包地址: $selected_wallet${NC}"

    read -p "请输入交易哈希 (txid): " txid
    if ! [[ "$txid" =~ ^[a-fA-F0-9]{64}$ ]]; then
        log_error "无效的交易哈希，请输入正确的 64 位十六进制字符串。"
        return 1
    fi

    read -p "请输入交易索引 (index): " index
    if ! [[ "$index" =~ ^[0-9]+$ ]]; then
        log_error "无效的交易索引，请输入一个正整数。"
        return 1
    fi

    read -p "请输入要 mint 的数量: " mint_amount
    if ! [[ "$mint_amount" =~ ^[0-9]+$ ]]; then
        log_error "无效的 mint 数量，请输入一个正整数。"
        return 1
    fi

    read -p "请输入要执行 mint 的次数: " mint_count
    if ! [[ "$mint_count" =~ ^[0-9]+$ ]]; then
        log_error "无效的输入，请输入一个正整数。"
        return 1
    fi

    for ((i = 1; i <= mint_count; i++)); do
        log "${GREEN}正在执行第 $i 次 mint...${NC}"

        mint_output=$(sudo yarn cli mint -i "${txid}_${index}" "$mint_amount" --wallet "$selected_wallet" 2>&1)
        
        if echo "$mint_output" | grep -q "TXID:"; then
            mint_txid=$(echo "$mint_output" | grep "TXID:" | awk -F ': ' '{print $2}')
            log "${GREEN}第 $i 次 mint 成功，交易哈希: $mint_txid${NC}"
        else
            log_error "第 $i 次 mint 失败，错误信息: $mint_output"
            continue  # 继续执行后续步骤，而非退出循环
        fi
    done

    log "${GREEN}重复 mint 操作完成。${NC}"
}

# 清理 Docker 资源
cleanup() {
    log "清理 Docker 资源..."
    sudo docker-compose down
    sudo docker rm -f tracker
}

# 捕捉退出信号，执行清理
trap cleanup EXIT

# 查看 Fractal 节点运行日志
view_fractal_node_logs() {
    log "${GREEN}查看 Fractal 节点运行日志...${NC}"
    sudo docker logs -f tracker | tee -a $LOG_FILE
}

# 查看日志信息（自动刷新）
view_logs() {
    log "${GREEN}查看日志信息...${NC}"
    tail -f $LOG_FILE
}

# 主程序
while true; do
    print_menu
    read -p "请输入选项 (1-8) [默认 8]: " choice
    choice=${choice:-8}  # 默认值为 8（退出）

    case $choice in
        1)
            install_dependencies
            ;;
        2)
            clone_and_build
            ;;
        3)
            run_fractal_node
            ;;
        4)
            create_new_wallet
            ;;
        5)
            repeated_mint
            ;;
        6)
            view_logs
            ;;
        7)
            view_fractal_node_logs
            ;;
        8)
            log "${GREEN}退出脚本。${NC}"
            exit 0
            ;;
        *)
            log_error "无效的选项，请重新输入。"
            ;;
    esac
done
