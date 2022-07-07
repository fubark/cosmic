function initStdxImports(wasm) {
    const text_decoder = new TextDecoder();
    function getString(ptr, len) {
        return text_decoder.decode(wasm.exports.memory.buffer.slice(ptr, ptr+len));
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
        }
    }
}