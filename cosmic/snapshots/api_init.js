"use strict";

(function() {

    // Initialize runtime on the js side. Once this gets big, extract to runtime_init.js.

    // cs.core is duplicated into global scope.
    Object.assign(globalThis, cs.core)

    // Prepare stack traces.
    // Use js stack trace API to gain access to the richer CallSiteInfo since v8's StackFrame API is limited (meant for use with debugger).
    // The js stack trace is also able to link together async stack frames.
    // prepareStackTrace is lazily invoked the moment Error.stack is accessed from either js or v8.
    // Once invoked, the structured trace is also saved into the Error object so it can be accessed from v8.
    Error.prepareStackTrace = function(err, frames) {
        // The return value should be a string and is then set to Error.stack.
        // It should match the stack trace format of runtime.JsStackTrace in the backend.
        let res = err.toString()

        err.__frames = frames.map(frame => {
            const cs_frame = {
                url: frame.getFileName(),
                line_num: frame.getLineNumber(),
                col_num: frame.getColumnNumber(),
                func_name: frame.getFunctionName(),
                is_async: frame.isAsync(),
                is_constructor: frame.isConstructor(),
            }
            const async_str = cs_frame.is_async ? 'async ' : ''
            const func_str = cs_frame.func_name ? cs_frame.func_name + ' ' : ''
            res += `\n    at ${async_str}${func_str}${cs_frame.url}:${cs_frame.line_num}:${cs_frame.col_num}`
            return cs_frame
        })
        return res
    }

    // Errors from native async calls are wrapped in an ApiError to create a js side stack trace.
    globalThis.ApiError = class extends Error {
        constructor(nativeErr) {
            super(nativeErr.message)
            this.name = 'ApiError'
            this.code = nativeErr.code
        }
    }

    cs.files.walkDir = function* (path) {
        const entries = cs.files.listDir(path)
        if (entries === null) {
            return
        }
        for (const entry of cs.files.listDir(path)) {
            yield {
                path: path + '/' + entry.name,
                kind: entry.kind,
            }
            if (entry.kind == 'Directory') {
                yield* cs.files.walkDir(path + '/' + entry.name)
            }
        }
    }

    cs.files.walkDirAsync = async function* (path) {
        const entries = await cs.files.listDirAsync(path).catch(err => { throw new ApiError(err) })
        if (entries === null) {
            return
        }
        for (const entry of entries) {
            yield await {
                path: path + '/' + entry.name,
                kind: entry.kind,
            }
            if (entry.kind == 'Directory') {
                yield* cs.files.walkDirAsync(path + '/' + entry.name)
            }
        }
    }

    cs.http.request = function(method, url) {
        const resp = cs.http._request(method, url)
        const headers = resp.headers
        resp.headers = new Map()
        for (const h of headers) {
            const key = h.key.toLowerCase()
            if (resp.headers.has(key)) {
                resp.headers.set(key, resp.headers.get(h.key) + ' ' + h.value)
            } else {
                resp.headers.set(key, h.value)
            }
        }
        return resp
    }

    cs.http.requestAsync = async function(method, url) {
        const resp = await cs.http._requestAsync(method, url).catch(err => { throw new ApiError(err) })
        const headers = resp.headers
        resp.headers = new Map()
        for (const h of headers) {
            const key = h.key.toLowerCase()
            if (resp.headers.has(key)) {
                resp.headers.set(key, resp.headers.get(h.key) + ' ' + h.value)
            } else {
                resp.headers.set(key, h.value)
            }
        }
        return resp
    }

    cs.http.Response.prototype.getHeader = function(key) {
        return this.headers.get(key.toLowerCase())
    }

    cs.http.Response.prototype.text = function() {
        return this.body;
    }

    cs.http.Response.prototype.json = function() {
        return JSON.parse(this.body);
    }
})();