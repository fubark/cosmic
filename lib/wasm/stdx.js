function initStdxImports(wasm) {
    const textDecoder = new TextDecoder()
    const textEncoder = new TextEncoder()
    function getString(ptr, len) {
        return textDecoder.decode(wasm.exports.memory.buffer.slice(ptr, ptr+len));
    }

    let next_fetch_id = 1

    return {
        jsWarn(ptr, len) {
            console.warn(getString(ptr, len));
        },
        jsLog(ptr, len) {
            console.log(getString(ptr, len));
        },
        jsErr(ptr, len) {
            console.error(getString(ptr, len));
        },
        jsFetchData(ptr, len) {
            const id = next_fetch_id
            next_fetch_id += 1
            fetch(getString(ptr, len))
                .then(resp => resp.arrayBuffer())
                .then(buf => {
                    wasm.postFetchResult(id, buf)
                });
            return id
        },
        jsPerformanceNow() {
            return performance.now()
        },
        jsSetSystemCursor(ptr, len) {
            const name = getString(ptr, len)
            document.body.style.cursor = name
        },
        jsGetClipboard(len_ptr) {
            throw new Error('todo')
        },
        jsSetClipboardText(ptr, len) {
            const text = getString(ptr, len)
            navigator.clipboard.writeText(text)
        },
        jsOpenUrl(ptr, len) {
            const url = getString(ptr, len)
            window.open(url, '_blank').focus()
        }
    }
}