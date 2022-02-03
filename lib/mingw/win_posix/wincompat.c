#include <wincompat.h>

size_t getpagesize() {
    SYSTEM_INFO S;
    GetNativeSystemInfo(&S);
    return S.dwPageSize;
}

int writev(int sock, struct iovec *iov, int nvecs) {
	DWORD ret;
	if (WSASend(sock, (LPWSABUF)iov, nvecs, &ret, 0, NULL, NULL) == 0) {
		return ret;
	}
	return -1;
}