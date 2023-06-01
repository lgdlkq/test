#!/bin/sh

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
release=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
echo "检测到系统为：$release"
arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
elif [[ $arch == "i686" ]]; then
    arch="i686"
else
    arch="amd64"
    echo -e "${red}检测架构失败，将尝试使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi
echo "系统版本: ${os_version}"

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar -y
    elif [[ x"${release}" == x"alpine" ]]; then
        apk add wget curl tar
    else
        apt install wget curl tar -y
    fi
}

#This function will be called when user installed x-ui out of sercurity
config_after_install() {
    echo -e "${yellow}出于安全考虑，安装/更新完成后需要强制修改端口与账户密码${plain}"
    read -p "确认是否继续?[y/n]": config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "请设置您的账户名:" config_account
        echo -e "${yellow}您的账户名将设定为:${config_account}${plain}"
        read -p "请设置您的账户密码:" config_password
        echo -e "${yellow}您的账户密码将设定为:${config_password}${plain}"
        read -p "请设置面板访问端口:" config_port
        echo -e "${yellow}您的面板访问端口将设定为:${config_port}${plain}"
        echo -e "${yellow}确认设定,设定中${plain}"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${yellow}账户密码设定完成${plain}"
        /usr/local/x-ui/x-ui setting -port ${config_port}
        echo -e "${yellow}面板端口设定完成${plain}"
    else
        echo -e "${red}已取消,所有设置项均为默认设置,请及时修改${plain}"
    fi
}

install_x-ui() {
    if [[ x"${release}" == x"alpine" ]]; then
        if rc-service x-ui status | grep -q "started"; then
            service x-ui stop
        fi
    else
        systemctl stop x-ui
    fi
    cd /usr/local/

    if [ $# == 0 ]; then
        last_version=$(curl -s https://data.jsdelivr.com/v1/package/gh/vaxilu/x-ui | sed -n 4p | tr -d ',"' | awk '{$1=$1};1')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 x-ui 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 x-ui 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 x-ui 最新版本：${last_version}，开始安装"
        if [[ $arch == "i686" ]]; then
            wget -N --no-check-certificate -O /usr/local/x-ui-linux.tar.gz https://github.com/vaxilu/x-ui/releases/download/${last_version}/x-ui-linux-amd64.tar.gz
        else
            wget -N --no-check-certificate -O /usr/local/x-ui-linux.tar.gz https://github.com/vaxilu/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz
        fi
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        echo -e "开始安装 x-ui v$1"
        if [[ $arch == "i686" ]]; then
            url="https://github.com/vaxilu/x-ui/releases/download/${last_version}/x-ui-linux-amd64.tar.gz"
        else
            url="https://github.com/vaxilu/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
        fi
        wget -N --no-check-certificate -O /usr/local/x-ui-linux.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui v$1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux.tar.gz
    rm x-ui-linux.tar.gz -f
    cd x-ui

    if [[ $(getconf LONG_BIT) != '64' ]]; then
        echo "开始下载替换的Xray文件..."
        xray_last_version=$(curl -s https://data.jsdelivr.com/v1/package/gh/XTLS/Xray-core | sed -n 4p | tr -d ',"' | awk '{$1=$1};1')
        yellow "xray最新版本号为： $xray_last_version"
        wget https://github.com/XTLS/Xray-core/releases/download/$xray_last_version/Xray-linux-32.zip
        mkdir temp
        unzip -d temp Xray-linux-32.zip
        rm Xray-linux-32.zip
        mv temp/xray bin/xray-linux-amd64
        rm -rf ./temp
        chmod +x x-ui bin/xray-linux-amd64
        wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/lgdlkq/test/main/x-ui.sh?token=GHSAT0AAAAAACBBHNZ7BRSNIQXAOMVTQTQ6ZDYNYKQ
    else
        chmod +x x-ui bin/xray-linux-${arch}
        cp -f x-ui.service /etc/systemd/system/
        wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/vaxilu/x-ui/main/x-ui.sh
    fi

    if [[ $release == "alpine" ]]; then
        rm -f /etc/init.d/x-ui
        cat << EOF > /etc/init.d/x-ui
#!/sbin/openrc-run
name="x-ui"
description="X-UI Service"

command="/usr/local/x-ui/x-ui"
pidfile="/var/run/x-ui.pid"
directory="/usr/local/x-ui"
command_background="yes"

depend() {
    need net
}

start() {
    ebegin "Starting X-UI"
    start-stop-daemon --start --exec /usr/local/x-ui/x-ui
    eend $?
}

stop() {
    ebegin "Stopping X-UI"
    start-stop-daemon --stop --exec /usr/local/x-ui/x-ui
    eend $?
}

restart() {
    ebegin "Restarting X-UI"
    start-stop-daemon --stop --exec /usr/local/x-ui/x-ui
    sleep 1
    start-stop-daemon --start --exec /usr/local/x-ui/x-ui
    eend $?
}

EOF
    fi

    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    config_after_install
    #echo -e "如果是全新安装，默认网页端口为 ${green}54321${plain}，用户名和密码默认都是 ${green}admin${plain}"
    #echo -e "请自行确保此端口没有被其他程序占用，${yellow}并且确保 54321 端口已放行${plain}"
    #    echo -e "若想将 54321 修改为其它端口，输入 x-ui 命令进行修改，同样也要确保你修改的端口也是放行的"
    #echo -e ""
    #echo -e "如果是更新面板，则按你之前的方式访问面板"
    #echo -e ""
    if [[ x"${release}" == x"alpine" ]]; then
        if ! rc-update show | grep x-ui | grep 'default' > /dev/null;then
            rc-update add x-ui default
        fi
        service x-ui restart
    else
        systemctl daemon-reload
        systemctl enable x-ui
        systemctl start x-ui
    fi

    echo -e "${green}x-ui v${last_version}${plain} 安装完成，面板已启动，"
    echo -e ""
    echo -e "x-ui 管理脚本使用方法: "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - 显示管理菜单 (功能更多)"
    echo -e "x-ui start        - 启动 x-ui 面板"
    echo -e "x-ui stop         - 停止 x-ui 面板"
    echo -e "x-ui restart      - 重启 x-ui 面板"
    echo -e "x-ui status       - 查看 x-ui 状态"
    echo -e "x-ui enable       - 设置 x-ui 开机自启"
    echo -e "x-ui disable      - 取消 x-ui 开机自启"
    echo -e "x-ui log          - 查看 x-ui 日志"
    echo -e "x-ui v2-ui        - 迁移本机器的 v2-ui 账号数据至 x-ui"
    echo -e "x-ui update       - 更新 x-ui 面板"
    echo -e "x-ui install      - 安装 x-ui 面板"
    echo -e "x-ui uninstall    - 卸载 x-ui 面板"
    echo -e "----------------------------------------------"
}

echo -e "${green}开始安装${plain}"
install_base
install_x-ui $1
