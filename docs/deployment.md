# Patroni Cluster Deployment


## 部署方式

Patroni的配置部署较为方便，可以通过网上提供的自动化的部署方式进行配置，也可以自行配置。下面将介绍两种方式的配置方式

### 方式一 [自动化部署]

```shell
# 安装内容主要有以下
1.依赖软件包安装及系统配置
2.consul安装
3.patroni安装
4.postgresql安装
5.haproxy安装
6.peometheus安装
7.grafana配置

# pigsty软件下载
$ curl -fsSL https://pigsty.cc/pigsty.tgz | gzip -d | tar -xC ~; cd ~/pigsty

# 编译安装
## 此步会提示下载整个集群需要的所有程序资源/tmp/pkg.tgz = 1.1GB
$ make config

## 安装meta管理集群
$ make install   # INSTALL infrasturcture on meta node，实际测试中和./infra.yaml实现一样

# 创建其他集群
$ cat pigsty.yml
all: # top-level namespace
  children:
    #-----------------------------
    # meta controller
    #-----------------------------
    meta:      # special group 'meta' defines the main controller machine
      vars:
        meta_node: true                    # mark node as meta controller
        ansible_group_priority: 99         # meta group has top priority
      hosts:
        10.37.129.2: {}
    pg-meta:
      hosts:
        10.37.129.3: {pg_seq: 1, pg_role: primary, pg_offline_query: true}
        10.37.129.4: {pg_seq: 2, pg_role: replica, pg_offline_query: true}
        10.37.129.5: {pg_seq: 3, pg_role: replica, pg_offline_query: true}

      # - cluster configs - #
      vars:
        pg_cluster: pg-test                 # define actual cluster name
        pg_version: 13                      # define installed pgsql version
        node_tune: tiny                     # tune node into oltp|olap|crit|tiny mode
        pg_conf: tiny.yml                   # tune pgsql into oltp|olap|crit|tiny mode
        patroni_watchdog_mode: off          # disable watchdog (require|automatic|off)
        pg_lc_ctype: en_US.UTF8             # enabled pg_trgm i18n char support

# 开始配置新集群
$ ./pgsql.yml 

# 可以通过meta节点3000端口访问监控管理端
http://10.37.129.2:3000
```



### 方式二 [手动部署]

#### 1. 操作系统配置

```shell
# 禁用防火墙
$ systemctl stop firewalld && systemctl disable firewalld

# 禁用selinux
$ sed -i 's/=enforcing/=disabled/g' /etc/selinux/config && setenforce 0

# 启用时间同步
$ yum install -y chrony
$ sed -i '/^server/d;2a server ntp1.aliyun.com iburst' /etc/chrony.conf
$ systemctl start chronyd && systemctl enable chronyd

# 安装python3及开发包
$ yum insatll -y python3 python3-devel

# 安装watchdog
$ yum install -y watchdog

# 安装gcc编译器,yum-utils模块
$ yum install -y gcc yum-utils
```

#### 2. Consul部署

```shell
# 配置consul yum仓库
$ yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo

# 安装consul
$ yum install -y consul

# 配置consul
## consul-01
$ cat /etc/consul.d/consul.hcl
datacenter = "my-dc-1"
data_dir = "/opt/consul"
client_addr = "0.0.0.0"
ui = true
server = true
bootstrap_expect=3
retry_join = ["10.37.129.3","10.37.129.4","10.37.129.5"]
node_name = "consul-01"
bind_addr = "10.37.129.3" # the other node with different ip address
## consul-02
node_name = "consul-02"
bind_addr = "10.37.129.4"
## consul-03
node_name = "consul-03"
bind_addr = "10.37.129.5"

# 创建数据目录
## consul01/02/03
$ mkdir /opt/consul

# 启动consul
$ systmectl start consul && systemctl enable consul

# 查看consul集群状态
$ consul members
Node       Address             Status  Type    Build  Protocol  DC       Segment
consul-01  10.37.129.3:8301  alive   server  1.9.6  2         my-dc-1  <all>
consul-02  10.37.129.4:8301  alive   server  1.9.6  2         my-dc-1  <all>
consul-03  10.37.129.5:8301  alive   server  1.9.6  2         my-dc-1  <all>

# 查看leader
$ consul operator raft list-peers
Node       ID                                    Address           State     Voter  RaftProtocol
consul-03  5d93006e-eb8f-a3e6-d010-4617f19c292c  10.37.129.5:8300  leader    true   3
consul-01  c594a1f3-dd30-102b-f55d-04ad2b588180  10.37.129.3:8300  follower  true   3
consul-02  26d06224-b390-5e12-0d62-0c37e23644a0  10.37.129.4:8300  follower  true   3

# 通过web ui访问consul集群
http://10.37.129.3:8500
```

