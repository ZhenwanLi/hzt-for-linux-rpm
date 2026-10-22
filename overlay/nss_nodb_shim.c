/**
 * nss_nodb_shim.c — 让 CEF 以「无证书数据库」模式初始化 NSS
 *
 * 背景：
 *   上游程序的 application_gov.so 静态链接了 sqlite3，并把 245 个 sqlite3_*
 *   符号以默认可见性导出。CEF 初始化 NSS 时，系统 libsqlite3 的内部 PLT 调用
 *   被解析到这份副本上，导致 sqlite3GlobalConfig 未初始化，最终在
 *   NSS_InitReadWrite() 路径上调用空函数指针崩溃。
 *
 * 做法：
 *   LD_PRELOAD 拦截 NSS_Init / NSS_InitReadWrite，改为调用 NSS_NoDB_Init()。
 *   证书数据库这条路直接不走了，也就不会再触发符号冲突。
 *
 * 代价：
 *   程序不再读取 ~/.pki/nssdb 中的客户端证书（扫码/短信登录不受影响）。
 *
 * 编译：
 *   gcc -shared -fPIC -O2 -o libhzt_nss_nodb.so nss_nodb_shim.c -ldl
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>

typedef int SECStatus; /* SECSuccess = 0, SECFailure = -1 */

static SECStatus nodb_init(void) {
    static void *h_nss;
    SECStatus (*fn)(const char *) = NULL;

    if (!h_nss)
        h_nss = dlopen("libnss3.so", RTLD_NOW | RTLD_GLOBAL);
    if (h_nss)
        fn = (SECStatus (*)(const char *))dlsym(h_nss, "NSS_NoDB_Init");
    if (!fn) {
        fprintf(stderr, "[hzt-shim] NSS_NoDB_Init not found\n");
        return -1;
    }
    return fn(NULL);
}

SECStatus NSS_InitReadWrite(const char *configdir) {
    fprintf(stderr, "[hzt-shim] NSS_InitReadWrite(%s) -> NSS_NoDB_Init\n",
            configdir ? configdir : "(null)");
    return nodb_init();
}

SECStatus NSS_Init(const char *configdir) {
    fprintf(stderr, "[hzt-shim] NSS_Init(%s) -> NSS_NoDB_Init\n",
            configdir ? configdir : "(null)");
    return nodb_init();
}
