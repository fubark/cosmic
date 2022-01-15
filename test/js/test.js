const eq = cs.asserts.eq
const neq = cs.asserts.neq
const contains = cs.asserts.contains
const fs = cs.files
const throws = cs.asserts.throws

cs.test('cs.asserts', () => {
    eq(1, 1)
    eq(0, 0)
    neq(0, false)
    neq(false, '')
})

cs.test('cs.files.readFile', () => {
    fs.writeFile('foo.txt', 'foo')
    try {
        eq(fs.readFile('foo.txt'), 'foo')
        eq(fs.readFile('bar.txt'), false)
    } finally {
        fs.removeFile('foo.txt')
    }
})

cs.testIsolated('cs.files.readFileAsync', async () => {
    fs.writeFile('foo.txt', 'foo')
    try {
        let content = await fs.readFileAsync('foo.txt')
        eq(content, 'foo');
        content = await fs.readFileAsync('bar.txt')
        eq(content, false);
    } finally {
        fs.removeFile('foo.txt')
    }
})

cs.test('cs.files.writeFile', () => {
    eq(fs.writeFile('foo.txt', 'foo'), true)
    try {
        eq(fs.readFile('foo.txt'), 'foo')
        eq(fs.writeFile('foo.txt', 'bar'), true)
        // File is overwritten.
        eq(fs.readFile('foo.txt'), 'bar')
    } finally {
        fs.removeFile('foo.txt')
    }
})

cs.testIsolated('cs.files.writeFileAsync', async () => {
    eq(await fs.writeFileAsync('foo.txt', 'foo'), true);
    try {
        eq(fs.readFile('foo.txt'), 'foo')
        eq(await fs.writeFileAsync('foo.txt', 'bar'), true)
        // File is overwritten.
        eq(fs.readFile('foo.txt'), 'bar')
    } finally {
        fs.removeFile('foo.txt')
    }
})

cs.test('cs.files.appendFile', () => {
    eq(fs.appendFile('foo.txt', 'foo'), true)
    try {
        eq(fs.readFile('foo.txt'), 'foo')
        eq(fs.appendFile('foo.txt', 'bar'), true)
        eq(fs.readFile('foo.txt'), 'foobar')
    } finally {
        fs.removeFile('foo.txt')
    }
})

cs.testIsolated('cs.files.appendFileAsync', async () => {
    eq(await fs.appendFileAsync('foo.txt', 'foo'), true)
    try {
        eq(fs.readFile('foo.txt'), 'foo')
        eq(await fs.appendFileAsync('foo.txt', 'bar'), true)
        eq(fs.readFile('foo.txt'), 'foobar')
    } finally {
        fs.removeFile('foo.txt')
    }
})

cs.test('cs.files.removeFile', () => {
    eq(fs.removeFile('foo.txt'), false)
    fs.writeFile('foo.txt', 'foo');
    eq(fs.removeFile('foo.txt'), true);
})

cs.testIsolated('cs.files.removeFileAsync', async () => {
    eq(await fs.removeFileAsync('foo.txt'), false)
    fs.writeFile('foo.txt', 'foo');
    eq(await fs.removeFileAsync('foo.txt'), true);
})

cs.test('cs.files.removeDir', () => {
    eq(fs.pathExists('foo'), false)
    eq(fs.ensurePath('foo/bar', true), true)
    eq(fs.removeDir('foo', false), false)
    eq(fs.removeDir('foo/bar', false), true)
    eq(fs.ensurePath('foo/bar', true), true)
    eq(fs.removeDir('foo', true), true)
})

cs.testIsolated('cs.files.removeDirAsync', async () => {
    eq(fs.pathExists('foo'), false)
    eq(fs.ensurePath('foo/bar', true), true)
    eq(await fs.removeDirAsync('foo', false), false)
    eq(await fs.removeDirAsync('foo/bar', false), true)
    eq(fs.ensurePath('foo/bar', true), true)
    eq(await fs.removeDirAsync('foo', true), true)
})

cs.test('cs.files.ensurePath, cs.files.pathExists', () => {
    eq(fs.pathExists('foo/bar'), false)
    eq(fs.ensurePath('foo/bar'), true)
    try {
        eq(fs.pathExists('foo/bar'), true)
    } finally {
        eq(fs.removeDir('foo', true), true)
    }
})

