#!/bin/bash
set -e


Primary="10.0.0.4"
Secondary1="10.0.0.2"
Secondary2="10.0.0.3"
temp_install_dir="/install/mongodb"
remote_user="administrator"

function  generate_install_sh() {
SCRIPT_NAME="install.sh"
################################################################################################################################################

sudo tee -a "${temp_install_dir}/$SCRIPT_NAME" >/dev/null <<'install'
#!/bin/bash


sudo setenforce 0
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

# 副本集名称
#mongodb配置文件
MONGO_CONF="/etc/mongod.conf"

echo "############配置repo源##################"
REPO_FILE="/etc/yum.repos.d/mongodb-enterprise-6.0.repo"
rm -rf ${REPO_FILE}
echo ${REPO_FILE}
# 使用EOF将内容添加到repo文件中
sudo tee -a "$REPO_FILE" >/dev/null <<eofrepo
[mongodb-enterprise-6.0]
name=MongoDB Enterprise Repository
baseurl=https://repo.mongodb.com/yum/redhat/9/mongodb-enterprise/6.0/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-6.0.asc
eofrepo


echo "############安装mongodb##################"

sudo yum install -y mongodb-enterprise-6.0.16 mongodb-enterprise-database-6.0.16 mongodb-enterprise-server-6.0.16 mongodb-enterprise-mongos-6.0.16 mongodb-enterprise-tools-6.0.16

echo "############修改配置文件##################"

rm -rf $MONGO_CONF
sudo tee -a "$MONGO_CONF" >/dev/null<<eofmongod
# mongod.conf
systemLog:
  destination: file
  logAppend: false
  path: /var/log/mongodb/mongod.log

# Where and how to store data.
storage:
  dbPath: /var/lib/mongo
  journal:
    enabled: true
  engine: wiredTiger
  wiredTiger:
    engineConfig:
       cacheSizeGB: 7

# how the process runs
processManagement:
  timeZoneInfo: /usr/share/zoneinfo

# network interfaces
net:
  port: 27017
  bindIp: 0.0.0.0  # Enter 0.0.0.0,:: to bind to all IPv4 and IPv6 addresses or, alternatively, use the net.bindIpAll setting.


security:
  authorization: enabled
  keyFile: /var/log/mongodb/mongo.key

replication:
  replSetName: 

eofmongod

mv $1/mongo.key /var/log/mongodb/
chmod 400 /var/log/mongodb/mongo.key
chown -R mongod:mongod /var/log/mongodb/mongo.key

echo "############启动mongodb##################"
systemctl start mongod

echo "############检查启动状态##################"
sleep 3


state=$(systemctl status mongod|grep "Active"|awk -F" " '{print $2}')
if [ "${state}" = "active" ];then
	echo "mongod  启动成功"
else
	echo "mongo 启动失败,启动日志如下"
	tail -n20 /var/log/mongodb/mongod.log
	exit 1
fi
install
sed -i "s/replSetName:/replSetName: ${replic_name}/g" $temp_install_dir/$SCRIPT_NAME
}
################################################################################################################################################

function generate_rm_mongo() {
UNSTALL_SCRIPT="rm_mongo.sh"

sudo tee -a "${temp_install_dir}/$UNSTALL_SCRIPT" >/dev/null <<'eofuninstall'
#!/bin/bash
systemctl stop mongod
yum erase -y  $(rpm -qa | grep mongodb-enterprise)
rm -rf /var/log/mongodb/
rm -rf /var/lib/mongo/
eofuninstall
}

function create_install_path(){
	if [ -d "$temp_install_dir" ];then
			echo "${temp_install_dir} 目录存在"
	else

			mkdir -p ${temp_install_dir}
	fi
	ssh "${remote_user}@${Secondary1}" "
	    if [ -d '${temp_install_dir}' ]; then 
	        echo 'Directory ${temp_install_dir} exists on ${Secondary1}'; 
	    else 
	        echo 'Directory ${temp_install_dir} does not exist on ${Secondary1}, creating it...'; 
	        sudo mkdir -p '${temp_install_dir}' && sudo chmod 777 -R '${temp_install_dir}'; 
	    fi"
	ssh "${remote_user}@${Secondary2}" "
	    if [ -d '${temp_install_dir}' ]; then 
	        echo 'Directory ${temp_install_dir} exists on ${Secondary2}'; 
	    else 
	        echo 'Directory ${temp_install_dir} does not exist on ${Secondary2}, creating it...'; 
	        sudo mkdir -p '${temp_install_dir}' && sudo chmod 777 -R '${temp_install_dir}'; 
	    fi"
}

