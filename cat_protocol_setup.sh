#!/bin/bash

# 定义颜色
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

# 日志文件路径
readonly LOG_FILE="cat_protocol.log"
# 钱包信息保存路径
readonly WALLETS_FILE="wallets.txt"

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

# 安装 Docker 和依赖
install_dependencies() {
    log "${GREEN}正在安装 Docker 和依赖...${NC}"
    sudo apt-get update | tee -a $LOG_FILE
    sudo apt-get install docker.io -y | tee -a $LOG_FILE
    sudo apt-get install npm -y | tee -a $LOG_FILE
    sudo npm install n -g | tee -a $LOG_FILE
    sudo n stable | tee -a $LOG_FILE
    sudo npm i -g yarn | tee -a $LOG_FILE
    # 安装 docker-compose
    VERSION=$(curl --silent https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*\d')
    DESTINATION=/usr/local/bin/docker-compose
    sudo curl -L https://github.com/docker/compose/releases/download/${VERSION}/docker-compose-$(uname -s)-$(uname -m) -o $DESTINATION | tee -a $LOG_FILE
    sudo chmod 755 $DESTINATION | tee -a $LOG_FILE
    log "${GREEN}依赖安装完成。${NC}"
}

# 拉取 Git 仓库并编译
clone_and_build() {
    log "${GREEN}正在拉取 Git 仓库并进行编译...${NC}"
    git clone https://github.com/CATProtocol/cat-token-box | tee -a $LOG_FILE
    cd cat-token-box
    sudo yarn install | tee -a $LOG_FILE
    sudo yarn build | tee -a $LOG_FILE
    log "${GREEN}编译完成。${NC}"
}

# 清除 yarn 缓存并重新安装依赖
fix_yarn_install() {
    log "${GREEN}检测到 yarn install 错误，正在清除缓存并重新安装依赖...${NC}"
    yarn cache clean | tee -a $LOG_FILE
    yarn install | tee -a $LOG_FILE
    if [ $? -ne 0 ]; then
        log_error "重新安装依赖失败，请检查网络连接或依赖配置。"
        exit 1
    else
        log "${GREEN}依赖重新安装成功。${NC}"
    fi
}

# 检查 config.json 文件
check_or_create_config() {
    local config_path="$1"

    # 检查 config.json 是否存在
    if [ ! -f "$config_path/config.json" ]; then
        log_error "config.json 文件不存在。请按照教程创建 config.json 文件。"
        log "${GREEN}自动创建 config.json 文件模板...${NC}"

        # 自动生成 config.json 模板
        cat > "$config_path/config.json" <<EOL
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

        log "${GREEN}config.json 模板已创建，请根据教程检查并修改内容。${NC}"
        exit 1
    else
        log "${GREEN}config.json 文件已存在，继续执行...${NC}"
    fi
}

# 运行 Fractal 节点和 CAT 索引器
run_fractal_node() {
    log "${GREEN}正在运行 Fractal 节点和 CAT 索引器...${NC}"
    
    cd ./packages/tracker/ || { log_error "无法进入 ./packages/tracker/ 目录。"; return 1; }

    sudo chmod 777 docker/data
    sudo chmod 777 docker/pgdata

    sudo docker-compose up -d | tee -a $LOG_FILE
    if [ $? -ne 0 ]; then
        log_error "启动 Fractal 节点失败。请检查 docker-compose 的配置和日志。"
        return 1
    fi
    log "${GREEN}Fractal 节点运行成功。${NC}"

    cd ../../
    
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

    # 确保进入项目根目录
    cd ~/cat-token-box/packages/cli || { log_error "无法进入 cat-token-box/packages/cli 目录。"; return 1; }

    # 检查依赖是否安装
    if [ ! -d "node_modules" ]; then
        log "${GREEN}node_modules 文件夹不存在，重新安装依赖...${NC}"
        yarn install || fix_yarn_install
    fi

    # 检查 config.json 文件
    check_or_create_config "$(pwd)"

    # 执行 yarn cli wallet create 并提取输出中的助记词、私钥和地址
    wallet_info=$(sudo yarn cli wallet create 2>&1)

    # 检查是否成功生成钱包
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

    # 确保进入项目根目录
    cd ~/cat-token-box/packages/cli || { log_error "无法进入 cat-token-box/packages/cli 目录。"; return 1; }

    # 检查 config.json 是否存在
    check_or_create_config "$(pwd)"

    # 检查依赖是否安装
    if [ ! -d "node_modules" ]; then
        log "${GREEN}node_modules 文件夹不存在，重新安装依赖...${NC}"
        yarn install || fix_yarn_install
    fi

    read -p "请输入要执行 mint 的次数: " mint_count

    if ! [[ "$mint_count" =~ ^[0-9]+$ ]]; then
        log_error "无效的输入，请输入一个正整数。"
        return 1
    fi

    for ((i = 1; i <= mint_count; i++)); do
        log "${GREEN}正在执行第 $i 次 mint...${NC}"
        sudo yarn cli mint -i 45ee725c2c5993b3e4d308842d87e973bf1951f5f7a804b21e4dd964ecd12d6b_0 5 2>&1 | tee -a $LOG_FILE
        if [[ $? -ne 0 ]]; then
            log_error "第 $i 次 mint 失败，请检查错误日志。"
            return 1
        fi
    done

    log "${GREEN}重复 mint 操作完成。${NC}"
}

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
    read -p "请输入选项 (1-8): " choice

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
