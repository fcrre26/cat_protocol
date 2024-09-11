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

# 记录日志
log() {
    local message="$1"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') : $message" | tee -a "$LOG_FILE"
}

# 记录错误日志（红色）
log_error() {
    local message="$1"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') : ${RED}$message${NC}" | tee -a "$LOG_FILE"
}

# 确保日志文件存在
if [ ! -f "$LOG_FILE" ]; then
    echo "日志文件不存在，尝试创建 $LOG_FILE"
    touch "$LOG_FILE" || { echo "无法创建日志文件 $LOG_FILE"; exit 1; }
else
    echo "日志文件已存在：$LOG_FILE"
fi

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
    echo "4. 创建新钱包"
    echo "5. 执行单次 mint"
    echo "6. 执行重复 mint"
    echo "7. 查看日志信息"
    echo "8. 退出"
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

# 创建新钱包
create_new_wallet() {
    log "${GREEN}正在创建新钱包...${NC}"

    cd "$PROJECT_DIR/packages/cli" || { log_error "无法进入 $PROJECT_DIR/packages/cli 目录。"; return 1; }

    # 创建 config.json 文件
    if [ ! -f "config.json" ]; then
        log "${GREEN}正在创建 config.json 文件...${NC}"
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

    # 创建钱包
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

# 单次 mint
single_mint() {
    log "${GREEN}执行单次 mint 操作...${NC}"

    cd "$PROJECT_DIR/packages/cli" || { log_error "无法进入 $PROJECT_DIR/packages/cli 目录。"; return 1; }

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

    mint_output=$(sudo yarn cli mint -i "${txid}_${index}" "$mint_amount" 2>&1)
    
    if echo "$mint_output" | grep -q "TXID:"; then
        mint_txid=$(echo "$mint_output" | grep "TXID:" | awk -F ': ' '{print $2}')
        log "${GREEN}mint 成功，交易哈希: $mint_txid${NC}"
    else
        log_error "mint 失败，错误信息: $mint_output"
        return 1
    fi

    log "${GREEN}mint 操作完成。${NC}"
}

# 重复 mint
repeated_mint() {
    log "${GREEN}执行重复 mint 操作...${NC}"

    cd "$PROJECT_DIR/packages/cli" || { log_error "无法进入 $PROJECT_DIR/packages/cli 目录。"; return 1; }

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

    command="sudo yarn cli mint -i ${txid}_${index} $mint_amount"

    for ((i = 1; i <= mint_count; i++)); do
        log "${GREEN}正在执行第 $i 次 mint...${NC}"

        mint_output=$(eval "$command 2>&1")
        
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

# 查看日志信息
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
            single_mint
            ;;
        6)
            repeated_mint
            ;;
        7)
            view_logs
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
