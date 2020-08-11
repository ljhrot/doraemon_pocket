#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# Current folder
cur_dir=`pwd`

# Color
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# Make sure only root can run our script
[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] This script must be run as root!" && exit 1

# rpm -qa|grep mariadb
# rpm -qa|grep mysql


# Disable selinux
disable_selinux(){
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
}

# Get version
getversion(){
    if [[ -s /etc/redhat-release ]]; then
        grep -oE  "[0-9.]+" /etc/redhat-release
    else
        grep -oE  "[0-9.]+" /etc/issue
    fi
}

# CentOS version
centosversion(){
    if check_sys sysRelease centos; then
        local code=$1
        local version="$(getversion)"
        local main_ver=${version%%.*}
        if [ "$main_ver" == "$code" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

get_char(){
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

#Check system
check_sys(){
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''

    if [[ -f /etc/redhat-release ]]; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "centos|red hat|redhat" /proc/version; then
        release="centos"
        systemPackage="yum"
    fi

    if [[ "${checkType}" == "sysRelease" ]]; then
        if [ "${value}" == "${release}" ]; then
            return 0
        else
            return 1
        fi
    elif [[ "${checkType}" == "packageManager" ]]; then
        if [ "${value}" == "${systemPackage}" ]; then
            return 0
        else
            return 1
        fi
    fi
}

# Pre-installation settings
pre_install(){
    if check_sys packageManager yum; then
        # Not support CentOS 5
        if centosversion 6; then
            echo -e "$[{red}Error${plain}] Not supported CentOS 6, please change to CentOS 7+ and try again."
            exit 1
        fi
    else
        echo -e "[${red}Error${plain}] Your OS is not supported. please change OS to CentOS and try again."
        exit 1
    fi

    # remove mariadb
    rpm -e --nodeps mariadb-server
    rpm -e --nodeps mariadb
    rpm -e --nodeps mariadb-libs

    echo
    echo
    
    # Set mysql config password
    while true
    do
    echo "Please enter password for MySQL8, 必须包含大小写特殊字符且超过8位"
    read -p "(Default password: Linkapp#2020):" mysqlpwd
    [ -z "${mysqlpwd}" ] && mysqlpwd="Linkapp#2020"
    strlen=`echo ${mysqlpwd} | grep -E --color '^(.{8,}).*$'`
    #密码长度是否8位以上（包含8位）
    strlow=`echo ${mysqlpwd} | grep -E --color '^(.*[a-z]+).*$'`
    #密码是否有小写字母
    strupp=`echo ${mysqlpwd} | grep -E --color '^(.*[A-Z]).*$'`
    #密码是否有大写字母
    strts=`echo ${mysqlpwd} | grep -E --color '^(.*\W).*$'`
    #密码是否有特殊字符
    strnum=`echo ${mysqlpwd} | grep -E --color '^(.*[0-9]).*$'`
    #密码是否有数字
    #-n 判断字符不为空 返回真
    if [ -n "${strlen}" ] && [ -n "${strlow}" ] && [ -n "${strupp}" ] && [ -n "${strts}" ]  && [ -n "${strnum}" ] 
    then
        echo
        echo "---------------------------"
        echo "password = ${mysqlpwd}"
        echo "---------------------------"
        echo
        break
    fi
    echo -e "[${red}Error${plain}] Please enter a correct password"
    done

    # Set mysql config port
    while true
    do
    dport=3306
    echo "Please enter a port for MySQL8 [1-65535]"
    read -p "(Default port: ${dport}):" mysqlport
    [ -z "$mysqlport" ] && mysqlport=${dport}
    expr ${mysqlport} + 1 &>/dev/null
    if [ $? -eq 0 ]; then
        if [ ${mysqlport} -ge 1 ] && [ ${mysqlport} -le 65535 ] && [ ${mysqlport:0:1} != 0 ]; then
            echo
            echo "---------------------------"
            echo "port = ${mysqlport}"
            echo "---------------------------"
            echo
            break
        fi
    fi
    echo -e "[${red}Error${plain}] Please enter a correct number [1-65535]"
    done

    echo
    echo "Press any key to start...or Press Ctrl+C to cancel"
    char=`get_char`
    # Install necessary dependencies
    if check_sys packageManager yum; then
        yum install -y unzip net-tools perl
    fi
    cd ${cur_dir}
}

# Config mysql8
config_mysql8(){
    cat > /etc/my.cnf<<-EOF
# The following options will be passed to all mysql clients
[client]
password	= "${mysqlpwd}"
default-character-set = utf8
port		= ${mysqlport}
socket		= /var/lib/mysql/mysql.sock

# Here follows entries for some specific programs

# The mysql server
[mysqld]
port		= ${mysqlport}
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock

log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid

skip-external-locking
max_connections=10240
max_connect_errors = 50
#key_buffer_size = 16M
key_buffer_size = 128M
#max_allowed_packet = 1M
max_allowed_packet = 32M
#table_open_cache = 64
table_open_cache = 4096
#sort_buffer_size = 512K
#net_buffer_length = 8K
binlog_cache_size = 8M
max_heap_table_size = 128M
#read_buffer_size = 256K
#read_rnd_buffer_size = 512K
read_rnd_buffer_size = 16M
#myisam_sort_buffer_size = 8M
sort_buffer_size = 32M
net_buffer_length = 160K
read_buffer_size = 5120K
read_rnd_buffer_size = 10240K
myisam_sort_buffer_size = 160M
lower_case_table_names=1

slow_query_log=1
long_query_time=1

# *** INNODB 相关选项 ***
#skip-innodb
innodb_buffer_pool_size = 28G
innodb_data_file_path = ibdata1:10M:autoextend
#innodb_data_home_dir =

innodb_flush_log_at_trx_commit = 0
#innodb_fast_shutdown
innodb_log_buffer_size = 16M
innodb_log_file_size = 1G
innodb_log_files_in_group = 3
innodb_max_dirty_pages_pct = 90
innodb_lock_wait_timeout = 120
innodb_file_per_table = on
innodb_flush_method=O_DIRECT

[mysqldump]
quick
#max_allowed_packet = 16M
max_allowed_packet = 32M

[mysql]
no-auto-rehash
# Remove the next comment character if you are not familiar with SQL
#safe-updates

[myisamchk]
#key_buffer_size = 400M
#sort_buffer_size = 400M
#read_buffer = 32M
#write_buffer = 32M

key_buffer = 32M
sort_buffer_size = 32M
read_buffer = 8M
write_buffer = 8M

innodb_io_capacity=400
innodb_io_capacity_max=4000
innodb_lru_scan_depth=1500

[mysqlhotcopy]
interactive-timeout

[mysqld_safe]  
# 增加每个进程的可打开文件数量.  
# 警告: 确认你已经将全系统限制设定的足够高!  
# 打开大量表需要将此值设大  
open-files-limit = 8192
EOF
}

# Install mysql8
install(){

    cd ${cur_dir}
    unzip -q mysql8.zip -d mysql8
    if [ $? -ne 0 ];then
        echo -e "[${red}Error${plain}] unzip mysql8.zip failed! please check unzip command."
        exit 1
    fi

    cd ${cur_dir}/mysql8

    rpm -ivh mysql-community-common-8.0.21-1.el7.x86_64.rpm
    if [ $? -ne 0 ]; then
        echo
        echo -e "[${red}Error${plain}] mysql8 install failed! please contact admin."
        exit 1
    fi

    rpm -ivh mysql-community-libs-8.0.21-1.el7.x86_64.rpm
    if [ $? -ne 0 ]; then
        echo
        echo -e "[${red}Error${plain}] mysql8 install failed! please contact admin."
        exit 1
    fi

    rpm -ivh mysql-community-client-8.0.21-1.el7.x86_64.rpm
    if [ $? -ne 0 ]; then
        echo
        echo -e "[${red}Error${plain}] mysql8 install failed! please contact admin."
        exit 1
    fi

    rpm -ivh mysql-community-server-8.0.21-1.el7.x86_64.rpm
    if [ $? -ne 0 ]; then
        echo
        echo -e "[${red}Error${plain}] mysql8 install failed! please contact admin."
        exit 1
    fi


    echo "Start MySQL 8 Server... "
    echo "please wait a minute... "
    systemctl start mysqld.service
    systemctl status mysqld.service

    # 关闭防火墙
    # systemctl status firewalld.service
    systemctl stop firewalld.service
    systemctl disable firewalld.service

    clear
    echo
    echo -e "Congratulations, mysql 8 server install completed!"
    echo -e "Your Server Port      : \033[41;37m ${mysqlport} \033[0m"
    echo -e "Your Password         : \033[41;37m ${mysqlpwd} \033[0m"
    echo
}

post_install(){
    MYSQL_PWD=`grep 'temporary password' /var/log/mysqld.log | awk -F "root@localhost: " '{print $2}'`
    mysqladmin -u root -p"${MYSQL_PWD}" password "${mysqlpwd}"
}

# Install mysql8
install_mysql8(){
    disable_selinux
    pre_install
    config_mysql8
    install
    post_install
}

install_mysql8