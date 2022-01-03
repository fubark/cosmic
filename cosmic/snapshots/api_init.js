(function() {

    cs.files.walkDir = function* (path) {
        const entries = cs.files.listDir(path)
        if (entries === false) {
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
        if (entries === false) {
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

})();