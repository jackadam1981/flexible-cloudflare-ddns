#/bin/bash

# 改写json文件
# echo $config | jq --arg v "test test" '.config[0].name=$v' | jq > t2.json

config=$(cat cfconf.json | jq)

ipv4_host_ip=""
ipv6_host_ip=""

# 查看日志
#  journalctl --no-pager --since today -g 'jaDDNS'
#  logread -e jaDDNS

# 日志设置
export log_header_name="jaDDNS"
jaLog() {
    echo "$@"
    logger $log_header_name:"$@"
}

# 定义排除的本地IPV6地址定义
arLanIp6() {

    local lanIps="(^$)"

    lanIps="$lanIps|(^::1$)"                            # RFC4291
    lanIps="$lanIps|(^64:[fF][fF]9[bB]:)"               # RFC6052, RFC8215
    lanIps="$lanIps|(^100::)"                           # RFC6666
    lanIps="$lanIps|(^2001:2:0?:)"                      # RFC5180
    lanIps="$lanIps|(^2001:[dD][bB]8:)"                 # RFC3849
    lanIps="$lanIps|(^[fF][cdCD][0-9a-fA-F]{2}:)"       # RFC4193 Unique local addresses
    lanIps="$lanIps|(^[fF][eE][8-9a-bA-B][0-9a-fA-F]:)" # RFC4291 Link-local addresses

    echo $lanIps

}