#### 3. Postgres部署

```shell
# 配置postgres yum仓库
$ yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# 安装postgres
$ yum install -y postgresql12-server libpq5-devel postgresql2-contrib

# 默认路径(nothing to do)
PGDATA=/var/lib/pgsql/12/data # database datafiles
PGHOME=/usr/pgsql-12  # binary file
```

#### 4. Patroni配置

```shell
# node pgsql-01
# 安装patroni
$ pip3 install psycopg2==2.8.6
$ pip3 install patroni[consul]

# 配置patroni
## [详细](3 - Configuration.md)

$ cat /etc/patroni/patroni.yml
############### General/Global ########################################
scope: pg-cluster  # cluster_name
namespace: /pg/  # dcs key prefix
name: pgsql-01  # node_name in cluster, unique

############### RestAPI ###############################################
restapi:
  listen: 0.0.0.0:8008  # listen address
  connect_address: 10.37.129.3:8008  # connect by RestAPI
  authentication:  # up to now, I don't know how does it works
    username: postgres
    password: "123456"
  http_extra_headers:  # just know about, I know nothing with http headers
    'X-Frame-Options': 'SAMEORIGIN'
    'X-XSS-Protection': '1; mode=block'
    'X-Content-Type-Options': 'nosniff'
  https_extra_headers:
    'Strict-Transport-Security': 'max-age=31536000; includeSubDomains'

############### Consul ################################################
consul:
  host: 127.0.0.1:8500  # connect to local consul agent with port 8500
  scheme: http  # wheather use tls encrypted
  verify: false  # wheather verify tls 
  dc: my-dc-1
  consistency: default  # consistent degree with consul
  check: false
  register_service: true  # wheather register a service in consul
  service_tags:
    - pg-cluster-consul
  service_check_interval: 15s # check for every 15 seconds

############### Ctl ##################################################
ctl:
  insecure: false  # if not configured tls, set to false

############### Log ##################################################
log:
  level: INFO
  traceback_level: INFO
  format: '%(asctime)s %(levelname)s: %(message)s'
  dateformat: '%Y-%m-%d %H:%M:%S %z'
  max_queue_size: 1000
  dir: /tmp/
  file_num: 10
  file_size: 10485760

############### Bootstrap ############################################
bootstrap:
  dcs:
    ttl: 30  # the leader key ttl
    loop_wait: 10  # patroni check interval time/sleep time(s)
    retry_timeout: 10  # if cannot connect to consul, 10s try again, not degrade, within 20s failed elected
    maximum_lag_on_failover: 1048576  # if lag lower than the values, patroni can failover
    maximum_lag_on_syncnode: 1048576  # if sync replica lag upper than the values, switch sync replica
    max_timeline_history: 10  # replica can get min timeline from consul
    master_start_timeout: 60  # if it doesn't start after 60s, it will post start failed
    master_stop_timeout: 60  # if it doesn't stop after 60s, it will post start failed
    synchronous_mode: true  # if use synchronous replica
    synchronous_mode_strict: false  # if there is no sync replica, hang the primary
    synchronous_node_count: 1  # the maximum sync replica 
    postgresql: 
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_connections: 300
        max_worker_processes: 8
        wal_keep_segments: 8
        max_wal_senders: 10
        max_replication_slots: 10
        max_prepared_transactions: 0
        max_locks_per_transaction: 64
        wal_log_hints: "on"
        track_commit_timestamp: "off"
        archive_mode: "on"
        archive_timeout: 1800s
        archive_command: mkdir -p ../wal_archive && test ! -f ../wal_archive/%f && cp %p ../wal_archive/%f
    slots:  # create permanent physical shot for standby cluster
      standby_cluster_slot:
        type: physical

  method: initdb  # when initialize new cluster, use initdb to initialize a new database

  initdb:
    - encoding: UTF8
    - locale: C
    - lc-collate: C
    - lc-ctype: en_US.UTF8
    - data-checksums

  pg_hba:
    # "local" is for Unix domain socket connections only
    - local   all             all                                     trust
    # IPv4 local connections:
    - host    all             all             127.0.0.1/32            trust
    # IPv6 local connections:
    - host    all             all             ::1/128                 trust
    # Allow replication connections from localhost
    - local   replication     all                                     trust
    - host    replication     all             127.0.0.1/32            trust
    - host    replication     all             ::1/128                 trust
    # Allow replication connection from subnet
    - host    replication     replicator      10.37.129.0/24          md5
    # Allow other connections
    - host    all             all             10.37.129.0/24          md5

  users:  # users created after new cluster initialized
    gitlab:  # username
      password: "123456" 
      options:  # you can set privileges or others options
        - createdb
        - createrole

  # post_init: /usr/local/bin/setup_cluster.sh  # when new cluster initialized execute this script

############### Postgresql ###########################################
postgresql:
  listen: 0.0.0.0:5432  # PGSQL listen_address
  connect_address: 10.37.129.3:5432  # patroni use this to connect to pgsql
  data_dir: /var/lib/pgsql/12/data  # PGDATA
  bin_dir: /usr/pgsql-12/bin  # PGHOME/bin
  config_dir: /var/lib/pgsql/12/data  # PGDATA
  pgpass: /var/lib/pgsql/12/.pgpass  # password file to store users password

  custom_conf: /var/lib/my_custom.conf  # you can specified a conf file to apply to pgsql, it should exists  before

  create_replica_methods:  # when patroni cluster create a replica, use pg_basebackup to init
    - basebackup
  basebackup:
    - max-rate: '1000M'
    - checkpoint: fast
    - status-interval: 1s
    - verbose
    - progress

  use_unix_socket: true
  use_unix_socket_repl: true
  use_pg_rewind: true
  pg_ctl_timeout: 60  # command pg_ctl execute stop/start/restart timeout to failed
  remove_data_directory_on_rewind_failure: true  # if pg_rewind failed, use pg_basebackup to init a replica
  remove_data_directory_on_diverged_timelines: true  # if timeline diverged cannot continue, use pg_basebackup to init a replica

  parameters:  # if this block parameters already exists before, overwrite it, it can take effect anytime when restart patroni
    logging_collector: "on"
    log_filename: "postgresql-%Y-%m-%d.log"
    log_statement: "all"
    log_replication_commands: "on"
    timezone: "Asia/Shanghai"
    log_timezone: "PRC"

  authentication:  # users created after new cluster initialized, different from before, can only create only create following three type of users
    replication:
      username: replicator
      password: "123456"
    superuser:
      username: postgres
      password: "123456"
    rewind:
      username: rewind-user
      password: "123456"

  pg_hba:
    # "local" is for Unix domain socket connections only
    - local   all             all                                     trust
    # IPv4 local connections:
    - host    all             all             127.0.0.1/32            trust
    # IPv6 local connections:
    - host    all             all             ::1/128                 trust
    # Allow replication connections from localhost
    - local   replication     all                                     trust
    - host    replication     all             127.0.0.1/32            trust
    - host    replication     all             ::1/128                 trust
    # Allow replication connection from subnet
    - host    replication     replicator      10.37.129.0/24          scram-sha-256
    # Allow other connections
    - host    all             all             10.37.129.0/24          scram-sha-256

  pg_ident:
    - gitlab git gitlab

  callbacks: # when patroni start/stop/restart/reload/role_change do it
    on_start: /bin/bash /etc/patroni/patroni_callback.sh
    on_stop: /bin/bash /etc/patroni/patroni_callback.sh
    on_role_change: /bin/bash /etc/patroni/patroni_callback.sh

############### Watchdog #############################################
watchdog:  # if system hang, use watchdog to force reboot
  mode: off
  device: /dev/watchdog
  safety_margin: 5  # if leader key free upper to 5s, the watchdog take effect

############### Tags #################################################
tags:
    nofailover: false  # true means it never be a leader 
    noloadbalance: false  # when use haproxy, it will return http 503 to avoid load balance to use
    clonefrom: false  # true means if new replica will be create, it will clone from this node
    nosync: false  # true means it never be a sync replica


# vip for standby cluster 
## /etc/patroni/patroni_callback.sh
#!/bin/bash

readonly OPERATION=$1
readonly ROLE=$2
readonly SCOPE=$3

VIP='10.37.129.15'
PREFIX='24'
BRD='10.37.129.255'
INF='eth1'

function usage() {
    echo "Usage: $0 <on_start|on_stop|on_role_change> <ROLE> <SCOPE>";
    exit 1;
}

echo "$(date "+%Y-%m-%d %H:%M:%S %z") This is patroni callback $OPERATION $ROLE $SCOPE"

case $OPERATION in
    on_stop)
        sudo ip addr del ${VIP}/${PREFIX} dev ${INF} label ${INF}:1
        echo "$(date "+%Y-%m-%d %H:%M:%S %z") VIP ${VIP} removed"
        ;;
    on_start | on_restart | on_role_change)
        if [[ $ROLE == 'master' || $ROLE == 'standby_leader' ]]; then
            sudo ip addr add ${VIP}/${PREFIX} brd ${BRD} dev ${INF} label ${INF}:1
            sudo arping -q -A -c 1 -I ${INF} ${VIP}
            echo "$(date "+%Y-%m-%d %H:%M:%S %z") VIP ${VIP} added"
        else
            sudo ip addr del ${VIP}/${PREFIX} dev ${INF} label ${INF}:1
            echo "$(date "+%Y-%m-%d %H:%M:%S %z") VIP ${VIP} removed"
        fi
        ;;
    *)
        usage
        ;;
esac

# 配置patroni服务
$ cat /usr/lib/systemd/system/patroni.service
[Unit]
Description=Runners to orchestrate a high-availability PostgreSQL
After=syslog.target network.target etcd.service

[Service]
Type=simple
User=postgres
Group=postgres
EnvironmentFile=-/etc/patroni/patroni_env.conf
ExecStartPre=-/usr/bin/sudo /sbin/modprobe softdog
ExecStartPre=-/usr/bin/sudo /bin/chown postgres /dev/watchdog
ExecStart=/usr/bin/env patroni /etc/patroni/patroni.yml
ExecReload=/bin/kill -s HUP $MAINPID
KillMode=process
TimeoutSec=30
Restart=on-failure

[Install]
WantedBy=multi-user.target

# node pgsql-02 同上
name: pgsql-02
restapi:
  connect_address: 10.37.129.4:8008
postgresql:
  connect_address: 10.37.129.4:5432
# node pgsql-03 同上
name: pgsql-03
restapi:
  connect_address: 10.37.129.5:8008
postgresql:
  connect_address: 10.37.129.5:5432
  
# 启用patroni
$ systemctl daemon-reload
$ systemctl enable patroni
$ systemctl start patroni

# 查看集群状态
$ export PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml
$ patronictl list
+ Cluster: pg-cluster (6976360105259810136) ------+----+-----------+
| Member   | Host        | Role         | State   | TL | Lag in MB |
+----------+-------------+--------------+---------+----+-----------+
| pgsql-01 | 10.37.129.3 | Leader       | running | 32 |           |
| pgsql-02 | 10.37.129.4 | Replica      | running | 32 |         0 |
| pgsql-03 | 10.37.129.5 | Sync Standby | running | 32 |         0 |
+----------+-------------+--------------+---------+----+-----------+
```

