#!/bin/sh
# k8s基础环境安装



# 获取脚本执行的路径
pwddir=$(pwd)


# 判断k8senv.yaml填写是否准确
function getk8senvline() {
     for line in local_ip,regis_repos,mirrors_repos
     do
       lines=$(grep "^$lines" k8senv.yaml|wc -l)
       if [ ! $lines -ne 1 ]; then
           echo "k8senv.yaml中填写的$lines过多或者过少,请修改"
           exit 1  # 退出脚本
       fi
     done
}
getk8senvline



# 判断部署的ip是否更改
function getk8senv() {
       variable=`cat k8senv.yaml |grep "^local_ip"|cut -d "=" -f2|sed 's/"//g'`
       if [ "$variable" = "localhost" ]; then
          echo "k8senv.yaml中local_ip的值没有修改,请修改完,再执行脚本"
          exit 1  #退出脚本
       fi

}


getk8senv



#
function stopfire() {
  # 1. 关闭防火墙
  systemctl stop firewalld
  systemctl disable firewalld

#  2. 关闭当前的selinux
   setenforce 0
   sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
   sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
   cat /etc/selinux/config
}




# 获取regis_repos地址
variable=`cat k8senv.yaml |grep "^local_ip"|cut -d "=" -f2|sed 's/"//g'`
mirrors_repo_infor=`cat k8senv.yaml |grep "^mirrors_repo"|cut -d "=" -f2|sed 's/"//g'`
regis_repos_infor=`cat k8senv.yaml |grep "^regis_repos"|cut -d "=" -f2|sed 's/"//g'`


# 添加hosts的方法
function add_hosts() {
  cat >>/etc/hosts << EOF
$variable $mirrors_repo_infor
$variable $regis_repos_infor
EOF
}



# 安全,启动nexus
function nexus_install() {
     cd $pwddir
     if [ ! -e "/data/nexus.tar.gz" ]; then
        cp -f nexus.tar.gz /data
     fi

     if [ ! -d "/data/nexus" ]; then
        tar -zxvf  ./nexus.tar.gz -C /data
     fi


     # 启动nexus.sh
     cd /data/nexus && sh nexus.sh start

     # 替换regis_repos信息
     sed -i s/mirrors.pixiu.com/\$mirrors_repo_infor/g   /etc/yum.repos.d/nexus.repo
     yum clean all
     echo "yum仓库完成"
}



# python ansible安装
function ansible_install() {
  cd $pwddir
  if [ ! -d "./ansibleinstall" ]; then
     tar -zxvf ansibleinstall.tar.gz
  fi
  cd ansibleinstall && sh ansibleinstall.sh
}



# docker 安装
function docker_install() {
  cd $pwddir
  if [ ! -d "./dockerinstall" ]; then
     tar -zxvf dockerinstall.tar.gz
  fi
  cd dockerinstall && sh docker.sh


}



# 导入镜像push镜像
function  k8soffimage_push() {
   cd $pwddir
   if [ ! -d "./k8soffimage" ]; then
      tar -zxvf k8soffimage.tar.gz
   fi
   cd k8soffimage && sh k8simage.sh load
   sleep 1

   # 判断/etc/docker目录是否存在
   if [ ! -d "/etc/docker" ]; then
      mkdir -p /etc/docker
   fi

   # 判断/etc/docker/daemon.json是否存在
   if [ ! -e "/etc/docker/daemon.json" ]; then
  cat > /etc/docker/daemon.json <<\EOF
{
  "insecure-registries": ["registry.pixiu.com:58001"]
}
EOF
    fi

  # 判断insecure-registrie是否添加信任
  docker_lines=$(grep "registry.pixiu.com" /etc/docker/daemon.json|wc -l)
   if [ ! $docker_lines -gt 0  ]; then
         yum localinstall -y jq/*
         cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%F_%H:%M)
         echo "正在添加registry-mirrors"
         jq --arg repositoryip "$variable" '.["insecure-registries"] += [$regis_repos:58001]' /etc/do
cker/daemon.json > /etc/docker/daemon.json.new
         mv /etc/docker/daemon.json.new /etc/docker/daemon.json
         systemctl reload docker
   fi

   $variable要传入的regis_repos信息
   sh k8simage.sh push $regis_repos_infor
}



# 脚本帮助信息
function printHelp() {
    printf "[WARN] 请选择你要输入的参数.\n\n"
    echo "Available Commands:"
    printf "  %-25s\t %s\t \n" "all" "安装所有服务"
    # printf "  %-25s\t %s\t \n" "nexus" "安装nexus服务"
    # printf "  %-25s\t %s\t \n" "ansible" "安装python36和ansible服务"
    # printf "  %-25s\t %s\t \n" "docker" "安装docker服务"
    # printf "  %-25s\t %s\t \n" "k8soffimage" "push所有k8s镜像到镜像仓库"
}






function k8sdeployserver() {
    case $1 in
  all)
   echo "正在安装所有服务"
   stopfire
   add_hosts
   nexus_install
   ansible_install
   docker_install
   k8soffimage_push
   ;;

   nexus)
   echo "将要安装nexus服务"
   nexus_install
   ;;

   ansible)
   echo "将要安装python36和ansible服务"
   ansible_install
   ;;

   docker)
   echo "将要安装docker服务"
   docker_install
   ;;

   -h)
   printHelp
   ;;

   *)
   printHelp
  esac
}

k8sdeployserver $1
