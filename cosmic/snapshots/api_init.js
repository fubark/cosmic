(function() {

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
        const entries = await cs.files.listDirAsync(path)
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
        const resp = await cs.http._requestAsync(method, url)
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