# 发布前脱敏清单

## 一、绝对不入库的内容

| 类型 | 说明 |
|---|---|
| 安装包 | `*.deb` / `*.rpm`，厂商版权 |
| 程序本体 | 解包后的 `/opt/apps/...`，约 780 MB |
| 任何 `.so` | 含厂商编译产物和打包用的 Debian 库 |
| 运行数据 | `~/com.hzt.xc/`（消息、通讯录、头像、DB） |
| 截图 | 含真实姓名、部门、会议通知、头像 |
| 日志 / 转储 | `*.log`、`*.dmp`，可能含路径、账号、令牌 |

`.gitignore` 已覆盖上述大部分；`scripts/leak-scan.sh` 会再兜底一遍。

## 二、必须替换的字符串

| 原文 | 替换为 |
|---|---|
| `/home/<你的用户名>` | `/home/user` |
| `工号@单位域名` 形式的账号 | 删除 |
| 单位名 / 党支部名 / 人名 | 删除，改「某单位」「A 部门」 |
| 内网下载域名 | `example.com`（README 只保留官方公开下载页） |
| 手机号 / 身份证 / 邮箱 | 删除 |

`taurushainanxc`（程序的 URL scheme）属于厂商公开标识，保留，扫描脚本已加白。

## 三、顺序（很重要）

```bash
# 1. 先复制一份再脱敏，原始文件留作私人备份
cp -a 原始文档.md docs/troubleshooting.md
sed -i 's|/home/你的用户名|/home/user|g' docs/troubleshooting.md

# 2. 脱敏完成后再初始化仓库
git init
git add -A
./scripts/leak-scan.sh && git commit -m "init"

# 3. 推送
gh repo create hzt-for-linux-rpm --public --source=. --push
```

**不要先 commit 再改文件**：`git log -p` 里会永久保留明文，
之后只能靠 `filter-repo` 重写历史，非常麻烦。

## 四、图片为什么一律不要

即使打码也可能通过以下方式还原：

- 马赛克区域太小 / 可逆
- 截图 EXIF、PNG 文本块（tEXt）残留路径与软件名
- 界面元素本身的组织架构、头像、群名

需要图示时，用文字或 ASCII 结构图代替（本项目已这样做）。

## 五、公开前的最后一关

- [ ] `./scripts/leak-scan.sh` 通过
- [ ] `git log --stat` 里没有二进制
- [ ] README 顶部有免责声明
- [ ] LICENSE 说明只覆盖本仓库代码
- [ ] 仓库里没有可用的下载直链（只指向官方公开页面）