function get_nic_ip() {
    # echo "get_nic_ip $1 $2"
    # 指定要获取IP地址的网卡,例如eth0
    iface=$1
    # 指定要获取的IP地址类型,例如A,AAAA
    type=$2
    # 定义要排除的本地IPV6地址定义
    lanIps=$(arLanIp6)
    # 选择使用 ip 还是 ifconfig
    # 使用ip命令获取IP地址
    if command -v ip >/dev/null 2>&1; then
        # echo "Using ip command"
        # 指定要获取的IP地址类型,例如A,AAAA
        # 指定IP地址类型为A,即IPV4
        if [ "$ip_version" = "A" ]; then

            # 使用ip addr show获取网卡IPv4地址信息
            ipv4_host_ip=$(ip addr show $iface | grep -o '(?<=inet\s)\d+(\.\d+){3}')
            # 打印获取到的IP地址
            # echo "IP Address of $iface is $ip_addr"
            # echo $ipv4_host_ip
        # 指定IP地址类型为AAA,即IPV6
        elif [ "$ip_version" = "AAAA" ]; then
            # 使用ip addr show获取网卡IPv6地址信息
            ipv6_info=$(ip addr show $iface)

            # 提取出地址和有效时间
            max_valid=0
            max_addr=""
            # 逐行读取ipv6_info
            while read -r line; do
                # echo "line::$line"
                # 如果含inet6，则提取地址
                if echo "$line" | grep -q 'inet6'; then
                    # echo "addr::$line"
                    addr=$(echo "$line" | awk '{print $2}' | cut -d' ' -f2 | cut -d "/" -f1)
                    # echo $addr
                    # 如果含有valid_lft，则提取有效时间
                elif echo "$line" | grep -q -e 'valid_lft'; then
                    # echo "valid::$line"
                    valid=$(echo "$line" | awk '{print $2}' | cut -d "s" -f 1)
                    # echo $valid
                    # 如果有效时间大于最大有效时间，则更新最大有效时间和最大地址
                    if [ "$valid" != "forever" ] && [ "$valid" -gt "$max_valid" ]; then
                        max_valid=$valid
                        max_addr="$addr"
                    fi
                fi
                # 逐行读取ipv6_info
            done < <(echo "$ipv6_info")

            # 兼容性设置，openwrt的ash，linux的bash，对echo返回支持不一致。
            if [[ "$SHELL" == "/bin/ash" ]]; then
                ipv6_host_ip=$max_addr
            else
                ipv6_host_ip=$max_addr
                echo "$ipv6_host_ip"
            fi
        fi
    fi
    # 使用ifconfig命令获取IP地址
    if command -v ifconfig >/dev/null 2>&1; then
        # echo "Using ifconfig command"
        if [ "$ip_version" = "A" ]; then
            # 使用ifconfig获取网卡IPv4地址信息
            ipv4_host_ip=$(ifconfig $iface | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
            # 打印获取到的IP地址
            # echo "IP Address of $iface is $ip_addr"
            echo $ipv4_host_ip

        elif [ "$ip_version" = "AAAA" ]; then
            # 使用ifconfig获取网卡IPv6地址信息
            ipv6_info=$(ifconfig $iface | grep 'inet6 addr')
            lanIps=$(arLanIp6)

            while read -r line; do
                addr=$(echo "$line" | awk '{print $3}' | cut -d' ' -f2 | cut -d/ -f1)
                addr=$(echo "$addr" | grep -Ev "$lanIps")
                if [ "$addr" != "" ]; then
                    tmp_ip=$addr
                fi
            done < <(echo "$ipv6_info")
            ipv6_host_ip=$tmp_ip
            echo $ipv6_host_ip
        fi
    fi
}

# 获取本地ip地址
function get_host_ip() {
    ip_version=$1
    is_static=$2
    nic_name=$3
    # echo "get_host_ip $ip_version $is_static"

    if [ "$ip_version" = "A" ]; then
        if [ -z "$ipv4_host_ip" ]; then
            if [ "$is_static" = "true" ]; then
                ipv4_host_ip=$(get_nic_ip $nic_name "A")
            elif [ "$is_static" = "false" ]; then
                ipv4_host_ip=$(curl -s https://api4.ipify.org)
            fi
        fi

    elif [ "$ip_version" = "AAAA" ]; then
        if [ -z "$ipv6_host_ip" ]; then
            if [ "$is_static" = "true" ]; then
                ipv6_host_ip=$(get_nic_ip $nic_name "AAAA")
            elif [ "$is_static" = "false" ]; then
                ipv6_host_ip=$(curl -s https://api6.ipify.org)
            fi
        fi
    fi
}

# 获取cf dns记录
function get_record_info() {
    zone_id=$1
    record_name=$2
    record_type=$3
    auth_key=$4

    url="https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=$record_type&name=$record_name"
    record_info=$(curl -s -X GET $url \
        -H "Authorization: Bearer $auth_key" \
        -H "Content-Type: application/json")
    # 用echo做函数返回值
    echo $record_info
}

# 获取cf zone记录
function get_zone_id() {
    domain_int=$1
    domain_name=$2
    auth_key=$3
    url="https://api.cloudflare.com/client/v4/zones?name=$domain_name"

    zone_id=$(curl -s -X GET $url \
        -H "Authorization: Bearer $auth_key" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')

    echo $zone_id
    # 将 zone_id 写入json配置文件
    echo $config | jq --arg d_int $((domain_int)) --arg id ${zone_id} '.config[$d_int|tonumber].zone_id=$id' | jq >cfconf.json
}

# 检查配置文件是否存在
check_config() {

    if [ -f "cfconf.json" ]; then
        jaLog "配置文件存在，开始运行"
    else
        config={\"config\":[{\"domain_name\":\"domain_name1\",\"zone_id\":\"\",\"auth_type\":\"key\",\"auth_key\":\"****************************************\",\"records\":[{\"name\":\"host_name1\",\"type\":\"AAAA\",\"proxy\":false,\"static\":true,\"nic_name\":\"eth0\"},{\"name\":\"host_name2\",\"type\":\"A\",\"proxy\":true,\"static\":false,\"nic_name\":\"\"}]},{\"domain_name\":\"domain_name2\",\"zone_id\":\"\",\"auth_type\":\"key\",\"auth_key\":\"****************************************\",\"records\":[{\"name\":\"host_name3\",\"type\":\"AAAA\",\"proxy\":false,\"static\":true,\"nic_name\":\"eth0\"},{\"name\":\"host_name4\",\"type\":\"AAAA\",\"proxy\":false,\"static\":true,\"nic_name\":\"eth0\"}]}]}
        echo $config | jq . >test.json
        jaLog "配置文件不存在，已创建模板，请修改后再执行。"
        exit 1
    fi
}

# 主运行函数
function main() {
    check_config
    # 获取域计数并遍历
    domain_size=$(echo $config | jq .config | jq length)
    domain_int=0
    while [ $domain_int -lt $domain_size ]; do

        #读取配置
        domain_name=$(echo $config | jq -r .config[$domain_int].domain_name)
        zone_id=$(echo $config | jq -r .config[$domain_int].zone_id)
        login_email=$(echo $config | jq -r .config[$domain_int].login_email)
        auth_type=$(echo $config | jq -r .config[$domain_int].auth_type)
        auth_key=$(echo $config | jq -r .config[$domain_int].auth_key)

        echo "检查域名 $domain_name"
        # 检查zone_id是否为空，空则获取一下
        if [ -z $zone_id ]; then
            zone_id=$(get_zone_id $domain_int $domain_name $auth_key)
            echo "域名zone_id:$zone_id"
        fi

        # 获取主机计数并遍历
        record_size=$(echo $config | jq .config[$domain_int].records | jq length)
        record_int=0
        while [ $record_int -lt $record_size ]; do

            record_name=$(echo $config | jq -r .config[$domain_int].records[$record_int].name)
            record_type=$(echo $config | jq -r .config[$domain_int].records[$record_int].type)
            record_proxy=$(echo $config | jq -r .config[$domain_int].records[$record_int].proxy)
            record_static=$(echo $config | jq -r .config[$domain_int].records[$record_int].static)
            record_nic_name=$(echo $config | jq -r .config[$domain_int].records[$record_int].nic_name)

            host_name=$record_name.$domain_name
            echo "检查主机 $host_name"
            # 获取主机详细信息，主要是主机id，主机ip
            record_info=$(get_record_info $zone_id $host_name $record_type $auth_key)
            echo $record_info
            record_id=$(echo $record_info | jq -r '.result[0].id')
            record_ip=$(echo $record_info | jq -r '.result[0].content')
            # 根据记录类型获取主机ip
            get_host_ip $record_type $record_static $record_nic_name
            if [ $record_type = "A" ]; then
                host_ip=$ipv4_host_ip
            elif [ $record_type = "AAAA" ]; then
                host_ip=$ipv6_host_ip
            fi
            echo "获取到的ID：$record_id"
            echo "获取到IP：$host_ip"
            echo "记录的IP：$record_ip"

            # # 比较主机ip和记录ip
            if [[ $host_ip != $record_ip ]]; then
                update=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
                    -H "Authorization: Bearer $auth_key" \
                    -H "Content-Type: application/json" \
                    --data "{\"content\":\"$host_ip\",\"name\":\"$host_name\",\"proxied\":$record_proxy,\"type\":\"$record_type\"}")
                result=$(echo $update | jq -r '.success')
                if [ "$result" == true ]; then
                    jaLog "域名更新成功：$record_name:$host_ip"
                else
                    jaLog "域名更新失败：$record_name:$host_ip"
                    jaLog $update
                fi
            else
                jaLog "域名解析不变：$record_name:$host_ip"
            fi

            record_int=$(expr $record_int + 1)
        done
        domain_int=$(expr $domain_int + 1)
    done
}

# 主函数启动
main
