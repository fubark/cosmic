const s = cs.http.serveHttps('127.0.0.1', 3000, './vendor/https/localhost.crt', './vendor/https/localhost.key')
s.setHandler((req, resp) => {
    if (req.path == '/') {
        resp.setStatus(200)
        resp.setHeader('content-type', 'text/html; charset=utf-8')
        const content = cs.files.readTextFile('./vendor/https/index.html')
        resp.send(content)
        return true
    } else if (req.path == '/style.css') {
        resp.setStatus(200)
        resp.setHeader('content-type', 'text/css; charset=utf-8')
        const content = cs.files.readTextFile('./vendor/https/style.css')
        resp.send(content)
    } else if (req.path == '/logo.png') {
        resp.setStatus(200)
        resp.setHeader('content-type', 'image/png')
        const bytes = cs.files.readFile('./vendor/https/logo.png')
        resp.sendBytes(bytes)
    } else if (req.path == '/foo') {
        resp.setStatus(200)
        resp.setHeader('content-type', 'text/plain; charset=utf-8')
        resp.send('foo from server')
        return true
    } else if (req.path == '/bar') {
        resp.setStatus(200)
        resp.setHeader('content-type', 'text/plain; charset=utf-8')
        resp.send('bar from server')
        return true
    }
})
print('server started')