cs.testIsolated('cs.files.ensurePathAsync, cs.files.pathExistsAsync', async () => {
    eq(await fs.pathExistsAsync('foo/bar'), false)
    eq(await fs.ensurePathAsync('foo/bar'), true)
    try {
        eq(await fs.pathExistsAsync('foo/bar'), true)
    } finally {
        eq(fs.removeDir('foo', true), true)
    }
})

cs.test('cs.files.resolvePath', () => {
    eq(fs.resolvePath('foo/../bar'), fs.resolvePath('bar'))
})

cs.test('cs.files.copyFile', () => {
    eq(fs.writeFile('foo.txt', 'foo'), true)
    try {
        eq(fs.readFile('bar.txt'), false)
        eq(fs.copyFile('foo.txt', 'bar.txt'), true)
        eq(fs.readFile('bar.txt'), 'foo')
        eq(fs.readFile('foo.txt'), 'foo')
    } finally {
        fs.removeFile('foo.txt')
        fs.removeFile('bar.txt')
    }
})

cs.testIsolated('cs.files.copyFileAsync', async () => {
    eq(fs.writeFile('foo.txt', 'foo'), true)
    try {
        eq(fs.readFile('bar.txt'), false)
        eq(await fs.copyFileAsync('foo.txt', 'bar.txt'), true)
        eq(fs.readFile('bar.txt'), 'foo')
        eq(fs.readFile('foo.txt'), 'foo')
    } finally {
        fs.removeFile('foo.txt')
        fs.removeFile('bar.txt')
    }
})

cs.test('cs.files.moveFile', () => {
    eq(fs.writeFile('foo.txt', 'foo'), true)
    try {
        eq(fs.readFile('bar.txt'), false)
        eq(fs.moveFile('foo.txt', 'bar.txt'), true)
        eq(fs.readFile('bar.txt'), 'foo')
        eq(fs.readFile('foo.txt'), false)
    } finally {
        fs.removeFile('foo.txt')
        fs.removeFile('bar.txt')
    }
})

cs.testIsolated('cs.files.moveFile', async () => {
    eq(fs.writeFile('foo.txt', 'foo'), true)
    try {
        eq(fs.readFile('bar.txt'), false)
        eq(await fs.moveFileAsync('foo.txt', 'bar.txt'), true)
        eq(fs.readFile('bar.txt'), 'foo')
        eq(fs.readFile('foo.txt'), false)
    } finally {
        fs.removeFile('foo.txt')
        fs.removeFile('bar.txt')
    }
})

cs.test('cs.files.cwd', () => {
    eq(fs.cwd(), fs.resolvePath('.'));
})

cs.test('cs.files.getPathInfo', () => {
    eq(fs.getPathInfo('foo.txt'), false)
    eq(fs.writeFile('foo.txt', 'foo'), true)
    try {
        eq(fs.getPathInfo('foo.txt'), { kind: 'File' });
    } finally {
        fs.removeFile('foo.txt')
    }
})

cs.testIsolated('cs.files.getPathInfo', async () => {
    eq(await fs.getPathInfo('foo.txt'), false)
    eq(fs.writeFile('foo.txt', 'foo'), true)
    try {
        eq(await fs.getPathInfo('foo.txt'), { kind: 'File' });
    } finally {
        fs.removeFile('foo.txt')
    }
})

cs.test('cs.files.listDir', () => {
    eq(fs.pathExists('foo/bar'), false)
    eq(fs.listDir('foo'), false)
    eq(fs.ensurePath('foo/bar'), true)
    try {
        eq(fs.writeFile('foo/foo.txt', 'foo'), true)
        eq(fs.listDir('foo'), [{ name: 'bar', kind: 'Directory' }, { name: 'foo.txt', kind: 'File' }]);
    } finally {
        fs.removeDir('foo', true)
    }
})

cs.testIsolated('cs.files.listDirAsync', async () => {
    eq(fs.pathExists('foo/bar'), false)
    eq(await fs.listDir('foo'), false)
    eq(fs.ensurePath('foo/bar'), true)
    try {
        eq(fs.writeFile('foo/foo.txt', 'foo'), true)
        eq(await fs.listDir('foo'), [{ name: 'bar', kind: 'Directory' }, { name: 'foo.txt', kind: 'File' }]);
    } finally {
        fs.removeDir('foo', true)
    }
})

