# 海政通信创版 Linux RPM 打包方案（非官方）

> **免责声明**
>
> - 本仓库**不包含**任何厂商二进制、安装包、截图或运行数据，只包含打包脚本与文档。
> - 与本软件的著作权人及任何厂商**无隶属关系，未获授权**。
> - 软件需你**自行通过官方渠道合法获取**。使用本仓库脚本产生的 RPM 仅供个人或本单位内部做 Linux 兼容性适配。
> - 本仓库不收集、不分发任何账号、通讯录、消息、头像或证书数据。

## 这是什么

海政通信创版官方只提供 `.deb`（UOS / 麒麟），没有 RPM，也没有 Fedora / RHEL 支持。
本项目是一个**本地转换器**：用你合法下载的 `.deb`，在 Fedora 上重打成本地 RPM，
并自动应用在 Fedora 上必需的 4 项兼容性修复。

## 不是什么

- 不是官方 RPM
- 不是破解 / 去限制工具（不修改授权、不绕过登录、不触碰服务端）
- 不提供下载链接，不托管任何二进制

## 环境要求

| 项目 | 要求 |
|---|---|
| 发行版 | Fedora 40+ / RHEL 9+ / 衍生版（已在 Fedora 44 验证） |
| 架构 | x86_64 |
| 构建工具 | `rpmbuild`、`gcc`、`python3`、`ar`、`tar`、`curl` |

```bash
sudo dnf install rpm-build gcc python3 curl
```

## 三步用法

```bash
# 1) 从官方下载页获取 UOS x64 版 .deb（自行确认使用授权）

# 2) 构建
git clone https://github.com/ZhenwanLi/hzt-for-linux-rpm.git
cd hzt-for-linux-rpm
./build.sh ~/Downloads/signed_com.hzt.xc_x.y.z_amd64.deb

# 3) 安装
sudo dnf install build/RPMS/x86_64/hzt-xc-*.rpm
```

安装后从应用菜单启动「海政通信创版」，或命令行执行 `hzt-xc`。

## 构建脚本自动做了 4 件事

| # | 动作 | 为什么 |
|---|---|---|
| 1 | 按官方 `postinst` 规则删除自带旧库（`libm.so.6`、`libgtk-x11`、`libGLX` 等） | glibc > 2.28 时这些库必须用系统的，否则符号冲突 |
| 2 | 清除 `application_gov.so` 的 `PT_GNU_STACK` 可执行位（RWE → RW） | glibc 2.43 + SELinux Enforcing 下 `dlopen` 会直接失败且程序静默退出 |
| 3 | 从 Debian 仓库补 4 个 soname（`librtmp.so.1`、`liblber-2.4.so.2`、`libldap_r-2.4.so.2`、`libsasl2.so.2`） | Fedora 没有这些版本；`libsasl2.so.3` 与 `.so.2` ABI 不兼容，不能软链 |
| 4 | 编译 NSS shim + 生成浅色 Qt/GTK 配置 | 修登录后 SIGSEGV，以及聊天输入框白字白底 |

细节与排查过程见 [`docs/troubleshooting.md`](docs/troubleshooting.md)。

## 已知限制

| 限制 | 说明 |
|---|---|
| 自动更新不可用 | 内置 updater 调用 `dpkg`，非 Debian 系无法使用；升级需重新构建安装 |
| 不读客户端证书 | 第 4 项修复的副作用：不再从 `~/.pki/nssdb` 加载证书。扫码 / 短信登录不受影响 |
| 仅 x86_64 | 官方 ARM / 龙芯包未验证 |
| GPU 加速 | `%post` 会尝试给 `chrome-sandbox` 设 `root:4755`；若被 SELinux 或挂载选项阻止，会自动退回软件渲染 |

## 目录结构

```
.
├── build.sh                      # 主流程：deb → 修复 → rpmbuild
├── rpm/hzt-xc.spec               # RPM 定义
├── overlay/
│   ├── hzt-xc.sh                 # 启动器（LD_LIBRARY_PATH / LD_PRELOAD / 浅色配置）
│   ├── hzt-xc.desktop            # 菜单项
│   ├── nss_nodb_shim.c           # 登录后崩溃修复
│   ├── gnu-stack-rw.py           # ELF 栈标记修正
│   └── gtk-3.0-settings.ini      # 浅色 GTK 模板
├── scripts/
│   ├── fetch-extra-libs.sh       # 从 Debian 镜像取 4 个 soname
│   └── leak-scan.sh              # 提交前敏感信息扫描
└── docs/
    ├── troubleshooting.md        # 完整排障过程（4 个问题的根因与验证方法）
    └── sanitize-checklist.md     # 发布前脱敏清单
```

## 提交前自检

```bash
./scripts/leak-scan.sh
```

会检查手机号、身份证、邮箱、家目录绝对路径、内网域名、账号 ID，以及是否误提交了
`.deb` / `.rpm` / 图片。

## 许可

- 本仓库中的脚本与文档：**MIT**（见 `LICENSE`）
- 上游软件：专有软件，版权归原权利人所有，本仓库不包含其任何部分

## 贡献

欢迎 issue / PR。但请不要提交：厂商二进制、日志、截图、任何包含个人或单位信息的文件。
