#!/bin/bash

# 定义颜色
readonly GREEN='\033[0;32m'
readonly NC='\033[0m' # No Color

# 日志文件路径
readonly LOG_FILE="cat_protocol.log"
# 钱包文件路径
readonly WALLETS_FILE="wallets.txt"

# 打印菜单
print_menu() {
    echo -e "${GREEN}请选择要执行的操作:${NC}"
    echo "1. 安装 Docker 和依赖"
    echo "2. 拉取 Git 仓库并编译"
    echo "3. 运行 Fractal 节点"
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

# 运行 Fractal 节点
run_fractal_node() {
    log "${GREEN}正在运行 Fractal 节点...${NC}"
    
    # 检查 docker-compose 文件是否存在
    if [ ! -f "./packages/tracker/docker-compose.yml" ]; then
        log "${GREEN}未找到 docker-compose.yml 文件，请确保您在正确的目录下。${NC}"
        return 1
    fi

    # 进入 Fractal 节点的目录
    cd ./packages/tracker/ || { log "${GREEN}无法进入 ./packages/tracker/ 目录。${NC}"; return 1; }

    # 设置权限
    sudo chmod 777 docker/data
    sudo chmod 777 docker/pgdata

    # 启动 Fractal 节点
    sudo docker-compose up -d | tee -a $LOG_FILE
    if [ $? -ne 0 ]; then
        log "${GREEN}启动 Fractal 节点失败。请检查 docker-compose 的配置和日志。${NC}"
        return 1
    fi
    log "${GREEN}Fractal 节点运行成功。${NC}"

    # 返回初始目录
    cd ../../

    # 运行 CAT Protocol 本地索引器
    log "${GREEN}正在运行 CAT Protocol 本地索引器...${NC}"
    sudo docker build -t tracker:latest . | tee -a $LOG_FILE
    if [ $? -ne 0 ]; then
        log "${GREEN}CAT Protocol 索引器构建失败。${NC}"
        return 1
    fi

    sudo docker run -d \
        --name tracker \
        --add-host="host.docker.internal:host-gateway" \
        -e DATABASE_HOST="host.docker.internal" \
        -e RPC_HOST="host.docker.internal" \
        -p 3000:3000 \
        tracker:latest | tee -a $LOG_FILE

    if [ $? -ne 0 ]; then
        log "${GREEN}运行 CAT Protocol 索引器失败。${NC}"
        return 1
    fi

    log "${GREEN}CAT Protocol 索引器运行成功。${NC}"
}


# 创建新钱包并导出信息
create_new_wallet() {
    log "${GREEN}正在创建新钱包...${NC}"

    # 执行 yarn cli wallet create 并提取输出中的助记词、私钥和 Taproot 地址
    wallet_info=$(sudo yarn cli wallet create)

    # 提取助记词、私钥和地址（Taproot格式）
    mnemonic=$(echo "$wallet_info" | grep "助记词" | awk -F ': ' '{print $2}')
    private_key=$(echo "$wallet_info" | grep "私钥" | awk -F ': ' '{print $2}')
    taproot_address=$(echo "$wallet_info" | grep "Taproot" | awk -F ': ' '{print $2}')

    # 打印并保存钱包信息
    log "${GREEN}新钱包信息:${NC}"
    echo -e "助记词: $mnemonic"
    echo -e "私钥: $private_key"
    echo -e "地址（Taproot格式）: $taproot_address"

    # 输出到文件
    wallet_file="wallet_info_$(date +%Y%m%d_%H%M%S).txt"
    echo -e "助记词: $mnemonic\n私钥: $private_key\n地址（Taproot格式）: $taproot_address" > "$wallet_file"

    # 保存地址到钱包地址列表文件
    echo "$taproot_address" >> "$WALLETS_FILE"

    log "${GREEN}钱包信息已保存到文件: $wallet_file，并将地址保存到 $WALLETS_FILE。${NC}"
}

# 让用户从保存的钱包地址中选择一个
select_wallet_address() {
    log "${GREEN}选择一个钱包地址用于 mint 操作:${NC}"

    # 检查钱包文件是否存在
    if [ ! -f "$WALLETS_FILE" ]; then
        echo "没有可以选择的钱包地址，请先创建一个钱包。"
        return 1
    fi

    # 显示所有钱包地址供用户选择
    mapfile -t wallets < "$WALLETS_FILE"
    if [ ${#wallets[@]} -eq 0 ]; then
        echo "没有可用的钱包地址，请先创建一个钱包。"
        return 1
    fi

    # 显示钱包地址列表
    for i in "${!wallets[@]}"; do
        echo "$((i+1)). ${wallets[$i]}"
    done

    read -p "请选择一个钱包地址 (输入序号): " wallet_choice

    if [[ "$wallet_choice" -lt 1 || "$wallet_choice" -gt ${#wallets[@]} ]]; then
        echo "选择无效。"
        return 1
    fi

    selected_wallet="${wallets[$((wallet_choice-1))]}"
    echo "您选择的钱包地址是: $selected_wallet"

    return 0
}

# 执行重复 mint 操作
repeated_mint() {
    echo -e "${GREEN}请输入需要执行 mint 的次数:${NC}"
    read -p "次数: " mint_count

    # 确认输入的次数
    read -p "您输入的 mint 次数是 $mint_count。是否确认？(yes/no): " confirmation

    if [ "$confirmation" != "yes" ]; then
        echo -e "${GREEN}操作已取消。${NC}"
        return
    fi

    # 动态输入 token ID 和数量
    read -p "请输入 token ID: " token_id
    read -p "请输入 mint 数量: " mint_amount

    # 选择一个钱包地址
    if ! select_wallet_address; then
        log "${GREEN}钱包选择失败，操作已取消。${NC}"
        return
    fi

    log "${GREEN}开始执行 mint 操作，共 $mint_count 次，使用钱包地址: $selected_wallet${NC}"

    # 循环执行 mint 指令
    for ((i=1; i<=mint_count; i++)); do
        tx_hash=$(sudo yarn cli mint -i "$token_id" "$mint_amount" --address "$selected_wallet")

        # 检查 mint 是否成功
        if [ $? -ne 0 ]; then
            log "${GREEN}Mint 操作在第 $i 次时失败。${NC}"
            continue  # Mint 失败时不退出，继续下次操作
        fi

        # 打印成功提交的交易哈希
        log "${GREEN}Mint 操作第 $i 次完成，交易哈希: $tx_hash${NC}"
        sleep 1  # 可根据需要调整间隔时间
    done

    log "${GREEN}Mint 操作执行完毕，共执行 $mint_count 次。${NC}"
}

# 查看日志并自动刷新
view_logs() {
    log "${GREEN}正在查看日志...${NC}"
    tail -f $LOG_FILE
}

# 查看 Fractal 节点运行情况
view_fractal_node_logs() {
    log "${GREEN}正在查看 Fractal 节点运行情况...${NC}"
    sudo docker logs -f tracker  # 假设 Fractal 节点的容器名称为 "tracker"
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
            run_fractal_node  # 确保此处函数名与定义的一致
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
            log "${GREEN}无效的选项，请重新输入。${NC}"
            ;;
    esac
done