function create_key(){
		echo "######################生成副本集密钥"
		openssl rand -base64 756 > ${temp_install_dir}/mongo.key
		echo "${Secondary1}" && scp ${temp_install_dir}/mongo.key ${remote_user}@${Secondary1}:${temp_install_dir}/
		echo "${Secondary2}" && scp ${temp_install_dir}/mongo.key ${remote_user}@${Secondary2}:${temp_install_dir}/
}

function copy_to_target_install_shell(){
		echo "######################传输安装脚本"
		if [ $option == "install" ];then
			scp ${temp_install_dir}/${SCRIPT_NAME} ${remote_user}@${Secondary1}:${temp_install_dir}
			scp ${temp_install_dir}/${SCRIPT_NAME} ${remote_user}@${Secondary2}:${temp_install_dir}
		else
			echo "######################传输删除脚本"
			scp ${temp_install_dir}/${UNSTALL_SCRIPT} ${remote_user}@${Secondary1}:/${temp_install_dir}
			scp ${temp_install_dir}/${UNSTALL_SCRIPT} ${remote_user}@${Secondary2}:/${temp_install_dir}
		fi
}

function clear_all_shell(){
		echo "清理安装脚本"
		rm -rf ${temp_install_dir}
		echo "${Secondary1}" && ssh "${remote_user}@${Secondary1}" "sudo rm -rf ${temp_install_dir}"
		echo "${Secondary2}" && ssh "${remote_user}@${Secondary2}" "sudo rm -rf ${temp_install_dir}"
}

function exec_shell(){
		if [ $option == "install" ];then

			echo "######################开始安装执行脚本:${Primary}######################" && sudo /bin/bash ${temp_install_dir}/${SCRIPT_NAME} ${temp_install_dir}
			echo "######################开始安装执行脚本:${Secondary1}######################" && sleep 3 && ssh "${remote_user}@${Secondary1}" "sudo chmod a+x ${temp_install_dir}/$SCRIPT_NAME && sudo /bin/bash  ${temp_install_dir}/$SCRIPT_NAME ${temp_install_dir}"
			echo "######################开始安装执行脚本:${Secondary2}######################" && sleep 3 && ssh "${remote_user}@${Secondary2}" "sudo chmod a+x ${temp_install_dir}/$SCRIPT_NAME && sudo /bin/bash  ${temp_install_dir}/$SCRIPT_NAME ${temp_install_dir}"
		else
			echo "######################开始执行删除脚本:${Primary}######################" && sudo /bin/bash ${temp_install_dir}/${UNSTALL_SCRIPT}
			echo "######################开始执行删除脚本:${Secondary1}######################" && sleep 3 && ssh "${remote_user}@${Secondary1}" "sudo chmod a+x ${temp_install_dir}/$UNSTALL_SCRIPT && sudo /bin/bash ${temp_install_dir}/$UNSTALL_SCRIPT"
			echo "######################开始执行删除脚本:${Secondary2}######################" && sleep 3 && ssh "${remote_user}@${Secondary2}" "sudo chmod a+x ${temp_install_dir}/$UNSTALL_SCRIPT && sudo /bin/bash ${temp_install_dir}/$UNSTALL_SCRIPT"
		fi

}

function mongo_repl_init(){
		username="admin"
		echo "######################开始进行副本集初始化:${Primary}######################"
		result=$(mongosh --eval "use admin;" --eval "rs.initiate({_id: '${replic_name}', members: [{ _id: 0, host: '${Primary}:27017', priority: 3 }, { _id: 1, host: '${Secondary1}:27017', priority: 2 }, { _id: 2, host: '${Secondary2}:27017', priority: 1 }]});")
  		echo "######################初始化结果： ${result} }######################"


  		#等待集群选主
  		sleep 20
  		cluster_state=$(mongosh --eval 'rs.status()'|grep -E 'name|stateStr')
  		echo "######################集群状态######################"
		echo "${cluster_state}"
		echo "###################################################"



}




option=$1

case $option in 
	install)
		clear_all_shell
		read -p "输入副本集名称: " replic_name
		create_install_path
		generate_install_sh
		create_key
		copy_to_target_install_shell
		exec_shell
		clear_all_shell
		mongo_repl_init
		;;
	uninstall)
		read -p "本操作将直接删除整个副本集群，请确认操作，输入 'yes' 确认继续，或者输入 'no' 取消操作: " confirmation
			if [[ "$confirmation" == "yes" ]]; then
				create_install_path
				generate_rm_mongo
				copy_to_target_install_shell
				exec_shell
				clear_all_shell
			else
				echo "操作停止"
				exit 1
			fi
		;;
	*)
	 	echo "Usage: $0 {install|uninstall|status}"
        exit 1
        ;;
esac


