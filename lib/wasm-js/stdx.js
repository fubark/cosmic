function initStdxImports(wasm) {
    const text_decoder = new TextDecoder();
    function getString(ptr, len) {
        return text_decoder.decode(wasm.exports.memory.buffer.slice(ptr, ptr+len));
    }

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
        jsFetchData(promiseId, ptr, len) {
            fetch(getString(ptr, len))
                .then(resp => resp.arrayBuffer())
                .then(buf => {
                    if (wasm.inputCap < buf.byteLength) {
                        const ptr = wasm.exports.wasmEnsureInputCapacity(buf.byteLength);
                        const view = new DataView(wasm.exports.memory.buffer);
                        wasm.inputPtr = view.getUint32(ptr, true);
                        wasm.inputCap = view.getUint32(ptr + 4, true);
                    }
                    const buf_view = new Uint8Array(buf);
                    const wasm_view = new Uint8Array(wasm.exports.memory.buffer);
                    for (let i = 0; i < buf.byteLength; i++) {
                        wasm_view[wasm.inputPtr + i] = buf_view[i];
                    }
                    wasm.exports.wasmResolvePromise(promiseId, buf.byteLength);
                });
        },
    }
}