#### 5.Standby cluster配置

```shell
# first you should prepare a normal patroni cluster as before but not initialize
# 调整配置文件
......
bootstrap:
  dcs:
    standby_cluster:  # if remove this block from config file and restart patroni, the cluster will become a  now patroni cluster, not standby cluster, so as switchover or failover 
    host: 10.37.129.15  # vip configured before
    port: 5432
    primary_slot_name: standby_cluster  # permanent physical replication slot created before
    create_replica_methods:
      - basebackup
......

# 开始初始化
# node pgsql-01/02/03-standby
$ sudo systemctl enable patroni
$ sudo systemctl start patroni

# 查看状态
$ patronictl list
+ Cluster: pg-cluster-standby (6976360105259810136) --------+----+-----------+
| Member           | Host        | Role           | State   | TL | Lag in MB |
+------------------+-------------+----------------+---------+----+-----------+
| pgsql-01-standby | 10.37.129.6 | Replica        | running | 32 |         0 |
| pgsql-02-standby | 10.37.129.7 | Replica        | running | 32 |         0 |
| pgsql-03-standby | 10.37.129.8 | Standby Leader | running | 32 |           |
+------------------+-------------+----------------+---------+----+-----------+

# 一个正在运行的Patroni cluster可以通过以下命令转换为一个正常的cluster
# 取消上游主库
$ patronictl edit-config -s standby_cluster= 
# 查看集群状态
$ patronictl list
+ Cluster: pg-cluster-standby (6976360105259810136) -+----+-----------+
| Member           | Host        | Role    | State   | TL | Lag in MB |
+------------------+-------------+---------+---------+----+-----------+
| pgsql-01-standby | 10.37.129.6 | Replica | running | 34 |         0 |
| pgsql-02-standby | 10.37.129.7 | Replica | running | 34 |         0 |
| pgsql-03-standby | 10.37.129.8 | Leader  | running | 34 |           |
+------------------+-------------+---------+---------+----+-----------+
```


