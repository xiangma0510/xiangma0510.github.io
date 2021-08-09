# Introduction of Patroni



## 起源

[Patroni]((https://github.com/zalando/patroni))是一个集群管理器，用于自定义和自动化 PostgreSQL HA（高可用性）集群的部署和维护。它使用分布式配置存储，如[Etcd](https://github.com/etcd-io/etcd)、[Consul](https://github.com/hashicorp/consul)、[ZooKeeper](https://github.com/apache/zookeeper) 或 [Kubernetes](https://github.com/kubernetes/kubernetes)，以获得最大的可访问性。Patroni起源于来自 Compose 的项目[Governor 的](https://github.com/compose/governor)一个分支。由德国公司人 Alexander 和 Oleksii使用python语言开发。目前属于[zalando](https://github.com/zalando)/[patroni](https://github.com/zalando/patroni)项目。



## 发展

Zalando在2015年9月发布了版本v0.1，截止2021年2月发布了最新版本v2.1.0，在起初的一段时间发布版本比较混乱，发布频率很不固定，截止目前发布频率依然不是很规律。



## 版本支持

目前官方声明支持的pgsql版本：9.3 ~ 13。但是按照其实现原理（相当于数据库托管软件），所以***理论上***可以支持更新的版本。

*Note :目前GitLab 13.12.x 中使用的pgsql的版本为11/12(default)。*



## 实现功能

- 故障检测

- 节点恢复

- 流量切换




## REST API

RestAPI 是前后端分离最佳实践，是开发的一套标准或者说是一套规范。

好处：

1. 轻量，直接通过http，不需要额外的协议，通常有POST/GET/PUT/DELETE/OPTIONS操作。
2. 面向资源，一目了然，具有自解释性
3. 数据描述简单，一般通过json或者xml做数据通讯

示例：`curl -w "%{http_code}" -X OPTIONS http://10.37.129.15:8008/master`



## 相似产品对比

PostgreSQL HA三种常见的解决方案PAF（PostgreSQL Automatic Failover）、repmgr和Patroni以及K8s中的stolon(因不可独立部署，本文忽略)。

- **PAF**

  优势：

  1.PAF为用户提供PostgreSQL的免费实践配置和设置。
  2.PAF可以处理节点故障，并在主服务器不可用时触发选举。
  3.法定人数行为可以在PAF中强制执行。
  4.将为资源提供完整的高可用管理解决方案，包括启动、停止、监控和处理网络隔离场景。
  5.这是一个分布式解决方案，可以管理来自另一个节点的任何节点。

  劣势：

  1.PAF不会检测待机是否在恢复配置中配置未知或不存在的节点。即使待机运行时没有连接到主节点/级联备用节点，节点也会显示为从节点。
  2.需要为Pacemaker和Corosync组件使用UDP进行通信打开一个额外的端口（默认5405）。
  3.不支持基于NAT的配置。
  4.没有pg_rewind支持。

- **repmgr**

  优势：

  1.Repmgr提供实用程序，帮助设置主节点和备用节点并配置复制。
  2.它不使用任何额外的端口进行通信。如果想执行切换，需要配置无密码的SSH。
  3.通过调用注册事件的用户脚本来提供通知。
  4.在主服务器故障的情况下执行自动故障转移。

  劣势：

  1.repmgr无法检测备用节点是否被错误配置为未知或不存在的节点。即该备用节点即使没有连接到主节点或者级联的主节点，也将显示为正常的备用节点。
  2.无法从 PostgreSQL 服务处于停机状态的节点检索另一个节点的状态。因此，它不提供分布式控制解决方案。
  3.它不处理恢复单个节点的健康。

- **patroni**

  优势：

  1.Patroni 启用集群的端到端设置。
  2.支持REST API和HAproxy集成。
  3.支持通过某些操作触发的回调脚本进行事件通知。
  4.利用DCS达成共识。

  劣势：

  1.Patroni不会检测到恢复配置中未知或不存在节点的待机配置错误。即使从节点没有连接到主节点/级联待机节点，节点也将显示为从节点。
  2.用户需要处理DCS软件的设置、管理和升级。
  3.需要多个端口打开组件通信：

  - Patroni的REST API端口
  - DCS至少2个端口



## 组件介绍

- **DCS**

  Patroni集群中最核心的服务就是DCS集群，DCS集群承载着patroni集群节点仲裁、集群元数据存储、数据库配置存储等重要功能。

- **HA Agent**

  Patroni作为postgres代理程序，负载数据库的流复制管理，配置管理，自动重建等诸多操作

- **Database**

  Postgres负责实际数据的存储，提供服务

- **Middleware**

  - Pgbouncer是一个针对PostgreSQL数据库的轻量级连接池，任何目标应用都可以把 pgbouncer 当作一个 PostgreSQL 服务器来连接，然后pgbouncer 会处理与服务器连接，或者是重用已存在的连接。

  - pgbouncer 的目标是降低因为新建到 PostgreSQL 的连接而导致的性能损失。

- **Load Balance**

  在以上架构中使用的是haproxy作为负载均衡，haproxy作为四层负载均衡软件，可以实现多种方式的负载均衡以及数据库的读写分离。

- **VIP**

  Keepalived和LVS是较为常见的VIP实现方式，keepalived功能比较单体，仅提供VIP功能，而LVS可以提供VIP以及负载均衡功能，同时Patroni内置的callback功能可以通过脚本配置实现VIP功能，且准确度较高、反应迅速。
