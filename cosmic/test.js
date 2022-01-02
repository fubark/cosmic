const eq = cs.asserts.eq;
const neq = cs.asserts.neq;
const fs = cs.files;

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

cs.test('cs.files.removeFile', () => {
    eq(fs.removeFile('foo.txt'), false)
    fs.writeFile('foo.txt', 'foo');
    eq(fs.removeFile('foo.txt'), true);
})

cs.test('cs.files.removeDir', () => {
    eq(fs.pathExists('foo'), false)
    eq(fs.ensurePath('foo/bar', true), true)
    eq(fs.removeDir('foo', false), false)
    eq(fs.removeDir('foo/bar', false), true)
    eq(fs.ensurePath('foo/bar', true), true)
    eq(fs.removeDir('foo', true), true)
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

cs.test('cs.files.walkDir', () => {
    eq(fs.pathExists('foo/bar'), false)
    eq(fs.walkDir('foo', () => {}), false)
    eq(fs.ensurePath('foo/bar'), true)
    try {
        eq(fs.writeFile('foo/foo.txt', 'foo'), true)
        eq(fs.writeFile('foo/bar/bar.txt', 'bar'), true)
        const paths = []
        const res = fs.walkDir('foo', (path, kind) => {
            paths.push(path)
        });
        eq(res, true)
        eq(paths, [
            'bar',
            'bar/bar.txt',
            'foo.txt',
        ])
    } finally {
        fs.removeDir('foo', true)
    }
})