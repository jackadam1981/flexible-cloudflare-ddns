# flexible-cloudflare-ddns

Cloudflare API settings include DDNS, multiple domain names, multiple host names, multiple IP acquisition methods, and optional proxies.

为了多接入主机，为了更多灵活域名，为了虚拟主机，为了docker容器。
非常灵活的cloudflare ddns。
使用shell curl jq实现。
已测试：Proxmox(Debian)、Armbian(onecloud)、Openwrt(23.05.2)

In order to access multiple hosts, for more flexible domain names, for virtual hosts, and for Docker containers.

Very flexible cloudflare ddns.

Implement using shell curl jq.

Tested: Proxmox (Debian), Armbian (onecloud), Openwrt (23.05.2)

# Guide手册

## Pre-work准备工作

[用户 API 令牌 | jackadam1981@hotmail.com | Cloudflare](https://dash.cloudflare.com/profile/api-tokens) 在这里申请令牌token，使用模板，编辑区域DNS

安装curl jq。

## 配置

一个典型的配置文件是cfddns.json，json格式的配置文件。

```
{
  "config": [
    {
      "domain_name": "域名",
      "zone_id": "",
      "auth_type": "key",
      "auth_key": "令牌",
      "records": [
        {
          "name": "主机名",
          "type": "AAAA",
          "proxy": false,
          "static": true,
          "nic_name": "pppoe-lan"
        }
      ]
    }
  ]
}
```

domain_name: 域名，如  google.com

auth_key: 令牌，挺长的一串随机码

name: 主机名，如 blog  ,

type：解析类型  A 或 AAAA， ipv4或ipv6的意思

proxy：是否开红云代理加速，

static：是否本机获取IP地址，如果false，将从网络获取本机访问互联网的地址。

nic_name：网卡名称，如果本机获取IP地址，将获取该网卡的IP地址，方便多网络环境的主机注册正确的IP地址。static如果为false，可以留空。

# 注意

由于没有交互生成配置文件，所以最好去[JSON在线解析及格式化验证 - JSON.cn](https://www.json.cn/) 验证一下，能正常的才能用。

否则可能报错：`./cfddns.sh: line 204: [: 0: unary operator expected`

# 特性：

仅从cloudflare获取一次zone_id，会覆写cfconf.json保存。

遍历检查更新每个主机的信息，根据配置来更新DNS信息，目前配置 IP类型、是否开启红云代理，网络还是本地获取IP地址。

遍历一个域的多个主机时，仅获取一次IP地址。（小bug？暂时只区分了IPV4、IPV6，需要优化为4类）

获取IPV6地址时，会使用剩余有效时间最长的一个IPV6地址

通过URL来查询主机的记录，获取主机ID，主机IP。决定是否更新。

日志放入系统日志，有自有标头来查询。

自动生成配置文件模板。

查看日志

```
#linux
#journalctl --no-pager --since today -g 'jaDDNS'

# openwrt
#logread -e jaDDNS
```

# 计划

兼容wget，似乎openwrt的wget 不支持--header，无法设置请求头，等待openwrt升级。

自动创建记录

分离IP地址设置，将IP地址分离为  本地IPV4，网络IPV4，本地IPV6，网络IPV6，根据具体情况来决定是否获取。、

自定义日志标头

自定义配置文件名

一键安装功能  “curl -s https://***** | bash *** ”

向导功能，交互式生成适配的配置文件。

# 一个离谱（完整）的配置文件

```
{
  "config": [
    {
      "domain_name": "domain_name1",
      "zone_id": "",
      "auth_type": "key",
      "auth_key": "****************************************",
      "records": [
        {
          "name": "host_name1",
          "type": "AAAA",
          "proxy": false,
          "static": true,
          "nic_name": "eth0"
        },
        {
          "name": "host_name2",
          "type": "A",
          "proxy": true,
          "static": false,
          "nic_name": ""
        }
      ]
    },
    {
      "domain_name": "domain_name2",
      "zone_id": "",
      "auth_type": "key",
      "auth_key": "****************************************",
      "records": [
        {
          "name": "host_name3",
          "type": "AAAA",
          "proxy": false,
          "static": true,
          "nic_name": "eth0"
        },
        {
          "name": "host_name4",
          "type": "AAAA",
          "proxy": false,
          "static": true,
          "nic_name": "eth0"
        }
      ]
    }
  ]
}

```
