# sing-box 管理脚本优化版

一个适合自用服务器的 `sing-box` 管理脚本，主要用于快速查看状态、检查配置、备份恢复、生成客户端参数、修改端口和进行基础安全检查。

脚本默认适配：

```bash
/etc/sing-box/config.json
````

服务名默认：

```bash
sing-box
```

适合已经手动或通过其他方式安装好 `sing-box` 的服务器使用。

---

## 功能特性

* 查看 sing-box 配置文件
* 编辑 sing-box 配置文件
* 检查配置文件是否合法
* 重启 sing-box 服务
* 查看 sing-box 运行状态
* 查看监听端口
* 查看最近运行日志
* 备份当前配置
* 恢复最近备份
* 生成 UUID
* 生成 Reality 密钥
* 保存 / 更新 PublicKey
* 显示客户端连接参数
* 自动生成 VLESS 分享链接
* 修改监听端口
* 修改端口前自动备份
* 配置检查失败自动回滚
* 支持 UFW 放行 TCP / UDP / all
* 一键安全检查

---

## 安装方法

下载脚本后赋予执行权限：

```bash
chmod +x sb.sh
```

运行：

```bash
sudo ./sb.sh
```

也可以安装为系统命令：

```bash
sudo install -m 755 sb.sh /usr/local/bin/sb
```

之后可以直接运行：

```bash
sudo sb
```

---

## 使用前提

服务器需要已经安装：

* bash
* python3
* sing-box
* systemd
* curl
* ss
* ufw，可选

脚本需要使用 `sudo` 运行，因为它会读取和修改：

```bash
/etc/sing-box/config.json
```

---

## 菜单说明

```text
1) 查看配置文件
2) 编辑配置文件
3) 检查配置文件
4) 重启 sing-box
5) 查看 sing-box 状态
6) 查看监听端口
7) 查看最近日志
8) 备份当前配置
9) 恢复最近备份
10) 生成 UUID
11) 生成 Reality 密钥
12) 显示客户端参数/分享链接
13) 修改监听端口
14) 放行端口到 ufw
15) 保存/更新 PublicKey
16) 安全检查
17) 退出
```

---

## 客户端参数生成

脚本会从 sing-box 配置文件中读取：

* 端口
* UUID
* Flow
* SNI
* ShortID
* Reality PrivateKey 状态
* 日志级别

PublicKey 会单独保存到：

```bash
/home/当前用户/.sb_public_key
```

保存 PublicKey 后，脚本可以自动生成 VLESS 分享链接，方便导入 v2rayN、v2rayNG、sing-box 客户端等工具。

---

## 备份机制

执行备份后，配置会保存到：

```bash
/etc/sing-box/backups/
```

修改监听端口时，脚本会自动备份当前配置。

如果修改后配置检查失败，会自动恢复旧配置，降低误操作风险。

---

## 安全检查内容

安全检查会检查：

* sing-box 服务是否运行
* 配置文件是否通过检查
* 当前端口是否正在监听
* UUID 是否存在
* Reality PrivateKey 是否存在
* Reality SNI 是否存在
* ShortID 是否存在
* PublicKey 是否已保存
* UFW 是否开启
* 当前端口是否已在 UFW 放行
* 配置文件权限和属主

---

## 注意事项

请不要把以下文件上传到公开仓库：

```bash
/etc/sing-box/config.json
/etc/sing-box/backups/
~/.sb_public_key
*.bak
*.log
.env
```

不要公开截图或提交包含以下内容的信息：

* UUID
* PrivateKey
* PublicKey
* ShortID
* 服务器真实 IP
* 完整 vless:// 分享链接

其中 `PrivateKey` 绝对不能泄露。

---

## 推荐 .gitignore

```gitignore
*.bak
*.log
*.key
.sb_public_key
config.json
backups/
.env
```

---

## 常用命令

检查脚本语法：

```bash
bash -n sb.sh
```

运行脚本：

```bash
sudo bash sb.sh
```

安装为命令：

```bash
sudo install -m 755 sb.sh /usr/local/bin/sb
```

运行命令版：

```bash
sudo sb
```

查看 sing-box 状态：

```bash
sudo systemctl status sing-box --no-pager
```

检查配置：

```bash
sudo sing-box check -c /etc/sing-box/config.json
```

查看监听端口：

```bash
sudo ss -tulpn | grep sing-box
```

---

## 适用场景

这个脚本适合：

* 自用 sing-box 节点管理
* Reality 节点参数查看
* 快速生成客户端连接信息
* 修改端口前自动备份
* 服务器日常维护
* 小白用户减少手动敲命令

---

## 免责声明

本脚本仅用于个人服务器管理和学习用途。

使用前请确认自己了解相关配置含义。修改端口、恢复备份、编辑配置等操作可能影响当前节点连接，请谨慎操作。

建议在修改配置前先备份当前配置。