cs.test('cs.files.walkDir', () => {
    eq(fs.pathExists('foo/bar'), false)
    eq(fs.walkDir('foo').next().done, true)
    eq(fs.ensurePath('foo/bar'), true)
    try {
        eq(fs.writeFile('foo/foo.txt', 'foo'), true)
        eq(fs.writeFile('foo/bar/bar.txt', 'bar'), true)
        const paths = []
        for (const e of fs.walkDir('foo')) {
            paths.push(e.path)
        }
        eq(paths, [
            'foo/bar',
            'foo/bar/bar.txt',
            'foo/foo.txt',
        ])
    } finally {
        fs.removeDir('foo', true)
    }
})

cs.testIsolated('cs.files.walkDirAsync', async () => {
    eq(fs.pathExists('foo/bar'), false)
    eq((await fs.walkDirAsync('foo').next()).done, true)
    eq(fs.ensurePath('foo/bar'), true)
    try {
        eq(fs.writeFile('foo/foo.txt', 'foo'), true)
        eq(fs.writeFile('foo/bar/bar.txt', 'bar'), true)
        const paths = []
        for await (const e of fs.walkDirAsync('foo')) {
            paths.push(e.path)
        }
        eq(paths, [
            'foo/bar',
            'foo/bar/bar.txt',
            'foo/foo.txt',
        ])
    } finally {
        fs.removeDir('foo', true)
    }
})

cs.test('cs.http.get', () => {
    let resp = cs.http.get('https://127.0.0.1')
    eq(resp, false)

    resp = cs.http.get('https://ziglang.org')
    contains(resp, 'Zig is a general-purpose programming language')
})

cs.test('cs.http.request', () => {
    throws(() => cs.http.request('https://127.0.0.1'), 'RequestFailed')

    const resp = cs.http.request('https://ziglang.org')
    eq(resp.status, 200)
    eq(resp.getHeader('content-type'), 'text/html')
    contains(resp.text(), 'Zig is a general-purpose programming language')
});

cs.testIsolated('cs.http.serveHttp', async () => {
    const s = cs.http.serveHttp('127.0.0.1', 3000)
    s.setHandler((req, resp) => {
        if (req.path == '/hello') {
            resp.setStatus(200)
            resp.setHeader('content-type', 'text/plain; charset=utf-8')
            resp.send('Hello from server!')
            return true
        }
    })

    try {
        // Sync get won't work since it blocks and the server won't be able to accept.
        // However, async get should work.
        eq(await cs.http.getAsync('http://127.0.0.1:3000'), 'not found')
        const resp = await cs.http.requestAsync('http://127.0.0.1:3000/hello')
        eq(resp.status, 200)
        eq(resp.getHeader('content-type'), 'text/plain; charset=utf-8')
        eq(resp.text(), 'Hello from server!')
    } finally {
        await s.closeAsync()
    }
    // return new Promise(() => {})
})

cs.testIsolated('cs.http.serveHttps', async () => {
    const s = cs.http.serveHttps('127.0.0.1', 3000, './vendor/https/localhost.crt', './vendor/https/localhost.key')
    s.setHandler((req, resp) => {
        if (req.path == '/hello') {
            resp.setStatus(200)
            resp.setHeader('content-type', 'text/plain; charset=utf-8')
            resp.send('Hello from server!')
            return true
        }
    })

    try {
        // Sync get won't work since it blocks and the server won't be able to accept.
        // However, async get should work.
        // Needs self-signed certificate localhost.crt installed in cainfo or capath and the request needs to hit
        // localhost and not 127.0.0.1 for ssl verify host step to work.
        // TODO: Add request option to use specific ca certificate and option to turn off verify host.
        // TODO: Should not be getting SIGPIPE when using 127.0.0.1
        eq(await cs.http.getAsync('https://localhost:3000'), 'not found')
        const resp = await cs.http.requestAsync('https://localhost:3000/hello')
        eq(resp.status, 200)
        eq(resp.getHeader('content-type'), 'text/plain; charset=utf-8')
        eq(resp.text(), 'Hello from server!')
    } finally {
        await s.closeAsync()
    }
    // return new Promise(() => {})
})