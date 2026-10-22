# 上游所有 .so 都带 RUNPATH '.'，rpmbuild 的 check-rpaths 会直接判失败。
# 这是厂商二进制的既有属性，重打包时保留原样，跳过该校验。
%define __brp_check_rpaths %{nil}
# 同理：上游库没有 man page / 不需要压缩与 shebang 修整
%define __brp_mangle_shebangs %{nil}

%{!?rpmver:%global rpmver 0.0.0}
%{!?rpmrel:%global rpmrel 1}
%{!?stage:%global stage %{_builddir}/stage}

Name:           hzt-xc
Version:        %{rpmver}
Release:        %{rpmrel}%{?dist}
Summary:        Unofficial Fedora/RHEL repackaging of a Debian-only client

License:        Proprietary (upstream binary); packaging scripts MIT
URL:            https://github.com/ZhenwanLi/hzt-for-linux-rpm
BuildArch:      x86_64

# 不要自动扫描 783 MB 的依赖，否则构建极慢且会引入大量噪声
AutoReqProv:    no

Requires:       libX11 libXext libSM libICE
Requires:       fontconfig freetype
Requires:       libXrender libXi libXtst libXcursor libXfixes
Requires:       mesa-libGL libXcomposite libXdamage libXrandr
Requires:       alsa-lib nss nspr

%description
Unofficial repackaging helper for a proprietary government IM client that is
shipped only as a Debian package. This RPM is produced locally from a package
you obtained yourself; no vendor binaries are distributed with this project.

It applies the compatibility fixes required on Fedora/RHEL: bundled library
cleanup, ELF stack flag correction, Debian-side sonames, an NSS shim and a
light Qt/GTK profile.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/opt/apps
cp -a %{stage}/opt/apps/com.hzt.xc %{buildroot}/opt/apps/

install -Dm755 %{_sourcedir}/hzt-xc.sh      %{buildroot}/usr/bin/hzt-xc
install -Dm644 %{_sourcedir}/hzt-xc.desktop %{buildroot}/usr/share/applications/com.hzt.xc.desktop

%files
/opt/apps/com.hzt.xc
/usr/bin/hzt-xc
/usr/share/applications/com.hzt.xc.desktop

%post
# Chromium 沙箱要求 setuid root，否则 GPU 进程起不来（会自动退回软件渲染）
for sb in /opt/apps/com.hzt.xc/files/*/chrome-sandbox; do
    [ -e "$sb" ] && chown root:root "$sb" && chmod 4755 "$sb" || :
done
update-desktop-database -q /usr/share/applications 2>/dev/null || :

%postun
update-desktop-database -q /usr/share/applications 2>/dev/null || :

%changelog
* Thu Oct 22 2026 hzt-for-linux-rpm contributors - 3.14.0-2
- Initial packaging: Fedora/RHEL compatibility fixes
